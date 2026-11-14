"""Held old-limit recipient/writer plus an unrelated authenticated IMAP read."""
import sys,json,pathlib,socket,ssl,imaplib,smtplib,time,multiprocessing
r=json.loads(sys.stdin.buffer.read());root=pathlib.Path('/private');pw=json.loads((root/'passwords.json').read_text());ctx=ssl.create_default_context(cafile='/keys/ca.pem')
class IMAP(imaplib.IMAP4_SSL):
 def _create_socket(self,timeout):return ctx.wrap_socket(socket.create_connection(('dovecot',993),timeout),server_hostname='mail.oxymot.fr')
def login(user):
 s=IMAP('dovecot',993,ssl_context=ctx,timeout=120);s.authenticate('PLAIN',lambda _:b'\0'+user.encode()+b'\0'+pw[user].encode());s.select('INBOX');return s
def wait(suffix):
 for _ in range(1800):
  if (root/(r['marker']+suffix)).exists():return
  time.sleep(.05)
 raise TimeoutError('qualification marker not released')
def reader():
 other=login(r['other']);(root/(r['marker']+'.reader-ready')).write_text('unrelated authenticated session held');wait('.verify');result={'unrelated_imap':other.noop()[0]};other.logout();(root/(r['marker']+'.reader.json')).write_text(json.dumps(result))
observer=multiprocessing.get_context('fork').Process(target=reader);observer.start();wait('.reader-ready')
body=('From: outside@dest.invalid\r\nMessage-ID: <'+r['marker']+'@fixture.invalid>\r\n\r\n').encode()+b'x'*r['bytes'];kind=r['kind']
if kind=='imap':
 client=login(r['user']);client.send(b'PEND APPEND INBOX {'+str(len(body)).encode()+b'}\r\n');assert client.readline().startswith(b'+');client.send(body[:100000])
else:
 client=smtplib.LMTP('/run/mail-sockets/lmtp',timeout=120);client.ehlo();assert client.mail('outside@dest.invalid')[0]==250;assert client.rcpt('mbx-'+r['id']+'@local.invalid')[0]==250
 if kind=='data':assert client.docmd('DATA')[0]==354;client.send(body[:100000])
(root/(r['marker']+'.ready')).write_text('old quota context established');wait('.release');result={}
try:
 if kind=='imap':
  client.send(body[100000:]+b'\r\n');line=client.readline();result['writer_result']='OK' if b' OK ' in line else 'refused';client.shutdown()
 else:
  if kind=='rcpt':assert client.docmd('DATA')[0]==354;client.send(body)
  else:client.send(body[100000:])
  client.send(b'\r\n.\r\n');result['writer_result']=client.getreply()[0];client.quit()
except (OSError,smtplib.SMTPException,imaplib.IMAP4.error):result['writer_result']='disconnected'
result['writer_finished_monotonic']=time.monotonic();(root/(r['marker']+'.writer.json')).write_text(json.dumps(result));wait('.verify');observer.join(timeout=30);assert observer.exitcode==0;result.update(json.loads((root/(r['marker']+'.reader.json')).read_text()));print(json.dumps(result))
