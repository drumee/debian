"""Fresh synthetic mailbox: quota-full queue resumes after expunging only this test's seed."""
import hashlib,json,pathlib,subprocess,sys,time,uuid
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];tag='quota-release-'+uuid.uuid4().hex;commands=[];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8'
def run(args):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});assert r.returncode==0,r.stderr.decode()[-600:];return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def helper(code):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'-c',"import sys,json,imaplib,smtplib,re;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import IMAP,ctx,cfg;tag="+repr(tag)+';'+code]).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
assert not queue();seed=helper("s=IMAP('dovecot',993,ssl_context=ctx,timeout=20);s.login('second@oxymot.fr',cfg['second']);s.select('INBOX');assert not s.search(None,'ALL')[1][0];assert s.create(tag)[0]=='OK';wire=('From: outside@dest.invalid\\r\\nMessage-ID: <'+tag+'-seed@fixture.invalid>\\r\\n\\r\\n').encode()+b'x'*800000;assert s.append(tag,None,None,wire)[0]=='OK';s.logout();c=smtplib.SMTP('postfix',25,timeout=20);c.ehlo();assert c.mail('outside@dest.invalid')[0]==250;assert c.rcpt('second@oxymot.fr')[0]==250;code,response=c.data(('From: outside@dest.invalid\\r\\nMessage-ID: <'+tag+'-pending@fixture.invalid>\\r\\n\\r\\n').encode()+b'y'*500000);assert code==250;q=re.search(rb'queued as ([A-Z0-9]+)',response).group(1).decode();c.quit();print(json.dumps({'queue_id':q,'smtp_final_code':code,'seed_bytes':len(wire)}))")
for _ in range(80):
 pending=next((x for x in queue() if x['queue_id']==seed['queue_id'] and x['queue_name']=='deferred' and any('452' in y.get('delay_reason','') and 'quota' in y.get('delay_reason','').lower() for y in x['recipients'])),None)
 if pending:break
 time.sleep(.25)
assert pending
freed=helper("s=IMAP('dovecot',993,ssl_context=ctx,timeout=20);s.login('second@oxymot.fr',cfg['second']);s.select('INBOX');assert not s.search(None,'HEADER','Message-ID',tag+'-pending')[1][0];s.select(tag);ids=s.search(None,'HEADER','Message-ID',tag+'-seed')[1][0];assert len(ids.split())==1;assert s.store(ids,'+FLAGS','(\\\\Deleted)')[0]=='OK';assert s.expunge()[0]=='OK';assert not s.search(None,'ALL')[1][0];s.select('INBOX');assert s.delete(tag)[0]=='OK';s.logout();print(json.dumps({'only_owned_seed_expunged':True}))")
comp('exec','-T','postfix','postqueue','-c','/config','-f')
for _ in range(60):
 observed=helper("s=IMAP('dovecot',993,ssl_context=ctx,timeout=20);s.login('second@oxymot.fr',cfg['second']);s.select('INBOX');ids=s.search(None,'HEADER','Message-ID',tag+'-pending')[1][0];n=len(ids.split());s.logout();print(json.dumps({'matches':n}))")
 if observed['matches']:break
 time.sleep(.3)
assert observed['matches']==1 and not any(x['queue_id']==seed['queue_id'] for x in queue());result={'status':'PASS_NATIVE_QUOTA_EXPUNGE_RELEASE','accepted':seed,'deferred_before_release':pending,'release':freed,'after_release':observed,'quota_unchanged_bytes':1048576,'driver_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'commands':commands};(root/'quota-release-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'queue_id':seed['queue_id'],'matches':observed['matches']}))
