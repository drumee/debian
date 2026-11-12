"""Atomic capacity, actual lock contention, worker death, queued retry and UUID isolation."""
import concurrent.futures,hashlib,json,pathlib,subprocess,sys,time,uuid
root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8';commands=[];checks=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('quota test failed '+str(args[:3])+r.stderr.decode()[-500:])
 return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
control=root/'quota-control';control.mkdir(mode=0o700,exist_ok=True)
def helper(*args):return run(['docker','run','--rm','--network',project+'-edge','--ip','10.243.47.90','--mount','type=volume,source='+project+'-sockets,target=/run/mail-sockets','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--mount',f'type=bind,source={control},target=/control','--entrypoint','python3',image,*args])
def client(*args):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/client.py',*args]).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
for action in ['high','fits','copy-race','move-race','copy-move']:
 value=json.loads(helper('/lab/atomic-check.py',action).stdout);checks.append({'name':action,'status':'PASS','observation':value});print(json.dumps(checks[-1]),flush=True)
with concurrent.futures.ThreadPoolExecutor(1) as pool:
 pending=pool.submit(helper,'/lab/atomic-check.py','hold')
 for _ in range(100):
  if (control/'held.json').exists():break
  time.sleep(.1)
 else:raise TimeoutError('APPEND did not reach held literal')
 lockcode="import fcntl,json,time;f=open('/box/home/.drumee-quota.lock','rb');held=False\nfor i in range(100):\n try:fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.flock(f,fcntl.LOCK_UN)\n except BlockingIOError:held=True;break\n time.sleep(.02)\nassert held;print(json.dumps({'kernel_lock_observed':held}))"
 value=json.loads(run(['docker','run','--rm','--network','none','--read-only','--user','5000:5000','--mount',f'type=bind,source={root}/service/durable/mailboxes/22222222-2222-4222-8222-222222222222,target=/box,readonly','--entrypoint','python3',image,'-c',lockcode]).stdout)
 tag='queued-lock-'+uuid.uuid4().hex;client('send','-','outside@dest.invalid','second@oxymot.fr',tag,'25');time.sleep(6);before=queue();assert before and any('temporar' in str(q).lower() or 'quota' in str(q).lower() for q in before)
 other='other-uuid-'+uuid.uuid4().hex;client('send','-','outside@dest.invalid','contact@oxymot.fr',other,'25');time.sleep(1);assert len(client('imap','contact@oxymot.fr',other)['matches'])==1
 who=json.loads(comp('exec','-T','dovecot','doveadm','-c','/registry/active.conf','-f','json','who').stdout);matches=[row for row in who if 'second@oxymot.fr' in str(row)];assert len(matches)==1,who
 row={k.lower().strip('()'):v for k,v in matches[0].items()};pids=str(row.get('pids',row.get('pid',''))).strip('() ').split(',');assert len(pids)==1 and pids[0].strip().isdigit(),row;pid=pids[0].strip()
 info=comp('exec','-T','dovecot','cat','/proc/'+pid+'/status').stdout.decode();assert 'Uid:\t5000\t5000\t5000\t5000' in info
 comp('exec','-T','dovecot','kill','-KILL',pid);value.update(interrupted_worker_pid=int(pid),separate_uuid_delivered=True,queued_ids=[q['queue_id'] for q in before]);print(json.dumps(value),flush=True)
 comp('exec','-T','postfix','postqueue','-c','/config','-f')
 for _ in range(40):
  found=client('imap','second@oxymot.fr',tag)['matches']
  if found:break
  time.sleep(.5)
 assert len(found)==1 and not any(q['queue_id'] in value['queued_ids'] for q in queue());assert json.loads(pending.result().stdout)['status'].startswith('PASS_');checks.append({'name':'held-write-crash-and-queued-retry','status':'PASS','observation':value})
comp('restart','dovecot');time.sleep(2);assert len(client('imap','second@oxymot.fr',tag)['matches'])==1;checks.append({'name':'restart-recounts-committed-Maildir','status':'PASS'})
data={'status':'PASS_ATOMIC_QUOTA_NATIVE','checks':checks,'commands':commands};(root/'atomic-quota-result.json').write_text(json.dumps(data,indent=2));print('REPORT '+str(root/'atomic-quota-result.json'))
