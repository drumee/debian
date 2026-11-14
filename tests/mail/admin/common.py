"""Real drumee-ctl against an isolated canonical profile; public receipts only."""
import hashlib,json,os,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[3];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(__file__).resolve().parent;cfg=root/'config.json';p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];checks=[];commands=[];passwords={};private=root/'admin-probe';private.mkdir(mode=0o700,exist_ok=True);password_file=private/'passwords.json'
def remember(values):
 file=private/'synthetic-secrets.json';known=json.loads(file.read_text()) if file.exists() else [];file.write_text(json.dumps(sorted(set(known+list(values)))));file.chmod(0o600)
def write_passwords():remember(passwords.values());password_file.write_text(json.dumps(passwords));password_file.chmod(0o600)
def run(args,input=None,pass_fds=()):
 r=subprocess.run(args,input=input,capture_output=True,pass_fds=pass_fds,timeout=180);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});return r
def cli(family,verb=None,selector=None,opts=(),password=None,request=None,revision=None,expected='OK',mutate=False):
 args=['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail',family]+([verb] if verb else [])+([selector] if selector else [])+list(opts)+['--config',str(cfg),'--json'];fd=None
 if mutate:args+=['--execute','--if-revision',str(state['revision'] if revision is None else revision),'--request-id',request or str(uuid.uuid4())]
 if password is not None:
  remember([password])
  file=private/'input-password';file.write_text(password);file.chmod(0o600);fd=os.open(file,os.O_RDONLY);args+=['--password-fd',str(fd)]
 try:r=run(args,pass_fds=(() if fd is None else (fd,)))
 finally:
  if fd is not None:os.close(fd)
 data=json.loads(r.stdout);assert data['contract']=='drumee.mail-cli/1' and data['code']==expected,(data,r.stderr[-100:]);assert (r.returncode==0)==(expected=='OK');assert not any(value.encode() in r.stdout+r.stderr for value in passwords.values())
 if data['ok']:state['revision']=data['applied_revision']
 return data
state={'revision':0};state['revision']=cli('status')['applied_revision']
def check(name,observation):checks.append({'name':name,'status':'PASS','observation':observation});print('PASS',name,flush=True)
def probe(**request):
 write_passwords();args=['docker','run','--rm','-i','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={private},target=/private,readonly','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','/lab/probe.py'];r=run(args,json.dumps(request).encode());assert r.returncode==0;return json.loads(r.stdout)
def wait_read(user,tag):
 for _ in range(30):
  d=probe(action='imap',user=user,tag=tag)
  if d.get('matches')==1:return d
  time.sleep(.2)
 raise AssertionError('not delivered')
