import hashlib
import importlib.util
import io
import json
import pathlib
import tarfile
import tempfile
import unittest

module_path = pathlib.Path(__file__).resolve().parents[2] / "profiles/minimal-kernel/scripts/image-archive.py"
spec = importlib.util.spec_from_file_location("image_archive", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PortableImages(unittest.TestCase):
    def archive(self, directory, mutation=None, symlink=False):
        blobs = {}
        def blob(value):
            data = value if isinstance(value, bytes) else json.dumps(value, separators=(",", ":")).encode()
            digest = "sha256:" + hashlib.sha256(data).hexdigest()
            blobs["blobs/sha256/" + digest[7:]] = data
            return {"digest": digest, "size": len(data)}
        layer = blob(b"owned-test-layer")
        receipt = {"revision": "a" * 40, "alignment_sha256": "c" * 64, "tags": {"kernel": "drumee-minimal-kernel:" + "a" * 40, "tools": "drumee-minimal-tools:" + "b" * 40}}
        entries = []
        for role in ("kernel", "tools"):
            labels = {"org.opencontainers.image.source": "https://github.com/drumee/" + ("debian" if role == "kernel" else "infra-layer"), "org.opencontainers.image.revision": "a" * 40 if role == "kernel" else "b" * 40, "org.drumee.distribution.alignment": receipt["alignment_sha256"]}
            config = {"os": "linux", "architecture": "amd64", "config": {"Labels": labels}, "rootfs": {"diff_ids": [layer["digest"]]}}
            if mutation:
                mutation(role, config)
            record = blob(config)
            receipt[role] = record["digest"]
            manifest = blob({"schemaVersion": 2, "config": record, "layers": [{**layer, "mediaType": "application/vnd.oci.image.layer.v1.tar"}]})
            entries.append({**manifest, "annotations": {"io.containerd.image.name": "docker.io/library/" + receipt["tags"][role]}})
        blobs["index.json"] = json.dumps({"schemaVersion": 2, "manifests": entries}).encode()
        filename = pathlib.Path(directory) / "images.tar.gz"
        with tarfile.open(filename, "w:gz") as target:
            for name, data in blobs.items():
                info = tarfile.TarInfo(name); info.size = len(data)
                target.addfile(info, io.BytesIO(data))
            if symlink:
                info = tarfile.TarInfo("unexpected-link"); info.type = tarfile.SYMTYPE; info.linkname = "/etc/passwd"
                target.addfile(info)
        return filename, receipt

    def test_config_and_manifest_identities_are_proven_without_relaxing_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            filename, receipt = self.archive(directory)
            result = module.inspect_archive(filename, receipt)
            self.assertNotEqual(result["kernel"], receipt["kernel"])
            self.assertEqual(result["exported_images"]["kernel"]["config_digest"], receipt["kernel"])
            self.assertEqual(result["archive_sha256"], hashlib.sha256(filename.read_bytes()).hexdigest())

    def test_wrong_source_image_id_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            filename, receipt = self.archive(directory); receipt["kernel"] = "sha256:" + "0" * 64
            with self.assertRaisesRegex(ValueError, "IMAGE_REFERENCE_MISMATCH"):
                module.inspect_archive(filename, receipt)

    def test_wrong_source_labels_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            filename, receipt = self.archive(directory, lambda role, config: config["config"]["Labels"].update({"org.opencontainers.image.revision": "f" * 40}))
            with self.assertRaisesRegex(ValueError, "IMAGE_SOURCE_PROVENANCE_MISMATCH"):
                module.inspect_archive(filename, receipt)

    def test_layer_chain_cannot_be_rebound_to_another_rootfs(self):
        with tempfile.TemporaryDirectory() as directory:
            filename, receipt = self.archive(directory, lambda role, config: config["rootfs"].update({"diff_ids": ["sha256:" + "0" * 64]}))
            with self.assertRaisesRegex(ValueError, "IMAGE_LAYER_CHAIN_MISMATCH"):
                module.inspect_archive(filename, receipt)

    def test_archive_links_are_never_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            filename, receipt = self.archive(directory, symlink=True)
            with self.assertRaisesRegex(ValueError, "UNSAFE_IMAGE_ARCHIVE"):
                module.inspect_archive(filename, receipt)


if __name__ == "__main__":
    unittest.main()
