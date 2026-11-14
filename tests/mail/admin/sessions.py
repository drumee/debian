"""CLI rotation observed on active SMTP/IMAP and accepted-message boundary."""
from common import *
users=['session-'+uuid.uuid4().hex[:8]+'@oxymot.fr' for _ in range(2)]
for user in users:
 passwords[user]='Session-'+uuid.uuid4().hex;cli('mailbox','create',user,password=passwords[user],mutate=True)
cli('mailbox','enable',users[0],opts=['--scope','submission'],mutate=True);write_passwords()
for name in ('session-ready','session-release'):
 file=private/name
 if file.exists():file.unlink()
tag='before-rotation-'+uuid.uuid4().hex
args=['docker','run','--rm','-i','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={private},target=/private','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','/lab/session-probe.py']
child=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);child.stdin.write(json.dumps({'user':users[0],'other':users[1],'tag':tag}).encode());child.stdin.close()
try:
 for _ in range(200):
  if (private/'session-ready').exists():break
  if child.poll() is not None:raise AssertionError('session preparation failed '+child.stderr.read().decode()[-300:])
  time.sleep(.1)
 else:raise TimeoutError('held session synchronization')
 old=passwords[users[0]];passwords[users[0]]='Rotated-'+uuid.uuid4().hex;cli('mailbox','password',users[0],password=passwords[users[0]],mutate=True)
 (private/'session-release').write_text('go');child.wait(timeout=60);assert child.returncode==0;observed=json.loads(child.stdout.read());assert observed['mail_after_change']==421 and observed['data_after_change']==421;assert observed['target_imap_after_change']=='disconnected';assert observed['unrelated_imap_after_change']=='OK';check('rotation-revokes-held-smtp-and-target-imap-preserves-unrelated',observed)
 assert wait_read(users[0],tag)['matches']==1;passwords['old']=old;assert not probe(action='imap',user=users[0],credential='old')['ok'];assert probe(action='imap',user=users[0])['ok'];check('rotation-preserves-final-250-message-and-rejects-old-password',{'matches':1})
finally:
 if child.poll() is None:child.terminate();child.wait(timeout=10)
result={'status':'PASS_MAIL03_NATIVE_SESSIONS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-session-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
