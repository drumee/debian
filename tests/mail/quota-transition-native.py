"""Linearize quota changes after old LMTP contexts; preserve unrelated IMAP."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
import sqlite3,contextlib,threading
other='quota-reader-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[other]='Reader-'+uuid.uuid4().hex;cli('mailbox','create',other,password=passwords[other],mutate=True)
database=root/'service/durable/operator-state/admin/registry.sqlite3';drainfile=root/'service/durable/operator-state/quota-drain.json'
for label,kind,size,busy in [('rcpt-before-data','rcpt',1200000,False),('data-in-progress','data',1200000,False),('fits-new-limit','data',400000,False),('target-imap-append','imap',1200000,False),('busy-drain-reconcile','data',1200000,True)]:
 if len(sys.argv)>3 and label!=sys.argv[3]:continue
 user='quota-transition-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Transition-'+uuid.uuid4().hex;box=cli('mailbox','create',user,opts=['--quota-bytes','2097152'],password=passwords[user],mutate=True)['data'];write_passwords();marker='quota-transition-'+uuid.uuid4().hex
 args=['docker','run','--rm','-i','--network',project+'-edge','--mount','type=volume,source='+project+'-sockets,target=/run/mail-sockets','--mount',f'type=bind,source={private},target=/private','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={repo}/tests/mail,target=/lab,readonly','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-B','/lab/quota-transition-probe.py'];writer=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);writer.stdin.write(json.dumps({'kind':kind,'bytes':size,'user':user,'other':other,'id':box['id'],'marker':marker}).encode());writer.stdin.close();change=None
 try:
  for _ in range(400):
   if (private/(marker+'.ready')).exists():break
   if writer.poll() is not None:raise AssertionError('writer setup '+writer.stderr.read().decode()[-300:])
   time.sleep(.05)
  else:raise TimeoutError('old writer not ready')
  request=str(uuid.uuid4());revision=state['revision'];command=['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail','mailbox','quota',user,'--bytes','1048576','--config',str(cfg),'--json','--execute','--request-id',request,'--if-revision',str(revision)];change=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE);exited={}
  def observe_exit():change.wait();exited['at']=time.monotonic()
  watcher=threading.Thread(target=observe_exit);watcher.start()
  for _ in range(1200):
   with contextlib.closing(sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True)) as db:row=db.execute('SELECT target FROM operations WHERE id=?',(request,)).fetchone()
   observed=json.loads(drainfile.read_text()) if drainfile.exists() else {}
   if row and observed.get('to')==row[0] and observed.get('phase')=='waiting':break
   if change.poll() is not None:raise AssertionError('change finished before observable drain')
   time.sleep(.01)
  else:raise TimeoutError('quota drain not observed')
  if kind!='imap':
   assert change.poll() is None;public=json.loads((root/'service/durable/registry/public/current.json').read_text());assert next(x for x in public['mailboxes'] if x['id']==box['id'])['quota_bytes']==2097152
  if busy:
   change.wait(timeout=40);out=json.loads(change.stdout.read());assert change.returncode==7 and out['code']=='MAIL_APPLY_INCOMPLETE';assert out['applied_revision']==revision and (root/'service/durable/registry/public/admission-closed').exists();check('busy-quota-drain-refuses-success-and-retains-old-applied-state',out)
  (private/(marker+'.release')).write_text('go')
  for _ in range(400):
   if (private/(marker+'.writer.json')).exists():break
   if kind!='imap' and not busy:assert change.poll() is None,'quota returned before the old LMTP writer completed'
   time.sleep(.05)
  else:raise TimeoutError('old writer not completed')
  completion=json.loads((private/(marker+'.writer.json')).read_text());assert (completion['writer_result']==250 if kind!='imap' else completion['writer_result']!='OK')
  if busy:out=cli('reconcile',opts=['--execute'])
  else:
   change.wait(timeout=120);out=json.loads(change.stdout.read());assert change.returncode==0,(out,change.stderr.read()[-100:]);state['revision']=out['applied_revision']
  watcher.join(timeout=2);assert out['ok'] and out['data']['quota_bytes']==1048576
  if kind!='imap' and not busy:assert completion['writer_finished_monotonic']<exited['at']
  (private/(marker+'.verify')).write_text('check unrelated session');writer.wait(timeout=30);assert writer.returncode==0,writer.stderr.read().decode()[-2000:];wire=json.loads(writer.stdout.read());assert wire['unrelated_imap']=='OK';shown=cli('mailbox','show',user)['data'];assert shown['used_bytes']==out['data']['used_bytes'];assert shown['over_quota']==(kind!='imap' and size>1048576)
  if shown['over_quota']:assert probe(action='append',user=user,folder='mail03-quota-after-'+uuid.uuid4().hex,bytes=100)['append_code']=='NO'
  check(label+'-old-writer-resolved-before-new-quota-success',{'writer':wire,'new_limit':shown['quota_bytes'],'used_at_success':out['data']['used_bytes'],'over_quota_at_success':out['data']['over_quota'],'applied_revision':out['applied_revision']})
 finally:
  (private/(marker+'.release')).write_text('go');(private/(marker+'.verify')).write_text('go')
  if writer.poll() is None:writer.wait(timeout=30)
  if change is not None and change.poll() is None:change.wait(timeout=120)
result={'status':'PASS_HELD_LMTP_QUOTA_CHANGE' if len(sys.argv)==3 else 'PASS_PARTIAL_QUOTA_DIAGNOSTIC','checks':checks,'commands':commands,'last_revision':state['revision']};(root/('held-quota-result.json' if len(sys.argv)==3 else 'held-quota-'+sys.argv[3]+'-result.json')).write_text(json.dumps(result,indent=2));print(result['status'])
