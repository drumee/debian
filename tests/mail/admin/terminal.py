"""Real controlling-terminal input, cancellation and public-output secrecy."""
from common import *
import pty,termios,errno,signal
def terminal_case(kind):
 user='tty-'+uuid.uuid4().hex[:8]+'@oxymot.fr';secret='Masked-'+uuid.uuid4().hex;master,slave=pty.openpty();before=termios.tcgetattr(slave);pid=os.fork()
 if pid==0:
  os.close(master);os.login_tty(slave)
  os.execv('/bin/bash',['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail','mailbox','create',user,'--config',str(cfg),'--execute','--json'])
 observed=bytearray();sent=set();deadline=time.monotonic()+120;status=None;done=0
 import select
 try:
  while time.monotonic()<deadline:
   ready,_,_=select.select([master],[],[],.1)
   if ready:
    try:part=os.read(master,8192)
    except OSError as e:
     if e.errno==errno.EIO:break
     raise
    if not part:break
    observed.extend(part)
   if b'Type yes: ' in observed and 'yes' not in sent:os.write(master,b'yes\n');sent.add('yes')
   if b'Password: ' in observed and 'first' not in sent:
    sent.add('first')
    if kind=='cancel':os.kill(pid,signal.SIGINT)
    else:os.write(master,secret.encode()+b'\n')
   if b'Confirm password: ' in observed and 'second' not in sent:
    os.write(master,((secret if kind=='valid' else 'Mismatch-'+uuid.uuid4().hex)+'\n').encode());sent.add('second')
   done,status=os.waitpid(pid,os.WNOHANG)
   if done:break
  else:raise TimeoutError('TTY deadline')
  if status is None or not done:_,status=os.waitpid(pid,0)
  code=os.waitstatus_to_exitcode(status);assert code=={'valid':0,'mismatch':2,'cancel':130}[kind],(kind,code,observed.decode()[-500:]);assert secret.encode() not in observed;assert termios.tcgetattr(slave)==before;check('masked-tty-'+kind+'-restores-terminal',{'exit':code,'output_sha256':hashlib.sha256(observed).hexdigest(),'secret_in_output':False})
  if kind=='valid':passwords[user]=secret;assert probe(action='imap',user=user)['ok']
 finally:
  os.close(master);os.close(slave)
for kind in ('mismatch','cancel','valid'):terminal_case(kind)
result={'status':'PASS_MAIL03_NATIVE_TTY','checks':checks,'commands':commands};(root/'mail03-tty-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
