"""Native signer outage must defer before final acceptance; operational aliases deliver locally.
The client deadline includes Docker DNS resolution of a withdrawn service alias.
A timeout/disconnect is a failed probe; require an explicit native 4xx and no new queue.
"""
import hashlib,json,pathlib,subprocess,sys,time,uuid
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';commands=[]
def run(args):
 r=subprocess.run(args,capture_output=True,timeout=240);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});assert r.returncode==0,r.stderr.decode()[-1000:];return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def helper(*args):return run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,*args])
before=comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout;comp('stop','opendkim')
try:
 code="""import sys,json,smtplib,time;sys.path.insert(0,'/lab');sys.argv=['probe','probe'];from client import ctx,cfg
started=time.monotonic()
try:
 with smtplib.SMTP('postfix',587,timeout=180) as s:
  s.ehlo('fixture.invalid');s._host='mail.oxymot.fr';s.starttls(context=ctx);s.ehlo('fixture.invalid');s.login('oxymotion',cfg['oxymotion'])
  s.sendmail('second@oxymot.fr',['second@oxymot.fr'],'From: second@oxymot.fr\\r\\nSubject: synthetic signer outage\\r\\n\\r\\nnot accepted')
 raise AssertionError('missing signer accepted')
except smtplib.SMTPResponseException as e:assert 400<=e.smtp_code<500;print(json.dumps({'temporary_code':e.smtp_code,'before_final_acceptance':True,'elapsed_seconds':time.monotonic()-started}))
"""
 result=json.loads(helper('-c',code).stdout);after=comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout;assert before==after
finally:comp('start','opendkim')
routes=[]
for prefix in ['postmaster','abuse']:
 tag=prefix+'-'+uuid.uuid4().hex;helper('/lab/client.py','send','-','outside@dest.invalid',prefix+'@oxymot.fr',tag,'25');time.sleep(2);read=json.loads(helper('/lab/client.py','imap','second@oxymot.fr',tag).stdout);assert len(read['matches'])==1;routes.append({'address':prefix+'@oxymot.fr','mailbox':'22222222-2222-4222-8222-222222222222','matches':1})
data={'status':'PASS_NATIVE_SIGNER_OUTAGE_AND_OPERATIONAL_ROUTES','signer_outage':result,'queue_unchanged':True,'operational_routes':routes,'commands':commands};(root/'signing-result.json').write_text(json.dumps(data,indent=2));print(json.dumps({k:v for k,v in data.items() if k!='commands'}))
