"""Synthetic protocol probe. Passwords come only from a private read-only mount."""
import sys,json,pathlib,imaplib,smtplib,socket,ssl,email.utils,re,base64
request=json.loads(sys.stdin.buffer.read());passwords=json.loads(pathlib.Path('/private/passwords.json').read_text());ctx=ssl.create_default_context(cafile='/keys/ca.pem')
class IMAP(imaplib.IMAP4_SSL):
 def _create_socket(self,timeout):return ctx.wrap_socket(socket.create_connection(('dovecot',993),timeout),server_hostname='mail.oxymot.fr')
def smtp(auth=None):
 s=smtplib.SMTP('postfix',587 if auth else 25,timeout=15);s.ehlo('fixture.invalid')
 if auth:
  s._host='mail.oxymot.fr';s.starttls(context=ctx);s.ehlo();code,response=s.docmd('AUTH','PLAIN '+base64.b64encode(b'\0'+auth.encode()+b'\0'+passwords[request.get('credential',auth)].encode()).decode())
  if code!=235:raise smtplib.SMTPAuthenticationError(code,b'authentication refused')
 return s
try:
 action=request['action'];out={}
 if action in ('send','rcpt','submit'):
  with smtp(request.get('auth')) as s:
   sender=request.get('sender','outside@dest.invalid');code,_=s.mail(sender);out['mail_code']=code
   if code==250:
    code,_=s.rcpt(request['recipient']);out['rcpt_code']=code
    if code==250 and action!='rcpt':
     tag=request['tag'];wire=('From: '+request.get('header',sender)+'\r\nTo: '+request['recipient']+'\r\nMessage-ID: <'+tag+'@fixture.invalid>\r\nDate: '+email.utils.formatdate()+'\r\n\r\n'+tag+'\r\n').encode();code,text=s.data(wire);out['data_code']=code;m=re.search(rb'queued as ([A-Z0-9]+)',text);out['queue_id']=m.group(1).decode() if m else None
 elif action in ('imap','metadata','append','clear-folder'):
  with IMAP('dovecot',993,ssl_context=ctx,timeout=15) as s:
   s.authenticate('PLAIN',lambda _:b'\0'+request['user'].encode()+b'\0'+passwords[request.get('credential',request['user'])].encode());out['login']=True;s.select('INBOX');out['uidvalidity']=s.response('UIDVALIDITY')[1][0].decode();out['uids']=s.uid('search',None,'ALL')[1][0].decode().split();out['matches']=len(s.uid('search',None,'HEADER','Message-ID',request.get('tag','not-present'))[1][0].split());out['folders']=[x.decode() for x in s.list()[1]]
   if action=='append':
    folder=request['folder'];s.create(folder);out['append_code']=s.append(folder,None,None,b'From: quota@dest.invalid\r\nSubject: synthetic capacity\r\n\r\n'+b'x'*request['bytes'])[0]
   if action=='clear-folder':
    assert request['folder'].startswith('mail03-quota-');s.select(request['folder']);ids=s.search(None,'ALL')[1][0]
    if ids:s.store(ids.replace(b' ',b','),'+FLAGS','(\\Deleted)');s.expunge()
    s.select('INBOX');out['delete_code']=s.delete(request['folder'])[0]
   if action=='metadata':
    s.create('Kept');s.subscribe('Kept');ids=s.uid('search',None,'ALL')[1][0]
    if ids:s.uid('store',ids.replace(b' ',b','),'+FLAGS','(\\Flagged)')
    out['subscriptions']=[x.decode() for x in s.lsub()[1]];out['flags']=[x.decode() for x in s.fetch('1:*','FLAGS')[1] if isinstance(x,bytes)] if out['uids'] else []
    s.select('Kept');kept=s.uid('search',None,'ALL')[1][0]
    if not kept:
     s.append('Kept','(\\Seen)',None,b'From: fixture@dest.invalid\r\nSubject: retained folder metadata\r\n\r\nSynthetic retained message\r\n');s.select('Kept')
    out['kept_uidvalidity']=s.response('UIDVALIDITY')[1][0].decode();out['kept_uids']=s.uid('search',None,'ALL')[1][0].decode().split();out['kept_flags']=[x.decode() for x in s.fetch('1:*','FLAGS')[1] if isinstance(x,bytes)]
 else:raise ValueError('unknown probe')
 print(json.dumps({'ok':True,**out}))
except (imaplib.IMAP4.error,smtplib.SMTPException,OSError) as e:
 print(json.dumps({'ok':False,'type':type(e).__name__,'smtp_code':getattr(e,'smtp_code',None)}))
