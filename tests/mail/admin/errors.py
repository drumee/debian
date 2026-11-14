"""Stable CLI refusals and preservation of protected authority/input inodes."""
from common import *
import fcntl
cli('mailbox','show','missing-'+uuid.uuid4().hex[:8]+'@oxymot.fr',expected='MAIL_NOT_FOUND')
cli('mailbox','create','denied@oxymot.fr',expected='MAIL_NOT_AUTHORIZED')
cli('mailbox','create','CONTACT@oxymot.fr',mutate=True,expected='MAIL_ADDRESS_CONFLICT')
cli('mailbox','create','invalid@oxymot.fr',opts=['--quota-bytes','0'],mutate=True,expected='MAIL_VALIDATION')
cli('mailbox','update','contact@oxymot.fr',opts=['--receive','yes'],mutate=True,expected='MAIL_USAGE')
cli('alias','create','bad-chain@oxymot.fr',opts=['--mailbox','hello@oxymot.fr'],mutate=True,expected='MAIL_NOT_FOUND')
cli('mailbox','create','short-'+uuid.uuid4().hex[:8]+'@oxymot.fr',password='short',mutate=True,expected='MAIL_PASSWORD_INVALID')
cli('mailbox','create','unsafe-'+uuid.uuid4().hex[:8]+'@oxymot.fr',opts=['--password-fd','127'],mutate=True,expected='MAIL_SECRET_INPUT_UNSAFE');check('stable-input-notfound-collision-authorization-errors',{'exits':[2,3,4,5]})
database=root/'service/durable/operator-state/admin/registry.sqlite3';original=database.stat();database.chmod(0o640)
try:cli('mailbox','list',expected='MAIL_STORAGE_UNSAFE');assert database.stat().st_mode&0o777==0o640
finally:database.chmod(0o600)
retained=database.with_name('temporarily-retained.sqlite3');assert not retained.exists();database.rename(retained)
try:cli('mailbox','list',expected='MAIL_RESOURCE_IDENTITY_MISMATCH');assert not database.exists()
finally:retained.rename(database)
assert database.stat().st_ino==original.st_ino;cli('status');check('unsafe-or-missing-database-refuses-without-repair-or-readoption',{'inode_preserved':True,'exits':[5,8]})
lock=root/('.mail-admin-'+hashlib.sha256(str(root/'service').encode()).hexdigest()+'.lock');fd=os.open(lock,os.O_RDWR);fcntl.flock(fd,fcntl.LOCK_EX)
try:
 r=run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','stop','--execute','--config',str(cfg)]);assert r.returncode==6 and json.loads(r.stdout)['code']=='MAIL_LOCK_BUSY';cli('status',expected='MAIL_LOCK_BUSY')
finally:os.close(fd)
check('live-descriptor-lock-bounds-cli-and-lifecycle-contention',{'exit':6,'force_unlock':False})
user='exact-'+uuid.uuid4().hex[:8]+'@oxymot.fr';secret=' '+('é'*510)+' ! ';assert len(secret.encode())==1024;passwords[user]=secret;cli('mailbox','create',user,password=secret,mutate=True);assert probe(action='imap',user=user)['ok'];passwords['trimmed']=secret.strip();assert not probe(action='imap',user=user,credential='trimmed')['ok'];check('1024-byte-utf8-and-spaces-native-verifier-no-normalization',{'bytes':1024,'exact_accepted':True,'trimmed_refused':True})
result={'status':'PASS_MAIL03_NATIVE_ERRORS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-errors-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':len(checks)}))
