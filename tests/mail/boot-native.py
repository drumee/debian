"""Guest-only guarded boot preparation and verification, never reboots its caller."""
import hashlib,json,pathlib,subprocess,sys,time,uuid
repo=pathlib.Path(__file__).resolve().parents[2];root=pathlib.Path(sys.argv[1]);source=pathlib.Path(sys.argv[2]);scripts=pathlib.Path(sys.argv[3]);mode=sys.argv[4];p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];commands=[];image='sha256:36afa984f1187ff7fef17356fa7ead13af9a756681ac4a0c234a58fdc38f47e8'
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=180);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('boot command failed '+str(args[:3])+r.stdout.decode()[-200:])
 return r
def comp(*args):return run(['docker','compose','-p',project,'-f',p['compose_file'],*args])
def client(*args):return json.loads(run(['docker','run','--rm','--network',project+'-edge','--user','1000:1000','--mount',f'type=bind,source={source}/keys,target=/keys,readonly','--mount',f'type=bind,source={scripts},target=/lab,readonly','--entrypoint','python3',image,'/lab/client.py',*args]).stdout)
def queue():return [json.loads(x) for x in comp('exec','-T','postfix','postqueue','-c','/config','-j').stdout.splitlines()]
def bodies():
 code="import pathlib,hashlib,json; r=pathlib.Path('/data'); print(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in r.rglob('*') if p.is_file() and p.parent.name in ('cur','new')}))"
 return json.loads(run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={root}/service/durable/mailboxes,target=/data,readonly','--entrypoint','python3',image,'-c',code]).stdout)
unit=project+'.service';state=root/'boot-before.json'
if mode=='stage':
 data=json.loads(run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','boot-unit','--config',str(root/'config.json')]).stdout);file=root/unit;file.write_text(data['unit']);run(['sudo','install','-m','0644',str(file),'/etc/systemd/system/'+unit]);run(['sudo','systemctl','daemon-reload']);run(['sudo','systemctl','enable','--now',unit]);tag='boot-'+uuid.uuid4().hex
 client('send','-','outside@dest.invalid','contact@oxymot.fr',tag+'-delivered','25');time.sleep(2);assert client('imap','contact@oxymot.fr',tag+'-delivered')['matches']
 comp('stop','dovecot');client('send','-','outside@dest.invalid','contact@oxymot.fr',tag+'-queued','25');time.sleep(2);pending=queue();assert pending
 data={'boot_id':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),'queue_ids':[q['queue_id'] for q in pending],'body_hashes':bodies(),'tag':tag,'unit':unit,'commands':commands};state.write_text(json.dumps(data,indent=2));print(json.dumps({'staged':True,'queue_ids':data['queue_ids'],'unit':unit}))
elif mode=='verify':
 before=json.loads(state.read_text());assert before['boot_id']!=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip();run(['sudo','systemctl','is-active',unit]);run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','preflight','--config',str(root/'config.json')]);observed=[];comp('exec','-T','postfix','postqueue','-c','/config','-f')
 for i in range(60):
  found=client('imap','contact@oxymot.fr',before['tag']+'-queued')['matches']
  if found:break
  time.sleep(1)
 assert len(found)==1;old=client('imap','contact@oxymot.fr',before['tag']+'-delivered')['matches'];assert len(old)==1
 # Dovecot may move new to cur; compare content hashes, not mutable Maildir names.
 after=bodies();assert set(before['body_hashes'].values())<=set(after.values());assert not any(q['queue_id'] in before['queue_ids'] for q in queue())
 data={'status':'PASS_GUARDED_GUEST_REBOOT','checks':['guest-boot-id-changed','mail-owned-systemd-preflight-before-start','nonempty-local-queue-delivered-on-existing-storage','old-maildir-content-retained','registry-secrets-runtime-preflight'],'before_queue_ids':before['queue_ids'],'queued_message_imap_matches':len(found),'commands':commands};(root/'boot-result.json').write_text(json.dumps(data,indent=2));print(json.dumps({'status':data['status'],'checks':data['checks']}))
else:raise ValueError('stage or verify required')
