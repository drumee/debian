"""WAL transactions, foreign keys, crash-released locks and protected targets."""
import pathlib,sys,tempfile,unittest,json,os,subprocess,signal,sqlite3
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[3]/'profiles/mail/admin'))
from storage import Authority,atomic,private_read,service_lock
from model import Refusal
class StorageTests(unittest.TestCase):
 def setUp(self):self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name);self.owner={'id':'synthetic-service'}
 def tearDown(self):self.temp.cleanup()
 def test_wal_full_foreign_keys_and_phase_journal(self):
  a=Authority(self.root/'admin',self.owner);self.assertEqual(a.db.execute('PRAGMA journal_mode').fetchone()[0],'wal');self.assertEqual(a.db.execute('PRAGMA synchronous').fetchone()[0],2);self.assertEqual(a.db.execute('PRAGMA foreign_keys').fetchone()[0],1)
  a.db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?,?,?,?)',('id','{}',1,2,'validated','{}','ref',None,os.getuid()));a.db.execute("UPDATE operations SET phase='staged' WHERE id='id'");self.assertEqual([x[0] for x in a.db.execute('SELECT phase FROM operation_events')],['validated','staged'])
  with self.assertRaises(sqlite3.IntegrityError):a.db.execute('INSERT INTO addresses VALUES(?,?,?,?)',('alias@example.invalid','missing','alias',1))
  a.db.close()
 def test_uncommitted_transaction_rolls_back(self):
  a=Authority(self.root/'admin',self.owner);a.put('revision',1);a.begin();a.put('revision',2);a.db.close();b=Authority(self.root/'admin',self.owner);self.assertEqual(b.get('revision'),1);b.db.close()
 def test_foreign_authority_refused(self):
  a=Authority(self.root/'admin',self.owner);a.db.close()
  with self.assertRaises(Refusal):Authority(self.root/'admin',{'id':'foreign'})
 def test_exclusive_generation_preserves_target(self):
  p=self.root/'secret';atomic(p,b'original',exclusive=True)
  with self.assertRaises(Refusal):atomic(p,b'foreign',exclusive=True)
  self.assertEqual(private_read(p),b'original');self.assertEqual(p.stat().st_nlink,1)
 def test_symlink_and_unsafe_database_refused_without_repair(self):
  d=self.root/'admin';d.mkdir(mode=0o700);sentinel=self.root/'sentinel';sentinel.write_text('retained');sentinel.chmod(0o600);(d/'registry.sqlite3').symlink_to(sentinel)
  with self.assertRaises((Refusal,OSError)):Authority(d,self.owner)
  self.assertEqual(sentinel.read_text(),'retained');self.assertTrue((d/'registry.sqlite3').is_symlink());d.rename(self.root/'retained-foreign');d=self.root/'owned';a=Authority(d,self.owner);a.db.close();(d/'registry.sqlite3').chmod(0o640)
  with self.assertRaises(Refusal):Authority(d,self.owner)
  self.assertEqual((d/'registry.sqlite3').stat().st_mode&0o777,0o640)
 def test_initialized_authority_refuses_missing_or_replaced_database(self):
  d=self.root/'admin';a=Authority(d,self.owner);a.put('desired_revision',1);a.mark_initialized();a.db.close();file=d/'registry.sqlite3';file.rename(d/'retained.sqlite3')
  with self.assertRaises(Refusal):Authority(d,self.owner)
  file.write_bytes(b'');file.chmod(0o600)
  with self.assertRaises(Refusal):Authority(d,self.owner)
  self.assertEqual(file.stat().st_size,0);self.assertGreater((d/'retained.sqlite3').stat().st_size,0)
 def test_live_descriptor_lock_survives_helper_and_releases_after_death(self):
  path=str(pathlib.Path(__file__).resolve().parents[3]/'profiles/mail/admin');code="import sys,time;sys.path.insert(0,sys.argv[1]);from storage import service_lock;\nwith service_lock(sys.argv[2]):\n print('locked',flush=True);time.sleep(30)"
  p=subprocess.Popen([sys.executable,'-c',code,path,str(self.root/'service')],stdout=subprocess.PIPE)
  try:
   self.assertEqual(p.stdout.readline(),b'locked\n')
   with self.assertRaises(Refusal):
    with service_lock(self.root/'service'):pass
   p.kill();p.wait(timeout=5)
   with service_lock(self.root/'service'):pass
  finally:
   if p.poll() is None:p.kill();p.wait()
   p.stdout.close()
if __name__=='__main__':unittest.main()
