"""Public administrative state and immutable transport projection; no credentials."""
import copy,re,uuid,datetime
class Refusal(Exception):
 def __init__(self,code):self.code=code;super().__init__(code)
def refuse(code):raise Refusal(code)
def address(value,domains):
 if not isinstance(value,str):refuse('MAIL_VALIDATION')
 value=value.lower()
 if len(value)>254 or value.count('@')!=1:refuse('MAIL_VALIDATION')
 user,domain=value.split('@')
 if domain not in domains or not re.fullmatch(r'[a-z0-9][a-z0-9._-]{0,63}',user) or '..' in user or user.endswith('.'):refuse('MAIL_VALIDATION')
 return value
def find(state,family,selector,deleted=False):
 key='mailboxes' if family=='mailbox' else 'accounts'
 for obj in state[key]:
  if selector in (obj['id'],obj.get('address')) and (deleted or not obj.get('deleted')):return obj
 refuse('MAIL_NOT_FOUND')
def initial(registry):
 s=copy.deepcopy(registry);s['reserved']=[]
 for b in s['mailboxes']:b.update(deleted=False,credential_generation=b.get('credential_generation',registry['generation']))
 for a in s['aliases']:a.update(deleted=False)
 for a in s['accounts']:
  target=a['envelope_from'][0];box=next((b for b in s['mailboxes'] if b['address']==target),None);alias=next((x for x in s['aliases'] if x['address']==target),None)
  a.update(deleted=False,dsn_native='dsn_mailbox_id' in a,dsn_mailbox=a.get('dsn_mailbox_id',box['id'] if box else alias['mailbox_id'] if alias else None))
 return s
def projection(s,generation):
 boxes=[{k:b[k] for k in ('id','address','quota_bytes','receive_enabled','imap_enabled','submission_enabled','credential_generation')} for b in s['mailboxes']]
 aliases=[{k:a[k] for k in ('address','mailbox_id','receive_enabled')} for a in s['aliases'] if not a['deleted']]
 accounts=[{k:a[k] for k in ('id','enabled','credential_generation','envelope_from','header_from')}|({'dsn_mailbox_id':a['dsn_mailbox']} if a.get('dsn_native') else {}) for a in s['accounts'] if not a['deleted']]
 return dict(contract='drumee.mail-registry/1',generation=generation,mailboxes=boxes,aliases=aliases,accounts=accounts)
