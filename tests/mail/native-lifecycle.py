"""Explicit isolated operator test using private synthetic source fixtures."""
import hashlib,json,os,pathlib,subprocess,sys,tempfile,uuid
repo=pathlib.Path(__file__).resolve().parents[2];source=pathlib.Path(sys.argv[1]);root=pathlib.Path(tempfile.mkdtemp(prefix='mail02-profile-'));project='mail02-profile-'+uuid.uuid4().hex[:8];commands=[]
def run(args,ok=True):
 p=subprocess.run(args,capture_output=True,timeout=120)
 commands.append({'argv':args,'exit':p.returncode,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr).hexdigest()})
 if ok and p.returncode:raise RuntimeError('operator qualification failed: '+p.stdout.decode()[-500:]+p.stderr.decode()[-500:])
 return p
def operator(verb,execute=False,ok=True):
 return run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail',verb,'--config',str(root/'config.json')]+(['--execute'] if execute else []),ok)
def identities():
 p=run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]);return sorted(p.stdout.decode().split())
previous=json.loads((source/'prepared.json').read_text());spec=previous['plan']['spec'];spec['deployment'].update({'id':project,'project':project,'root':str(root/'service'),'backup_root':str(root/'backups')})
registry=json.loads((source/'service/durable/registry/public/current.json').read_text());verifiers=json.loads((source/'rotate-input.json').read_text())['verifiers']
for name,value in [('registry.json',registry),('verifiers.json',verifiers)]:
 (root/name).write_text(json.dumps(value));(root/name).chmod(0o600)
cfg={'distribution':{'profile':'mail'},'service':spec,'registry_file':str(root/'registry.json'),'verifiers_file':str(root/'verifiers.json'),'secret_sources':previous['plan']['secret_sources'],'acceptance':True};(root/'config.json').write_text(json.dumps(cfg));(root/'config.json').chmod(0o600)
network=project+'-foreign-test';created=False;checks=[]
try:
 operator('validate');checks.append('profile-validation')
 operator('install',True);ids=identities();assert len(ids)==4;operator('status');checks.append('four-owned-services-start-and-status')
 operator('install',True);assert identities()==ids;checks.append('repeat-install-preserves-container-identities')
 run(['docker','network','create','--internal',network]);created=True;run(['docker','network','connect',network,ids[0]])
 denied=operator('status',ok=False);assert denied.returncode==1 and json.loads(denied.stdout)['code']=='MAIL_RUNTIME_NETWORK_MISMATCH';checks.append('extra-runtime-network-refused')
 run(['docker','network','disconnect',network,ids[0]]);operator('status');operator('stop',True);checks.append('stop-retains-durable-owned-storage')
 assert (root/'service/durable/spool/.infra-owner').exists() and (root/'service/durable/mailboxes/.infra-owner').exists()
 result={'status':'PASS_ISOLATED_PROFILE_LIFECYCLE','project':project,'private_root':str(root),'checks':checks,'commands':commands,'infra_receipt':json.loads((repo/'profiles/mail/infra-source-lock.json').read_text())}
 (root/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'report':str(root/'result.json'),'checks':checks}))
finally:
 if created:run(['docker','network','rm',network],False)
 prepared=root/'service/durable/operator-state/prepared.json'
 if prepared.exists():
  p=json.loads(prepared.read_text());run(['docker','compose','-p',project,'-f',p['compose_file'],'down'],False)
