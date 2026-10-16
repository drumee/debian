#!/usr/bin/env python3
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

script = Path(__file__).resolve().parents[2] / 'profiles/minimal-application/scripts/plugin-artifact.py'
spec = importlib.util.spec_from_file_location('plugin_artifact', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class PluginArtifacts(unittest.TestCase):
    def archive(self, root, extra=(), metadata=None):
        archive = Path(root) / 'plugin.tgz'
        with tarfile.open(archive, 'w:gz') as output:
            for name, body in [('package/package.json', json.dumps(metadata or {'name':'qualification','version':'1.0.0'}).encode()), ('package/server/acl/qualification.json', b'{}'), ('package/server/worker.js', b'module.exports=class{};')]:
                info = tarfile.TarInfo(name); info.size = len(body); output.addfile(info, io.BytesIO(body))
            for info, body in extra: output.addfile(info, io.BytesIO(body) if body is not None else None)
        sri = 'sha512-' + base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
        return archive, sri, Path(root)/'output'
    def test_valid_native_plugin(self):
        with tempfile.TemporaryDirectory() as root:
            a,s,d=self.archive(root); report=module.unpack(a,s,d)
            self.assertEqual(report['files'],3);self.assertEqual((d/'server/worker.js').read_text(),'module.exports=class{};')
            self.assertEqual(d.stat().st_mode & 0o777,0o755)
    def test_bad_integrity_never_creates_output(self):
        with tempfile.TemporaryDirectory() as root:
            a,s,d=self.archive(root)
            with self.assertRaisesRegex(ValueError,'PLUGIN_INTEGRITY_MISMATCH'):module.unpack(a,s+'x',d)
            self.assertFalse(d.exists())
    def test_traversal_and_absolute_paths(self):
        for name in ['package/../outside','/package/outside','package/server/./outside','package/server\\outside']:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as root:
                info=tarfile.TarInfo(name);info.size=1;a,s,d=self.archive(root,[(info,b'x')])
                with self.assertRaisesRegex(ValueError,'PLUGIN_PATH_INVALID'):module.unpack(a,s,d)
                self.assertFalse(d.exists())
    def test_links_and_special_files(self):
        for kind in [tarfile.SYMTYPE,tarfile.LNKTYPE,tarfile.CHRTYPE]:
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as root:
                info=tarfile.TarInfo('package/server/link');info.type=kind;info.linkname='/etc/passwd';a,s,d=self.archive(root,[(info,None)])
                with self.assertRaisesRegex(ValueError,'PLUGIN_LINK_OR_SPECIAL_FILE_FORBIDDEN'):module.unpack(a,s,d)
                self.assertFalse(d.exists())
    def test_duplicate_members(self):
        with tempfile.TemporaryDirectory() as root:
            info=tarfile.TarInfo('package/server/worker.js');info.size=1;a,s,d=self.archive(root,[(info,b'x')])
            with self.assertRaisesRegex(ValueError,'PLUGIN_PATH_INVALID'):module.unpack(a,s,d)
    def test_credential_and_provenance_files(self):
        for name in ['.npmrc','.env','.git/config','.aws/credentials','.drumee-artifact.json']:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as root:
                info=tarfile.TarInfo('package/'+name);info.size=1;a,s,d=self.archive(root,[(info,b'x')])
                with self.assertRaisesRegex(ValueError,'PLUGIN_PATH_INVALID'):module.unpack(a,s,d)
    def test_unbundled_dependencies(self):
        with tempfile.TemporaryDirectory() as root:
            a,s,d=self.archive(root,metadata={'dependencies':{'unrecorded':'latest'}})
            with self.assertRaisesRegex(ValueError,'PLUGIN_DEPENDENCIES_MUST_BE_BUNDLED'):module.unpack(a,s,d)
    def test_repeated_root_headers_are_bounded(self):
        with tempfile.TemporaryDirectory() as root:
            info=tarfile.TarInfo('package');info.type=tarfile.DIRTYPE
            a,s,d=self.archive(root,[(info,None)]*10001)
            with self.assertRaisesRegex(ValueError,'PLUGIN_PATH_INVALID'):module.unpack(a,s,d)

if __name__=='__main__':unittest.main()
