"""Single-writer SQLite authority, public operation journal and protected generations."""
import contextlib,ctypes,errno,fcntl,hashlib,json,os,pathlib,sqlite3,stat,uuid,time,subprocess
from model import refuse

def safe_directory(path,create=False,private=True):
 path=pathlib.Path(path)
 if not path.is_absolute() or str(path.resolve())!=str(path):refuse('MAIL_STORAGE_UNSAFE')
 if create:path.mkdir(mode=0o700,exist_ok=True)
 for node in [path,*path.parents]:
  s=node.lstat()
  if not stat.S_ISDIR(s.st_mode) or s.st_uid not in (0,os.getuid()) or (s.st_mode&0o022 and not (s.st_uid==0 and s.st_mode&stat.S_ISVTX)):refuse('MAIL_STORAGE_UNSAFE')
 s=path.stat()
 if private and (s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o700):refuse('MAIL_STORAGE_UNSAFE')
 return path

def private_read(path):
 path=pathlib.Path(path);safe_directory(path.parent,private=False)
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
 try:
  s=os.fstat(fd);l=path.lstat()
  if not stat.S_ISREG(s.st_mode) or s.st_nlink!=1 or s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o600 or (s.st_dev,s.st_ino)!=(l.st_dev,l.st_ino):refuse('MAIL_STORAGE_UNSAFE')
  with os.fdopen(os.dup(fd),'rb') as file:return file.read()
 finally:os.close(fd)

def atomic(path,data,exclusive=False):
 path=pathlib.Path(path);safe_directory(path.parent,private=False);tmp=path.parent/('.admin-'+str(uuid.uuid4()));fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 try:
  with os.fdopen(fd,'wb') as file:file.write(data);file.flush();os.fsync(file.fileno())
  if path.exists():private_read(path)
  if exclusive:
   libc=ctypes.CDLL(None,use_errno=True)
   if not hasattr(libc,'renameat2'):refuse('MAIL_STORAGE_UNSAFE')
   if libc.renameat2(-100,os.fsencode(tmp),-100,os.fsencode(path),1)!=0:
    if ctypes.get_errno()==errno.EEXIST:refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
    refuse('MAIL_STORAGE_UNSAFE')
  else:os.replace(tmp,path)
  syncdir(path.parent)
 finally:
  if tmp.exists():tmp.unlink()

def syncdir(path):
 fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY)
 try:os.fsync(fd)
 finally:os.close(fd)

def encode(value):return json.dumps(value,sort_keys=True,separators=(',',':'))

@contextlib.contextmanager
def service_lock(root,timeout=0):
 root=pathlib.Path(root);safe_directory(root.parent,private=False);file=root.parent/('.mail-admin-'+hashlib.sha256(str(root).encode()).hexdigest()+'.lock');fd=os.open(file,os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  s=os.fstat(fd)
  if not stat.S_ISREG(s.st_mode) or s.st_nlink!=1 or s.st_uid!=os.getuid() or stat.S_IMODE(s.st_mode)!=0o600:refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
  deadline=time.monotonic()+timeout
  while True:
   try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);break
   except BlockingIOError:
    if time.monotonic()>=deadline:refuse('MAIL_LOCK_BUSY')
    time.sleep(.02)
  yield fd
 finally:os.close(fd)

def check_runtime(root):
 import platform
 lock=json.loads(pathlib.Path(__file__).with_name('runtime-lock.json').read_text())
 if platform.system().lower()!=lock['platform'] or platform.machine()!=lock['architecture'] or sqlite3.sqlite_version not in lock['sqlite_versions']:refuse('MAIL_DEPENDENCY_UNAVAILABLE')
 result=subprocess.run(['/usr/bin/findmnt','-n','-o','FSTYPE','--target',str(root)],capture_output=True,env={'PATH':'/usr/bin:/bin','LANG':'C'},timeout=5)
 if result.returncode or result.stdout.decode().strip() not in lock['filesystems']:refuse('MAIL_STORAGE_UNSAFE')

