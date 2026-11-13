"""Verified local OCI acquisition. No registry, upload, tag lookup or extraction of tar paths."""
import hashlib,json,pathlib,re,sys,tarfile

def encode(value):return json.dumps(value,separators=(',',':')).encode()
def digest(data):return 'sha256:'+hashlib.sha256(data).hexdigest()
def fail(code):raise ValueError(code)
def check_lock(lock):
 if lock.get('contract')!='drumee.mail-native-base/1' or any(not re.fullmatch(r'sha256:[0-9a-f]{64}',lock.get(x,'')) for x in ['manifest','config']):fail('MAIL_NATIVE_BASE_LOCK_INVALID')
 if lock.get('from')!='drumee-minimal-application-tools@'+lock['manifest'] or not re.fullmatch(r'moby/buildkit@sha256:[0-9a-f]{64}',lock.get('buildkit','')):fail('MAIL_NATIVE_BASE_LOCK_INVALID')
def validate(root,lock):
 check_lock(lock);root=pathlib.Path(root);index=json.loads((root/'index.json').read_text());items=index.get('manifests',[])
 if len(items)!=1 or items[0].get('digest')!=lock['manifest']:fail('MAIL_NATIVE_BASE_MANIFEST_MISMATCH')
 def read(desc):
  dg=desc.get('digest','')
  if not re.fullmatch(r'sha256:[0-9a-f]{64}',dg):fail('MAIL_NATIVE_BASE_BLOB_INVALID')
  file=root/'blobs/sha256'/dg[7:]
  if file.is_symlink() or not file.is_file():fail('MAIL_NATIVE_BASE_BLOB_MISSING')
  data=file.read_bytes()
  if len(data)!=desc.get('size') or digest(data)!=dg:fail('MAIL_NATIVE_BASE_BLOB_INTEGRITY')
  return data
 manifest=json.loads(read(items[0]))
 if manifest.get('schemaVersion')!=2 or manifest['config']['digest']!=lock['config']:fail('MAIL_NATIVE_BASE_CONFIG_MISMATCH')
 config=json.loads(read(manifest['config']));layers=manifest['layers']
 if config.get('os')!='linux' or config.get('architecture')!='amd64' or config['rootfs']['diff_ids']!=[x['digest'] for x in layers]:fail('MAIL_NATIVE_BASE_PLATFORM_OR_LAYER_MISMATCH')
 for desc in layers:
  if desc['mediaType']!='application/vnd.oci.image.layer.v1.tar':fail('MAIL_NATIVE_BASE_LAYER_FORMAT')
  read(desc)
 return {'from':lock['from'],'manifest':lock['manifest'],'config':lock['config'],'layers':[x['digest'] for x in layers]}
def prepare(archive,root,lock):
 check_lock(lock);root=pathlib.Path(root)
 if root.exists() and any(root.iterdir()):fail('MAIL_NATIVE_BASE_TARGET_NOT_EMPTY')
 (root/'blobs/sha256').mkdir(parents=True,mode=0o700,exist_ok=True)
 def blob(data,kind):
  dg=digest(data);(root/'blobs/sha256'/dg[7:]).write_bytes(data);return {'mediaType':kind,'digest':dg,'size':len(data)}
 with tarfile.open(archive) as tar:
  def read(name):
   member=tar.getmember(name)
   if not member.isfile() or member.size>1024**3:fail('MAIL_NATIVE_BASE_ARCHIVE_INVALID')
   return tar.extractfile(member).read()
  entries=json.loads(read('manifest.json'))
  if len(entries)!=1:fail('MAIL_NATIVE_BASE_ARCHIVE_INVALID')
  entry=entries[0];config=blob(read(entry['Config']),'application/vnd.oci.image.config.v1+json')
  if config['digest']!=lock['config']:fail('MAIL_NATIVE_BASE_CONFIG_MISMATCH')
  layers=[blob(read(name),'application/vnd.oci.image.layer.v1.tar') for name in entry['Layers']]
  desc=blob(encode({'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':config,'layers':layers}),'application/vnd.oci.image.manifest.v1+json')
  if desc['digest']!=lock['manifest']:fail('MAIL_NATIVE_BASE_MANIFEST_MISMATCH')
  (root/'index.json').write_bytes(encode({'schemaVersion':2,'manifests':[desc]}));(root/'oci-layout').write_text('{"imageLayoutVersion":"1.0.0"}')
 return validate(root,lock)
if __name__=='__main__':
 try:
  mode,archive,root,lockfile=sys.argv[1:];lock=json.loads(pathlib.Path(lockfile).read_text());print(json.dumps(prepare(archive,root,lock) if mode=='prepare' else validate(root,lock) if mode=='validate' else fail('MAIL_NATIVE_BASE_OPERATION_INVALID')))
 except (ValueError,OSError,KeyError,tarfile.TarError,json.JSONDecodeError) as error:
  print(json.dumps({'ok':False,'code':str(error) if str(error).startswith('MAIL_') else 'MAIL_NATIVE_BASE_ACQUISITION_FAILED'}));sys.exit(1)
