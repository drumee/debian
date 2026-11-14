"""Use the same live-descriptor administrative lock for lifecycle mutations."""
import json,os,pathlib,subprocess,sys
from storage import private_read,service_lock
from model import Refusal
args=sys.argv[1:]
if args and args[0] in ('backup','restore','recovery-release'):
 os.execve('/usr/bin/python3',['/usr/bin/python3','-I',str(pathlib.Path(__file__).with_name('checkpoint.py')),*args],{'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':'/'})
script=str(pathlib.Path(__file__).parents[1]/'lifecycle.cjs');command=['/usr/bin/node',script,*args]
try:
 if args and args[0] in ('install','start','stop','restart') and '--config' in args:
  cfg=json.loads(private_read(args[args.index('--config')+1]));root=cfg['service']['deployment']['root']
  with service_lock(root) as fd:code=subprocess.run(command,pass_fds=(fd,)).returncode
 else:code=subprocess.run(command).returncode
except Refusal as e:print(json.dumps({'ok':False,'code':e.code}));code=6 if e.code=='MAIL_LOCK_BUSY' else 8
except (ValueError,OSError,KeyError,IndexError):print(json.dumps({'ok':False,'code':'MAIL_CLI_USAGE'}));code=2
sys.exit(code)
