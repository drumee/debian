#!/usr/bin/python3
"""Explicit cold checkpoint/replacement-storage protocol; normal start never repairs.

The logical root and transport contract stay fixed. Mount a distinct ext4 device
at that root only after the source has been stopped, fenced and preserved.
"""
import argparse,hashlib,json,os,pathlib,resource,sqlite3,stat,subprocess,sys,time,uuid
sys.path.insert(0,str(pathlib.Path(__file__).parent))
from storage import atomic,encode,private_read,safe_directory,service_lock,syncdir,check_runtime
from model import Refusal,refuse
BASE=pathlib.Path(__file__).parents[1]
LOCK_FD=None
HELPER='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8'
ENV={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':'/'}

def run(args,data=None):
 p=subprocess.run([str(x) for x in args],input=data,capture_output=True,env=ENV,timeout=600,pass_fds=(() if LOCK_FD is None else (LOCK_FD,)))
 if p.returncode:refuse('MAIL_CHECKPOINT_DEPENDENCY_FAILED')
 return p.stdout

def jsonfile(p):return json.loads(private_read(p))
def write(p,v):atomic(p,encode(v).encode())
def ident(p):s=pathlib.Path(p).stat();return {'device':s.st_dev,'inode':s.st_ino}
def containers():
 ids=run(['/usr/bin/docker','ps','-q']).decode().split()
 return json.loads(run(['/usr/bin/docker','inspect',*ids])) if ids else []
def no_writers(root):
 for c in containers():
  if any(m.get('Type')=='bind' and (m['Source']==str(root) or m['Source'].startswith(str(root)+'/')) for m in c['Mounts']):refuse('MAIL_RECOVERY_WRITERS_PRESENT')

def mount(root,expected=None):
 d=json.loads(run(['/usr/bin/findmnt','-J','-o','TARGET,UUID,FSTYPE','--target',root]))['filesystems'][0]
 if d['target']!=str(root) or d['fstype']!='ext4' or not d.get('uuid'):refuse('MAIL_RESTORE_DEDICATED_MOUNT_REQUIRED')
 if expected is not None and d['uuid']!=expected:refuse('MAIL_RESTORE_TARGET_UNAUTHORIZED')
 return d['uuid']

def worker(action,archive,root=None,metadata=None,expected=None):
 if action=='quiet':
  p=subprocess.run(['/usr/bin/sudo','-n','/usr/bin/python3','-I',str(BASE/'admin/checkpoint_worker.py'),'--quiet-host',str(root)],capture_output=True,env=ENV,timeout=60)
  try:result=json.loads(p.stdout)
  except ValueError:refuse('MAIL_RECOVERY_WRITER_SCAN_INCOMPLETE')
  if p.returncode or not result.get('ok'):refuse(result.get('code','MAIL_RECOVERY_WRITER_SCAN_INCOMPLETE'))
  return result['data']
 image=run(['/usr/bin/docker','image','inspect',HELPER,'--format','{{.Id}}']).decode().strip()
 if image!=HELPER:refuse('MAIL_IMAGE_IDENTITY_MISMATCH')
 args=['/usr/bin/docker','run','--rm','-i','--network','none','--read-only','--cap-drop','ALL','--cap-add','DAC_OVERRIDE','--cap-add','CHOWN','--cap-add','FOWNER','--security-opt','no-new-privileges:true','--memory','536870912','--pids-limit','32','--mount','type=bind,source='+str(BASE/'admin/checkpoint_worker.py')+',target=/worker.py,readonly','--mount','type=bind,source='+str(archive)+',target=/archive'+('' if action=='capture' else ',readonly')]
 if root:args+=['--mount','type=bind,source='+str(root)+',target='+('/source,readonly' if action in ('capture','quiet') else '/target')]
 p=subprocess.run([*args,'--entrypoint','python3',HELPER,'-B','/worker.py'],input=encode(dict(action=action,metadata=metadata,expected=expected)).encode(),capture_output=True,env=ENV,timeout=600,pass_fds=(() if LOCK_FD is None else (LOCK_FD,)))
 try:result=json.loads(p.stdout)
 except ValueError:refuse('MAIL_CHECKPOINT_DEPENDENCY_FAILED')
 if p.returncode or not result.get('ok'):refuse(result.get('code','MAIL_CHECKPOINT_INVALID'))
 return result['data']

def database(root,checkpoint=False):
 directory=root/'durable/operator-state/admin';file=directory/'registry.sqlite3';private_read(file)
 db=sqlite3.connect(file)
 try:
  db.execute('PRAGMA trusted_schema=OFF')
  if db.execute('PRAGMA integrity_check').fetchall()!=[('ok',)]:refuse('MAIL_INTEGRITY_FAILURE')
  meta={k:json.loads(v) for k,v in db.execute('SELECT key,value FROM meta')}
  if db.execute("SELECT count(*) FROM operations WHERE phase NOT IN ('applied','aborted')").fetchone()[0] or meta.get('desired_revision')!=meta.get('applied_revision'):refuse('MAIL_RECOVERY_REQUIRED')
  current=jsonfile(root/'durable/registry/public/current.json')
  if current['generation']!=meta['applied_revision'] or os.readlink(root/'durable/registry/private/current')!='generation-'+str(current['generation']):refuse('MAIL_GENERATION_INCOHERENT')
  if checkpoint and db.execute('PRAGMA wal_checkpoint(TRUNCATE)').fetchone()!=(0,0,0):refuse('MAIL_RECOVERY_WRITERS_PRESENT')
  return meta
 finally:db.close()

def runtime_files():
 files=[p for p in (BASE/'admin').iterdir() if p.is_file() and p.suffix in ('.py','.cjs','.json')]+[BASE/n for n in ('lifecycle.cjs','config.cjs','operator.js','consumer.cjs')]
 return {str(p.relative_to(BASE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}

def capture(a,cfg,root):
 check_runtime(root);mount_id=mount(root);no_writers(root) if (root/'recovery-fence.json').exists() else None
 if (root/'recovery-fence.json').exists():
  old=jsonfile(root/'recovery-fence.json')
  if old.get('phase')!='released' or {k:old.get(k) for k in ('device','inode')}!=ident(root):refuse('MAIL_RECOVERY_ALREADY_FENCED')
 run(['/usr/bin/node',BASE/'lifecycle.cjs','preflight','--config',a.config])
 # Stop every native role; no automatic restart or writer remains.
 run(['/usr/bin/node',BASE/'lifecycle.cjs','stop','--config',a.config,'--execute'])
 no_writers(root);worker('quiet',BASE,root);meta=database(root,True)
 previous_journal=root.parent/('.mail-restore-'+hashlib.sha256(str(root).encode()).hexdigest()+'.json')
 if previous_journal.exists():
  previous=jsonfile(previous_journal)
  if previous.get('target')==ident(root) and previous.get('phase')=='validated-held' and jsonfile(root/'recovery-fence.json').get('phase')=='released':
   previous['phase']='released';write(previous_journal,previous)
 for name in ('admission-closed',):
  if (root/'durable/registry/public'/name).exists():refuse('MAIL_RECOVERY_REQUIRED')
 for name,allowed in [('tls-intent.json',('applied','rolled-back')),('quota-drain.json',('released',))]:
  p=root/'durable/operator-state'/name
  if p.exists() and jsonfile(p).get('phase') not in allowed:refuse('MAIL_RECOVERY_REQUIRED')
 intent=root/'durable/operator-state/registry-intent.json'
 if intent.exists() and (jsonfile(intent).get('phase')!='applied' or jsonfile(intent).get('to')!=meta['applied_revision']):refuse('MAIL_GENERATION_INCOHERENT')
 inputs=root/'durable/recovery-inputs';safe_directory(inputs,True)
 restored=json.loads(json.dumps(cfg))
 dependencies=[('registry_file',cfg['registry_file']),('verifiers_file',cfg['verifiers_file'])]
 for field,path in dependencies:
  out=inputs/field;atomic(out,private_read(path));restored[field]=str(out)
 for n,item in enumerate(restored['secret_sources']):
  out=inputs/('secret-'+str(n));atomic(out,private_read(item['file']));item['file']=str(out)
 write(root/'recovery-config.json',restored)
 fence=dict(contract='drumee.mail-recovery-fence/1',phase='captured',operation_id=str(uuid.uuid4()),source_device=root.stat().st_dev,source_inode=root.stat().st_ino)
 write(root/'recovery-fence.json',fence)
 archive=pathlib.Path(a.archive);safe_directory(archive.parent,private=False)
 if archive.exists():refuse('MAIL_CHECKPOINT_TARGET_OCCUPIED')
 archive.mkdir(mode=0o700)
 if archive.stat().st_dev==root.stat().st_dev:refuse('MAIL_CHECKPOINT_ARCHIVE_ON_SOURCE_DEVICE')
 metadata=dict(root=str(root),source_uuid=mount_id,source_identity=ident(root),uid=os.getuid(),gid=os.getgid(),generation=meta['applied_revision'],owner=jsonfile(root/'owner.json'),fence=fence,source_lock=json.loads((BASE/'infra-source-lock.json').read_text()),distribution_files=runtime_files(),helper_image=HELPER,captured_at=time.time())
 result=worker('capture',archive,root,metadata=metadata);syncdir(archive);return dict(**result,generation=metadata['generation'],source_fenced=True,archive=str(archive))

def restore(a,cfg,root):
 if not a.manifest_sha256 or len(a.manifest_sha256)!=64 or not a.target_uuid:refuse('MAIL_USAGE')
 archive=safe_directory(a.archive);private_read(archive/'manifest.json')
 fd=os.open(archive/'payload.tar',os.O_RDONLY|os.O_NOFOLLOW)
 try:
  st=os.fstat(fd)
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or stat.S_IMODE(st.st_mode)!=0o600 or st.st_nlink!=1:refuse('MAIL_STORAGE_UNSAFE')
 finally:os.close(fd)
 verified=worker('verify',archive,expected=a.manifest_sha256);m=verified['metadata']
 if m['root']!=str(root) or m['uid']!=os.getuid() or m['gid']!=os.getgid() or m['owner']['id']!=cfg['service']['deployment']['id'] or m['owner']['project']!=cfg['service']['deployment']['project'] or m['source_lock']!=json.loads((BASE/'infra-source-lock.json').read_text()) or m['helper_image']!=HELPER or m.get('distribution_files')!=runtime_files():refuse('MAIL_CHECKPOINT_ARTIFACT_MISMATCH')
 mount(root,a.target_uuid);safe_directory(root);check_runtime(root);no_writers(root)
 if root.stat().st_dev==m['source_identity']['device'] or a.target_uuid==m['source_uuid']:refuse('MAIL_RESTORE_SOURCE_TARGET_ALIAS')
 journal=root.parent/('.mail-restore-'+hashlib.sha256(str(root).encode()).hexdigest()+'.json')
 if journal.exists():
  prior=jsonfile(journal)
  if prior.get('phase')=='released' and prior.get('target')!=ident(root):
   if list(root.iterdir()):refuse('MAIL_RESTORE_TARGET_OCCUPIED')
   history=journal.with_name(journal.stem+'-history-'+prior['checkpoint']+'-'+prior['target_uuid']+'.json')
   if history.exists():
    if jsonfile(history)!=prior:refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
   else:write(history,prior)
   journal.unlink();syncdir(journal.parent)
 if journal.exists():
  j=jsonfile(journal)
  if j['checkpoint']!=a.manifest_sha256 or j['target']!=ident(root) or j['target_uuid']!=a.target_uuid:refuse('MAIL_RESTORE_TARGET_UNAUTHORIZED')
 else:
  if list(root.iterdir()):refuse('MAIL_RESTORE_TARGET_OCCUPIED')
  j=dict(contract='drumee.mail-restore-operation/1',checkpoint=a.manifest_sha256,target=ident(root),target_uuid=a.target_uuid,phase='allocated');write(journal,j)
 stage=root/'.restore-stage'
 if j['phase']=='allocated':
  if stage.exists():
   name='.restore-interrupted-'+str(uuid.uuid4());j.setdefault('retained_stages',[]).append(name);write(journal,j);os.rename(stage,root/name);syncdir(root)
  stage.mkdir(mode=0o700);worker('extract',archive,stage,expected=a.manifest_sha256);j['phase']='verified';write(journal,j)
 if j['phase']=='verified':
  worker('verify-promotion',archive,root,expected=a.manifest_sha256,metadata={'retained_stages':j.get('retained_stages',[])})
  # Rename-only promotion, resumable after interruption; never replace any
  # pre-existing target entry. The journal binds this exact mounted inode.
  for p in sorted(stage.iterdir()) if stage.exists() else []:
   if (root/p.name).exists() or (root/p.name).is_symlink():refuse('MAIL_RESTORE_TARGET_OCCUPIED')
   os.rename(p,root/p.name);syncdir(root);syncdir(stage)
  if stage.exists():stage.rmdir()
  j['phase']='promoted';write(journal,j)
 if j['phase']=='promoted':
  if database(root)['applied_revision']!=m['generation']:refuse('MAIL_GENERATION_INCOHERENT')
  # Explicit new authority identity, preserving schema/state/revision/nonce.
  directory=root/'durable/operator-state/admin';marker=jsonfile(directory/'owner.json');allocation=root/'durable/operator-state/admin-bootstrap.json';record=jsonfile(allocation)
  for v in (marker,record):
   v['directory']={'dev':directory.stat().st_dev,'ino':directory.stat().st_ino};v['database']={'dev':(directory/'registry.sqlite3').stat().st_dev,'ino':(directory/'registry.sqlite3').stat().st_ino}
  write(directory/'owner.json',marker);write(allocation,record)
  fence=dict(m['fence'],phase='restoring',checkpoint=a.manifest_sha256);write(root/'recovery-fence.json',fence)
  out=run(['/usr/bin/node',BASE/'admin/restore-seal.cjs',str(root),a.manifest_sha256]);result=json.loads(out)
  if not result.get('ok'):refuse(result.get('code','MAIL_RECOVERY_REQUIRED'))
  j['phase']='sealed';write(journal,j)
 if j['phase']=='sealed':
  # Hold ALL queue entries offline before any daemon/listener can start.
  p=jsonfile(root/'durable/operator-state/prepared.json');image=p['compose']['services']['postfix']['image']
  run(['/usr/bin/docker','run','--rm','--network','none','--mount','type=bind,source='+str(root/'durable/spool')+',target=/var/spool/postfix','--mount','type=bind,source='+str(pathlib.Path(p['compose_file']).parent/'config')+',target=/config,readonly','--entrypoint','postsuper',image,'-c','/config','-h','ALL'])
  j['phase']='validated-held';write(journal,j)
 return dict(checkpoint=a.manifest_sha256,phase=j['phase'],queue_held=True,config=str(root/'recovery-config.json'),elapsed_seconds=time.monotonic()-START)

def release(a,cfg,root):
 fence=jsonfile(root/'recovery-fence.json')
 journal=root.parent/('.mail-restore-'+hashlib.sha256(str(root).encode()).hexdigest()+'.json');j=jsonfile(journal)
 if j['phase']!='validated-held' or j['target']!=ident(root) or j['checkpoint']!=a.manifest_sha256 or fence['checkpoint']!=a.manifest_sha256 or fence['source_device']==root.stat().st_dev:refuse('MAIL_RECOVERY_REQUIRED')
 no_writers(root);database(root)
 write(root/'recovery-fence.json',dict(fence,phase='released',**ident(root)))
 try:run(['/usr/bin/node',BASE/'lifecycle.cjs','preflight','--config',root/'recovery-config.json'])
 except Refusal:write(root/'recovery-fence.json',fence);raise
 j['phase']='released';write(journal,j)
 return dict(checkpoint=a.manifest_sha256,phase='released',queue_held=True,automatic_start=False)

START=time.monotonic()
def main():
 global LOCK_FD
 resource.setrlimit(resource.RLIMIT_CORE,(0,0));os.umask(0o077)
 p=argparse.ArgumentParser();p.add_argument('operation',choices=['backup','restore','recovery-release']);p.add_argument('--config',required=True);p.add_argument('--archive');p.add_argument('--manifest-sha256');p.add_argument('--target-uuid');p.add_argument('--execute',action='store_true');a=p.parse_args()
 if not a.execute:refuse('MAIL_NOT_AUTHORIZED')
 if a.operation!='recovery-release' and not a.archive:refuse('MAIL_USAGE')
 cfg=jsonfile(a.config);root=pathlib.Path(cfg['service']['deployment']['root']);deployment=cfg['service']['deployment']
 if (os.getuid(),os.getgid())!=(deployment['owner_uid'],deployment['owner_gid']):refuse('MAIL_OPERATOR_IDENTITY_MISMATCH')
 with service_lock(root) as fd:
  LOCK_FD=fd
  data=capture(a,cfg,root) if a.operation=='backup' else restore(a,cfg,root) if a.operation=='restore' else release(a,cfg,root)
 print(json.dumps(dict(contract='drumee.mail-recovery/1',ok=True,code='OK',data=data)))
if __name__=='__main__':
 try:main()
 except (Refusal,OSError,ValueError,KeyError) as e:
  print(json.dumps(dict(contract='drumee.mail-recovery/1',ok=False,code=e.code if isinstance(e,Refusal) else 'MAIL_CHECKPOINT_INVALID')));sys.exit(8)
