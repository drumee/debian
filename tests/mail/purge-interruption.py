"""Kill the real purge at executing; qualify a verified partial-erasure state."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent/'admin'))
from common import *
import signal
user='purge-interrupt-'+uuid.uuid4().hex[:8]+'@oxymot.fr';passwords[user]='Purge-interrupt-'+uuid.uuid4().hex;box=cli('mailbox','create',user,password=passwords[user],mutate=True)['data'];id=box['id']
for _ in range(2):
 tag='purge-partial-'+uuid.uuid4().hex;assert probe(action='send',recipient=user,tag=tag)['data_code']==250;wait_read(user,tag)
cli('mailbox','delete',id,mutate=True)
def lifecycle(verb):
 r=run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail',verb,'--config',str(cfg),'--execute']);assert r.returncode==0,r.stdout.decode()[-200:]
lifecycle('stop');spec=json.loads(cfg.read_text())['service'];backuproot=pathlib.Path(spec['deployment']['backup_root']);backuproot.mkdir(mode=0o700,exist_ok=True);owner={'contract':'drumee.mail-backup-owner/1','service_id':spec['deployment']['id'],'uid':os.getuid(),'gid':os.getgid()};ownerfile=backuproot/'owner.json'
if ownerfile.exists():assert json.loads(ownerfile.read_text())==owner
else:ownerfile.write_text(json.dumps(owner));ownerfile.chmod(0o600)
backupid='interrupted-retained';catalog=backuproot/'mailboxes'/id/backupid
for directory in [backuproot/'mailboxes',backuproot/'mailboxes'/id,catalog]:directory.mkdir(mode=0o700,exist_ok=True)
mailbox=root/'service/durable/mailboxes'/id;image='sha256:ab41ba434fa20afd54f71f43fc31ad2aaa94260193a4e9b56cc0e5c971fb1a56';node=p['compose']['services']['policy']['image'];assert run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={mailbox},target=/source,readonly','--mount',f'type=bind,source={catalog},target=/backup','--entrypoint','/bin/cp',image,'-a','/source','/backup/data']).returncode==0
module=repo/'profiles/mail/.cache/consumer/node_modules/@drumee/infra-layer/capabilities/mail-service/purge.js';code=run(['node','-e','process.stdout.write(require(process.argv[1]).inventory.toString())',str(module)]).stdout.decode();inventorycode='const inventory='+code+';console.log(JSON.stringify(inventory("/data")));'
def inventory(path):
 r=run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={path},target=/data,readonly','--entrypoint','node',node,'-e',inventorycode]);assert r.returncode==0;return json.loads(r.stdout)
snapshot=inventory(mailbox);assert snapshot==inventory(catalog/'data');manifest={'contract':'drumee.mailbox-purge-backup/1','mailbox_id':id,'backup_id':backupid,'service_id':spec['deployment']['id'],'snapshot':snapshot};file=catalog/'manifest.json';file.write_text(json.dumps(manifest));file.chmod(0o600);request=str(uuid.uuid4());revision=state['revision'];receipt=root/('service/durable/operator-state/purge-'+request+'.json')
args=['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','mail','mailbox','purge',id,'--confirm-mailbox',id,'--backup-id',backupid,'--execute','--if-revision',str(revision),'--request-id',request,'--config',str(cfg),'--json'];child=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True);interrupted=False
try:
 for _ in range(60000):
  value=json.loads(receipt.read_text()) if receipt.exists() else {}
  if value.get('phase')=='executing':os.killpg(child.pid,signal.SIGSTOP);os.killpg(child.pid,signal.SIGKILL);interrupted=True;break
  if child.poll() is not None:raise AssertionError('purge exited before executing boundary')
  time.sleep(.002)
 assert interrupted;child.wait(timeout=10)
finally:
 if child.poll() is None:os.killpg(child.pid,signal.SIGKILL);child.wait(timeout=10)
# The Docker RPC may have started an eraser before its caller died. Wait for that
# exact owned UUID writer, never edit concurrently or signal an unrelated worker.
for _ in range(120):
 ids=run(['docker','ps','-q']).stdout.decode().split();containers=json.loads(run(['docker','inspect',*ids]).stdout) if ids else [];writers=[c for c in containers if any(m['Source']==str(mailbox) and m['RW'] for m in c['Mounts'])]
 if not writers:break
 time.sleep(.1)
else:raise AssertionError('owned eraser did not quiesce')
assert json.loads(receipt.read_text())['phase']=='executing','executing cutpoint was not retained'
remaining=inventory(mailbox);payload=[name for name in remaining if name.startswith(('Maildir/new/','Maildir/cur/')) and remaining[name]['type']=='file'];injected=False
if len(payload)>=2:
 # Controlled crash-state construction after the durable executing receipt:
 # remove two verified synthetic messages, leaving all other entries untouched.
 selected={name:snapshot[name]['sha256'] for name in payload[:2]};erase="const fs=require('node:fs'),c=require('node:crypto'),items="+json.dumps(selected)+";for(const [name,sha]of Object.entries(items)){if(!/^Maildir\\/(new|cur)\\/[^/]+$/.test(name))throw Error('path');const f='/data/'+name,s=fs.lstatSync(f);if(!s.isFile()||s.isSymbolicLink()||c.createHash('sha256').update(fs.readFileSync(f)).digest('hex')!==sha)throw Error('integrity');fs.unlinkSync(f);}for(const name of ['Maildir/new','Maildir/cur']){const f=fs.openSync('/data/'+name,'r');fs.fsyncSync(f);fs.closeSync(f);}"
 assert run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={mailbox},target=/data','--entrypoint','node',node,'-e',erase]).returncode==0;injected=True
elif not payload:
 # If the detached eraser finished before quiescence, reconstruct a strict
 # subset with two independent retained-copy payloads, never overwrite a target.
 selected=[name for name in snapshot if name.startswith(('Maildir/new/','Maildir/cur/')) and snapshot[name]['type']=='file'][:1];assert len(selected)==1
 copy="const fs=require('node:fs'),cp=require('node:child_process'),paths="+json.dumps(selected)+";for(const name of paths){if(!/^Maildir\\/(new|cur)\\/[^/]+$/.test(name))throw Error('path');if(fs.existsSync('/data/'+name))continue;const r=cp.spawnSync('/bin/cp',['-a','--no-clobber','/backup/'+name,'/data/'+name]);if(r.status!==0)throw Error('copy');}"
 assert run(['docker','run','--rm','--network','none','--read-only','--mount',f'type=bind,source={mailbox},target=/data','--mount',f'type=bind,source={catalog}/data,target=/backup,readonly','--entrypoint','node',node,'-e',copy]).returncode==0;injected=True
partial=inventory(mailbox);assert len(partial)<len(snapshot) and any(e['type']=='file' and name!='home/.drumee-quota.lock' for name,e in partial.items());assert (root/'service/durable/registry/public/admission-closed').exists();assert inventory(catalog/'data')==snapshot;check('purge-executing-interruption-preserves-backup-and-closed-admission',{'partial_state_constructed':injected,'source_entries_before':len(snapshot),'source_entries_after':len(partial),'executing_receipt':request})
resumed=cli('reconcile',opts=['--execute']);after=inventory(mailbox);assert set(after)<=set(['','home','home/.drumee-quota.lock','Maildir','Maildir/new','Maildir/cur','Maildir/tmp']);assert inventory(catalog/'data')==snapshot;assert cli('status')['data']['transport_running']==0;check('purge-reconcile-verifies-remaining-subset-and-finishes-same-generation',{'remaining_entries':sorted(after),'backup_unchanged':True,'applied_revision':resumed['applied_revision']});lifecycle('start')
result={'status':'PASS_MAIL03_PURGE_INTERRUPTION','checks':checks,'commands':commands,'last_revision':state['revision']};(root/'mail03-purge-interruption-result.json').write_text(json.dumps(result,indent=2));print(result['status'])
