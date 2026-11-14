"""Historical mail03.6 failure reproduction; corrected contract: quota-transition-native.py."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
user='held-quota-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Held-quota-'+uuid.uuid4().hex;box=cli('mailbox','create',user,opts=['--quota-bytes','2097152'],password=passwords[user],mutate=True)['data'];tag='held-quota-'+uuid.uuid4().hex
for name in ('held-lmtp','release-lmtp'):
 file=private/name
 if file.exists():file.unlink()
code="""import smtplib,pathlib,time,json,sys
r=json.loads(sys.stdin.buffer.read());body=('From: outside@dest.invalid\\r\\nMessage-ID: <'+r['tag']+'@fixture.invalid>\\r\\n\\r\\n').encode()+b'x'*1200000
s=smtplib.LMTP('/run/mail-sockets/lmtp',timeout=120);s.ehlo();assert s.mail('outside@dest.invalid')[0]==250;assert s.rcpt('mbx-'+r['id']+'@local.invalid')[0]==250;assert s.docmd('DATA')[0]==354;s.send(body[:100000]);pathlib.Path('/private/held-lmtp').write_text('DATA first100000 bytes sent')
for _ in range(1200):
 if pathlib.Path('/private/release-lmtp').exists():break
 time.sleep(.1)
else:raise TimeoutError('release')
try:s.send(body[100000:]+b'\\r\\n.\\r\\n');print(json.dumps({'lmtp_final_code':s.getreply()[0]}))
except (smtplib.SMTPException,OSError):print(json.dumps({'lmtp_final_code':None,'disconnected':True}))
"""
args=['docker','run','--rm','-i','--network','none','--mount','type=volume,source='+project+'-sockets,target=/run/mail-sockets','--mount',f'type=bind,source={private},target=/private','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-c',code];child=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE);child.stdin.write(json.dumps({'id':box['id'],'tag':tag}).encode());child.stdin.close()
try:
 for _ in range(200):
  if (private/'held-lmtp').exists():break
  if child.poll() is not None:raise AssertionError(child.stderr.read().decode()[-300:])
  time.sleep(.1)
 else:raise TimeoutError('LMTP DATA not held')
 time.sleep(.5);changed=cli('mailbox','quota',user,opts=['--bytes','1048576'],mutate=True);(private/'release-lmtp').write_text('go');child.wait(timeout=60);assert child.returncode==0;delivery=json.loads(child.stdout.read());time.sleep(.5);shown=cli('mailbox','show',user)['data'];valid=shown['used_bytes'] is not None and shown['used_bytes']<=1048576;result={'status':'PASS_HELD_LMTP_QUOTA_CHANGE' if valid else 'FAIL_HELD_LMTP_QUOTA_CHANGE','checks':[{'name':'held-old-limit-lmtp-cannot-commit-above-new-applied-quota','status':'PASS' if valid else 'FAIL','observation':{'change':changed,'delivery':delivery,'used_bytes':shown['used_bytes'],'quota_bytes':shown['quota_bytes']}}],'commands':commands};(root/'held-quota-result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result['checks'][0]),flush=True)
finally:
 if child.poll() is None:(private/'release-lmtp').write_text('go');child.wait(timeout=60)
raise SystemExit(0 if valid else 1)
