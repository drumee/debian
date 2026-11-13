"""Dedicated guest only: create a NEW bounded filesystem; refuse missing mount before exposure.
Never formats an existing file or removes retained mail. Does not reboot its caller.
"""
import hashlib,json,os,pathlib,subprocess,sys,uuid
mode=sys.argv[1];commands=[]
def run(args,ok=True):
 r=subprocess.run(args,capture_output=True,timeout=120);commands.append({'argv':args,'exit':r.returncode,'stdout_sha256':hashlib.sha256(r.stdout).hexdigest(),'stderr_sha256':hashlib.sha256(r.stderr).hexdigest()})
 if ok and r.returncode:raise RuntimeError('mount test failed '+str(args[:3]))
 return r
def digest(file):
 h=hashlib.sha256()
 with file.open('rb') as f:
  for block in iter(lambda:f.read(1048576),b''):h.update(block)
 return h.hexdigest()
assert pathlib.Path('/home/lab/runs').is_dir() and os.getuid()==1000
assert run(['docker','version','--format','{{.Server.Version}}']).stdout.decode().startswith('26.')
repo=pathlib.Path(__file__).resolve().parents[2]
if mode=='create':
 token=uuid.uuid4().hex[:8];base=pathlib.Path('/home/lab/runs');image=base/('mail02-bounded-'+token+'.ext4');mount=pathlib.Path('/home/lab')/('mail02-bounded-'+token);mount.mkdir(mode=0o700);sentinel=mount/'UNDERLYING-SENTINEL';sentinel.write_text('No fallback storage '+token+'\n');sentinel.chmod(0o600)
 fd=os.open(image,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.ftruncate(fd,256*1024*1024);os.close(fd)
 run(['/usr/sbin/mkfs.ext4','-q',str(image)])
 unit=run(['systemd-escape','--path','--suffix=mount',str(mount)]).stdout.decode().strip();file=base/(unit+'.fixture');file.write_text('[Unit]\nDescription=MAIL02 isolated bounded storage '+token+'\n\n[Mount]\nWhat='+str(image)+'\nWhere='+str(mount)+'\nType=ext4\nOptions=loop,nodev,nosuid\n\n[Install]\nWantedBy=local-fs.target\n')
 run(['sudo','install','-m','0644',str(file),'/etc/systemd/system/'+unit]);run(['sudo','systemctl','daemon-reload']);run(['sudo','systemctl','enable','--now',unit]);run(['sudo','chown','1000:1001',str(mount)]);run(['sudo','chmod','0700',str(mount)])
 record={'image':str(image),'mount':str(mount),'unit':unit,'sentinel_sha256':digest(sentinel) if sentinel.exists() else hashlib.sha256(('No fallback storage '+token+'\n').encode()).hexdigest(),'commands':commands};manifest=base/('mail02-mount-'+token+'.json');manifest.write_text(json.dumps(record,indent=2));manifest.chmod(0o600);print(json.dumps({'manifest':str(manifest),'mount':str(mount),'unit':unit}))
elif mode=='refuse':
 manifest=pathlib.Path(sys.argv[2]);root=pathlib.Path(sys.argv[3]);m=json.loads(manifest.read_text());mount=pathlib.Path(m['mount']);image=pathlib.Path(m['image']);assert root.is_relative_to(mount) and mount.is_mount();p=json.loads((root/'service/durable/operator-state/prepared.json').read_text());project=p['project'];unit=project+'.service'
 data=json.loads(run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','boot-unit','--config',str(root/'config.json')]).stdout);file=root/unit;file.write_text(data['unit']);run(['sudo','install','-m','0644',str(file),'/etc/systemd/system/'+unit]);run(['sudo','systemctl','daemon-reload']);run(['sudo','systemctl','start',unit]);run(['sudo','systemctl','stop',unit]);assert not run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]).stdout.strip()
 run(['sudo','systemctl','stop',m['unit']]);assert not mount.is_mount();sentinel=mount/'UNDERLYING-SENTINEL';assert digest(sentinel)==m['sentinel_sha256'];before=sorted(x.name for x in mount.iterdir());retained=image.with_suffix('.ext4.retained');assert not retained.exists();before_hash=digest(image);image.rename(retained)
 try:
  denied=run(['sudo','systemctl','start',unit],False);assert denied.returncode!=0;assert not run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]).stdout.strip();assert not mount.is_mount();assert sorted(x.name for x in mount.iterdir())==before and digest(sentinel)==m['sentinel_sha256'];assert digest(retained)==before_hash
 finally:
  retained.rename(image);run(['sudo','systemctl','reset-failed'],False);run(['sudo','systemctl','start',m['unit']]);run(['sudo','systemctl','start',unit])
 run(['bash',str(repo/'bin/drumee-ctl'),'--profile','mail','preflight','--config',str(root/'config.json')]);result={'status':'PASS_MISSING_ACTUAL_MOUNT_REFUSED','checks':['mail-stopped-before-unmount','missing-loop-source-refuses-unit-dependency-before-exposure','underlying-sentinel-and-files-unchanged','retained-image-hash-unchanged-before-recovery','explicit-mount-recovery-and-preflight'],'image_sha256_when_stopped':before_hash,'commands':commands};(root/'mount-result.json').write_text(json.dumps(result,indent=2));print(json.dumps({'status':result['status'],'checks':result['checks']}))
else:raise ValueError('create or refuse')
