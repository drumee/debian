"""Grant/password changes during DATA and retained all-disabled local delivery."""
import concurrent.futures,copy,hashlib,json,pathlib,secrets,shutil,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';engine=p['compose']['services']['dovecot']['image'];cfg=json.loads((root/'config.json').read_text());private=root/'session-private';private.mkdir(mode=0o700,exist_ok=True);keys=private/'keys';shutil.copytree(source/'keys',keys);control=private/'control';control.mkdir(mode=0o700);commands=[];checks=[];ip=100
verifierfile=pathlib.Path(cfg['verifiers_file']);original_verifiers=json.loads(verifierfile.read_text());clientfile=keys/'client.json';original_clients=json.loads(clientfile.read_text());public=root/'service/durable/registry/public'
def run(args,input=None,ok=True):
 r=subprocess.run(args,input=input,capture_output=True,timeout=150);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('session command failed '+str(args[:3]))
 return r
def change(fn):
 registry=json.loads((public/'current.json').read_text());staged=[int(f.name.split('-')[-1]) for f in (root/'service/durable/registry/private').glob('generation-*')];registry['generation']=max([registry['generation'],*staged])+1;fn(registry);request=private/('request-'+uuid.uuid4().hex+'.json');request.write_text(json.dumps(registry));request.chmod(0o600);return json.loads(run(['node',str(repo/'tests/mail/api.cjs'),'registry',str(root/'config.json'),str(request)]).stdout)
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def helper(*args):
 global ip
 ip+=1
 return run(['docker','run','--rm','--network',project+'-edge','--ip','10.243.47.'+str(ip),'--user','1000:1000','--mount',f'type=bind,source={keys},target=/keys,readonly','--mount',f'type=bind,source={control},target=/control','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,*args])
def probe(code):return json.loads(helper('-c',"import sys,json,imaplib,smtplib;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import connect,IMAP,cfg,ctx;"+code).stdout)
def client(*args):return json.loads(helper('/lab/client.py',*args).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
def ids():return {q['queue_id'] for q in queue()}
def inflight(name,mutation):
 tag=name+'-'+uuid.uuid4().hex;before=ids()
 with concurrent.futures.ThreadPoolExecutor(1) as pool:
  future=pool.submit(helper,'/lab/transaction-probe.py','inflight',tag)
  for _ in range(100):
   if (control/(tag+'-ready')).exists():break
   time.sleep(.1)
  else:raise TimeoutError('DATA354 not observed')
  result=change(mutation);(control/(tag+'-release')).write_text('applied');observed=json.loads(future.result().stdout)
 assert ids()==before;checks.append({'name':name,'status':'PASS','generation':result['generation'],'observation':observed,'no_new_queue':True});print(json.dumps(checks[-1]),flush=True)
def grants(r):r['accounts'][0].update(credential_generation=r['accounts'][0]['credential_generation']+1,envelope_from=['second@oxymot.fr'],header_from=['second@oxymot.fr'])
inflight('grant-only-during-data',grants)
change(lambda r:r['accounts'][0].update(credential_generation=r['accounts'][0]['credential_generation']+1,envelope_from=['contact@oxymot.fr'],header_from=['contact@oxymot.fr']))
password='Synthetic-'+secrets.token_hex(20);hashed=run(['docker','run','--rm','-i','--network','none','--entrypoint','doveadm',engine,'pw','-s','ARGON2ID'],input=(password+'\n'+password+'\n').encode()).stdout.decode().strip();verifiers=copy.deepcopy(original_verifiers);verifiers['ghost']=hashed;verifierfile.write_text(json.dumps(verifiers));verifierfile.chmod(0o600)
inflight('password-rotation-during-data',lambda r:r['accounts'][0].update(credential_generation=r['accounts'][0]['credential_generation']+1))
old=probe("s=connect(587,None)\ntry:s.auth('PLAIN',lambda challenge=None:'\\0ghost\\0'+cfg['ghost']);raise AssertionError('old password accepted')\nexcept smtplib.SMTPAuthenticationError as e:assert e.smtp_code==535;print(json.dumps({'old_password_code':e.smtp_code}))\ns.close()")
clients=copy.deepcopy(original_clients);clients['ghost']=password;clientfile.write_text(json.dumps(clients));clientfile.chmod(0o600);assert probe("s=connect();s.quit();print(json.dumps({'new_password':True}))")['new_password'];checks.append({'name':'rotated-new-authentication','status':'PASS','observation':old})
verifierfile.write_text(json.dumps(original_verifiers));verifierfile.chmod(0o600);change(lambda r:r['accounts'][0].update(credential_generation=r['accounts'][0]['credential_generation']+1));clientfile.write_text(json.dumps(original_clients));clientfile.chmod(0o600)
# Deliberate quota decrease preserves existing messages; it does not allocate space.
change(lambda r:r['mailboxes'][1].update(quota_bytes=2097152));seed=probe("s=IMAP('dovecot',993,ssl_context=ctx,timeout=8);s.login('second@oxymot.fr',cfg['second']);assert s.append('INBOX',None,None,b'From: outside@dest.invalid\\r\\nSubject: retained boundary seed\\r\\n\\r\\n'+b'x'*1100000)[0]=='OK';s.logout();print(json.dumps({'seeded':True}))");change(lambda r:r['mailboxes'][1].update(quota_bytes=1048576))
tag='accepted-before-revoke-'+uuid.uuid4().hex;accepted=json.loads(helper('/lab/transaction-probe.py','accepted',tag).stdout);time.sleep(1);assert accepted['queue_id'] in ids();change(lambda r:r['accounts'][0].update(enabled=False,credential_generation=r['accounts'][0]['credential_generation']+1));assert accepted['queue_id'] in ids();change(lambda r:r['mailboxes'][1].update(quota_bytes=2097152));comp('exec','-T','postfix','postqueue','-c','/config','-f');time.sleep(2);assert len(client('imap','second@oxymot.fr',tag)['matches'])==1;assert accepted['queue_id'] not in ids();checks.append({'name':'final-250-before-revocation-retains-instance-queue','status':'PASS','queue_id':accepted['queue_id'],'observed_deliveries':1});change(lambda r:r['accounts'][0].update(enabled=True,credential_generation=r['accounts'][0]['credential_generation']+1))
# Transport projection of retained deletion: UUID lookup survives while every new access is disabled.
previous=json.loads((public/'current.json').read_text());change(lambda r:r['mailboxes'][0].update(submission_enabled=True,quota_bytes=2097152));rows=json.loads(comp('exec','-T','dovecot','doveadm','-c','/registry/active.conf','-f','json','quota','get','-u','contact@oxymot.fr').stdout);used=max(int({k.lower():v for k,v in x.items()}.get('value',0))*1024 for x in rows if str({k.lower():v for k,v in x.items()}.get('type','')).upper()=='STORAGE')
if used<1048576:probe("s=IMAP('dovecot',993,ssl_context=ctx,timeout=8);s.login('contact@oxymot.fr',cfg['contact']);assert s.append('INBOX',None,None,b'From: outside@dest.invalid\\r\\nSubject: retained disabled seed\\r\\n\\r\\n'+b'x'*1100000)[0]=='OK';s.logout();print(json.dumps({'seeded':True}))")
change(lambda r:r['mailboxes'][0].update(quota_bytes=1048576));tag='all-disabled-'+uuid.uuid4().hex
with concurrent.futures.ThreadPoolExecutor(1) as pool:
 future=pool.submit(helper,'/lab/transaction-probe.py','human-sessions',tag)
 for _ in range(100):
  if (control/(tag+'-ready')).exists():break
  time.sleep(.1)
 else:raise TimeoutError('human sessions not ready')
 client('send','-','outside@dest.invalid','contact@oxymot.fr',tag,'25');time.sleep(1);pending=ids();assert pending
 def disabled(r):r['mailboxes'][0].update(receive_enabled=False,imap_enabled=False,submission_enabled=False,quota_bytes=2097152);r['aliases']=[a for a in r['aliases'] if a['mailbox_id']!=r['mailboxes'][0]['id']]
 change(disabled);(control/(tag+'-release')).write_text('all disabled');sessions=json.loads(future.result().stdout);comp('exec','-T','postfix','postqueue','-c','/config','-f');time.sleep(2)
negative=probe("s=connect(25,None,False);s.mail('outside@dest.invalid');a=s.rcpt('contact@oxymot.fr')[0];b=s.rcpt('hello@oxymot.fr')[0];s.close();i=IMAP('dovecot',993,ssl_context=ctx,timeout=8)\ntry:i.login('contact@oxymot.fr',cfg['contact']);raise AssertionError('disabled IMAP accepted')\nexcept imaplib.IMAP4.error:pass\ni.logout();s=connect(587,None)\ntry:s.auth('PLAIN',lambda challenge=None:'\\0contact@oxymot.fr\\0'+cfg['contact']);raise AssertionError('disabled human SMTP accepted')\nexcept smtplib.SMTPAuthenticationError as e:assert e.smtp_code==535\ns.close();print(json.dumps({'primary':a,'retired_alias':b,'imap_refused':True,'human_smtp_refused':True}))");assert negative['primary']==negative['retired_alias']==550
change(lambda r:r['mailboxes'][0].update(imap_enabled=True));assert len(client('imap','contact@oxymot.fr',tag)['matches'])==1;change(lambda r:r['mailboxes'][0].update(imap_enabled=False));checks.append({'name':'all-disabled-retained-delivery-projection','status':'PASS','mailbox_id':'11111111-1111-4111-8111-111111111111','new_access':negative,'sessions':sessions,'accepted_before_disable_read_once_after_imap_only_reenable':True})
change(lambda r:(r['mailboxes'][0].update(receive_enabled=previous['mailboxes'][0]['receive_enabled'],imap_enabled=previous['mailboxes'][0]['imap_enabled'],submission_enabled=previous['mailboxes'][0]['submission_enabled'],quota_bytes=2097152),r.update(aliases=previous['aliases'])))
result={'status':'PASS_NATIVE_ACCEPTANCE_BOUNDARIES','checks':checks,'commands':commands};(root/'session-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'session-result.json'))
