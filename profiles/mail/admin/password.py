"""Secret input is bounded, descriptor based, and never part of an operation intent."""
import os,stat,termios,fcntl
from model import refuse

def validate(data):
 try:text=data.decode('utf-8',errors='strict')
 except UnicodeDecodeError:refuse('MAIL_PASSWORD_INVALID')
 if not 16<=len(data)<=1024 or any(c in text for c in ('\x00','\r','\n','\ufeff')):refuse('MAIL_PASSWORD_INVALID')
 return data

def read_fd(fd):
 if not 3<=fd<=128:refuse('MAIL_SECRET_INPUT_UNSAFE')
 try:s=os.fstat(fd)
 except OSError:refuse('MAIL_SECRET_INPUT_UNSAFE')
 flags=fcntl.fcntl(fd,fcntl.F_GETFL)
 if flags&os.O_ACCMODE!=os.O_RDONLY or flags&getattr(os,'O_PATH',0) or flags&os.O_NONBLOCK:refuse('MAIL_SECRET_INPUT_UNSAFE')
 if s.st_uid!=os.getuid() or not (stat.S_ISREG(s.st_mode) or stat.S_ISFIFO(s.st_mode)) or stat.S_IMODE(s.st_mode)!=0o600 or (stat.S_ISREG(s.st_mode) and s.st_nlink!=1):refuse('MAIL_SECRET_INPUT_UNSAFE')
 # /proc identifies a symlink-opened regular FD even when the final path is safe.
 if stat.S_ISREG(s.st_mode):
  target=os.readlink('/proc/self/fd/'+str(fd))
  if os.path.realpath(target)!=target:refuse('MAIL_SECRET_INPUT_UNSAFE')
  try:l=os.lstat(target)
  except OSError:refuse('MAIL_SECRET_INPUT_UNSAFE')
  if (l.st_dev,l.st_ino)!=(s.st_dev,s.st_ino) or stat.S_ISLNK(l.st_mode):refuse('MAIL_SECRET_INPUT_UNSAFE')
 try:
  result=bytearray()
  while len(result)<=1024:
   piece=os.read(fd,1025-len(result))
   if not piece:break
   result.extend(piece)
  return validate(bytes(result))
 finally:os.close(fd)

def read_tty():
 fd=os.open('/dev/tty',os.O_RDWR|os.O_NOCTTY);old=termios.tcgetattr(fd);new=old.copy();new[3]&=~termios.ECHO
 def prompt(label):
  os.write(fd,label);data=bytearray()
  while True:
   c=os.read(fd,1)
   if not c:refuse('MAIL_CANCELLED')
   if c==b'\n':break
   data.extend(c)
   if len(data)>1024:refuse('MAIL_PASSWORD_INVALID')
  os.write(fd,b'\n');return validate(bytes(data))
 try:
  termios.tcsetattr(fd,termios.TCSANOW,new);a=prompt(b'Password: ');b=prompt(b'Confirm password: ')
  if a!=b:refuse('MAIL_PASSWORD_INVALID')
  return a
 finally:termios.tcflush(fd,termios.TCIFLUSH);termios.tcsetattr(fd,termios.TCSANOW,old);os.close(fd)
