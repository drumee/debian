"""Pre-existing network/volume negatives. Synthetic target resources remain intact."""
import copy,hashlib,json,pathlib,subprocess,sys,tempfile,uuid
repo=pathlib.Path(__file__).resolve().parents[2];source=pathlib.Path(sys.argv[1]);original=json.loads((source/'config.json').read_text());checks=[];commands=[];retained=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('foreign resource fixture failed '+str(args[:3]))
 return r
def inspect(kind,name):return json.loads(run(['docker',kind,'inspect',name]).stdout)[0]
for index,kind in enumerate(['edge-owner','edge-internal','edge-ipam','control-owner','control-internal','volume-owner','volume-options']):
 root=pathlib.Path(tempfile.mkdtemp(prefix='mail02-foreign-'));cfg=copy.deepcopy(original);project='mail02-foreign-'+uuid.uuid4().hex[:8];cfg['service']['deployment'].update(id=project,project=project,root=str(root/'service'),backup_root=str(root/'backups'));cfg['service']['networks'].update(edge_subnet=f'10.243.{60+index}.0/24',edge_gateway=f'10.243.{60+index}.1');cfg['service']['networks']['private_submission']['address']=f'10.243.{60+index}.1';cfg['acceptance_private_listener']=False;file=root/'config.json';file.write_text(json.dumps(cfg));file.chmod(0o600);run(['node',str(repo/'tests/mail/api.cjs'),'prepare',str(file)]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());owner=project if not kind.endswith('owner') else 'synthetic-foreign-owner';name=project+('-sockets' if kind.startswith('volume') else '-control' if kind.startswith('control') else '-edge');resource='volume' if kind.startswith('volume') else 'network'
 if resource=='network':
  args=['docker','network','create','--label','org.drumee.mail.owner='+owner,'--label','drumee.qualification.owner='+project]
  if not kind.endswith('internal'):args.append('--internal')
  if kind.startswith('edge'):
   args+=['--subnet',f'10.243.{160+index if kind.endswith("ipam") else 60+index}.0/24','--gateway',f'10.243.{160+index if kind.endswith("ipam") else 60+index}.1']
  run([*args,name])
 else:
  run(['docker','volume','create','--label','org.drumee.mail.owner='+owner,'--label','drumee.qualification.owner='+project,name])
  run(['docker','run','--rm','--network','none','--mount','type=volume,source='+name+',target=/data','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-c',"import pathlib;pathlib.Path('/data/retained.txt').write_text('pre-existing synthetic target data')"])
 before=inspect(resource,name);result=run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','start','--config',str(file),'--execute'],False);assert result.returncode;code=json.loads(result.stdout)['code'];assert code==('MAIL_RUNTIME_STORAGE_MISMATCH' if resource=='volume' else 'MAIL_RUNTIME_NETWORK_MISMATCH'),code;assert not run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]).stdout.strip();after=inspect(resource,name);assert before==after
 if resource=='volume':assert run(['docker','run','--rm','--network','none','--read-only','--mount','type=volume,source='+name+',target=/data,readonly','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-c',"import pathlib;assert pathlib.Path('/data/retained.txt').read_text()=='pre-existing synthetic target data'"]).returncode==0
 checks.append({'name':kind,'status':'PASS','code':code,'no_core_exposure':True,'target_identity_unchanged':True});retained.append({'root':str(root),'type':resource,'name':name,'id':after.get('Id',after.get('Name'))});print(json.dumps(checks[-1]),flush=True)
data={'status':'PASS_FOREIGN_RESOURCE_CONTROLS','checks':checks,'retained_targets':retained,'commands':commands};(source/'foreign-resource-result.json').write_text(json.dumps(data,indent=2));print('REPORT '+str(source/'foreign-resource-result.json'))
