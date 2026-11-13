"""Native TLS generation, rejected material and rollback qualification."""
import concurrent.futures,datetime,hashlib,json,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);cfg=json.loads((root/'config.json').read_text());prepared=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=prepared['project'];commands=[];checks=[];fixtures=root/'tls-fixtures';fixtures.mkdir(mode=0o700,exist_ok=True)
clientimage='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8'
def run(args,input=None,ok=True):
 p=subprocess.run(args,input=input,capture_output=True,timeout=120);commands.append({'argv':args,'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit':p.returncode,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr).hexdigest()})
 if ok and p.returncode:raise RuntimeError('TLS command failed '+str(args[:3])+': '+p.stdout.decode()[-200:])
 return p
def d(*args,**kw):return run(['docker',*args],**kw)
def comp(*args,**kw):return d('compose','-p',project,'-f',prepared['compose_file'],*args,**kw)
def api(op,input=None,ok=True):
 args=['node',str(repo/'tests/mail/api.cjs'),op,str(root/'config.json')]
 if input is not None:
  path=root/('tls-request-'+uuid.uuid4().hex+'.json');path.write_text(json.dumps(input));path.chmod(0o600);args.append(str(path))
 return run(args,ok=ok)
def wait(fn):
 for _ in range(200):
  value=fn()
  if value:return value
  time.sleep(.1)
 raise TimeoutError('TLS observation timeout')
