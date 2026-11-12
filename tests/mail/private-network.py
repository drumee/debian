"""Canonical mail-owned frontal attachment, independent backends, observed source and packet refusal."""
import hashlib,json,pathlib,subprocess,sys,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';checks=[];commands=[];project=p['project'];frontend=project+'-edge'
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=45);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('private test command failed '+str(args[:3]))
 return r
def rules():return json.loads(run(['docker','exec',project+'-postfix-1','nft','-j','list','table','inet','drumee_mail_private']).stdout)
def dropped(r):return sum(e.get('counter',{}).get('packets',0) for x in r['nftables'] if 'rule' in x and any('drop' in e for e in x['rule']['expr']) for e in x['rule']['expr'])
front_id=json.loads(run(['docker','network','inspect',frontend]).stdout)[0]['Id']
for generation in range(2):
 for kind,octet,last in [('allowed',48,10+generation),('forbidden',49,200+generation)]:
  network='mail02-client-'+uuid.uuid4().hex[:8];name='mail02-client-'+uuid.uuid4().hex[:8];created=False;started=False;address='10.243.47.'+str(last)
  try:
   descriptor=json.loads(run(['node',str(repo/'profiles/mail/private-client.cjs'),str(root/'config.json'),address]).stdout);assert descriptor['network']=={'external':True,'name':frontend}
   run(['docker','network','create','--internal','--subnet',f'10.243.{octet}.0/24','--label','drumee.mail02.synthetic-client=true',network]);created=True
   run(['docker','run','-d','--name',name,'--network',network,'--user','1000:1000','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','/bin/sleep',image,'infinity']);started=True;run(['docker','network','connect','--ip',address,frontend,name])
   actual=json.loads(run(['docker','inspect',name]).stdout)[0]['NetworkSettings']['Networks'];assert set(actual)=={frontend,network} and actual[frontend]['IPAddress']==address
   dns=json.loads(run(['docker','exec',name,'python3','-c',"import socket,json;print(json.dumps({'address':socket.gethostbyname('"+descriptor['submission']['host']+"')}))"]).stdout);assert dns['address']==descriptor['submission']['address']
   before=dropped(rules());result=run(['docker','exec',name,'python3','/lab/private-probe.py',descriptor['submission']['address'],kind]);observation=json.loads(result.stdout);after=dropped(rules());observation.update(observed_frontend_source=address,backend_network=network)
   if kind=='forbidden':assert after>before;observation['kernel_drop_packets']=after-before
   checks.append({'name':f'{kind}-client-generation-{generation}','status':observation['status'],'observation':observation});print(json.dumps(checks[-1]),flush=True)
  except Exception as e:checks.append({'name':f'{kind}-client-generation-{generation}','status':'FAIL','reason':str(e)});print(json.dumps(checks[-1]),flush=True)
  finally:
   if started:run(['docker','rm','-f',name],False)
   if created:run(['docker','network','rm',network],False)
inspection=json.loads(run(['docker','inspect',project+'-postfix-1']).stdout)[0]
caps=run(['docker','exec',project+'-postfix-1','cat','/proc/1/status']).stdout.decode();bounding=int(next(x.split()[1] for x in caps.splitlines() if x.startswith('CapBnd:')),16);assert bounding&((1<<8)|(1<<12))==0
assert json.loads(run(['docker','network','inspect',frontend]).stdout)[0]['Id']==front_id
assert inspection['NetworkSettings']['Ports'].get('1587/tcp')
logs=run(['docker','logs','--since','10m',project+'-postfix-1']).stderr.decode()+run(['docker','logs','--since','10m',project+'-postfix-1']).stdout.decode();assert '[10.243.47.10]' in logs and '[10.243.47.11]' in logs
result={'runtime':{'bindings':inspection['HostConfig']['PortBindings'],'ports':inspection['NetworkSettings']['Ports'],'postfix_networks':inspection['NetworkSettings']['Networks'],'pid1_bounding_caps':hex(bounding),'private_rules':rules(),'mail_frontend_id_retained':front_id},'status':'PASS_PRIVATE_NETWORKS' if len(checks)==4 and all(c['status']=='PASS' for c in checks) else 'FAIL_PRIVATE_NETWORKS','checks':checks,'commands':commands};(root/'private-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'private-result.json'))
