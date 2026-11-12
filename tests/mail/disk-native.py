"""Only for a disposable guest profile on its dedicated bounded loop filesystem."""
import hashlib,json,os,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';commands=[];checks=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('disk command failed '+str(args[:3])+r.stdout.decode()[-200:])
 return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def probe(code):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'-c',"import sys,json,time;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import connect,IMAP,cfg,ctx;"+code]).stdout)
def client(*args):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/client.py',*args]).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
def observe():return json.loads(run(['node',str(repo/'tests/mail/api.cjs'),'observe',str(root/'config.json')]).stdout)
mount=json.loads(run(['findmnt','--json','--target',str(root),'-o','SOURCE,FSTYPE,SIZE']).stdout)['filesystems'][0];assert mount['source'].startswith('/dev/loop') and mount['fstype']=='ext4'
stat=os.statvfs(root);assert stat.f_blocks*stat.f_frsize<512*1024**2
old='disk-old-'+uuid.uuid4().hex;pending='disk-held-'+uuid.uuid4().hex
client('send','-','outside@dest.invalid','contact@oxymot.fr',old,'25');time.sleep(2);assert len(client('imap','contact@oxymot.fr',old)['matches'])==1
comp('stop','dovecot');client('send','-','outside@dest.invalid','contact@oxymot.fr',pending,'25');time.sleep(2);before=queue();assert before
filler=root.parent/'synthetic-disk-pressure.bin';assert not filler.exists()
try:
 free=os.statvfs(root).f_bavail*os.statvfs(root).f_frsize
 with open(filler,'xb') as f:os.posix_fallocate(f.fileno(),0,free-48*1024**2);f.flush();os.fsync(f.fileno())
 remaining=os.statvfs(root).f_bavail*os.statvfs(root).f_frsize
 result=probe("s=connect(25,None,False);a=s.mail('outside@dest.invalid');b=s.rcpt('contact@oxymot.fr');s.close();print(json.dumps({'mail_code':a[0],'rcpt_code':b[0]}))");assert 400<=result['mail_code']<500 or 400<=result['rcpt_code']<500
 after=queue();assert {q['queue_id'] for q in before}=={q['queue_id'] for q in after};checks.append({'name':'disk-admission-refuses-before-new-acceptance-and-preserves-pending-queue','status':'PASS','observation':{'remaining_bytes':remaining,'smtp':result,'queue_ids':[q['queue_id'] for q in after]}})
 obs=observe();(root/'disk-pressure-observation.json').write_text(json.dumps(obs,indent=2));codes=[a['code'] for a in obs['alerts']];assert 'MAIL_DISK_PRESSURE' in codes and 'MAIL_QUEUE_AGE' in codes;checks.append({'name':'disk-and-queue-age-alerts','status':'PASS','codes':codes})
finally:
 if filler.exists():filler.unlink()
 comp('start','dovecot')
comp('exec','-T','postfix','postqueue','-c','/config','-f')
for _ in range(60):
 found=client('imap','contact@oxymot.fr',pending)['matches']
 if found:break
 time.sleep(1)
assert len(found)==1 and len(client('imap','contact@oxymot.fr',old)['matches'])==1;checks.append({'name':'space-release-recovers-delivery-with-old-mail-and-one-pending-match','status':'PASS'})
data={'status':'PASS_BOUNDED_DISK_PRESSURE','mount':mount,'filesystem_bytes':stat.f_blocks*stat.f_frsize,'checks':checks,'commands':commands};(root/'disk-result.json').write_text(json.dumps(data,indent=2));print(json.dumps({'status':data['status'],'checks':checks}))
