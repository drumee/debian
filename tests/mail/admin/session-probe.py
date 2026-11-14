"""Held native sessions; synchronization contains public markers only."""
import json,pathlib,sys,time,smtplib,imaplib,socket,ssl,base64
r=json.loads(sys.stdin.buffer.read());private=pathlib.Path('/private');pw=json.loads((private/'passwords.json').read_text());ctx=ssl.create_default_context(cafile='/keys/ca.pem')
def smtp(user):
 s=smtplib.SMTP('postfix',587,timeout=30);s.ehlo();s._host='mail.oxymot.fr';s.starttls(context=ctx);s.ehlo();assert s.docmd('AUTH','PLAIN '+base64.b64encode(b'\0'+user.encode()+b'\0'+pw[user].encode()).decode())[0]==235;return s
class IMAP(imaplib.IMAP4_SSL):
 def _create_socket(self,timeout):return ctx.wrap_socket(socket.create_connection(('dovecot',993),timeout),server_hostname='mail.oxymot.fr')
def imap(user):
 s=IMAP('dovecot',993,ssl_context=ctx,timeout=30);s.authenticate('PLAIN',lambda _:b'\0'+user.encode()+b'\0'+pw[user].encode());s.select('INBOX');return s
user=r['user'];other=r['other'];first=smtp(user);data=smtp(user);accepted=smtp(user);target=imap(user);unrelated=imap(other)
assert data.mail(user)[0]==250 and data.rcpt(user)[0]==250
assert data.docmd('DATA')[0]==354
assert accepted.sendmail(user,[user],('From: '+user+'\r\nMessage-ID: <'+r['tag']+'@fixture.invalid>\r\n\r\n'+r['tag']+'\r\n').encode())=={}
(private/'session-ready').write_text('accepted-250-and-held-before-MAIL-and-final-DATA')
for _ in range(1200):
 if (private/'session-release').exists():break
 time.sleep(.1)
else:raise TimeoutError('release not observed')
out={'accepted_before_change':True}
try:out['mail_after_change']=first.mail(user)[0]
except (smtplib.SMTPException,OSError):out['mail_after_change']='disconnected'
try:
 data.send(('From: '+user+'\r\n\r\nunaccepted\r\n.\r\n').encode());out['data_after_change']=data.getreply()[0]
except (smtplib.SMTPException,OSError):out['data_after_change']='disconnected'
try:out['target_imap_after_change']=target.noop()[0]
except (imaplib.IMAP4.error,OSError):out['target_imap_after_change']='disconnected'
try:out['unrelated_imap_after_change']=unrelated.noop()[0]
except (imaplib.IMAP4.error,OSError):out['unrelated_imap_after_change']='disconnected'
print(json.dumps(out))
