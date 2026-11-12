"""Native independent registry flags, retained delivery IDs, quota changes and alerts."""
import copy,hashlib,json,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';checks=[];commands=[];ip=70
public=root/'service/durable/registry/public';reg=lambda:json.loads((public/'current.json').read_text())
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('registry command failed '+str(args[:3])+r.stdout.decode()[-200:])
 return r
def api(op,input=None,ok=True):
 args=['node',str(repo/'tests/mail/api.cjs'),op,str(root/'config.json')]
 if input is not None:
  file=root/('registry-request-'+uuid.uuid4().hex+'.json');file.write_text(json.dumps(input));file.chmod(0o600);args.append(str(file))
 return run(args,ok)
def change(fn,ok=True):
 next=reg();staged=[int(p.name.split('-')[-1]) for p in (root/'service/durable/registry/private').glob('generation-*')];next['generation']=max([next['generation'],*staged])+1;fn(next);return api('registry',next,ok)
def probe(code):
 global ip
 ip+=1
 return json.loads(run(['docker','run','--rm','--network',project+'-edge','--ip','10.243.47.'+str(ip),'--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'-c',"import sys,json,time,smtplib,imaplib;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import connect,IMAP,cfg,ctx;"+code]).stdout)
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def case(name,fn):
 try:detail=fn();checks.append({'name':name,'status':'PASS','observation':detail});print('PASS '+name,flush=True)
 except Exception as e:checks.append({'name':name,'status':'FAIL','reason':str(e)});print('FAIL '+name+': '+str(e),flush=True)
def receive():
 change(lambda r:r['mailboxes'][0].update(receive_enabled=False))
 try:
  value=probe("s=connect(25,None,False);s.mail('outside@dest.invalid');a=s.rcpt('contact@oxymot.fr')[0];b=s.rcpt('hello@oxymot.fr')[0];s.close();i=IMAP('dovecot',993,ssl_context=ctx,timeout=8);i.login('contact@oxymot.fr',cfg['contact']);assert i.select('INBOX')[0]=='OK';i.logout();s=connect();s.quit();print(json.dumps({'primary':a,'alias':b,'imap_and_app_smtp':True}))");assert value['primary']==value['alias']==550;return value
 finally:change(lambda r:r['mailboxes'][0].update(receive_enabled=True))
case('receive-disable-refuses-primary-and-alias-but-preserves-imap-and-app-smtp',receive)
def imap():
 change(lambda r:r['mailboxes'][0].update(imap_enabled=False))
 try:
  value=probe("s=connect(25,None,False);s.mail('outside@dest.invalid');a=s.rcpt('contact@oxymot.fr')[0];s.close();s=connect();s.quit();i=IMAP('dovecot',993,ssl_context=ctx,timeout=8)\ntry:i.login('contact@oxymot.fr',cfg['contact']);accepted=True\nexcept imaplib.IMAP4.error:accepted=False\ni.logout();print(json.dumps({'rcpt':a,'imap_authenticated':accepted}))");assert value['rcpt']==250 and not value['imap_authenticated'];return value
 finally:change(lambda r:r['mailboxes'][0].update(imap_enabled=True))
case('imap-disable-preserves-reception-and-app-submission',imap)
def human():
 change(lambda r:r['mailboxes'][0].update(submission_enabled=True))
 try:
  v=probe("s=connect(587,None);s.login('contact@oxymot.fr',cfg['contact']);a=s.mail('contact@oxymot.fr')[0];s.rset();b=s.mail('second@oxymot.fr')[0];s.close();print(json.dumps({'own':a,'foreign':b}))");assert v['own']==250 and v['foreign']>=500;return v
 finally:change(lambda r:r['mailboxes'][0].update(submission_enabled=False))
case('optional-human-submission-restricted-to-own-address',human)
def alias():
 change(lambda r:r['aliases'][0].update(receive_enabled=False))
 try:
  v=probe("s=connect(25,None,False);s.mail('outside@dest.invalid');a=s.rcpt('hello@oxymot.fr')[0];b=s.rcpt('contact@oxymot.fr')[0];s.close();print(json.dumps({'retired_alias':a,'primary':b}))");assert v=={'retired_alias':550,'primary':250};return v
 finally:change(lambda r:r['aliases'][0].update(receive_enabled=True))
case('retired-alias-refused-while-primary-remains',alias)
def retain():
 result=change(lambda r:(r.update(mailboxes=r['mailboxes'][1:],aliases=[a for a in r['aliases'] if a['mailbox_id']!='11111111-1111-4111-8111-111111111111']),r['accounts'][0].update(envelope_from=['second@oxymot.fr'],header_from=['second@oxymot.fr'],credential_generation=r['accounts'][0]['credential_generation']+1)),False)
 assert result.returncode and json.loads(result.stdout)['code']=='MAIL_RETAINED_DELIVERY_IDENTITY_REQUIRED';assert not (public/'admission-closed').exists();return {'code':json.loads(result.stdout)['code']}
case('mailbox-removal-refuses-loss-of-retained-delivery-identity',retain)
def grants():
 result=change(lambda r:r['accounts'][0].update(header_from=['second@oxymot.fr']),False)
 assert result.returncode and json.loads(result.stdout)['code']=='MAIL_CREDENTIAL_GENERATION_REQUIRED';return {'code':json.loads(result.stdout)['code']}
case('grant-change-requires-new-credential-generation',grants)
# Quota reduction preserves accepted messages; it is not an atomic concurrent quota fix.
def quota():
 change(lambda r:r['mailboxes'][0].update(quota_bytes=2097152))
 v=probe("i=IMAP('dovecot',993,ssl_context=ctx,timeout=8);i.login('contact@oxymot.fr',cfg['contact']);a=i.append('INBOX',None,None,b'From: quota@dest.invalid\\r\\nSubject: retained quota change\\r\\n\\r\\n'+b'x'*1150000)[0];i.logout();print(json.dumps({'append':a}))");assert v['append']=='OK'
 change(lambda r:r['mailboxes'][0].update(quota_bytes=1048576));observation=json.loads(api('observe').stdout);codes=[a['code'] for a in observation['alerts']];assert 'MAIL_QUOTA_HIGH' in codes and 'MAIL_QUOTA_AT_LIMIT' in codes
 tag='retained-disabled-'+uuid.uuid4().hex
 v=probe("s=connect(25,None,False);s.sendmail('outside@dest.invalid',['contact@oxymot.fr'],'From: outside@dest.invalid\\r\\nSubject: "+tag+"\\r\\n\\r\\n"+tag+"');s.quit();print(json.dumps({'accepted':True}))");time.sleep(2);q=[json.loads(l) for l in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()];assert q
 change(lambda r:r['mailboxes'][0].update(receive_enabled=False,quota_bytes=2097152));comp('exec','-T','postfix','postqueue','-c','/config','-f');time.sleep(2)
 v=probe("i=IMAP('dovecot',993,ssl_context=ctx,timeout=8);i.login('contact@oxymot.fr',cfg['contact']);i.select('INBOX');a=i.search(None,'TEXT','"+tag+"')[1][0].split();i.logout();print(json.dumps({'matches':len(a)}))");assert v['matches']==1
 change(lambda r:r['mailboxes'][0].update(receive_enabled=True));(root/'quota-alert-observation.json').write_text(json.dumps(observation,indent=2));return {'quota_alerts':codes,'accepted_queued_message_delivered_after_receive_disable':True,'mail_preserved':True}
case('quota-change-alerts-and-retained-accepted-local-delivery',quota)
def incomplete():
 marker=public/'admission-closed';assert not marker.exists();marker.write_text('synthetic incomplete qualification generation')
 try:
  value=json.loads(api('observe').stdout);assert 'MAIL_GENERATION_INCOMPLETE' in [a['code'] for a in value['alerts']];return {'alert':'MAIL_GENERATION_INCOMPLETE'}
 finally:marker.unlink()
case('incomplete-generation-alert',incomplete)
observation=json.loads(api('observe').stdout);(root/'alerts-result.json').write_text(json.dumps(observation,indent=2))
data={'status':'PASS_NATIVE_REGISTRY_CONTROLS' if all(c['status']=='PASS' for c in checks) else 'FAIL_NATIVE_REGISTRY_CONTROLS','checks':checks,'commands':commands};(root/'registry-result.json').write_text(json.dumps(data,indent=2));print('REPORT '+str(root/'registry-result.json'))
