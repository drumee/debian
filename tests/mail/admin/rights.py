"""Grant and scope changes on held native sessions and final acceptance."""
from common import *
users=['rights-'+uuid.uuid4().hex[:8]+'@oxymot.fr' for _ in range(2)]
for user in users:
 passwords[user]='Rights-'+uuid.uuid4().hex;cli('mailbox','create',user,password=passwords[user],mutate=True)
passwords['ghost']='Ghost-'+uuid.uuid4().hex;cli('account','password','ghost',password=passwords['ghost'],mutate=True);cli('account','update','ghost',opts=['--envelope-from',users[0],'--header-from',users[0],'--dsn-mailbox',users[0]],mutate=True);cli('account','enable','ghost',mutate=True)
for mode in ('account-grants','mailbox-all-disable'):
 if mode=='mailbox-all-disable':cli('mailbox','enable',users[0],opts=['--scope','submission'],mutate=True)
 write_passwords()
 for name in ('session-ready','session-release'):
  file=private/name
  if file.exists():file.unlink()
 tag='rights-accepted-'+uuid.uuid4().hex
 args=['docker','run','--rm','-i','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={private},target=/private','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','/lab/session-probe.py']
 child=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);child.stdin.write(json.dumps({'user':users[0],'other':users[1],'auth':'ghost' if mode=='account-grants' else users[0],'tag':tag}).encode());child.stdin.close()
 try:
  for _ in range(200):
   if (private/'session-ready').exists():break
   if child.poll() is not None:raise AssertionError('session setup '+child.stderr.read().decode()[-300:])
   time.sleep(.1)
  else:raise TimeoutError('held session synchronization')
  if mode=='account-grants':cli('account','update','ghost',opts=['--header-from',users[1]],mutate=True)
  else:cli('mailbox','disable',users[0],opts=['--scope','all'],mutate=True)
  (private/'session-release').write_text('go');child.wait(timeout=60);assert child.returncode==0;observed=json.loads(child.stdout.read());assert observed['mail_after_change']==421 and observed['data_after_change']==421;assert observed['unrelated_imap_after_change']=='OK';assert observed['target_imap_after_change']==('OK' if mode=='account-grants' else 'disconnected');check(mode+'-revokes-smtp-at-next-mail-and-final-data',observed)
  if mode=='mailbox-all-disable':
   assert probe(action='rcpt',recipient=users[0])['rcpt_code']==550;assert not probe(action='imap',user=users[0])['ok'];assert not probe(action='submit',auth=users[0],sender=users[0],recipient=users[1],tag='denied')['ok'];cli('mailbox','enable',users[0],opts=['--scope','imap'],mutate=True)
  assert wait_read(users[0],tag)['matches']==1;check(mode+'-preserves-accepted-message',{'matches':1})
 finally:
  if child.poll() is None:child.terminate();child.wait(timeout=10)
result={'status':'PASS_MAIL03_NATIVE_RIGHTS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-rights-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
