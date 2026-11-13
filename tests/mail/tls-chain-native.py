"""A still-valid leaf with an expired issuer is refused before activation and by the TLS client."""
import hashlib,json,pathlib,subprocess,sys
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);directory=root/'expired-issuer';directory.mkdir(mode=0o700,exist_ok=True);commands=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('chain fixture command failed '+str(args[:3]))
 return r
sys.path.insert(0,sys.argv[3])
from certificate_fixture import issue_expired
for name,cn in [('issuer','Expired lab issuer'),('leaf','mail.oxymot.fr')]:run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-subj','/CN='+cn,'-keyout',str(directory/(name+'.key')),'-out',str(directory/(name+'.csr'))])
(directory/'issuer.ext').write_text('basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n');(directory/'leaf.ext').write_text('subjectAltName=DNS:mail.oxymot.fr\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
issue_expired(run,directory,directory/'issuer.csr',directory/'issuer.key',None,None,directory/'issuer.ext',directory/'issuer.pem',self_signed=True);run(['openssl','x509','-req','-in',str(directory/'leaf.csr'),'-CA',str(directory/'issuer.pem'),'-CAkey',str(directory/'issuer.key'),'-set_serial','901','-days','2','-extfile',str(directory/'leaf.ext'),'-out',str(directory/'leaf.pem')])
for file in directory.iterdir():file.chmod(0o600)
request=directory/'request.json';request.write_text(json.dumps({'certificate_file':str(directory/'leaf.pem'),'key_file':str(directory/'leaf.key'),'ca_file':str(directory/'issuer.pem')}));request.chmod(0o600);pointer=root/'service/durable/tls/current';before=pointer.readlink();r=run(['node',str(repo/'tests/mail/api.cjs'),'rotate',str(root/'config.json'),str(request)],False);assert r.returncode and json.loads(r.stdout)['code']=='MAIL_CERTIFICATE_INVALID';assert pointer.readlink()==before
code="""import ssl,socket,threading,json
ctx=ssl.create_default_context(cafile='/chain/issuer.pem');server=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);server.load_cert_chain('/chain/leaf.pem','/chain/leaf.key');sock=socket.socket();sock.bind(('127.0.0.1',0));sock.listen();port=sock.getsockname()[1]
def peer():
 c,_=sock.accept()
 try:server.wrap_socket(c,server_side=True).close()
 except ssl.SSLError:c.close()
t=threading.Thread(target=peer);t.start()
try:ctx.wrap_socket(socket.create_connection(('127.0.0.1',port)),server_hostname='mail.oxymot.fr');raise AssertionError('expired issuer trusted')
except ssl.SSLCertVerificationError as e:assert e.verify_code==10;print(json.dumps({'issuer_verify_code':e.verify_code,'auth_emitted':False}))
t.join();sock.close()
"""
peer=json.loads(run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={directory},target=/chain,readonly','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-c',code]).stdout);result={'status':'PASS_EXPIRED_ISSUER_NATIVE','activation_code':'MAIL_CERTIFICATE_INVALID','active_generation_unchanged':True,'client':peer,'commands':commands};(root/'expired-issuer-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='commands'}))
