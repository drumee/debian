"""New IMAP authentication must fail closed when the native policy gate is down."""
import pathlib,json,subprocess,sys,hashlib,time
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];private=root/'auth-gate-fixture';private.mkdir(mode=0o700);clients=json.loads((source/'keys/client.json').read_text());file=private/'passwords.json';file.write_text(json.dumps({'contact@oxymot.fr':clients['contact']}));file.chmod(0o600);commands=[];checks=[]
def run(args,input=None):
 r=subprocess.run(args,input=input,capture_output=True,timeout=60);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});return r
def probe():
 r=run(['docker','run','--rm','-i','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={private},target=/private,readonly','--mount',f'type=bind,source={repo}/tests/mail/admin,target=/lab,readonly','--entrypoint','python3','sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8','-B','/lab/probe.py'],json.dumps({'action':'imap','user':'contact@oxymot.fr'}).encode());assert r.returncode==0;return json.loads(r.stdout)
assert probe()['ok'];checks.append({'name':'known-credential-imap-before-policy-outage','status':'PASS'});command=['docker','compose','-p',project,'-f',p['compose_file']]
try:
 assert run([*command,'stop','policy']).returncode==0;assert not probe()['ok'];checks.append({'name':'new-imap-authentication-refuses-policy-outage','status':'PASS'})
finally:assert run([*command,'start','policy']).returncode==0
for _ in range(30):
 if probe()['ok']:break
 time.sleep(.2)
else:raise AssertionError('authentication did not recover')
checks.append({'name':'same-credential-imap-after-policy-recovery','status':'PASS'});result={'status':'PASS_NATIVE_AUTH_GATE_OUTAGE','checks':checks,'commands':commands};(root/'auth-gate-result.json').write_text(json.dumps(result,indent=2));print(result['status'])
