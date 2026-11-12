"""Native negatives on distinct source IPs, retaining Dovecot authentication penalties."""
import hashlib,json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';checks=[];commands=[]
def d(*args):
 r=subprocess.run(['docker',*args],capture_output=True,timeout=90);commands.append({'argv':['docker',*args],'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});return r
control={}
for role,ports in [('policy',[10001,10002,10003]),('opendkim',[8891])]:
 data=json.loads(d('inspect',project+'-'+role+'-1').stdout)[0];address=data['NetworkSettings']['Networks'][project+'-control']['IPAddress']
 for port in ports:control[role+'-'+str(port)]=[address,port]
names=['edge-anonymous-relay-refused','plaintext-mail-requires-starttls','verified-tls-without-auth-refused']+['smtp-ineligible-or-wrong-password-'+w for w in ['ghost','oxymotion','contact@oxymot.fr','hello@oxymot.fr']]+['sasl-authorization-identity-impersonation-refused']+['imap-ineligible-'+w for w in ['ghost','oxymotion','hello@oxymot.fr']]+['imap-list-and-absolute-shared-namespace-isolation','internal-recipient-and-orcpt-cannot-bypass-rcpt-validation','mx-auth-remains-absent-after-starttls','authenticated-application-null-envelope-refused']+['native-tls11-refused-'+str(port) for port in [587,465,993]]+['plaintext-imap-not-listening']+['control-network-refuses-'+x for x in control]+['unix-auth-lmtp-not-mounted-in-client']
for i,name in enumerate(names+['loopback-anonymous-relay-refused']):
 mode='loopback' if name.startswith('loopback') else 'normal';network=['--network','container:'+project+'-postfix-1'] if mode=='loopback' else ['--network',project+'-edge','--ip','10.243.47.'+str(10+i)]
 r=d('run','--rm',*network,'--user','1000:1000','--env','MAIL02_ONLY_CASE='+name,'--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/protocol-check.py',mode,json.dumps(control))
 try:
  assert r.returncode==0;value=json.loads(r.stdout);assert len(value['checks'])==1 and value['checks'][0]['name']==name;checks.extend(value['checks'])
 except Exception:checks.append({'name':name,'status':'FAIL','reason':'probe did not return exactly its designated native result'})
 print(checks[-1]['status']+' '+name,flush=True)
result={'status':'PASS_NATIVE_PROTOCOL_NEGATIVES' if all(c['status']=='PASS' for c in checks) else 'FAIL_NATIVE_PROTOCOL_NEGATIVES','checks':checks,'commands':commands};(root/'protocol-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'protocol-result.json'))
