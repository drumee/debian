"""Native IMAP/LMTP write errors must rollback capacity and preserve accepted queue."""
import hashlib,json,pathlib,subprocess,sys,time,uuid
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';commands=[];box=root/'service/durable/mailboxes/22222222-2222-4222-8222-222222222222'
def run(args):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});assert r.returncode==0,r.stderr.decode()[-300:];return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def meta(code):return run(['docker','run','--rm','--network','none','--mount',f'type=bind,source={box},target=/box','--entrypoint','python3',image,'-c',code])
def helper(*args):return run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,*args])
def probe(code):return json.loads(helper('-c',"import sys,json,imaplib;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import IMAP,cfg,ctx;"+code).stdout)
mode="import pathlib,os; p=pathlib.Path('/box/Maildir/tmp');assert p.is_dir() and not p.is_symlink() and p.stat().st_uid==5000;os.chmod(p,"
tag='write-failure-'+uuid.uuid4().hex
try:
 meta(mode+'0o500)');observed=probe("s=IMAP('dovecot',993,ssl_context=ctx,timeout=8);s.login('second@oxymot.fr',cfg['second']);code=s.append('INBOX',None,None,b'From: outside@dest.invalid\\r\\nSubject: refused write\\r\\n\\r\\nsynthetic')[0];assert code=='NO';s.logout();print(json.dumps({'imap_append':code}))")
 json.loads(helper('/lab/client.py','send','-','outside@dest.invalid','second@oxymot.fr',tag,'25').stdout);time.sleep(2);queued=[json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()];assert queued
finally:meta(mode+'0o700)')
lock=json.loads(meta("import fcntl,json;f=open('/box/home/.drumee-quota.lock','rb');fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);print(json.dumps({'released_after_error':True}))").stdout);assert lock['released_after_error']
comp('exec','-T','postfix','postqueue','-c','/config','-f')
for _ in range(40):
 found=json.loads(helper('/lab/client.py','imap','second@oxymot.fr',tag).stdout)['matches']
 if found:break
 time.sleep(.5)
assert len(found)==1;after=probe("s=IMAP('dovecot',993,ssl_context=ctx,timeout=8);s.login('second@oxymot.fr',cfg['second']);code=s.append('INBOX',None,None,b'From: outside@dest.invalid\\r\\nSubject: recovered write\\r\\n\\r\\nsynthetic')[0];assert code=='OK';s.logout();print(json.dumps({'imap_append':code}))")
result={'status':'PASS_NATIVE_WRITE_FAILURE_ROLLBACK','refusal':observed,'kernel_lock':lock,'accepted_queue_ids':[q['queue_id'] for q in queued],'observed_delivery_after_permission_recovery':len(found),'new_write':after,'commands':commands};(root/'write-failure-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='commands'}))
