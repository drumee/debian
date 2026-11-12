"""Actual expiry/material rejection and native endpoint expiry-alert transitions."""
import hashlib,json,pathlib,subprocess,sys,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';fixtures=root/'expiry-fixtures';fixtures.mkdir(mode=0o700,exist_ok=True);commands=[];checks=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=150);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('expiry command failed '+str(args[:3])+r.stdout.decode()[-150:])
 return r
def api(op,input=None,ok=True):
 args=['node',str(repo/'tests/mail/api.cjs'),op,str(root/'config.json')]
 if input is not None:
  file=fixtures/('request-'+uuid.uuid4().hex+'.json');file.write_text(json.dumps(input));file.chmod(0o600);args.append(str(file))
 return run(args,ok)
def material(days):
 stem=fixtures/('days'+str(days));run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN=mail.oxymot.fr','-keyout',str(stem)+'.key','-out',str(stem)+'.csr']);ext=fixtures/'leaf.ext';ext.write_text('subjectAltName=DNS:mail.oxymot.fr\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n');run(['openssl','x509','-req','-in',str(stem)+'.csr','-CA',str(source/'keys/ca.pem'),'-CAkey',str(source/'keys/ca.key'),'-set_serial',str(100+days),'-days',str(days),'-extfile',str(ext),'-out',str(stem)+'.pem'])
 for suffix in ['.key','.pem']:(pathlib.Path(str(stem)+suffix)).chmod(0o600)
 return {'certificate_file':str(stem)+'.pem','key_file':str(stem)+'.key','ca_file':str(source/'keys/ca.pem')}
expired=material(-1);old=(root/'service/durable/tls/current').readlink();refused=api('rotate',expired,False);assert refused.returncode and json.loads(refused.stdout)['code']=='MAIL_CERTIFICATE_INVALID';assert (root/'service/durable/tls/current').readlink()==old;checks.append({'name':'expired-leaf-refused-before-native-activation','status':'PASS','code':'MAIL_CERTIFICATE_INVALID'})
for days,expected in [(31,None),(20,'MAIL_CERTIFICATE_EXPIRES_30_DAYS'),(10,'MAIL_CERTIFICATE_EXPIRES_14_DAYS'),(6,'MAIL_CERTIFICATE_EXPIRES_7_DAYS')]:
 result=json.loads(api('rotate',material(days)).stdout);obs=json.loads(api('observe').stdout);codes=[a['code'] for a in obs['alerts'] if a['code'].startswith('MAIL_CERTIFICATE_EXPIRES_')];assert codes==([] if expected is None else [expected]),codes;checks.append({'name':'expiry-transition-'+str(days)+'-days','status':'PASS','alerts':codes});print(json.dumps(checks[-1]),flush=True)
# Actual TLS handshake to an expired peer and mandatory STARTTLS client behavior.
code="""import ssl,socket,threading,json,smtplib
ctx=ssl.create_default_context(cafile='/keys/ca.pem');server=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server.load_cert_chain('/expired/days-1.pem','/expired/days-1.key');listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();port=listener.getsockname()[1]
def expired_peer():
 c,_=listener.accept()
 try:server.wrap_socket(c,server_side=True).close()
 except ssl.SSLError:c.close()
t=threading.Thread(target=expired_peer);t.start()
try:ctx.wrap_socket(socket.create_connection(('127.0.0.1',port)),server_hostname='mail.oxymot.fr');raise AssertionError('expired peer trusted')
except ssl.SSLCertVerificationError as e:assert e.verify_code==10;expiry_code=e.verify_code
t.join();listener.close();listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen();port=listener.getsockname()[1];wire=[]
def plain_peer():
 c,_=listener.accept();c.sendall(b'220 fixture.invalid SMTP\\r\\n');wire.append(c.recv(4096));c.sendall(b'250 fixture.invalid\\r\\n');wire.append(c.recv(4096));c.close()
t=threading.Thread(target=plain_peer);t.start();s=smtplib.SMTP('127.0.0.1',port,timeout=5);s.ehlo()
try:s.starttls(context=ctx);raise AssertionError('missing STARTTLS accepted')
except smtplib.SMTPNotSupportedError:pass
s.close();t.join();listener.close();assert b'AUTH' not in b''.join(wire).upper();print(json.dumps({'expired_verify_code':expiry_code,'missing_starttls_refused':True,'auth_emitted':False}))
"""
result=json.loads(run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={fixtures},target=/expired,readonly','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--entrypoint','python3',image,'-c',code]).stdout);checks.append({'name':'expired-peer-and-missing-starttls-refused-without-auth','status':'PASS','observation':result})
api('rotate',{'certificate_file':str(source/'keys/certificate.pem'),'key_file':str(source/'keys/key.pem'),'ca_file':str(source/'keys/ca.pem')})
data={'status':'PASS_NATIVE_TLS_EXPIRY_CONTROLS','checks':checks,'commands':commands};(root/'expiry-result.json').write_text(json.dumps(data,indent=2));print('REPORT '+str(root/'expiry-result.json'))
