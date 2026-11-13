"""Exercise inherited shell fixes with controlled inputs; no real Docker/publish/database operation."""
import json,os,pathlib,pwd,shlex,subprocess,tempfile,unittest
repo=pathlib.Path(__file__).resolve().parents[1]
class RegressionTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='drumee-ci ');self.root=pathlib.Path(self.temp.name);self.bin=self.root/'bin';self.bin.mkdir();self.log=self.root/'docker.jsonl';self.env={**os.environ,'PATH':str(self.bin)+':'+os.environ['PATH'],'TASK_DOCKER_LOG':str(self.log),'PUSH':'0','TAG':'synthetic','SERVER_DIGEST':'sha256:'+'b'*64,'DRUMEE_QUIET_DEPRECATION':'1'}
  for key in ['SERVER_SRC','UI_SRC','SCHEMAS_SRC','SETUP_SCHEMAS_SRC','SETUP_INFRA_SRC','STATIC_SRC']:
   p=self.root/key;p.mkdir();self.env[key]=str(p)
  docker=self.bin/'docker';docker.write_text('''#!/usr/bin/env python3
import sys,os,json
a=sys.argv[1:]
with open(os.environ['TASK_DOCKER_LOG'],'a') as f:f.write(json.dumps(a)+'\\n')
if a[:2]==['buildx','version']:print('fixture buildx')
elif a[:2]==['buildx','build']:
 if os.environ.get('STOP_AT_BUILD'):sys.exit(77)
elif a[:2]==['image','inspect']:print('sha256:'+('e' if os.environ.get('WRONG_PARENT') and '@' in a[2] else 'd')*64)
elif a[:2]==['image','ls']:print('drumee/server-pod:synthetic')
else:sys.exit(91)
''');docker.chmod(0o700)
 def tearDown(self):self.temp.cleanup()
 def execute(self,file,env=None):return subprocess.run(['bash',str(repo/file)],env=env or self.env,capture_output=True,cwd=self.root)
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()] if self.log.exists() else []
 def test_publish_arguments_no_push_and_locked_parent(self):
  r=self.execute('scripts/publish-images.sh');self.assertEqual(r.returncode,0,r.stderr.decode());calls=[x for x in self.calls() if x[:2]==['buildx','build']];self.assertEqual(len(calls),7)
  for call in calls:
   self.assertNotIn('--push',call);self.assertIn('--load',call);self.assertEqual(call.count('-t'),3)
   f=call[call.index('-f')+1]
   if f.endswith(('Dockerfile.infra-init','Dockerfile.populate')):self.assertIn('SERVER_DIGEST='+self.env['SERVER_DIGEST'],call)
   if f.endswith('Dockerfile.server'):self.assertIn('node-runtime='+str(repo/'node-runtime'),call)
 def test_absent_invalid_parent_refuses_before_build(self):
  for value in ['', 'latest','sha256:bad','sha256:'+'g'*64]:
   if self.log.exists():self.log.unlink()
   r=self.execute('scripts/publish-images.sh',{**self.env,'SERVER_DIGEST':value});self.assertNotEqual(r.returncode,0);self.assertFalse(any(x[:2]==['buildx','build'] for x in self.calls()))
 def test_wrong_immutable_parent_cannot_build_child(self):
  r=self.execute('scripts/publish-images.sh',{**self.env,'WRONG_PARENT':'1'});self.assertNotEqual(r.returncode,0);self.assertFalse(any('Dockerfile.populate' in ' '.join(x) or 'Dockerfile.infra-init' in ' '.join(x) for x in self.calls()))
 def test_disabled_optional_tags_keep_primary(self):
  r=self.execute('scripts/publish-images.sh',{**self.env,'ALSO_STABLE':'0','ALSO_LATEST':'0'});self.assertEqual(r.returncode,0,r.stderr.decode());self.assertTrue(all(x.count('-t')==1 for x in self.calls() if x[:2]==['buildx','build']))
 def test_seed_build_context_is_one_command(self):
  source=pathlib.Path(self.env['SCHEMAS_SRC']);(source/'templates/factory/seed').mkdir(parents=True);(source/'templates/factory/seed/yp.sql').write_text('-- synthetic\n');r=self.execute('scripts/build-seed.sh',{**self.env,'STOP_AT_BUILD':'1'});self.assertEqual(r.returncode,77,r.stderr.decode());call=next(x for x in self.calls() if x[:2]==['buildx','build']);self.assertIn('helpers='+str(repo/'bootstrap/usr/lib/drumee/schemas'),call)
 def test_posix_missing_credential_exits_caller(self):
  env={**self.env,'CRED':str(self.root)};lib=shlex.quote(str(repo/'bootstrap/usr/lib/drumee/entrypoint/lib.sh'));r=subprocess.run(['sh','-c','. '+lib+'; drumee_require_credentials absent.json; echo UNREACHABLE'],env=env,capture_output=True);self.assertEqual(r.returncode,1);self.assertNotIn(b'UNREACHABLE',r.stdout)
 def test_log_rotation_preserves_space_names_and_missing_directory(self):
  logs=self.root/'logs with spaces';logs.mkdir();(logs/'two words.log').write_text('current');(logs/'two words.log.1').write_text('previous');config=self.root/'drumee.sh';config.write_text('DRUMEE_LOG_DIR='+shlex.quote(str(logs))+'\nDRUMEE_SYSTEM_USER=synthetic\n');chown=self.bin/'chown';chown.write_text('#!/bin/sh\nexit 0\n');chown.chmod(0o700)
  file=self.root/'rotate';file.write_text((repo/'server/usr/share/drumee/sbin/log-rotate.sh').read_text().replace('source /etc/drumee/drumee.sh','source '+shlex.quote(str(config))));r=subprocess.run(['bash',str(file)],env=self.env,capture_output=True);self.assertEqual(r.returncode,0,r.stderr.decode());self.assertEqual((logs/'two words.log.1').read_text(),'current');self.assertEqual((logs/'two words.log.2').read_text(),'previous');self.assertEqual((logs/'two words.log').read_bytes(),b'')
  config.write_text('DRUMEE_LOG_DIR='+shlex.quote(str(logs/'absent'))+'\n');sentinel=self.root/'untouched.log';sentinel.write_text('preserve');r=subprocess.run(['bash',str(file)],cwd=self.root,env=self.env,capture_output=True);self.assertNotEqual(r.returncode,0);self.assertEqual(sentinel.read_text(),'preserve')
if __name__=='__main__':unittest.main()
