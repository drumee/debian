#!/usr/bin/python3
"""MAIL-03 operator: public journal in SQLite; credentials in private immutable files."""
import argparse,copy,json,os,pathlib,re,signal,sqlite3,subprocess,sys,uuid,resource,datetime
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from model import Refusal,refuse,initial,projection,mutate,find,address
from storage import Authority,atomic,encode,private_read,safe_directory,service_lock,syncdir,check_runtime
from password import read_fd,read_tty
EXITS={'MAIL_USAGE':2,'MAIL_VALIDATION':2,'MAIL_PASSWORD_INVALID':2,'MAIL_SECRET_INPUT_UNSAFE':2,'MAIL_NOT_FOUND':3,'MAIL_ADDRESS_CONFLICT':4,'MAIL_REVISION_CONFLICT':4,'MAIL_REQUEST_CONFLICT':4,'MAIL_DOMAIN_IN_USE':4,'MAIL_PURGE_REFERENCED':4,'MAIL_NOT_AUTHORIZED':5,'MAIL_RESOURCE_IDENTITY_MISMATCH':5,'MAIL_LOCK_BUSY':6,'MAIL_DEPENDENCY_UNAVAILABLE':6,'MAIL_APPLY_INCOMPLETE':7,'MAIL_RECOVERY_REQUIRED':7,'MAIL_STORAGE_UNSAFE':8,'MAIL_INTEGRITY_FAILURE':8,'SMTP_RECOVERY_UNQUALIFIED':8,'MAIL_CANCELLED':130}
CURRENT=None
HELP='''drumee-ctl --profile mail mail mailbox|alias|account OPERATION [ID|ADDRESS] --config FILE [--json]
Mailbox: list show create update rename enable disable delete quota password purge
Alias: list create update delete (no credentials)
Account: list show create update enable disable delete password
Mutations: --execute --if-revision N --request-id UUID
Passwords: masked TTY twice, or --password-fd N (N>=3); never a password argument.
Recovery: mail reconcile --config FILE --execute --json (same committed operation).
Status: mail status --config FILE --json
See docs/mail-03/cli.md for exact per-verb options and stable result/error codes.'''
class Parser(argparse.ArgumentParser):
 def error(self,message):refuse('MAIL_USAGE')

def parse(argv):
 if '--help' in argv or not argv:print(HELP);raise SystemExit(0)
 p=Parser(add_help=False);p.add_argument('family',choices=['mailbox','alias','account','reconcile','status']);p.add_argument('verb',nargs='?');p.add_argument('selector',nargs='?')
 p.add_argument('--config',required=True);p.add_argument('--json',action='store_true');p.add_argument('--execute',action='store_true');p.add_argument('--include-deleted',action='store_true')
 for name in ['request-id','if-revision','quota-bytes','bytes','password-fd','limit','cursor','to','old-address','scope','receive','imap','submission','mailbox','dsn-mailbox','confirm-mailbox','backup-id']:p.add_argument('--'+name)
 for name in ['envelope-from','header-from']:p.add_argument('--'+name,action='append')
 a=p.parse_args(argv);vals=vars(a)
 for key in ['if_revision','quota_bytes','bytes','password_fd','limit']:
  if vals[key] is not None:
   if not re.fullmatch(r'0|[1-9][0-9]{0,15}',vals[key]):refuse('MAIL_USAGE')
   vals[key]=int(vals[key])
 for key in ('receive','imap','submission'):
  if vals[key] is not None:
   if vals[key] not in ('true','false'):refuse('MAIL_USAGE')
   vals[key]=vals[key]=='true'
 allowed={
  'mailbox':{'list':set(),'show':set(),'create':{'quota_bytes','password_fd'},'update':{'receive','imap','submission'},'rename':{'to','old_address'},'enable':{'scope'},'disable':{'scope'},'delete':set(),'quota':{'bytes'},'password':{'password_fd'},'purge':{'confirm_mailbox','backup_id'}},
  'alias':{'list':{'mailbox'},'create':{'mailbox'},'update':{'mailbox','receive'},'delete':set()},
  'account':{'list':set(),'show':set(),'create':{'envelope_from','header_from','dsn_mailbox','password_fd'},'update':{'envelope_from','header_from','dsn_mailbox'},'enable':set(),'disable':set(),'delete':set(),'password':{'password_fd'}}}
 opts={k:v for k,v in vals.items() if k in {'quota_bytes','bytes','password_fd','to','old_address','scope','receive','imap','submission','mailbox','dsn_mailbox','confirm_mailbox','backup_id','envelope_from','header_from'} and v is not None}
 if a.family in ('reconcile','status'):
  if a.verb or a.selector or opts:refuse('MAIL_USAGE')
 else:
  if a.verb not in allowed[a.family] or set(opts)-allowed[a.family][a.verb]:refuse('MAIL_USAGE')
  if (a.verb=='list')!=(a.selector is None):refuse('MAIL_USAGE')
  required={'rename':{'to'},'quota':{'bytes'},'enable':{'scope'},'disable':{'scope'},'purge':{'confirm_mailbox','backup_id'}} if a.family=='mailbox' else {'create':{'mailbox'}} if a.family=='alias' else {'create':{'envelope_from','header_from','dsn_mailbox'}}
  if not required.get(a.verb,set())<=set(opts):refuse('MAIL_USAGE')
  if a.verb=='update' and not opts:refuse('MAIL_USAGE')
  if a.family=='mailbox' and a.verb in ('enable','disable') and a.scope not in ('receive','imap','submission','all'):refuse('MAIL_USAGE')
  if a.old_address is not None and a.old_address not in ('alias','reject'):refuse('MAIL_USAGE')
  if a.include_deleted and a.verb not in ('list','show'):refuse('MAIL_USAGE')
  if a.verb!='list' and (a.limit is not None or a.cursor is not None):refuse('MAIL_USAGE')
  if a.limit is not None and not 1<=a.limit<=1000:refuse('MAIL_USAGE')
 return a,opts

