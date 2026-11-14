"""Linux/x86_64 syscall tracing of the unmodified real CLI, lab only."""
import pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
import ctypes,signal,sqlite3
libc=ctypes.CDLL(None,use_errno=True);libc.ptrace.restype=ctypes.c_long
class Registers(ctypes.Structure):
 _fields_=[(name,ctypes.c_ulonglong) for name in 'r15 r14 r13 r12 rbp rbx r11 r10 r9 r8 rax rcx rdx rsi rdi orig_rax rip cs eflags rsp ss fs_base gs_base ds es fs gs'.split()]
def trace(request,pid,address=0,data=0):
 ctypes.set_errno(0);value=libc.ptrace(request,pid,ctypes.c_void_p(address),ctypes.c_void_p(data) if isinstance(data,int) else data)
 if value==-1 and ctypes.get_errno():raise OSError(ctypes.get_errno(),'lab ptrace failed')
 return value
def string(pid,address):
 out=bytearray()
 for offset in range(0,4096,8):
  try:part=(trace(2,pid,address+offset)&((1<<64)-1)).to_bytes(8,'little')
  except OSError:return None
  out.extend(part)
  if 0 in part:return bytes(out).split(b'\0',1)[0].decode(errors='replace')
 return None
database=root/'service/durable/operator-state/admin/registry.sqlite3'
def operation(id):
 with sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True) as db:
  db.row_factory=sqlite3.Row;value=db.execute('SELECT * FROM operations WHERE id=?',(id,)).fetchone();return dict(value) if value else None
def interrupt(args,destination,predicate=lambda:True):
 output=private/'syscall-child.stdout';error=private/'syscall-child.stderr';pid=os.fork()
 if pid==0:
  os.setsid()
  for target,file in [(1,output),(2,error)]:
   fd=os.open(file,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600);os.dup2(fd,target);os.close(fd)
  trace(0,0);os.kill(os.getpid(),signal.SIGSTOP);os.execv('/bin/bash',args)
 tasks={pid};hit=False;deadline=time.monotonic()+180
 try:
  os.waitpid(pid,0);trace(0x4200,pid,0,1|2|4|8|16|(1<<20));trace(24,pid)
  while time.monotonic()<deadline:
   try:who,status=os.waitpid(-1,0x40000000|os.WNOHANG)
   except ChildProcessError:break
   if not who:time.sleep(.0005);continue
   if os.WIFEXITED(status) or os.WIFSIGNALED(status):
    tasks.discard(who)
    if who==pid and not hit:raise AssertionError('CLI exited before requested syscall boundary')
    continue
   tasks.add(who);sig=os.WSTOPSIG(status)
   if sig==(signal.SIGTRAP|0x80):
    regs=Registers()
    try:trace(12,who,0,ctypes.byref(regs))
    except ProcessLookupError:tasks.discard(who);continue
    if regs.orig_rax in (82,264,316) and regs.rax==0:
     target=string(who,regs.rsi if regs.orig_rax==82 else regs.r10)
     if target==str(destination) and predicate():hit=True;os.killpg(pid,signal.SIGKILL);break
   try:trace(24,who,0,0 if sig in (signal.SIGTRAP,signal.SIGSTOP,signal.SIGTRAP|0x80) else sig)
   except ProcessLookupError:tasks.discard(who)
  assert hit,'syscall boundary was not observed'
 finally:
  try:os.killpg(pid,signal.SIGKILL)
  except ProcessLookupError:pass
  end=time.monotonic()+10
  while tasks and time.monotonic()<end:
   try:who,status=os.waitpid(-1,0x40000000|os.WNOHANG)
   except ChildProcessError:break
   if not who:time.sleep(.005);continue
   if os.WIFEXITED(status) or os.WIFSIGNALED(status):tasks.discard(who)
   else:
    try:trace(7,who,0,signal.SIGKILL)
    except OSError:pass
  assert not tasks,'traced tasks did not terminate'
user='cut-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Cutpoint-'+uuid.uuid4().hex;cli('mailbox','create',user,password=passwords[user],mutate=True)
pub=root/'service/durable/registry/public';priv=root/'service/durable/registry/private';native=root/'service/durable/operator-state/registry-intent.json'
for index,boundary in enumerate(('barrier-before-sqlite-commit','private-before-public','public-before-native-probes','native-applied-before-sqlite-applied')):
 id=str(uuid.uuid4());revision=state['revision'];target_quota=(index+2)*1048576;args=['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail','mailbox','quota',user,'--bytes',str(target_quota),'--config',str(cfg),'--json','--execute','--if-revision',str(revision),'--request-id',id]
 destination=pub/'admission-closed' if index==0 else priv/'current' if index==1 else pub/'current.json' if index==2 else native
 interrupt(args,destination,(lambda:json.loads(native.read_text())['phase']=='applied') if index==3 else lambda:True)
 row=operation(id);assert row and row['phase']==('staged' if index==0 else 'applying');published=json.loads((pub/'current.json').read_text())['generation'];private_generation=int(os.readlink(priv/'current').split('-')[1]);assert (pub/'admission-closed').exists();assert published==(revision if index<=1 else row['target']);assert private_generation==(revision if index==0 else row['target']);assert not probe(action='imap',user=user)['ok'];old=cli('mailbox','show',user)['data'];assert old['quota_bytes']!=target_quota
 observed={'syscall':'successful rename exit before next instruction','phase':row['phase'],'base':revision,'target':row['target'],'public_generation':published,'private_generation':private_generation,'admission':'closed'};resumed=cli('reconcile',opts=['--execute']);assert resumed['applied_revision']==row['target'];assert probe(action='imap',user=user)['ok'];check(boundary+'-same-sealed-generation-reconciled',observed)
result={'status':'PASS_MAIL03_NATIVE_SYSCALL_CUTPOINTS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-cutpoints-result.json').write_text(json.dumps(result,indent=2));print(result['status'])
