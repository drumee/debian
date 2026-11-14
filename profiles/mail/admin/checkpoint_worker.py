"""Offline archive worker. Invoked in a pinned, network-less helper, never a service.

Manifests and payloads are private: they include hashes of credential material.
Only aggregate receipts may leave the protected checkpoint directory.
"""
import hashlib,json,os,pathlib,resource,sqlite3,stat,sys,tarfile

def digest(path):
 h=hashlib.sha256()
 with open(path,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()

def inventory(root):
 root=pathlib.Path(root);out={}
 def walk(p):
  rel=str(p.relative_to(root));s=p.lstat();v=dict(uid=s.st_uid,gid=s.st_gid,mode=stat.S_IMODE(s.st_mode),mtime_ns=s.st_mtime_ns)
  if os.listxattr(p,follow_symlinks=False):raise ValueError('MAIL_CHECKPOINT_XATTR_UNQUALIFIED')
  if stat.S_ISDIR(s.st_mode):
   v['kind']='directory';out[rel]=v
   for child in sorted(p.iterdir()):walk(child)
  elif stat.S_ISREG(s.st_mode):
   if s.st_nlink!=1:raise ValueError('MAIL_CHECKPOINT_HARDLINK_UNQUALIFIED')
   v.update(kind='file',size=s.st_size,sha256=digest(p));out[rel]=v
  elif stat.S_ISLNK(s.st_mode):
   target=os.readlink(p)
   if os.path.isabs(target) or not (p.parent/target).resolve().is_relative_to(root.resolve()):raise ValueError('MAIL_CHECKPOINT_LINK_UNSAFE')
   v.update(kind='symlink',target=target);out[rel]=v
  elif not (stat.S_ISSOCK(s.st_mode) or stat.S_ISFIFO(s.st_mode)):raise ValueError('MAIL_CHECKPOINT_TYPE_UNSAFE')
  # Unix sockets/FIFOs are ephemeral and recreated by the native daemons.
 walk(root);return out

def quiet(root):
 device=pathlib.Path(root).stat().st_dev
 for proc in pathlib.Path('/proc').iterdir():
  if not proc.name.isdecimal() or int(proc.name)==os.getpid():continue
  try:
   nodes=[proc/'cwd',proc/'root',*list((proc/'fd').iterdir()),*list((proc/'map_files').iterdir())]
   for p in nodes:
    try:
     if p.stat().st_dev==device:raise ValueError('MAIL_RECOVERY_WRITERS_PRESENT')
    except FileNotFoundError:pass
  except (FileNotFoundError,ProcessLookupError):pass
  except PermissionError:raise ValueError('MAIL_RECOVERY_WRITER_SCAN_INCOMPLETE')
 return {'writers':0,'device':device,'host_proc_scan':True}

def capture(root,destination,metadata):
 root=pathlib.Path(root);destination=pathlib.Path(destination);items=inventory(root)
 archive=destination/'payload.tar'
 with archive.open('xb') as out:
  os.chmod(archive,0o600)
  with tarfile.open(fileobj=out,mode='w') as tar:
   for rel,v in items.items():
    p=root/rel;info=tar.gettarinfo(str(p),arcname=rel);info.uname=info.gname=''
    if v['kind']=='file':
     with p.open('rb') as f:tar.addfile(info,f)
    else:tar.addfile(info)
  out.flush();os.fsync(out.fileno())
 if items!=inventory(root):raise ValueError('MAIL_CHECKPOINT_WRITER_DETECTED')
 manifest=dict(contract='drumee.mail-checkpoint/1',metadata=metadata,archive_sha256=digest(archive),entries=items)
 file=destination/'manifest.json'
 with file.open('x') as out:os.chmod(file,0o600);json.dump(manifest,out,sort_keys=True);out.flush();os.fsync(out.fileno())
 for p in (archive,file):os.chown(p,metadata['uid'],metadata['gid'])
 return dict(manifest_sha256=digest(file),archive_sha256=manifest['archive_sha256'],entries=len(items))

def verify(archive_root,expected):
 a=pathlib.Path(archive_root);file=a/'manifest.json'
 if digest(file)!=expected:raise ValueError('MAIL_CHECKPOINT_INTEGRITY_FAILURE')
 manifest=json.loads(file.read_text())
 if manifest.get('contract')!='drumee.mail-checkpoint/1':raise ValueError('MAIL_CHECKPOINT_SCHEMA_INCOMPATIBLE')
 if digest(a/'payload.tar')!=manifest['archive_sha256']:raise ValueError('MAIL_CHECKPOINT_INTEGRITY_FAILURE')
 with tarfile.open(a/'payload.tar') as tar:
  members=tar.getmembers();seen=set()
  for m in members:
   p=pathlib.PurePosixPath(m.name)
   if p.is_absolute() or '..' in p.parts or m.name in seen or m.name not in manifest['entries']:raise ValueError('MAIL_CHECKPOINT_MEMBER_UNSAFE')
   seen.add(m.name);v=manifest['entries'][m.name]
   if (m.uid,m.gid,m.mode)!=(v['uid'],v['gid'],v['mode']):raise ValueError('MAIL_CHECKPOINT_METADATA_MISMATCH')
   if m.isdir() and v['kind']=='directory':pass
   elif m.isfile() and v['kind']=='file':
    if m.size!=v['size'] or hashlib.file_digest(tar.extractfile(m),'sha256').hexdigest()!=v['sha256']:raise ValueError('MAIL_CHECKPOINT_INTEGRITY_FAILURE')
   elif m.issym() and v['kind']=='symlink':
    target=pathlib.PurePosixPath(m.linkname)
    if target.is_absolute() or '..' in target.parts or m.linkname!=v['target']:raise ValueError('MAIL_CHECKPOINT_MEMBER_UNSAFE')
   else:raise ValueError('MAIL_CHECKPOINT_MEMBER_UNSAFE')
  if seen!=set(manifest['entries']):raise ValueError('MAIL_CHECKPOINT_INCOMPLETE')
  if 'root' in manifest['metadata']:
   try:
    registry=json.load(tar.extractfile('durable/registry/public/current.json'))
    db=sqlite3.connect(':memory:');db.deserialize(tar.extractfile('durable/operator-state/admin/registry.sqlite3').read());db.execute('PRAGMA trusted_schema=OFF')
    if db.execute('PRAGMA integrity_check').fetchall()!=[('ok',)]:raise ValueError('MAIL_CHECKPOINT_INTEGRITY_FAILURE')
    meta={k:json.loads(v) for k,v in db.execute('SELECT key,value FROM meta')}
    if meta['applied_revision']!=meta['desired_revision'] or meta['applied_revision']!=registry['generation'] or meta['applied_revision']!=manifest['metadata']['generation'] or meta['owner']!=manifest['metadata']['owner'] or db.execute("SELECT count(*) FROM operations WHERE phase NOT IN ('applied','aborted')").fetchone()[0]:raise ValueError('MAIL_GENERATION_INCOHERENT')
    if manifest['entries']['durable/registry/private/current']['target']!='generation-'+str(registry['generation']):raise ValueError('MAIL_GENERATION_INCOHERENT')
    db.close()
   except (sqlite3.Error,KeyError,TypeError):raise ValueError('MAIL_CHECKPOINT_SCHEMA_INCOMPATIBLE')
 return manifest

def extract(archive_root,expected,target):
 manifest=verify(archive_root,expected);target=pathlib.Path(target)
 if any(target.iterdir()):raise ValueError('MAIL_RESTORE_TARGET_OCCUPIED')
 with tarfile.open(pathlib.Path(archive_root)/'payload.tar') as tar:
  # Members have been exhaustively checked; build regular objects first and
  # symlinks last, never follow an archive-controlled link while writing.
  for m in sorted(tar.getmembers(),key=lambda m:(m.issym(),len(pathlib.PurePosixPath(m.name).parts),m.name)):
   p=target/m.name
   if m.isdir():p.mkdir(mode=0o700,exist_ok=m.name=='.')
   elif m.isfile():
    fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as out,tar.extractfile(m) as source:
     for b in iter(lambda:source.read(1048576),b''):out.write(b)
     out.flush();os.fsync(out.fileno())
   else:p.symlink_to(m.linkname)
  for rel,v in sorted(manifest['entries'].items(),key=lambda x:-len(pathlib.PurePosixPath(x[0]).parts)):
   p=target/rel;os.chown(p,v['uid'],v['gid'],follow_symlinks=False)
   if v['kind']!='symlink':os.chmod(p,v['mode'])
   os.utime(p,ns=(v['mtime_ns'],v['mtime_ns']),follow_symlinks=False)
   if v['kind']=='directory':
    fd=os.open(p,os.O_RDONLY|os.O_DIRECTORY)
    try:os.fsync(fd)
    finally:os.close(fd)
 if inventory(target)!=manifest['entries']:raise ValueError('MAIL_CHECKPOINT_METADATA_MISMATCH')
 return dict(entries=len(manifest['entries']),verified=True)

def verify_promotion(archive_root,expected,target,retained):
 m=verify(archive_root,expected);target=pathlib.Path(target);stage=target/'.restore-stage';entries=m['entries'];tops={pathlib.PurePosixPath(x).parts[0] for x in entries if x!='.'}
 if {p.name for p in target.iterdir()}-tops-{'.restore-stage'}-set(retained):raise ValueError('MAIL_RESTORE_TARGET_OCCUPIED')
 if not ({p.name for p in stage.iterdir()} if stage.exists() else set())<=tops:raise ValueError('MAIL_CHECKPOINT_INCOMPLETE')
 actual={'.':inventory_root(target)}
 for name in tops:
  left=target/name;right=stage/name
  present=lambda p:p.exists() or p.is_symlink()
  if present(left)==present(right):raise ValueError('MAIL_RESTORE_TARGET_OCCUPIED')
  actual.update({name if k=='.' else name+'/'+k:v for k,v in inventory(left if present(left) else right).items()})
 # Promotion changes the enclosing root's mtime; no stored data metadata changes.
 actual['.']['mtime_ns']=entries['.']['mtime_ns']
 if actual!=entries:raise ValueError('MAIL_CHECKPOINT_METADATA_MISMATCH')
 return {'verified':True}

def inventory_root(p):
 s=p.lstat();return dict(uid=s.st_uid,gid=s.st_gid,mode=stat.S_IMODE(s.st_mode),mtime_ns=s.st_mtime_ns,kind='directory')

if __name__=='__main__':
 try:
  resource.setrlimit(resource.RLIMIT_CORE,(0,0))
  a={'action':'quiet'} if len(sys.argv)==3 and sys.argv[1]=='--quiet-host' else json.load(sys.stdin)
  if a['action']=='quiet':result=quiet(sys.argv[2] if len(sys.argv)==3 else '/source')
  elif a['action']=='capture':result=capture('/source','/archive',a['metadata'])
  elif a['action']=='verify':m=verify('/archive',a['expected']);result={'metadata':m['metadata'],'entries':len(m['entries'])}
  elif a['action']=='extract':result=extract('/archive',a['expected'],'/target')
  elif a['action']=='verify-promotion':result=verify_promotion('/archive',a['expected'],'/target',a.get('metadata',{}).get('retained_stages',[]))
  else:raise ValueError('MAIL_USAGE')
  print(json.dumps({'ok':True,'data':result}))
 except (OSError,ValueError,KeyError,tarfile.TarError) as e:
  code=str(e) if str(e).startswith('MAIL_') else 'MAIL_CHECKPOINT_INVALID'
  print(json.dumps({'ok':False,'code':code}));sys.exit(8)
