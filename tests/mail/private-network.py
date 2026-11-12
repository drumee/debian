"""Private submission from separate owned client projects, including recreation."""
import hashlib,json,pathlib,subprocess,sys,uuid
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';checks=[];commands=[]
def run(args):
 r=subprocess.run(args,capture_output=True,timeout=45);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()});return r
for generation in range(2):
 for kind,octet in [('allowed',48),('forbidden',49)]:
  network='mail02-client-'+uuid.uuid4().hex[:8];created=False
  try:
   r=run(['docker','network','create','--subnet',f'10.243.{octet}.0/24','--label','drumee.mail02.synthetic-client=true',network]);assert r.returncode==0;created=True
   r=run(['docker','run','--rm','--network',network,'--ip',f'10.243.{octet}.10','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/private-probe.py','10.243.47.1',kind]);assert r.returncode==0
   observation=json.loads(r.stdout);checks.append({'name':f'{kind}-client-generation-{generation}','status':observation['status'],'observation':observation});print(json.dumps(checks[-1]),flush=True)
  except Exception as e:checks.append({'name':f'{kind}-client-generation-{generation}','status':'FAIL','reason':str(e)})
  finally:
   if created:run(['docker','network','rm',network])
result={'status':'PASS_PRIVATE_NETWORKS' if len(checks)==4 and all(c['status']=='PASS' for c in checks) else 'FAIL_PRIVATE_NETWORKS','checks':checks,'commands':commands};(root/'private-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'private-result.json'))
