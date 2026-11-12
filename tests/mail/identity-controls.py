"""Activation must refuse each identity drift before a mail process starts."""
import copy,hashlib,json,pathlib,subprocess,sys,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);prepared=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=prepared['project'];commands=[];checks=[]
nodeimage=prepared['compose']['services']['policy']['image'];clientimage='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8'
def run(args,ok=True):
 p=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':p.returncode,'stdout_sha256':hashlib.sha256(p.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr).hexdigest()})
 if ok and p.returncode:raise RuntimeError('identity test command failed '+str(args[:3]))
 return p
def d(*args,**kw):return run(['docker',*args],**kw)
def comp(*args,**kw):return d('compose','-p',project,'-f',prepared['compose_file'],*args,**kw)
def operator(op,ok=True):return run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail',op,'--config',str(root/'config.json'),'--execute'],ok)
def snapshot():
 code="import pathlib,os,stat,json,hashlib;r=pathlib.Path('/data');o={};[(o.update({str(p.relative_to(r)):{'uid':s.st_uid,'gid':s.st_gid,'mode':stat.S_IMODE(s.st_mode),'ino':s.st_ino,'link':os.readlink(p) if stat.S_ISLNK(s.st_mode) else None,'sha256':hashlib.sha256(p.read_bytes()).hexdigest() if stat.S_ISREG(s.st_mode) else None}})) for p in r.rglob('*') for s in [p.lstat()]];print(hashlib.sha256(json.dumps(o,sort_keys=True).encode()).hexdigest())"
 return d('run','--rm','--network','none','--read-only','--mount',f'type=bind,source={root}/service,target=/data,readonly','--entrypoint','python3',clientimage,'-c',code).stdout.decode().strip()
def no_running():return not d('ps','-q','--filter','label=com.docker.compose.project='+project).stdout.strip()
def rejected(codes):
 before=snapshot();result=operator('start',False);assert result.returncode and json.loads(result.stdout)['code'] in codes,(result.returncode,result.stdout.decode());assert no_running();assert snapshot()==before;return {'code':json.loads(result.stdout)['code'],'before_exposure':True,'data_unchanged':True}
def case(name,fn):
 before=snapshot()
 try:detail=fn();assert snapshot()==before;checks.append({'name':name,'status':'PASS','observation':detail});print('PASS '+name,flush=True)
 except Exception as e:checks.append({'name':name,'status':'FAIL','reason':str(e)});print('FAIL '+name+': '+str(e),flush=True)
 finally:comp('stop',ok=False)
def file_change(file,mutate,codes):
 original=file.read_bytes();mode=file.stat().st_mode&0o777
 try:mutate(file);return rejected(codes)
 finally:file.write_bytes(original);file.chmod(mode)
def rootfile(file,operation,*args):
 code="const f=require('node:fs'),p='/data/'+process.argv[1];if(process.argv[2]==='write')f.writeFileSync(p,process.argv[3]);else if(process.argv[2]==='chown')f.chownSync(p,Number(process.argv[3]),Number(process.argv[4]));"
 return d('run','--rm','--network','none','--read-only','--user','0:0','--mount',f'type=bind,source={root}/service,target=/data','--entrypoint','node',nodeimage,'-e',code,str(file.relative_to(root/'service')),operation,*map(str,args))
operator('stop');assert no_running()
case('prepared-compose-listener-injection',lambda:file_change(pathlib.Path(prepared['compose_file']),lambda p:p.write_text(p.read_text().replace('"name":','"unrecognized":',1)),['MAIL_PREPARED_TAMPERED']))
def extra():
 p=pathlib.Path(prepared['compose_file']).parent/'config/unexpected.cf';p.write_text('untrusted configuration')
 try:return rejected(['MAIL_PREPARED_TAMPERED'])
 finally:p.unlink()
case('closed-candidate-config-inventory',extra)
key=pathlib.Path(prepared['compose_file']).parent/'keys/tls/key.pem'
case('unsafe-private-key-permissions',lambda:file_change(key,lambda p:p.chmod(0o644),['MAIL_PREPARED_TAMPERED']))
owner=root/'service/owner.json'
case('foreign-resource-owner',lambda:file_change(owner,lambda p:p.write_text(p.read_text().replace(project,'foreign-owner')),['MAIL_RESOURCE_IDENTITY_MISMATCH']))
marker=root/'service/durable/spool/.infra-owner'
def wrong_marker():
 original=marker.read_text()
 try:rootfile(marker,'write','{"owner":"foreign","resource":"mail-queue"}');return rejected(['MAIL_STORAGE_GUARD_FAILED'])
 finally:rootfile(marker,'write',original)
case('foreign-spool-marker',wrong_marker)
def replaced_spool():
 spool=root/'service/durable/spool';saved=spool.with_name('spool-retained');spool.rename(saved)
 try:
  spool.mkdir(mode=0o700);(spool/'.infra-owner').write_bytes((saved/'.infra-owner').read_bytes());(spool/'target-retained.txt').write_text('pre-existing replacement target data')
  before=(spool/'target-retained.txt').read_bytes();result=rejected(['MAIL_STORAGE_GUARD_FAILED']);assert (spool/'target-retained.txt').read_bytes()==before;return result
 finally:
  spool.rename(root/('foreign-target-retained-'+uuid.uuid4().hex));saved.rename(spool)