def bridge(action,cfg,input=None,lock_fd=None):
 data=input if isinstance(input,bytes) else encode(input or {}).encode()
 r=subprocess.run(['/usr/bin/node',str(pathlib.Path(__file__).with_name('bridge.cjs')),action,cfg],input=data,capture_output=True,timeout=180,pass_fds=(() if lock_fd is None else (lock_fd,)),env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':'/'})
 try:out=json.loads(r.stdout)
 except (ValueError,UnicodeError):refuse('MAIL_DEPENDENCY_UNAVAILABLE')
 if not out.get('ok'):
  native=out.get('code');mapping={'MAIL_PROFILE_INVALID':'MAIL_VALIDATION','MAIL_SERVICE_INVALID':'MAIL_VALIDATION','MAIL_PRIVATE_FILE_UNSAFE':'MAIL_STORAGE_UNSAFE','MAIL_RUNTIME_UPGRADE_REQUIRED':'MAIL_DEPENDENCY_UNAVAILABLE','MAIL_RUNTIME_NETWORK_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_RUNTIME_MOUNT_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_RUNTIME_LISTENER_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_RUNTIME_EXECUTION_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_RUNTIME_IMAGE_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_MAILBOX_IDENTITY_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_SECRET_PROJECTION_MISMATCH':'MAIL_RESOURCE_IDENTITY_MISMATCH','MAIL_STORAGE_GUARD_FAILED':'MAIL_STORAGE_UNSAFE','RESOURCE_PERMISSIONS_UNSAFE':'MAIL_STORAGE_UNSAFE','UNSAFE_RESOURCE_PATH':'MAIL_STORAGE_UNSAFE'}
  error=Refusal(native if native in EXITS else mapping.get(native,'MAIL_DEPENDENCY_UNAVAILABLE'))
  if isinstance(out.get('code'),str) and re.fullmatch(r'[A-Z0-9_]+',out['code']):error.dependency_code=out['code']
  raise error
 return out['data']

def envelope(db=None,**fields):
 result=dict(contract='drumee.mail-cli/1',ok=True,code='OK')
 if db:result.update(desired_revision=db.get('desired_revision'),applied_revision=db.get('applied_revision'))
 result.update(fields);return result

def sanitize(data):
 # Never project a credential file reference or verifier into an operator result.
 if isinstance(data,list):return [sanitize(x) for x in data]
 if isinstance(data,dict):return {k:sanitize(v) for k,v in data.items() if k not in ('dsn_native',)}
 return copy.deepcopy(data)

def abort_precommit(db,row,code='MAIL_CANCELLED'):
 result=envelope(db,ok=False,code=code,operation_id=row['id'],changed=False,retryable=False,data={'phase':'aborted-before-staging'})
 db.db.execute("UPDATE operations SET phase='aborted',result=? WHERE id=?",(encode(result),row['id']));return result

def finish(db,row,cfg,fd):
 phase=row['phase']
 if phase in ('applied','aborted'):return json.loads(row['result'])
 target=row['target'];intent=json.loads(row['intent']);purge=intent['family']=='mailbox' and intent['verb']=='purge'
 parent=safe_directory(db.dir/'requests',True);directory=parent/row['id'];safe_directory(directory,True)
 marker=directory/'owner.json';identity=encode({'operation_id':row['id'],'base':row['base'],'target':target})
 if marker.exists():
  if private_read(marker).decode()!=identity:refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
 else:
  if list(directory.iterdir()):refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
  atomic(marker,identity.encode())
 native={'prepared':str(directory/'prepared.json'),'previous':row['base'],'keep_barrier':True}
 if purge:native.update(mailbox_id=intent['selector'],backup_id=intent['options']['backup_id'],operation_id=row['id'])
 # SQLite already records the verified target, but the final admission/receipt step
 # may have been interrupted. Never read another password or allocate a revision.
 if db.get('applied_revision')==target and row['result']:
  try:bridge('purge-finish' if purge else 'release',cfg,native,fd)
  except Refusal:
   if purge:refuse('MAIL_APPLY_INCOMPLETE')
   bridge('resume-runtime',cfg,native,fd);bridge('apply',cfg,native,fd);bridge('release',cfg,native,fd)
  db.db.execute("UPDATE operations SET phase='applied' WHERE id=?",(row['id'],));return json.loads(row['result'])
 input=dict(registry=projection(json.loads(row['state']),target),verifiers=row['secrets'],output=native['prepared'])
 if phase=='validated':
  if not pathlib.Path(row['secrets']).exists():
   if (directory/'prepare-started').exists():refuse('MAIL_INTEGRITY_FAILURE')
   return abort_precommit(db,row)
  private_read(row['secrets']);atomic(directory/'prepare-started',b'true')
  bridge('prepare',cfg,input,fd);db.db.execute("UPDATE operations SET phase='staged' WHERE id=?",(row['id'],));phase='staged'
 if phase=='staged':
  if purge:bridge('purge-check',cfg,native,fd)
  else:bridge('resume-runtime',cfg,native,fd);bridge('barrier',cfg,native,fd)
  db.begin();db.store(json.loads(row['state']));db.put('desired_revision',target);db.put('secret_file',row['secrets']);db.db.execute("UPDATE operations SET phase='committed' WHERE id=?",(row['id'],));db.commit();phase='committed'
 if phase in ('committed','applying'):
  db.db.execute("UPDATE operations SET phase='applying' WHERE id=?",(row['id'],))
  try:
   if purge:bridge('purge-erase',cfg,native,fd)
   bridge('resume-runtime',cfg,native,fd);bridge('apply',cfg,native,fd)
  except Refusal:refuse('MAIL_APPLY_INCOMPLETE')
  state=json.loads(row['state']);family=intent['family'];obj=None
  if family in ('mailbox','account'):obj=find(state,family,intent['options']['to'] if intent['verb']=='rename' else intent['selector'],True) if intent['verb']!='create' else next(x for x in state['mailboxes' if family=='mailbox' else 'accounts'] if x.get('address',x['id'])==intent['selector'])
  elif family=='alias':obj=next(x for x in state['aliases'] if x['address']==intent['selector'])
  data=sanitize(obj)
  if family=='alias' and intent['verb']=='update' and 'mailbox' in intent['options']:
   old=next(x for x in db.get('applied_state')['aliases'] if x['address']==intent['selector']);data.update(old_mailbox_id=old['mailbox_id'],new_mailbox_id=obj['mailbox_id'])
  result=envelope(db,operation_id=row['id'],changed=True,desired_revision=target,applied_revision=target,data=data)
  if family=='mailbox' and intent['verb']=='quota':result['data'].update(bridge('usage',cfg,{'id':obj['id']},fd))
  db.begin();db.put('applied_revision',target);db.put('applied_state',state);db.db.execute("UPDATE operations SET result=? WHERE id=?",(encode(result),row['id']));db.commit()
  try:bridge('purge-finish' if purge else 'release',cfg,native,fd)
  except Refusal:refuse('MAIL_APPLY_INCOMPLETE')
  db.db.execute("UPDATE operations SET phase='applied' WHERE id=?",(row['id'],));return result
 refuse('MAIL_RECOVERY_REQUIRED')

def execute(a,opts):
 global CURRENT
 if not a.execute and (a.family=='reconcile' or a.family in ('mailbox','alias','account') and a.verb not in ('list','show')):refuse('MAIL_NOT_AUTHORIZED')
 cfgfile=os.path.abspath(a.config)
 try:
  cfg=json.loads(private_read(cfgfile));service=cfg['service'];deployment=service['deployment'];assert isinstance(deployment,dict)
 except (ValueError,KeyError,TypeError,AssertionError):refuse('MAIL_VALIDATION')
 root=safe_directory(service['deployment']['root']);check_runtime(root);owner=json.loads(private_read(root/'owner.json'))
 if owner!={'contract':'drumee.mail-owner/1','id':service['deployment']['id'],'project':service['deployment']['project'],'uid':os.getuid(),'gid':os.getgid()}:refuse('MAIL_NOT_AUTHORIZED')
 # Share this descriptor lock with every lifecycle entry point; inherited by bridge children.
 with service_lock(root,timeout=15) as fd:
  service=bridge('identity',cfgfile,lock_fd=fd)['service']
  db=Authority(root/'durable/operator-state/admin',owner);CURRENT=(db,root)
  if db.get('desired_revision') is None:
   if db.initialized or any(db.db.execute('SELECT count(*) FROM '+table).fetchone()[0] for table in ('mailboxes','addresses','accounts','operations')):refuse('MAIL_INTEGRITY_FAILURE')
   registry=bridge('inspect',cfgfile,lock_fd=fd);bridge('snapshot',cfgfile,lock_fd=fd);state=initial(registry);secret=private_read(cfg['verifiers_file']);secretdir=safe_directory(db.dir/'credentials',True);atomic(secretdir/'bootstrap.json',secret)
   db.begin();db.store(state);db.put('applied_state',state);db.put('desired_revision',registry['generation']);db.put('applied_revision',registry['generation']);db.put('secret_file',str(secretdir/'bootstrap.json'));db.commit()
  if not db.initialized:db.mark_initialized()
  state=db.get('applied_state');revision=db.get('applied_revision')
  actual=json.loads(private_read(root/'durable/registry/public/current.json'));pending=db.pending()
  expected=projection(state,revision);observed={k:actual[k] for k in ('contract','generation','mailboxes','aliases','accounts')}
  for box in observed['mailboxes']:box.setdefault('credential_generation',actual['generation'])
  if not pending and observed!=expected:refuse('MAIL_INTEGRITY_FAILURE')
  if a.family=='status':return envelope(db,data={'pending_operation':db.pending(),'native_generation':actual['generation'],'transport_running':bridge('runtime',cfgfile,lock_fd=fd)['running'],'admission':'closed' if (root/'durable/registry/public/admission-closed').exists() else 'open'})
  if a.family=='reconcile':
   if not a.execute:refuse('MAIL_NOT_AUTHORIZED')
   id=db.pending();return finish(db,db.operation(id),cfgfile,fd) if id else envelope(db,changed=False,data={'pending_operation':None})
  if a.verb in ('list','show'):
   if a.verb=='show':
    obj=sanitize(find(state,a.family,a.selector.lower(),a.include_deleted))
    if a.family=='mailbox':
     obj['aliases']=[sanitize(x) for x in state['aliases'] if x['mailbox_id']==obj['id'] and not x['deleted']]
     try:
      usage=bridge('usage',cfgfile,{'id':obj['id']},fd);obj.update({k:usage[k] for k in ('used_bytes','messages','observed_at','advisory')});obj['over_quota']=usage['used_bytes']>obj['quota_bytes'];obj['observed_projection_quota_bytes']=usage['quota_bytes']
     except Refusal:obj.update(used_bytes=None,messages=None,over_quota=None,observation_available=False)
    return envelope(db,data=obj)
   items=state[{'mailbox':'mailboxes','alias':'aliases','account':'accounts'}[a.family]];items=[x for x in items if a.include_deleted or not x.get('deleted')];key='address' if a.family=='alias' else 'id';items=sorted(items,key=lambda x:x[key]);last=''
   if a.mailbox:items=[x for x in items if x['mailbox_id']==find(state,'mailbox',a.mailbox.lower(),a.include_deleted)['id']]
   if a.cursor:
    try:r,last=a.cursor.split(':',1);assert int(r)==revision
    except (ValueError,AssertionError):refuse('MAIL_REVISION_CONFLICT')
   items=[x for x in items if x[key]>last];limit=a.limit or 100;page=items[:limit];cursor=str(revision)+':'+page[-1][key] if len(items)>limit else None
   return envelope(db,data={'items':sanitize(page),'next_cursor':cursor,'snapshot_revision':revision})
  if not a.execute:refuse('MAIL_NOT_AUTHORIZED')
  if a.if_revision is None or a.request_id is None:
   if not sys.stdin.isatty():refuse('MAIL_USAGE')
   # CPython's update-mode text stream requires seekability; a controlling TTY
   # is not seekable. Separate read/write handles also keep confirmation bounded.
   with open('/dev/tty','w') as writer,open('/dev/tty','r') as reader:
    writer.write('Apply '+encode({'family':a.family,'verb':a.verb,'selector':a.selector,'options':{k:v for k,v in opts.items() if k!='password_fd'}})+' at revision '+str(revision)+'? Type yes: ');writer.flush()
    if reader.readline(32).strip()!='yes':refuse('MAIL_CANCELLED')
   a.if_revision=revision;a.request_id=str(uuid.uuid4())
  try:
   if str(uuid.UUID(a.request_id))!=a.request_id:refuse('MAIL_USAGE')
  except ValueError:refuse('MAIL_USAGE')
  selector=a.selector.lower();public_opts={k:v for k,v in opts.items() if k!='password_fd'}
  for k in ('to',):
   if k in public_opts:public_opts[k]=address(public_opts[k],service['domains'])
  for k in ('mailbox','dsn_mailbox'):
   if k in public_opts:public_opts[k]=public_opts[k].lower()
  for k in ('envelope_from','header_from'):
   if k in public_opts:public_opts[k]=sorted(set(address(x,service['domains']) for x in public_opts[k]))
  if a.family=='mailbox' and a.verb=='create':public_opts.setdefault('quota_bytes',service['delivery']['default_quota_bytes'])
  if a.family=='mailbox' and a.verb=='rename':public_opts.setdefault('old_address','alias')
  intent=dict(family=a.family,verb=a.verb,selector=selector,options=public_opts,if_revision=a.if_revision);encoded=encode(intent);prior=db.operation(a.request_id)
  if prior:
   if prior['intent']!=encoded:refuse('MAIL_REQUEST_CONFLICT')
   return finish(db,prior,cfgfile,fd)
  if db.pending():refuse('MAIL_RECOVERY_REQUIRED')
  if a.if_revision!=revision:refuse('MAIL_REVISION_CONFLICT')
  if a.verb=='purge':
   if a.confirm_mailbox!=selector:refuse('MAIL_VALIDATION')
   box=find(state,'mailbox',selector,True)
   if not box['deleted'] or selector!=box['id']:refuse('MAIL_VALIDATION')
   if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,63}',a.backup_id):refuse('MAIL_VALIDATION')
   bridge('purge-precheck',cfgfile,{'mailbox_id':selector,'backup_id':a.backup_id,'operation_id':a.request_id,'previous':revision},fd)
   nextstate=copy.deepcopy(state);obj=find(nextstate,'mailbox',selector,True);obj.update(purged=True,purge_backup_id=a.backup_id,retained_identity=True,purged_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
  else:
   nextstate,obj=mutate(state,a.family,a.verb,selector,public_opts,service['domains'],service['delivery']['default_quota_bytes'],service['listeners']['smtp25']['enabled'])
  if nextstate==state:
   result=envelope(db,operation_id=a.request_id,changed=False,data=obj);db.db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?,?,?,?)',(a.request_id,encoded,revision,revision,'applied',encode(state),db.get('secret_file'),encode(result),os.getuid()));return result
  if a.verb!='purge':bridge('available',cfgfile,lock_fd=fd)
  needs_password=a.verb in ('create','password') and a.family in ('mailbox','account')
  password=(read_fd(a.password_fd) if a.password_fd is not None else read_tty()) if needs_password else None
  secret=db.dir/'credentials'/(a.request_id+'.json') if needs_password else pathlib.Path(db.get('secret_file'))
  requestdir=safe_directory(db.dir/'requests',True)
  if (requestdir/a.request_id).exists() or needs_password and secret.exists():refuse('MAIL_RESOURCE_IDENTITY_MISMATCH')
  target=max(revision,db.get('generation_high_water') or revision)+1;nextstate['generation']=target
  db.begin();db.put('generation_high_water',target);db.db.execute('INSERT INTO operations VALUES(?,?,?,?,?,?,?,?,?)',(a.request_id,encoded,revision,target,'validated',encode(nextstate),str(secret),None,os.getuid()));db.commit()
  if needs_password:
   try:
    verifiers=json.loads(private_read(db.get('secret_file')));verifiers[obj['id']]=bridge('hash',cfgfile,password,fd)['verifier'];atomic(secret,encode(verifiers).encode(),exclusive=True);del password,verifiers
   except Refusal as error:return abort_precommit(db,db.operation(a.request_id),error.code)
  return finish(db,db.operation(a.request_id),cfgfile,fd)

