"""Guest-only administration reboot preparation/verification; never reboots caller."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
import sqlite3,signal
mode=sys.argv[3];statefile=root/'mail03-boot-before.json';unit=project+'.service';database=root/'service/durable/operator-state/admin/registry.sqlite3'
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def queue():return [json.loads(x) for x in run(['docker','exec',project+'-postfix-1','postqueue','-c','/config','-j']).stdout.splitlines()]
def row(id):
 with sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True) as db:
  db.row_factory=sqlite3.Row;value=db.execute('SELECT * FROM operations WHERE id=?',(id,)).fetchone();return dict(value) if value else None
if mode=='stage':
 user='boot-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Boot-'+uuid.uuid4().hex;cli('mailbox','create',user,password=passwords[user],mutate=True);tag='boot-preserved-'+uuid.uuid4().hex;assert probe(action='send',recipient=user,tag=tag)['data_code']==250;wait_read(user,tag)
 rendered=run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','boot-unit','--config',str(cfg)]);assert rendered.returncode==0;file=root/unit;file.write_text(json.loads(rendered.stdout)['unit']);assert run(['sudo','install','-m','0644',str(file),'/etc/systemd/system/'+unit]).returncode==0;assert run(['sudo','systemctl','daemon-reload']).returncode==0;assert run(['sudo','systemctl','enable','--now',unit]).returncode==0
 assert comp('stop','dovecot').returncode==0;queued='boot-queued-'+uuid.uuid4().hex;accepted=probe(action='send',recipient=user,tag=queued);assert accepted['data_code']==250;assert run(['docker','exec',project+'-postfix-1','postsuper','-c','/config','-h',accepted['queue_id']]).returncode==0;assert comp('start','dovecot').returncode==0
 id=str(uuid.uuid4());revision=state['revision'];args=['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail','mailbox','quota',user,'--bytes','2097152','--config',str(cfg),'--json','--execute','--if-revision',str(revision),'--request-id',id];child=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:
  for _ in range(60000):
   operation=row(id)
   if operation and operation['phase']=='applying':os.killpg(child.pid,signal.SIGSTOP);os.killpg(child.pid,signal.SIGKILL);break
   if child.poll() is not None:raise AssertionError('missed reboot interruption boundary')
   time.sleep(.002)
  else:raise TimeoutError('staged boot boundary')
  child.wait(timeout=10);assert (root/'service/durable/registry/public/admission-closed').exists()
 finally:
  if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=10)
 before={'boot_id':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'operation_id':id,'base':revision,'target':operation['target'],'user':user,'tag':tag,'queued_tag':queued,'queue_id':accepted['queue_id'],'unit':unit};statefile.write_text(json.dumps(before,indent=2));statefile.chmod(0o600);print(json.dumps({'staged':True,'operation_id':id,'target':operation['target'],'queue_id':accepted['queue_id'],'unit':unit}))
elif mode=='verify':
 before=json.loads(statefile.read_text());assert before['boot_id']!=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip();passwords.update(json.loads((private/'passwords.json').read_text()));observed=cli('status');assert observed['data']['pending_operation']==before['operation_id'] and observed['data']['admission']=='closed' and observed['applied_revision']==before['base'];check('reboot-retains-pending-intent-and-closed-admission',observed)
 # The ordinary boot entry refuses incomplete admission instead of guessing a
 # security generation. Explicit reconciliation starts the exact sealed target.
 resumed=cli('reconcile',opts=['--execute']);assert resumed['applied_revision']==before['target'];assert row(before['operation_id'])['phase']=='applied';assert any(x['queue_id']==before['queue_id'] for x in queue());assert run(['docker','exec',project+'-postfix-1','postsuper','-c','/config','-H',before['queue_id']]).returncode==0;assert run(['docker','exec',project+'-postfix-1','postqueue','-c','/config','-f']).returncode==0;assert wait_read(before['user'],before['queued_tag'])['matches']==1;assert wait_read(before['user'],before['tag'])['matches']==1;assert not any(x['queue_id']==before['queue_id'] for x in queue());assert run(['sudo','systemctl','reset-failed',unit]).returncode==0;assert run(['sudo','systemctl','start',unit]).returncode==0;check('reconcile-after-reboot-preserves-queue-and-mailbox-without-generation-rollback',{'queue_id':before['queue_id'],'applied_revision':state['revision'],'queued_matches':1,'old_matches':1})
 result={'status':'PASS_MAIL03_PENDING_GUEST_REBOOT','checks':checks,'commands':commands};(root/'mail03-boot-result.json').write_text(json.dumps(result,indent=2));print(result['status'])
else:raise ValueError('stage or verify')