def client(*args):return json.loads(d('run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--entrypoint','python3',clientimage,'/lab/client.py',*args).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
def inventory():return sorted((x['queue_id'],x['message_size'],tuple(sorted(y['address'] for y in x['recipients']))) for x in queue())
def material(name,hostname,serial):
 key=fixtures/(name+'.key');csr=fixtures/(name+'.csr');cert=fixtures/(name+'.pem');ext=fixtures/(name+'.ext')
 run(['openssl','req','-newkey','rsa:2048','-nodes','-subj','/CN='+hostname,'-keyout',str(key),'-out',str(csr)])
 ext.write_text('subjectAltName=DNS:'+hostname+'\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n')
 run(['openssl','x509','-req','-in',str(csr),'-CA',str(source/'keys/ca.pem'),'-CAkey',str(source/'keys/ca.key'),'-set_serial',str(serial),'-days','2','-extfile',str(ext),'-out',str(cert)])
 for p in [key,csr,cert,ext]:p.chmod(0o600)
 return {'certificate_file':str(cert),'key_file':str(key),'ca_file':str(source/'keys/ca.pem')}
def case(name,fn):
 try:detail=fn();checks.append({'name':name,'status':'PASS','observation':detail});print('PASS '+name,flush=True)
 except Exception as e:checks.append({'name':name,'status':'FAIL','reason':str(e)});print('FAIL '+name+': '+str(e),flush=True)
tag=uuid.uuid4().hex[:8];old='tls-existing-'+tag;pending='tls-deferred-'+tag
client('send','-','outside@dest.invalid','contact@oxymot.fr',old,'25');wait(lambda:client('imap','contact@oxymot.fr',old)['matches'])
comp('stop','dovecot');client('send','-','outside@dest.invalid','contact@oxymot.fr',pending,'25');q=wait(lambda:next((x for x in queue() if x['queue_name']=='deferred'),None));comp('exec','-T','postfix','postsuper','-c','/config','-h',q['queue_id']);comp('start','dovecot');time.sleep(1)
before=inventory();pointer=root/'service/durable/tls/current';original=pointer.readlink();good=material('renewed','mail.oxymot.fr',200);bad=material('wrong-san','wrong.invalid',201);fault=material('reload-fault','mail.oxymot.fr',202)
def rejected(sources,code):
 result=api('rotate',sources,False);assert result.returncode and json.loads(result.stdout)['code']==code;assert pointer.readlink()==original and inventory()==before;return {'code':code,'queue_preserved':True}
case('wrong-san-refused-before-activation',lambda:rejected(bad,'MAIL_CERTIFICATE_INVALID'))
case('mismatching-key-refused-before-activation',lambda:rejected({**good,'key_file':bad['key_file']},'MAIL_CERTIFICATE_INVALID'))
def sealed():
 mapping={x['ref']:pathlib.Path(x['file']) for x in cfg['secret_sources']};cert=mapping[cfg['service']['tls']['certificate_ref']];key=mapping[cfg['service']['tls']['key_ref']];c,k=cert.read_bytes(),key.read_bytes()
 try:
  cert.write_bytes(pathlib.Path(good['certificate_file']).read_bytes());key.write_bytes(pathlib.Path(good['key_file']).read_bytes());p=api('prepare',ok=False);assert p.returncode and json.loads(p.stdout)['code']=='MAIL_SEALED_INPUT_CONFLICT'
  assert pointer.readlink()==original and inventory()==before
 finally:cert.write_bytes(c);key.write_bytes(k)
 return {'sealed_candidate_unchanged':True,'queue_preserved':True}
case('same-reference-key-replacement-cannot-rewrite-sealed-candidate',sealed)
def rotate():
 control=root/'tls-control';control.mkdir(mode=0o700);session=scripts/'tls-session.py';assert session.exists()
 with concurrent.futures.ThreadPoolExecutor(1) as pool:
  thread=pool.submit(d,'run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={control},target=/control','--entrypoint','python3',clientimage,'/lab/tls-session.py')
  wait(lambda:(control/'tls-sessions-ready').exists());result=json.loads(api('rotate',good).stdout);(control/'tls-sessions-release').write_text('go');sessions=json.loads(thread.result().stdout)
 assert result['changed'] and len(result['endpoints'])==5 and inventory()==before and client('imap','contact@oxymot.fr',old)['matches']
 return {'rotation':result,**sessions,'queue_preserved':True,'old_mailbox_message_preserved':True}
case('renewed-leaf-on-all-five-endpoints-and-existing-session-accounting',rotate)
def failed_reload():
 old_target=pointer.readlink();intent=root/'service/durable/operator-state/tls-intent.json'
 def interrupt():
  wait(lambda:pointer.readlink()!=old_target and intent.exists() and json.loads(intent.read_text())['phase']=='applying');d('kill','--signal=KILL',project+'-dovecot-1')
 with concurrent.futures.ThreadPoolExecutor(1) as pool:
  thread=pool.submit(interrupt);result=api('rotate',fault,False);thread.result()
 assert result.returncode and json.loads(result.stdout)['code']=='MAIL_TLS_ROTATION_FAILED';assert pointer.readlink()==old_target and inventory()==before
 state=json.loads(intent.read_text());assert state['phase']=='rollback-incomplete'
 observation=json.loads(api('observe').stdout);codes=[x['code'] for x in observation['alerts']];assert 'MAIL_TLS_ROTATION_FAILED' in codes and 'MAIL_GENERATION_INCOMPLETE' in codes
 comp('start','dovecot');time.sleep(1);repaired=json.loads(api('reconcile').stdout);assert repaired['reconciled'] and len(repaired['endpoints'])==5 and inventory()==before
 return {'failure_code':'MAIL_TLS_ROTATION_FAILED','failure_phase':state['phase'],'alerts':codes,'reconciliation':repaired,'queue_preserved':True}
case('native-reload-failure-rolls-back-and-retains-barrier-until-reconciliation',failed_reload)
comp('exec','-T','postfix','postsuper','-c','/config','-H',q['queue_id']);comp('exec','-T','postfix','postqueue','-c','/config','-f');wait(lambda:not queue());delivered=wait(lambda:client('imap','contact@oxymot.fr',pending)['matches']);assert len(delivered)==1
result={'status':'PASS_NATIVE_TLS_GENERATIONS' if all(x['status']=='PASS' for x in checks) else 'FAIL_NATIVE_TLS_GENERATIONS','checks':checks,'commands':commands,'held_queue_delivered_after_release':True,'original_message_still_readable':bool(client('imap','contact@oxymot.fr',old)['matches']),'source_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()};(root/'tls-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'tls-result.json'))
