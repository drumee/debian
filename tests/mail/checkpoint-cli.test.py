"""Invalid recovery options must refuse before loading a configuration or touching data."""
import json,pathlib,subprocess,sys,unittest
script=pathlib.Path(__file__).resolve().parents[2]/'profiles/mail/admin/checkpoint.py'
class CLI(unittest.TestCase):
 def call(self,args):
  p=subprocess.run([sys.executable,'-I',str(script),*args,'--config','/nonexistent-mail05-protected-config'],capture_output=True,text=True);return p.returncode,json.loads(p.stdout)
 def test_explicit_execution_required_before_config_read(self):
  for op in ['backup','restore','recovery-release','recovery-resume-source','recovery-abort']:
   code,value=self.call([op]);self.assertEqual((code,value['code']),(5,'MAIL_NOT_AUTHORIZED'))
 def test_operation_option_sets_are_exact(self):
  cases=[['backup','--archive','/unused','--manifest-sha256','a'*64],['restore','--archive','/unused'],['recovery-release','--manifest-sha256','a'*64,'--target-uuid','unused'],['recovery-abort','--manifest-sha256','a'*64,'--target-uuid','unused','--archive','/unused'],['recovery-resume-source','--archive','/unused','--manifest-sha256','a'*64,'--target-uuid','unused']]
  for args in cases:
   code,value=self.call([*args,'--execute']);self.assertEqual((code,value['code']),(2,'MAIL_USAGE'))
 def test_private_replacement_approval_is_restore_only(self):
  for op,options in [('backup',['--archive','/unused']),('recovery-release',['--manifest-sha256','a'*64]),('recovery-resume-source',['--archive','/unused','--manifest-sha256','a'*64])]:
   code,value=self.call([op,*options,'--private-approval','/unapproved','--private-approval-sha256','b'*64,'--execute']);self.assertEqual((code,value['code']),(2,'MAIL_USAGE'))
if __name__=='__main__':unittest.main()
