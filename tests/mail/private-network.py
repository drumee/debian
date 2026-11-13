"""Real independent Compose projects consume the canonical mail-owned external frontend."""
import hashlib,json,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';checks=[];commands=[];project=p['project'];frontend=project+'-edge';clients=json.loads((source/'keys/client.json').read_text());fixtures=root/('private-clients-'+uuid.uuid4().hex);fixtures.mkdir(mode=0o700)
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=90);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('private test command failed '+str(args[:3]))
 return r
def rules():return json.loads(run(['docker','exec',project+'-postfix-1','nft','-j','list','table','inet','drumee_mail_private']).stdout)
def dropped(r):return sum(e.get('counter',{}).get('packets',0) for x in r['nftables'] if 'rule' in x and any('drop' in e for e in x['rule']['expr']) for e in x['rule']['expr'])
def core_ids():return sorted(run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]).stdout.decode().split())
front_id=json.loads(run(['docker','network','inspect',frontend]).stdout)[0]['Id'];core=core_ids();seen={};projects={k:'mail02-client-'+uuid.uuid4().hex[:8] for k in ['ghost','oxymotion','forbidden']}
for generation in range(2):
 for kind,octet,last in [('ghost',48,10),('oxymotion',50,11),('forbidden',49,200)]:
  client_project=projects[kind];backend=client_project+'-backend';address='10.243.47.'+str(last);allowed=kind!='forbidden';account=kind if allowed else 'ghost';app=fixtures/kind;app.mkdir(mode=0o700,exist_ok=True);(app/'ca.pem').write_bytes((source/'keys/ca.pem').read_bytes());(app/'client.json').write_text(json.dumps({'account':account,'password':clients[account],'sender':'contact@oxymot.fr' if account=='ghost' else 'second@oxymot.fr'}));(app/'client.json').chmod(0o600);(app/'ca.pem').chmod(0o600)
  descriptor=json.loads(run(['node',str(repo/'profiles/mail/private-client.cjs'),str(root/'config.json'),address]).stdout);assert descriptor['network']=={'external':True,'name':frontend}
  spec={'name':client_project,'services':{'client':{'image':image,'user':'1000:1000','read_only':True,'cap_drop':['ALL'],'security_opt':['no-new-privileges:true'],'entrypoint':['/bin/sleep','infinity'],'networks':{'backend':{},'mail_front':descriptor['attachment']},'volumes':[{'type':'bind','source':str(app),'target':'/keys','read_only':True},{'type':'bind','source':str(scripts),'target':'/lab','read_only':True}]}},'networks':{'backend':{'name':backend,'internal':True,'ipam':{'config':[{'subnet':f'10.243.{octet}.0/24'}]}},'mail_front':descriptor['network']}};file=fixtures/(kind+'.json');file.write_text(json.dumps(spec));file.chmod(0o600);compose=['docker','compose','-p',client_project,'-f',str(file)];started=False
  try:
   run([*compose,'up','-d']);started=True;client=run([*compose,'ps','-q','client']).stdout.decode().strip();actual=json.loads(run(['docker','inspect',client]).stdout)[0];networks=actual['NetworkSettings']['Networks'];assert set(networks)=={frontend,backend} and networks[frontend]['IPAddress']==address
   mounts=actual['Mounts'];assert len(mounts)==2 and all(not m['RW'] for m in mounts) and actual['HostConfig']['ReadonlyRootfs']
   assert next(m for m in mounts if m['Destination']=='/keys')['Source']==str(app)
   if generation:assert client!=seen[kind]
   seen[kind]=client;assert len(list(app.iterdir()))==2 and {f.name for f in app.iterdir()}=={'client.json','ca.pem'}
   dns=json.loads(run(['docker','exec',client,'python3','-c',"import socket,json;print(json.dumps({'address':socket.gethostbyname('"+descriptor['submission']['host']+"')}))"]).stdout);assert dns['address']==descriptor['submission']['address']
   tag='private-'+kind+'-'+uuid.uuid4().hex;before=dropped(rules());value=json.loads(run(['docker','exec',client,'python3','/lab/private-probe.py',descriptor['submission']['address'],'allowed' if allowed else 'forbidden',tag]).stdout);after=dropped(rules());value.update(observed_frontend_source=address,backend_project=client_project,client_id=client,restricted_secret_projection=True)
   if not allowed:assert after>before;value['kernel_drop_packets']=after-before
   else:
    for _ in range(30):
     probe=run(['docker','run','--rm','--network',frontend,'--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/client.py','imap','contact@oxymot.fr',tag]);found=json.loads(probe.stdout)['matches']
     if found:break
     time.sleep(.2)
    assert len(found)==1;value['observed_local_delivery']=len(found)
   checks.append({'name':f'{kind}-project-generation-{generation}','status':value['status'],'observation':value});print(json.dumps(checks[-1]),flush=True)
  except Exception as e:checks.append({'name':f'{kind}-project-generation-{generation}','status':'FAIL','reason':str(e)});print(json.dumps(checks[-1]),flush=True)
  finally:
   if started:run([*compose,'down'],False)
  assert json.loads(run(['docker','network','inspect',frontend]).stdout)[0]['Id']==front_id and core_ids()==core
inspection=json.loads(run(['docker','inspect',project+'-postfix-1']).stdout)[0];caps=run(['docker','exec',project+'-postfix-1','cat','/proc/1/status']).stdout.decode();bounding=int(next(x.split()[1] for x in caps.splitlines() if x.startswith('CapBnd:')),16);assert bounding&((1<<8)|(1<<12))==0
assert inspection['NetworkSettings']['Ports'].get('1587/tcp')
result={'runtime':{'bindings':inspection['HostConfig']['PortBindings'],'ports':inspection['NetworkSettings']['Ports'],'postfix_networks':inspection['NetworkSettings']['Networks'],'pid1_bounding_caps':hex(bounding),'private_rules':rules(),'mail_frontend_id_retained':front_id,'mail_container_ids_retained':core},'status':'PASS_PRIVATE_NETWORKS' if len(checks)==6 and all(c['status']=='PASS' for c in checks) else 'FAIL_PRIVATE_NETWORKS','checks':checks,'commands':commands};(root/'private-result.json').write_text(json.dumps(result,indent=2));print('REPORT '+str(root/'private-result.json'))
