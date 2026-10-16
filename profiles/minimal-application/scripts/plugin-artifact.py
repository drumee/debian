#!/usr/bin/env python3
"""Verify and unpack a pinned npm plugin archive into a new owned build context."""
import base64
import hashlib
import io
import stat
import json
import os
from pathlib import Path
import re
import sys
import tarfile

def unpack(archive, integrity, destination):
    archive, destination = Path(archive), Path(destination)
    if not archive.is_file() or archive.is_symlink() or archive.stat().st_size > 32 * 1024 * 1024:
        raise ValueError('PLUGIN_ARCHIVE_INVALID')
    fd = os.open(archive, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode): raise ValueError('PLUGIN_ARCHIVE_INVALID')
        data = source.read(32 * 1024 * 1024 + 1)
    if len(data) > 32 * 1024 * 1024: raise ValueError('PLUGIN_SIZE_LIMIT')
    expected = 'sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode()
    if integrity != expected:
        raise ValueError('PLUGIN_INTEGRITY_MISMATCH')
    if destination.exists():
        raise ValueError('PLUGIN_DESTINATION_OCCUPIED')
    records, names, total = [], set(), 0
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as stream:
        for index, member in enumerate(stream):
            parts = member.name.rstrip('/').split('/')
            if index >= 10000 or parts[0] != 'package' or any(p in ('', '.', '..') for p in parts) or member.name.startswith('/') or '\\' in member.name or not re.fullmatch(r'[a-zA-Z0-9_./@+ -]+', member.name):
                raise ValueError('PLUGIN_PATH_INVALID')
            if len(parts) == 1:
                if not member.isdir(): raise ValueError('PLUGIN_PATH_INVALID')
                continue
            relative = '/'.join(parts[1:])
            if relative in names or any(p in ('.npmrc', '.git', '.aws', '.drumee-artifact.json') or p.startswith('.env') for p in parts):
                raise ValueError('PLUGIN_PATH_INVALID')
            names.add(relative)
            if not member.isdir() and not member.isfile():
                raise ValueError('PLUGIN_LINK_OR_SPECIAL_FILE_FORBIDDEN')
            if member.size < 0 or member.size > 16 * 1024 * 1024:
                raise ValueError('PLUGIN_SIZE_LIMIT')
            total += member.size
            if total > 64 * 1024 * 1024: raise ValueError('PLUGIN_SIZE_LIMIT')
            body = stream.extractfile(member).read() if member.isfile() else None
            records.append((relative, body, member.mode))
    package = next((body for name, body, _ in records if name == 'package.json'), None)
    if package is None: raise ValueError('PLUGIN_PACKAGE_REQUIRED')
    metadata = json.loads(package)
    dependencies = {**metadata.get('dependencies', {}), **metadata.get('optionalDependencies', {})}
    bundled = metadata.get('bundledDependencies', metadata.get('bundleDependencies', []))
    if bundled is True: bundled = list(dependencies)
    if any(name not in bundled or not any(p.startswith('node_modules/' + name + '/') for p in names) for name in dependencies):
        raise ValueError('PLUGIN_DEPENDENCIES_MUST_BE_BUNDLED')
    if not any(p.startswith('server/acl/') and p.endswith('.json') for p in names):
        raise ValueError('PLUGIN_NATIVE_ACL_REQUIRED')
    destination.mkdir(mode=0o755, parents=False)
    for relative, body, mode in sorted(records, key=lambda item: (len(item[0].split('/')), item[0])):
        target = destination / relative
        if body is None:
            target.mkdir(mode=0o755, parents=True, exist_ok=True)
        else:
            target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            with target.open('xb') as output: output.write(body)
            os.chmod(target, 0o755 if mode & 0o111 else 0o644)
    os.chmod(destination, 0o755)
    for folder in destination.rglob('*'):
        if folder.is_dir(): os.chmod(folder, 0o755)
    return {'files': len(records), 'bytes': total, 'integrity': expected}

if __name__ == '__main__':
    try:
        print(json.dumps(unpack(*sys.argv[1:])))
    except (ValueError, OSError, tarfile.TarError, TypeError) as error:
        code = str(error)
        print(code if re.fullmatch(r'[A-Z_]+', code) else 'PLUGIN_ARCHIVE_INVALID', file=sys.stderr)
        sys.exit(1)
