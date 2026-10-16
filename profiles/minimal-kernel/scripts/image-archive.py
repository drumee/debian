"""Verify portable OCI identities against a committed local build receipt.

Docker classic stores report config IDs; containerd stores report manifest IDs.
Neither representation is substituted without proving the complete blob chain.
No archive member is extracted to the filesystem.
"""
import hashlib
import json
import os
import re
import stat
import sys
import tarfile


def fail(code):
    raise ValueError(code)


def inspect_archive(filename, receipt):
    values, records = {}, {}
    fd = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            fail("UNSAFE_IMAGE_ARCHIVE")
        with tarfile.open(fileobj=source, mode="r|gz") as archive:
            total = 0
            for member in archive:
                name = member.name.rstrip("/")
                if name.startswith("/") or ".." in name.split("/") or "\\" in name or name in records or not (member.isdir() or member.isfile()):
                    fail("UNSAFE_IMAGE_ARCHIVE")
                if member.isdir():
                    continue
                total += member.size
                if total > 16 * 1024**3 or len(records) > 10000:
                    fail("IMAGE_ARCHIVE_LIMIT_EXCEEDED")
                content, digest = bytearray(), hashlib.sha256()
                stream = archive.extractfile(member)
                while True:
                    chunk = stream.read(65536)
                    if not chunk:
                        break
                    digest.update(chunk)
                    if member.size <= 1024**2:
                        content.extend(chunk)
                actual = digest.hexdigest()
                if name.startswith("blobs/") and name != "blobs/sha256/" + actual:
                    fail("IMAGE_BLOB_INTEGRITY_MISMATCH")
                records[name] = {"digest": actual, "size": member.size}
                if content:
                    try:
                        values[name] = json.loads(content)
                    except (ValueError, UnicodeDecodeError):
                        pass
    index = values.get("index.json", {})
    if index.get("schemaVersion") != 2 or not isinstance(index.get("manifests"), list):
        fail("OCI_IMAGE_INDEX_REQUIRED")

    def blob(descriptor):
        digest = descriptor.get("digest", "")
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
            fail("OCI_DESCRIPTOR_INVALID")
        name = "blobs/sha256/" + digest[7:]
        if records.get(name, {}).get("size") != descriptor.get("size"):
            fail("OCI_DESCRIPTOR_INVALID")
        return values.get(name)

    result = dict(receipt)
    result["exported_images"] = {}
    for role in ("kernel", "tools"):
        tag = receipt["tags"][role]
        if not re.fullmatch("drumee-minimal-" + role + r":[a-f0-9]{40}", tag):
            fail("IMAGE_BUILD_TAG_INVALID")
        candidates = [entry for entry in index["manifests"] if entry.get("annotations", {}).get("io.containerd.image.name", "").endswith("/" + tag)]
        if len(candidates) != 1:
            fail("IMAGE_REFERENCE_MISMATCH")
        descriptor = candidates[0]
        manifest = blob(descriptor)
        if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 2:
            fail("OCI_MANIFEST_INVALID")
        config = blob(manifest["config"])
        if receipt[role] not in (descriptor["digest"], manifest["config"]["digest"]):
            fail("IMAGE_REFERENCE_MISMATCH")
        if not isinstance(config, dict):
            fail("OCI_CONFIG_INVALID")
        layers = manifest.get("layers", [])
        for layer in layers:
            blob(layer)
            if layer.get("mediaType") != "application/vnd.oci.image.layer.v1.tar":
                fail("PORTABLE_LAYER_FORMAT_UNSUPPORTED")
        if config.get("rootfs", {}).get("diff_ids") != [layer["digest"] for layer in layers]:
            fail("IMAGE_LAYER_CHAIN_MISMATCH")
        labels = config.get("config", {}).get("Labels", {})
        repository = "debian" if role == "kernel" else "infra-layer"
        revision = receipt["revision"] if role == "kernel" else tag.rsplit(":", 1)[1]
        if labels.get("org.opencontainers.image.source") != "https://github.com/drumee/" + repository or labels.get("org.opencontainers.image.revision") != revision:
            fail("IMAGE_SOURCE_PROVENANCE_MISMATCH")
        if role == "kernel" and labels.get("org.drumee.distribution.alignment") != receipt["alignment_sha256"]:
            fail("IMAGE_ALIGNMENT_MISMATCH")
        reference = tag.rsplit(":", 1)[0] + "@" + descriptor["digest"]
        result[role] = reference
        result["exported_images"][role] = {"reference": reference, "manifest_digest": descriptor["digest"], "config_digest": manifest["config"]["digest"], "platform": config.get("os", "") + "/" + config.get("architecture", ""), "layers": [layer["digest"] for layer in layers]}
    digest = hashlib.sha256()
    with open(filename, "rb") as source:
        for chunk in iter(lambda: source.read(65536), b""):
            digest.update(chunk)
    result["archive_sha256"] = digest.hexdigest()
    return result


if __name__ == "__main__":
    try:
        with open(sys.argv[2]) as source:
            receipt = json.load(source)
        print(json.dumps(inspect_archive(sys.argv[1], receipt), indent=2))
    except Exception as error:
        code = str(error)
        print(code if re.fullmatch(r"[A-Z0-9_]+", code) else "IMAGE_ARCHIVE_INVALID", file=sys.stderr)
        sys.exit(1)