def main(argv):
 a=None
 try:
  a,opts=parse(argv)
  for name in os.listdir('/proc/self/fd'):
   fd=int(name)
   if fd>2 and fd!=a.password_fd:
    try:os.close(fd)
    except OSError:pass
  result=execute(a,opts);code=0 if result["ok"] else EXITS.get(result["code"],8)
 except (KeyboardInterrupt,InterruptedError):result=envelope(ok=False,code='MAIL_CANCELLED');code=130
 except Refusal as e:result=envelope(ok=False,code=e.code,data={'dependency_code':e.dependency_code} if hasattr(e,'dependency_code') else {});code=EXITS.get(e.code,8)
 except (OSError,ValueError,KeyError,sqlite3.Error,subprocess.SubprocessError):result=envelope(ok=False,code='MAIL_RECOVERY_REQUIRED');code=7
 if not result['ok'] and a:
  if a.request_id and re.fullmatch(r'[a-f0-9-]{36}',a.request_id):result['operation_id']=a.request_id
  result.setdefault('retryable',code in (6,7))
  if CURRENT is not None:
   db,root=CURRENT
   try:
    if db.db.in_transaction:db.db.rollback()
    values=dict(db.db.execute("SELECT key,value FROM meta WHERE key IN ('desired_revision','applied_revision')"));pending=db.db.execute("SELECT id,phase FROM operations WHERE phase NOT IN ('applied','aborted') ORDER BY target LIMIT 1").fetchone();result.update({k:json.loads(v) for k,v in values.items()})
    if pending:result.setdefault('operation_id',pending[0]);result.setdefault('data',{}).update(phase=pending[1],pending_operation=pending[0],admission='closed' if (root/'durable/registry/public/admission-closed').exists() else 'open')
   except (OSError,ValueError,KeyError,sqlite3.Error,Refusal):pass
 if a and a.json:print(encode(result))
 else:print(result['code']+' '+encode(result.get('data',{})))
 return code
if __name__=='__main__':
 os.umask(0o077);resource.setrlimit(resource.RLIMIT_CORE,(0,0));signal.signal(signal.SIGTERM,lambda *_:refuse('MAIL_CANCELLED'));sys.exit(main(sys.argv[1:]))
