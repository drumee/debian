import sys,pathlib,unittest,copy
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[3]/'profiles/mail/admin'))
from model import initial,mutate,projection,Refusal
class ModelTests(unittest.TestCase):
 def setUp(self):self.s=initial(dict(contract='drumee.mail-registry/1',generation=1,mailboxes=[],aliases=[],accounts=[]))
 def op(self,f,v,id,**opts):self.s,o=mutate(self.s,f,v,id,opts,['oxymot.fr'],1048576);return o
 def test_stable_rename_alias_and_retention(self):
  b=self.op('mailbox','create','contact@oxymot.fr');id=b['id'];self.op('mailbox','rename','contact@oxymot.fr',to='accueil@oxymot.fr');self.assertEqual(self.s['aliases'][0]['mailbox_id'],id);b=self.op('mailbox','delete',id);self.assertTrue(b['deleted']);self.assertEqual(projection(self.s,2)['mailboxes'][0]['id'],id)
  with self.assertRaises(Refusal):self.op('mailbox','create','contact@oxymot.fr')
 def test_collision_and_alias_chain(self):
  self.op('mailbox','create','contact@oxymot.fr');self.op('alias','create','hello@oxymot.fr',mailbox='contact@oxymot.fr')
  with self.assertRaises(Refusal):self.op('alias','create','loop@oxymot.fr',mailbox='hello@oxymot.fr')
  with self.assertRaises(Refusal):self.op('mailbox','create','Hello@oxymot.fr')
 def test_disable_scopes_and_noop(self):
  self.op('mailbox','create','contact@oxymot.fr');self.op('mailbox','disable','contact@oxymot.fr',scope='receive');b=self.s['mailboxes'][0];self.assertTrue(b['imap_enabled']);before=copy.deepcopy(self.s);self.op('mailbox','disable',b['id'],scope='receive');self.assertEqual(before,self.s)
 def test_account_dsn_and_generation(self):
  self.op('mailbox','create','contact@oxymot.fr');self.op('account','create','ghost',envelope_from=['contact@oxymot.fr'],header_from=['contact@oxymot.fr'],dsn_mailbox='contact@oxymot.fr');self.assertFalse(self.s['accounts'][0]['enabled']);self.op('account','enable','ghost');self.assertTrue(self.s['accounts'][0]['enabled']);self.op('mailbox','disable','contact@oxymot.fr',scope='receive');self.assertEqual(self.s['accounts'][0]['credential_generation'],2)
 def test_rename_retires_explicit_sender_grants(self):
  self.op('mailbox','create','contact@oxymot.fr');self.op('account','create','ghost',envelope_from=['contact@oxymot.fr'],header_from=['contact@oxymot.fr'],dsn_mailbox='contact@oxymot.fr');self.op('mailbox','rename','contact@oxymot.fr',to='new@oxymot.fr',old_address='reject');a=self.s['accounts'][0];self.assertFalse(a['enabled']);self.assertEqual(a['envelope_from'],[])
if __name__=='__main__':unittest.main()