def mutate(original,family,verb,selector,opts,domains,default_quota,public_mx=True):
 s=copy.deepcopy(original);data=None
 def reserved(addr):
  if addr in s['reserved'] or any(x['address']==addr for x in s['mailboxes']+s['aliases']):refuse('MAIL_ADDRESS_CONFLICT')
 def local(value):return address(value,domains)
 def retire_grants(addr):
  for a in s['accounts']:
   if a['deleted']:continue
   if addr in a['envelope_from'] or addr in a['header_from']:
    a['envelope_from']=[x for x in a['envelope_from'] if x!=addr];a['header_from']=[x for x in a['header_from'] if x!=addr];a['credential_generation']+=1
    if not a['envelope_from'] or not a['header_from']:a['enabled']=False
 def quota(n):
  if not isinstance(n,int) or not 1048576<=n<=1099511627776:refuse('MAIL_VALIDATION')
  return n
 if family=='mailbox':
  if verb=='create':
   addr=local(selector);reserved(addr);data=dict(id=str(uuid.uuid4()),address=addr,quota_bytes=quota(opts.get('quota_bytes',default_quota)),receive_enabled=True,imap_enabled=True,submission_enabled=False,deleted=False,credential_generation=1);s['mailboxes'].append(data)
  else:
   data=find(s,family,selector,verb=='delete')
   if verb=='rename':
    new=local(opts['to']);old=data['address'];reserved(new);s['reserved'].append(old);retire_grants(old)
    if opts.get('old_address','alias')=='alias':s['aliases'].append(dict(address=old,mailbox_id=data['id'],receive_enabled=data['receive_enabled'],deleted=False));s['reserved'].remove(old)
    data['address']=new
   elif verb in ('enable','disable'):
    for scope in (('receive','imap','submission') if opts['scope']=='all' else (opts['scope'],)):data[scope+'_enabled']=verb=='enable'
   elif verb=='update':
    for scope in ('receive','imap','submission'):
     if scope in opts:data[scope+'_enabled']=opts[scope]
   elif verb=='quota':data['quota_bytes']=quota(opts['bytes'])
   elif verb=='password':data['credential_generation']+=1
   elif verb=='delete':
    data.update(deleted=True,receive_enabled=False,imap_enabled=False,submission_enabled=False);retire_grants(data['address'])
    for a in s['aliases']:
     if a['mailbox_id']==data['id']:a['deleted']=True;retire_grants(a['address'])
   else:refuse('MAIL_USAGE')
 elif family=='alias':
  addr=local(selector);data=next((a for a in s['aliases'] if a['address']==addr and (verb=='delete' or not a['deleted'])),None)
  if verb=='create':
   reserved(addr);box=find(s,'mailbox',opts['mailbox']);data=dict(address=addr,mailbox_id=box['id'],receive_enabled=True,deleted=False);s['aliases'].append(data)
  else:
   if data is None:refuse('MAIL_NOT_FOUND')
   if verb=='delete':data['deleted']=True;retire_grants(addr)
   elif verb=='update':
    if 'mailbox' in opts:
     destination=find(s,'mailbox',opts['mailbox'])['id']
     if destination!=data['mailbox_id']:retire_grants(addr)
     data['mailbox_id']=destination
    if 'receive' in opts:data['receive_enabled']=opts['receive']
   else:refuse('MAIL_USAGE')
 elif family=='account':
  if not re.fullmatch(r'[a-z][a-z0-9-]{0,62}',selector or ''):refuse('MAIL_VALIDATION')
  if verb=='create':
   if any(a['id']==selector for a in s['accounts']+s['mailboxes']):refuse('MAIL_ADDRESS_CONFLICT')
   data=dict(id=selector,enabled=False,deleted=False,credential_generation=1,envelope_from=[],header_from=[],dsn_mailbox=None,dsn_native=True);s['accounts'].append(data)
  else:data=find(s,family,selector,verb=='delete')
  if verb in ('create','update'):
   data['dsn_native']=True
   for key in ('envelope_from','header_from'):
    if key in opts:data[key]=sorted(set(local(x) for x in opts[key]))
   if 'dsn_mailbox' in opts:data['dsn_mailbox']=find(s,'mailbox',opts['dsn_mailbox'])['id']
   if verb=='update':data['credential_generation']+=1
  elif verb in ('enable','disable','password','delete'):
   data['credential_generation']+=1
   if verb in ('enable','disable'):data['enabled']=verb=='enable'
   elif verb=='delete':data.update(enabled=False,deleted=True)
  else:refuse('MAIL_USAGE')
 else:refuse('MAIL_USAGE')
 # Tombstoned mailbox identities remain in the transport for accepted queue mail.
 # Empty disabled-account grants are represented only by the administrative tombstone.
 for a in s['accounts']:
  if a['deleted']:continue
  if not a['envelope_from'] or not a['header_from']:
   if family=='account' and verb in ('create','update','enable') and a is data:refuse('MAIL_VALIDATION')
  if a['enabled'] and family=='account' and a is data and verb in ('create','update','enable'):
   dsn=next((b for b in s['mailboxes'] if b['id']==a['dsn_mailbox']),None)
   if not dsn or dsn['deleted'] or not dsn['receive_enabled']:refuse('MAIL_DEPENDENCY_UNAVAILABLE')
  if family=='account' and a is data and verb in ('create','update','enable'):
   for addr in a['header_from']:
    if addr in s['reserved'] or any(x['address']==addr and x.get('deleted') for x in s['mailboxes']+s['aliases']):refuse('MAIL_VALIDATION')
  for addr in (a['envelope_from'] if family=='account' and a is data and verb in ('create','update','enable') else []):
   box=next((b for b in s['mailboxes'] if b['address']==addr),None)
   alias=next((b for b in s['aliases'] if b['address']==addr and not b['deleted']),None)
   target=box or (find(s,'mailbox',alias['mailbox_id']) if alias else None)
   if not target or target['deleted'] or not target['receive_enabled'] or target['id']!=a['dsn_mailbox']:refuse('MAIL_VALIDATION')
 if public_mx:
  def routable(state,addr):
   box=next((b for b in state['mailboxes'] if b['address']==addr),None)
   alias=next((a for a in state['aliases'] if a['address']==addr and not a['deleted'] and a['receive_enabled']),None)
   if alias:box=next((b for b in state['mailboxes'] if b['id']==alias['mailbox_id']),None)
   return box is not None and not box['deleted'] and box['receive_enabled']
  for domain in domains:
   for role in ('postmaster','abuse'):
    addr=role+'@'+domain
    if routable(original,addr) and not routable(s,addr):refuse('MAIL_DOMAIN_IN_USE')
 # Repeated desired flags are no-ops, including account credential generations.
 if family=='account' and verb in ('enable','disable','delete'):
  old=find(original,family,selector,True)
  if old.get('deleted')==data.get('deleted') and old['enabled']==data['enabled']:data['credential_generation']=old['credential_generation']
 for collection in ('mailboxes','aliases','accounts'):
  key='address' if collection=='aliases' else 'id'
  previous={x[key]:x for x in original[collection]}
  for item in s[collection]:
   old=previous.get(item[key])
   if old!=item:
    if collection=='mailboxes' and old and any(old.get(k)!=item.get(k) for k in ('address','receive_enabled','imap_enabled','submission_enabled')):item['credential_generation']=max(item['credential_generation'],old['credential_generation']+1)
    now=datetime.datetime.now(datetime.timezone.utc).isoformat()
    item.setdefault('created_at',old.get('created_at') if old else now);item['modified_at']=now
 return s,data
