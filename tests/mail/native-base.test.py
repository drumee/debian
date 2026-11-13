"""No Docker/network: verify locked native FROM and actual OCI bytes before any build."""
import copy,hashlib,importlib.util,io,json,pathlib,subprocess,tarfile,tempfile,unittest
repo=pathlib.Path(__file__).resolve().parents[2];file=repo/'profiles/mail/native/oci-base.py';spec=importlib.util.spec_from_file_location('oci',file);oci=importlib.util.module_from_spec(spec);spec.loader.exec_module(oci)
class BaseTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name);self.layer=b'synthetic immutable layer';ld=oci.digest(self.layer);self.config=oci.encode({'os':'linux','architecture':'amd64','rootfs':{'diff_ids':[ld]}});self.lock={'contract':'drumee.mail-native-base/1','config':oci.digest(self.config),'buildkit':'moby/buildkit@sha256:'+'a'*64};c={'mediaType':'application/vnd.oci.image.config.v1+json','digest':oci.digest(self.config),'size':len(self.config)};l={'mediaType':'application/vnd.oci.image.layer.v1.tar','digest':ld,'size':len(self.layer)};m=oci.encode({'schemaVersion':2,'mediaType':'application/vnd.oci.image.manifest.v1+json','config':c,'layers':[l]});self.lock['manifest']=oci.digest(m);self.lock['from']='drumee-minimal-application-tools@'+self.lock['manifest'];self.archive=self.root/'base.tar'
  with tarfile.open(self.archive,'w') as tar:
   for name,data in [('manifest.json',oci.encode([{'Config':'config','Layers':['layer']}])),('config',self.config),('layer',self.layer)]:
    item=tarfile.TarInfo(name);item.size=len(data);tar.addfile(item,io.BytesIO(data))
  self.layout=self.root/'oci';oci.prepare(self.archive,self.layout,self.lock)
 def tearDown(self):self.temp.cleanup()
 def test_exact_config_manifest_and_layers(self):self.assertEqual(oci.validate(self.layout,self.lock)['config'],oci.digest(self.config))
 def test_corrupted_layer_refused(self):
  p=self.layout/'blobs/sha256'/oci.digest(self.layer)[7:];p.write_bytes(b'corrupt')
  with self.assertRaisesRegex(ValueError,'INTEGRITY'):oci.validate(self.layout,self.lock)
 def test_missing_layer_refused(self):
  (self.layout/'blobs/sha256'/oci.digest(self.layer)[7:]).unlink()
  with self.assertRaisesRegex(ValueError,'MISSING'):oci.validate(self.layout,self.lock)
 def test_wrong_manifest_and_config_refused(self):
  for key,code in [('manifest','MANIFEST_MISMATCH'),('config','CONFIG_MISMATCH')]:
   lock=copy.deepcopy(self.lock);lock[key]='sha256:'+'b'*64;lock['from']='drumee-minimal-application-tools@'+lock['manifest']
   with self.assertRaisesRegex(ValueError,code):oci.validate(self.layout,lock)
 def test_existing_target_preserved(self):
  before=(self.layout/'index.json').read_bytes()
  with self.assertRaisesRegex(ValueError,'NOT_EMPTY'):oci.prepare(self.archive,self.layout,self.lock)
  self.assertEqual(before,(self.layout/'index.json').read_bytes())
 def test_mutable_absent_invalid_native_from_refused(self):
  lockfile=self.root/'lock.json';lockfile.write_text(json.dumps(self.lock));source=self.root/'Dockerfile';code="const fs=require('node:fs'),v=require(process.argv[1]);v.validateFrom(fs.readFileSync(process.argv[2],'utf8'),JSON.parse(fs.readFileSync(process.argv[3])));"
  for value,valid in [('FROM '+self.lock['from'],True),('FROM image:latest',False),('FROM ${MISSING}',False),('FROM image@sha256:bad',False),('',False),('FROM '+self.lock['from']+'\nFROM image:latest',False)]:
   source.write_text(value);r=subprocess.run(['node','-e',code,str(repo/'profiles/mail/native/base-input.cjs'),str(source),str(lockfile)],capture_output=True);self.assertEqual(r.returncode==0,valid,value)
if __name__=='__main__':unittest.main()
