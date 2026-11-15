"""Archive boundary tests use synthetic bytes only; no service qualification claim."""
import hashlib,importlib.util,json,os,pathlib,socket,sqlite3,tarfile,tempfile,unittest
worker_path=pathlib.Path(__file__).resolve().parents[2]/'profiles/mail/admin/checkpoint_worker.py'
spec=importlib.util.spec_from_file_location('checkpoint_worker',worker_path);worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
class Checkpoint(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=pathlib.Path(self.tmp.name);self.source=self.base/'source';self.source.mkdir(mode=0o700);self.archive=self.base/'archive';self.archive.mkdir(mode=0o700);self.target=self.base/'target';self.target.mkdir(mode=0o700)
  (self.source/'generation-1').mkdir(mode=0o700);(self.source/'generation-1'/'record').write_bytes(b'synthetic-state');(self.source/'generation-1'/'record').chmod(0o600);(self.source/'current').symlink_to('generation-1')
  self.metadata=dict(uid=os.getuid(),gid=os.getgid(),generation=1);self.result=worker.capture(self.source,self.archive,self.metadata)
 def tearDown(self):self.tmp.cleanup()
 def test_round_trip_exact_metadata_and_source_preserved(self):
  before=worker.inventory(self.source);worker.extract(self.archive,self.result['manifest_sha256'],self.target);self.assertEqual(worker.inventory(self.target),before);self.assertEqual(worker.inventory(self.source),before)
 def test_corruption_before_writes(self):
  with (self.archive/'payload.tar').open('ab') as f:f.write(b'altered')
  with self.assertRaisesRegex(ValueError,'INTEGRITY'):worker.extract(self.archive,self.result['manifest_sha256'],self.target)
  self.assertEqual(list(self.target.iterdir()),[])
 def test_incompatible_schema(self):
  p=self.archive/'manifest.json';m=json.loads(p.read_text());m['contract']='drumee.mail-checkpoint/9';p.write_text(json.dumps(m));h=worker.digest(p)
  with self.assertRaisesRegex(ValueError,'SCHEMA'):worker.extract(self.archive,h,self.target)
  self.assertEqual(list(self.target.iterdir()),[])
 def test_occupied_target_preserved(self):
  sentinel=self.target/'existing';sentinel.write_bytes(b'must-survive')
  with self.assertRaisesRegex(ValueError,'OCCUPIED'):worker.extract(self.archive,self.result['manifest_sha256'],self.target)
  self.assertEqual(sentinel.read_bytes(),b'must-survive')
 def test_incomplete_inventory(self):
  p=self.archive/'manifest.json';m=json.loads(p.read_text());m['entries']['missing']={'kind':'file','uid':os.getuid(),'gid':os.getgid(),'mode':0o600,'size':0,'sha256':hashlib.sha256(b'').hexdigest()};p.write_text(json.dumps(m))
  with self.assertRaisesRegex(ValueError,'INCOMPLETE'):worker.extract(self.archive,worker.digest(p),self.target)
  self.assertEqual(list(self.target.iterdir()),[])
 def test_escaping_link_rejected_at_capture(self):
  (self.source/'foreign').symlink_to('../outside')
  with self.assertRaisesRegex(ValueError,'LINK_UNSAFE'):worker.inventory(self.source)
 def test_interrupted_promotion_is_verified_before_resume(self):
  stage=self.target/'.restore-stage';stage.mkdir(mode=0o700);worker.extract(self.archive,self.result['manifest_sha256'],stage)
  os.rename(stage/'generation-1',self.target/'generation-1')
  self.assertTrue(worker.verify_promotion(self.archive,self.result['manifest_sha256'],self.target,[])['verified'])
 def test_permission_change_in_stage_refuses_without_repair(self):
  stage=self.target/'.restore-stage';stage.mkdir(mode=0o700);worker.extract(self.archive,self.result['manifest_sha256'],stage);p=stage/'generation-1'/'record';p.chmod(0o644)
  with self.assertRaisesRegex(ValueError,'METADATA'):worker.verify_promotion(self.archive,self.result['manifest_sha256'],self.target,[])
  self.assertEqual(p.stat().st_mode&0o777,0o644);self.assertEqual(p.read_bytes(),b'synthetic-state')
 def test_checkpointed_wal_database_verified_without_rewriting_its_bytes(self):
  self.native_sqlite(False)
 def test_incoherent_database_generation_refused_before_extract(self):
  self.native_sqlite(True)
 def native_sqlite(self,incoherent):
  directory=self.source/'durable/operator-state/admin';directory.mkdir(parents=True,mode=0o700);file=directory/'registry.sqlite3';owner={'contract':'drumee.mail-owner/1','id':'synthetic'}
  db=sqlite3.connect(file);db.execute('PRAGMA journal_mode=WAL');db.executescript('CREATE TABLE meta(key TEXT,value TEXT);CREATE TABLE operations(phase TEXT);')
  db.executemany('INSERT INTO meta VALUES(?,?)',[(k,json.dumps(v)) for k,v in {'owner':owner,'desired_revision':1,'applied_revision':1}.items()]);db.commit();db.execute('PRAGMA wal_checkpoint(TRUNCATE)');db.close();file.chmod(0o600)
  self.assertEqual(file.read_bytes()[18:20],b'\x02\x02')
  public=self.source/'durable/registry/public';public.mkdir(parents=True);(public/'current.json').write_text(json.dumps({'generation':1}));private=self.source/'durable/registry/private';private.mkdir();(private/'generation-1').mkdir();(private/'current').symlink_to('generation-1')
  destination=self.base/'native-archive';destination.mkdir();original=worker.digest(file);receipt=worker.capture(self.source,destination,dict(self.metadata,root='/synthetic/mail',owner=owner,generation=2 if incoherent else 1))
  if incoherent:
   with self.assertRaisesRegex(ValueError,'GENERATION_INCOHERENT'):worker.extract(destination,receipt['manifest_sha256'],self.target)
   self.assertEqual(list(self.target.iterdir()),[])
  else:self.assertEqual(worker.verify(destination,receipt['manifest_sha256'])['metadata']['generation'],1)
  self.assertEqual(worker.digest(file),original)
if __name__=='__main__':unittest.main()
