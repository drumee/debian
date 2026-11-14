"""Export only nonsecret synthetic reports; never copy live storage or inputs."""
import pathlib,sys,json,hashlib,re,os
os.umask(0o077);root=pathlib.Path(sys.argv[1]).resolve();source=pathlib.Path(sys.argv[2]).resolve();target=pathlib.Path(sys.argv[3]).resolve();reports=['mail03-final-replay.json','mail03-admin-result.json','mail03-tty-result.json','mail03-errors-result.json','mail03-session-result.json','mail03-rights-result.json','mail03-accounts-result.json','mail03-tx-result.json','mail03-quota-result.json','atomic-quota-result.json','mail03-purge-result.json','held-quota-result.json','mail03-quota-guards-result.json','mail03-cutpoints-result.json','mail03-purge-interruption-result.json','mail03-boot-result.json','boot-result.json','private-result.json','identity-result.json','tls-result.json','expiry-result.json']
if target.exists():raise SystemExit('refuse populated evidence destination')
secrets=set()
for file in [root/'admin-probe/synthetic-secrets.json',source/'keys/client.json',*(root/'service/durable/operator-state/admin/credentials').glob('*.json')]:
 if not file.exists():continue
 data=json.loads(file.read_text());values=data.values() if isinstance(data,dict) else data
 for value in values:
  if isinstance(value,str) and len(value.encode())>=16:secrets.add(value)
needles=set()
for secret in secrets:needles.update([secret.encode(),json.dumps(secret)[1:-1].encode()])
unsafe=re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\{ARGON2ID\}\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+')
def sanitize(value):
 if isinstance(value,list):return [sanitize(x) for x in value]
 if isinstance(value,dict):
  result={k:sanitize(v) for k,v in value.items()}
  argv=value.get('argv',[])
  if isinstance(argv,list) and 'pw' in argv and any('doveadm' in str(x) for x in argv):
   for key in ('stdout_sha256','stderr_sha256'):result.pop(key,None)
   result['protected_output']='credential material; no output fingerprint exported'
  return result
 return value
outputs={}
for name in reports:
 file=root/name
 if file.exists():outputs[name]=(json.dumps(sanitize(json.loads(file.read_text())),indent=2)+'\n').encode()
for name,data in outputs.items():
 if unsafe.search(data) or any(needle in data for needle in needles):raise SystemExit('secret scan refused report: '+name)
target.mkdir(mode=0o700,parents=True)
for name,data in outputs.items():(target/name).write_bytes(data)
manifest={'contract':'drumee.mail03-public-evidence/1','synthetic_data_only':True,'secrets_or_verifiers_matched':0,'protected_literals_tested':len(secrets),'files':{name:hashlib.sha256(data).hexdigest() for name,data in sorted(outputs.items())}}
(target/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'reports':len(outputs),'secrets_or_verifiers_matched':0,'destination':str(target)}))
