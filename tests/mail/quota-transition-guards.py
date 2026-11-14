"""Native quota-transition refusals preserve foreign settings and lock metadata."""
import pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
user='quota-guard-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Guard-'+uuid.uuid4().hex;box=cli('mailbox','create',user,opts=['--quota-bytes','2097152'],password=passwords[user],mutate=True)['data'];home=root/'service/durable/mailboxes'/box['id']/'home';node=p['compose']['services']['policy']['image']
def setting():
 r=run(['docker','exec',project+'-postfix-1','postconf','-c','/config','-h','defer_transports']);assert r.returncode==0;return r.stdout.decode().strip()
def lock(operation):
 code="const f=require('node:fs'),p='/data/.drumee-quota.lock';if(process.argv[1]==='bad')f.chmodSync(p,0o644);else if(process.argv[1]==='repair')f.chmodSync(p,0o600);const s=f.lstatSync(p);console.log(JSON.stringify({ino:s.ino,uid:s.uid,gid:s.gid,mode:s.mode&0o7777,size:s.size,nlink:s.nlink}));"
 r=run(['docker','run','--rm','--network','none','--read-only','--user','5000:5000','--cap-drop','ALL','--security-opt','no-new-privileges:true','--mount',f'type=bind,source={home},target=/data','--entrypoint','node',node,'-e',code,operation]);assert r.returncode==0,r.stderr.decode()[-500:];return json.loads(r.stdout)
assert setting()=='';assert run(['docker','exec',project+'-postfix-1','postconf','-c','/config','-e','defer_transports=smtp']).returncode==0;before=state['revision']
try:
 refused=cli('mailbox','quota',user,opts=['--bytes','1048576'],mutate=True,expected='MAIL_APPLY_INCOMPLETE');assert refused['applied_revision']==before;assert setting()=='smtp';assert (root/'service/durable/registry/public/admission-closed').exists();check('unowned-defer-setting-refused-without-overwrite-or-new-quota',refused)
finally:assert run(['docker','exec',project+'-postfix-1','postconf','-c','/config','-X','defer_transports']).returncode==0
cli('reconcile',opts=['--execute']);before=state['revision'];bad=lock('bad')
try:
 refused=cli('mailbox','quota',user,opts=['--bytes','2097152'],mutate=True,expected='MAIL_APPLY_INCOMPLETE');assert refused['applied_revision']==before and lock('observe')==bad;assert setting()=='lmtp';check('unsafe-native-quota-lock-refused-and-left-unchanged',{'result':refused,'lock':bad})
finally:repaired=lock('repair');assert repaired['ino']==bad['ino'] and repaired['mode']==0o600
cli('reconcile',opts=['--execute']);assert setting()=='';assert not (root/'service/durable/registry/public/admission-closed').exists();check('same-intent-reconciliation-after-explicit-guard-repair',{'applied_revision':state['revision'],'lock_inode_preserved':True})
result={'status':'PASS_MAIL03_QUOTA_TRANSITION_GUARDS','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-quota-guards-result.json').write_text(json.dumps(result,indent=2));print(result['status'])
