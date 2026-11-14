import os,pathlib,sys,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[3]/'profiles/mail/admin'))
from password import validate,read_fd
from model import Refusal
class PasswordTests(unittest.TestCase):
 def test_exact_utf8_spaces_and_boundaries(self):
  value=('  '+chr(0xe9)*8+'  ').encode();self.assertEqual(validate(value),value);self.assertEqual(len(validate(b'x'*1024)),1024)
 def test_invalid_inputs(self):
  for value in [b'',b'x'*15,b'x'*1025,b'x'*16+b'\n',b'x'*16+b'\r',b'x'*16+b'\0',b'\xff'*16,b'\xef\xbb\xbf'+b'x'*16]:
   with self.subTest(size=len(value)):
    with self.assertRaises(Refusal):validate(value)
 def test_private_file_and_unsafe_mode(self):
  with tempfile.TemporaryDirectory() as root:
   p=pathlib.Path(root)/'secret';p.write_bytes(b'x'*16);p.chmod(0o600);self.assertEqual(read_fd(os.open(p,os.O_RDONLY)),b'x'*16);p.chmod(0o640)
   fd=os.open(p,os.O_RDONLY)
   try:
    with self.assertRaises(Refusal):read_fd(fd)
   finally:os.close(fd)
 def test_writable_and_path_only_descriptors_are_refused(self):
  with tempfile.TemporaryDirectory() as root:
   p=pathlib.Path(root)/'secret';p.write_bytes(b'x'*16);p.chmod(0o600)
   for flag in (os.O_RDWR,os.O_WRONLY,os.O_PATH):
    fd=os.open(p,flag)
    try:
     with self.assertRaises(Refusal):read_fd(fd)
    finally:os.close(fd)
 def test_pipe_and_link_refusals(self):
  a,b=os.pipe();os.write(b,b'y'*16);os.close(b);self.assertEqual(read_fd(a),b'y'*16)
  with tempfile.TemporaryDirectory() as root:
   p=pathlib.Path(root)/'secret';p.write_bytes(b'x'*16);p.chmod(0o600);os.link(p,pathlib.Path(root)/'link');fd=os.open(p,os.O_RDONLY)
   try:
    with self.assertRaises(Refusal):read_fd(fd)
   finally:os.close(fd)
if __name__=='__main__':unittest.main()
