"""External process interruption; no fault-injection hooks in the operator."""
from common import *
import concurrent.futures,signal,sqlite3
database=root/'service/durable/operator-state/admin/registry.sqlite3'
def operation(id):
 with sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True,timeout=1) as db:
  db.row_factory=sqlite3.Row;row=db.execute('SELECT * FROM operations WHERE id=?',(id,)).fetchone();return dict(row) if row else None
def command(family,verb,selector,opts,id,revision):return ['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail',family,verb,selector,*opts,'--config',str(cfg),'--json','--execute','--if-revision',str(revision),'--request-id',id]
user='tx-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Transaction-'+uuid.uuid4().hex;box=cli('mailbox','create',user,password=passwords[user],mutate=True)['data']
revision=state['revision']
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 jobs=[pool.submit(run,command('mailbox','disable',user,['--scope',scope],str(uuid.uuid4()),revision)) for scope in ('receive','imap')];answers=[job.result() for job in jobs]
assert sorted(x.returncode for x in answers)==[0,4];values=[json.loads(x.stdout) for x in answers];assert sorted(x['code'] for x in values)==['MAIL_REVISION_CONFLICT','OK'];state['revision']=cli('status')['applied_revision'];check('concurrent-cas-one-winner-no-last-write-wins',values)
cli('mailbox','update',user,opts=['--receive','true','--imap','true'],mutate=True)
def matching_bridge(group,action):
 for directory in pathlib.Path('/proc').iterdir():
  if not directory.name.isdigit():continue
  try:
   pid=int(directory.name)
   if os.getpgid(pid)!=group:continue
   args=(directory/'cmdline').read_bytes().split(b'\0')
   if any(x.endswith(b'/admin/bridge.cjs') for x in args) and action.encode() in args:return pid
  except (OSError,ProcessLookupError):continue
 return None
for boundary in ('validated','staged','committed-before-native-apply','applied-before-release'):
 id=str(uuid.uuid4());revision=state['revision'];fd=None
 if boundary=='validated':
  selector='lost-'+uuid.uuid4().hex[:8]+'@oxymot.fr';secret=private/'tx-input';secret.write_text('Lost-input-'+uuid.uuid4().hex);secret.chmod(0o600);fd=os.open(secret,os.O_RDONLY);args=command('mailbox','create',selector,['--password-fd',str(fd)],id,revision)
 else:
  selector=user;args=command('mailbox','quota',user,['--bytes',str(1048576*(2+('staged','committed-before-native-apply','applied-before-release').index(boundary)))],id,revision)
 child=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,pass_fds=(() if fd is None else (fd,)),start_new_session=True)
 if fd is not None:os.close(fd)
 try:
  deadline=time.monotonic()+120;observed=None
  while time.monotonic()<deadline:
   row=operation(id)
   hit=row and ((boundary=='validated' and row['phase']=='validated' and not pathlib.Path(row['secrets']).exists()) or (boundary=='staged' and row['phase']=='staged' and matching_bridge(child.pid,'resume-runtime')) or (boundary=='committed-before-native-apply' and row['phase']=='applying' and matching_bridge(child.pid,'apply')) or (boundary=='applied-before-release' and row['result'] and row['phase']=='applying' and matching_bridge(child.pid,'release')))
   if hit:
    os.killpg(child.pid,signal.SIGSTOP);observed=operation(id);os.killpg(child.pid,signal.SIGKILL);break
   if child.poll() is not None:raise AssertionError('missed external interruption boundary '+boundary)
   time.sleep(.002)
  assert observed is not None;child.wait(timeout=10)
  if boundary=='applied-before-release':
   assert (root/'service/durable/registry/public/admission-closed').exists();assert not probe(action='imap',user=user)['ok'];check('applied-db-durable-before-admission-release',{'target':observed['target'],'phase':observed['phase'],'admission':'closed'})
  cli('mailbox','disable',user,opts=['--scope','receive'],mutate=True,expected='MAIL_RECOVERY_REQUIRED')
  result=cli('reconcile',opts=['--execute'],expected='MAIL_CANCELLED' if boundary=='validated' else 'OK');state['revision']=cli('status')['applied_revision'];final=operation(id);assert final['phase']==('aborted' if boundary=='validated' else 'applied')
  replay=run(args,pass_fds=());value=json.loads(replay.stdout);assert value==result;assert replay.returncode==(130 if boundary=='validated' else 0);assert not (root/'service/durable/registry/public/admission-closed').exists();check('external-kill-'+boundary+'-reconcile-same-receipt',{'base':revision,'target':observed['target'],'phase_before':observed['phase'],'phase_after':final['phase'],'revision':state['revision']})
 finally:
  if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=10)
result={'status':'PASS_MAIL03_NATIVE_TRANSACTIONS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-tx-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