class Authority:
 def __init__(self,directory,owner):
  self.dir=safe_directory(directory,True);self.file=self.dir/'registry.sqlite3'
  for suffix in ('','-wal','-shm'):
   p=pathlib.Path(str(self.file)+suffix)
   if p.exists():private_read(p)
  self.db=sqlite3.connect(self.file,timeout=0,isolation_level=None);os.chmod(self.file,0o600)
  self.db.execute('PRAGMA journal_mode=WAL');self.db.execute('PRAGMA synchronous=FULL');self.db.execute('PRAGMA foreign_keys=ON');self.db.execute('PRAGMA trusted_schema=OFF')
  self.db.executescript('''CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS mailboxes(id TEXT PRIMARY KEY,data TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS addresses(address TEXT PRIMARY KEY,mailbox_id TEXT NOT NULL REFERENCES mailboxes(id),kind TEXT NOT NULL CHECK(kind IN ('primary','alias','retired')),active INTEGER NOT NULL CHECK(active IN (0,1)));
   CREATE UNIQUE INDEX IF NOT EXISTS primary_mailbox ON addresses(mailbox_id) WHERE kind='primary' AND active=1;
   CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY,data TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY,intent TEXT NOT NULL,base INTEGER NOT NULL,target INTEGER NOT NULL,phase TEXT NOT NULL,state TEXT NOT NULL,secrets TEXT NOT NULL,result TEXT,actor INTEGER NOT NULL);
  ''')
  self.db.executescript('''CREATE TABLE IF NOT EXISTS operation_events(operation_id TEXT NOT NULL REFERENCES operations(id),phase TEXT NOT NULL,at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')));
   CREATE TRIGGER IF NOT EXISTS operation_created AFTER INSERT ON operations BEGIN INSERT INTO operation_events(operation_id,phase) VALUES(NEW.id,NEW.phase); END;
   CREATE TRIGGER IF NOT EXISTS operation_phase AFTER UPDATE OF phase ON operations WHEN OLD.phase<>NEW.phase BEGIN INSERT INTO operation_events(operation_id,phase) VALUES(NEW.id,NEW.phase); END;''')
  check=self.db.execute('PRAGMA quick_check').fetchall()
  if check!=[('ok',)]:refuse('MAIL_INTEGRITY_FAILURE')
  current=self.get('owner')
  if current is not None and current!=owner:refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
  if current is None:self.put('owner',owner)
  syncdir(self.dir)
 def get(self,key):
  r=self.db.execute('SELECT value FROM meta WHERE key=?',(key,)).fetchone();return json.loads(r[0]) if r else None
 def put(self,key,value):self.db.execute('INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',(key,encode(value)))
 def begin(self):self.db.execute('BEGIN IMMEDIATE')
 def commit(self):self.db.execute('COMMIT');syncdir(self.dir)
 def store(self,state):
  for b in state['mailboxes']:self.db.execute('INSERT INTO mailboxes VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',(b['id'],encode(b)))
  self.db.execute("UPDATE addresses SET active=0,kind='retired'")
  for b in state['mailboxes']:self.address(b['address'],b['id'],'primary',not b['deleted'])
  for a in state['aliases']:self.address(a['address'],a['mailbox_id'],'alias',not a['deleted'])
  for a in state['accounts']:self.db.execute('INSERT INTO accounts VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',(a['id'],encode(a)))
  self.put('desired_state',state)
 def address(self,address,box,kind,active):
  r=self.db.execute('SELECT mailbox_id FROM addresses WHERE address=?',(address,)).fetchone()
  if r and r[0]!=box:refuse('MAIL_ADDRESS_CONFLICT')
  self.db.execute('INSERT INTO addresses VALUES(?,?,?,?) ON CONFLICT(address) DO UPDATE SET kind=excluded.kind,active=excluded.active',(address,box,kind,int(active)))
 def operation(self,id):
  self.db.row_factory=sqlite3.Row;r=self.db.execute('SELECT * FROM operations WHERE id=?',(id,)).fetchone();self.db.row_factory=None;return dict(r) if r else None
 def pending(self):
  r=self.db.execute("SELECT id FROM operations WHERE phase!='applied' ORDER BY target LIMIT 1").fetchone();return r[0] if r else None