case('replacement-directory-with-copied-owner-marker',replaced_spool)
private=root/'service/durable/registry/private';pointer=private/'current'
def wrong_projection():
 saved=private/'current-retained';pointer.rename(saved);pointer.symlink_to('../public')
 try:return rejected(['MAIL_SECRET_PROJECTION_MISMATCH'])
 finally:pointer.unlink();saved.rename(pointer)
case('foreign-secret-projection-pointer',wrong_projection)
passwd=private/pointer.readlink()/'smtp.passwd'
case('changed-verifier-projection',lambda:file_change(passwd,lambda p:p.write_bytes(p.read_bytes()+b'\n# modified'),['MAIL_PREPARED_TAMPERED']))
box=root/'service/durable/mailboxes/11111111-1111-4111-8111-111111111111'
def wrong_box_owner():
 try:rootfile(box,'chown',5001,5000);return rejected(['MAIL_MAILBOX_IDENTITY_MISMATCH'])
 finally:rootfile(box,'chown',5000,5000)
case('foreign-mailbox-numeric-owner',wrong_box_owner)
# Runtime metadata is altered only on stopped containers, never exposed first.
def container_change(role,change,codes):
 comp('rm','-f',role);spec=copy.deepcopy(prepared['compose']);change(spec['services'][role]);file=root/('create-negative-'+uuid.uuid4().hex+'.json');file.write_text(json.dumps(spec));file.chmod(0o600)
 try:
  d('compose','-p',project,'-f',str(file),'create',role);assert no_running();return rejected(codes)
 finally:comp('rm','-f',role);comp('create',role)
case('wrong-native-image',lambda:container_change('postfix',lambda s:s.update(image=clientimage),['MAIL_RUNTIME_IMAGE_MISMATCH']))
case('unreviewed-environment',lambda:container_change('postfix',lambda s:s.update(environment={'MAIL_CONFIG':'/etc/postfix'}),['MAIL_RUNTIME_EXECUTION_MISMATCH']))
case('wrong-runtime-user',lambda:container_change('dovecot',lambda s:s.update(user='5000:5000'),['MAIL_RUNTIME_EXECUTION_MISMATCH']))
case('undeclared-listener',lambda:container_change('postfix',lambda s:s.update(ports=[{'target':587,'published':22587,'host_ip':'127.0.0.1'}]),['MAIL_RUNTIME_LISTENER_MISMATCH']))
def mount_change(service):service['volumes'][0]['read_only']=False
case('writable-configuration-mount',lambda:container_change('postfix',mount_change,['MAIL_RUNTIME_MOUNT_MISMATCH']))
def restart_change(service):service['restart']='unless-stopped'
case('automatic-start-cannot-bypass-boot-guard',lambda:container_change('postfix',restart_change,['MAIL_RUNTIME_EXECUTION_MISMATCH']))
network=project+'-negative-extra'
def extra_network():
 d('network','create','--internal',network)
 try:
  d('network','connect',network,project+'-postfix-1');return rejected(['MAIL_RUNTIME_NETWORK_MISMATCH'])
 finally:d('network','disconnect',network,project+'-postfix-1');d('network','rm',network)
case('extra-runtime-network',extra_network)
# Every durable identity is exercised without starting a mail writer.
for storage_name in prepared['storage']:
 directory=root/'service/durable'/storage_name
 def missing(directory=directory):
  retained=directory.with_name(directory.name+'-guard-retained');directory.rename(retained)
  try:return rejected(['UNSAFE_RESOURCE_PATH','RESOURCE_MISSING','MAIL_OPERATION_FAILED','MAIL_STORAGE_GUARD_FAILED'])
  finally:retained.rename(directory)
 case('missing-durable-'+storage_name,missing)
 def replacement(directory=directory):
  retained=directory.with_name(directory.name+'-guard-retained');directory.rename(retained);directory.mkdir(mode=0o700);(directory/'target-retained.txt').write_text('pre-existing synthetic target')
  try:return rejected(['UNSAFE_RESOURCE_PATH','RESOURCE_MISSING','MAIL_OPERATION_FAILED','MAIL_STORAGE_GUARD_FAILED'])
  finally:directory.rename(root/('replacement-target-retained-'+uuid.uuid4().hex));retained.rename(directory)
 case('replacement-durable-'+storage_name,replacement)
 original_mode=directory.stat().st_mode&0o777
 def permissions(directory=directory,mode=original_mode):
  try:directory.chmod(0o777);return rejected(['RESOURCE_PERMISSIONS_UNSAFE','MAIL_STORAGE_GUARD_FAILED','MAIL_OPERATION_FAILED'])
  finally:directory.chmod(mode)
 case('unsafe-permissions-durable-'+storage_name,permissions)
 original_gid=directory.stat().st_gid;original_uid=directory.stat().st_uid
 def group(directory=directory,gid=original_gid,uid=original_uid):
  try:rootfile(directory,'chown',uid,5001);return rejected(['MAIL_STORAGE_GUARD_FAILED'])
  finally:rootfile(directory,'chown',uid,gid)
 case('foreign-numeric-group-'+storage_name,group)
operator('preflight');operator('start');result={'status':'PASS_NATIVE_IDENTITY_CONTROLS' if all(x['status']=='PASS' for x in checks) else 'FAIL_NATIVE_IDENTITY_CONTROLS','checks':checks,'commands':commands,'source_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()};(root/'identity-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'identity-result.json'))
