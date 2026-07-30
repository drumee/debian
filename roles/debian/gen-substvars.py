#!/usr/bin/env python3
"""Derive per-package substvars from release-manifest.yaml.

The manifest is the single authoritative statement of which component
version belongs to a release. Every drumee-role-* package pins its
components with `= ${drumee:SomethingVersion}`; this script resolves those
placeholders so that the pins cannot drift from the manifest by hand.

Run before dh_gencontrol. See debian/rules.
"""

from __future__ import annotations

import argparse
import datetime
import sys
from pathlib import Path

import yaml

# Mapping: substvar name -> key under `components:` in the manifest.
SUBSTVARS = {
    "drumee:ServerVersion": "server-pod",
    "drumee:UiVersion": "ui-pod",
    "drumee:StaticVersion": "static",
    "drumee:SchemasVersion": "schemas",
    "drumee:PatchVersion": "patch",
    "drumee:InfraVersion": "infra",
    "drumee:BootstrapVersion": "bootstrap",
    "drumee:NodeRuntimeVersion": "node-runtime",
}

# Which substvars each binary package actually references. Writing only the
# needed ones keeps dpkg-gencontrol from warning about unused substitutions.
PACKAGE_SUBSTVARS = {
    "drumee-role-app": [
        "drumee:ServerVersion",
        "drumee:BootstrapVersion",
        "drumee:NodeRuntimeVersion",
    ],
    "drumee-role-web": [
        "drumee:UiVersion",
        "drumee:StaticVersion",
        "drumee:BootstrapVersion",
    ],
    "drumee-role-media": [
        "drumee:BootstrapVersion",
        "drumee:NodeRuntimeVersion",
    ],
    "drumee-role-dns": [
        "drumee:BootstrapVersion",
    ],
    "drumee-role-mail": [
        "drumee:BootstrapVersion",
    ],
    "drumee-role-schemas": [
        "drumee:SchemasVersion",
        "drumee:PatchVersion",
        "drumee:BootstrapVersion",
        "drumee:NodeRuntimeVersion",
    ],
    "drumee-role-infra": [
        "drumee:InfraVersion",
        "drumee:BootstrapVersion",
        "drumee:NodeRuntimeVersion",
    ],
    "drumee-release": [],
}


def load_manifest(path: Path) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        sys.exit(f"gen-substvars: manifest not found: {path}")
    except yaml.YAMLError as exc:
        sys.exit(f"gen-substvars: cannot parse {path}: {exc}")

    if not isinstance(data, dict):
        sys.exit(f"gen-substvars: {path} does not contain a mapping")
    return data


def resolve(manifest: dict) -> tuple[str, str, dict[str, str]]:
    release = str(manifest.get("release") or "").strip()
    if not release:
        sys.exit("gen-substvars: manifest is missing a top-level 'release'")

    channel = str(manifest.get("channel") or "trixie").strip()
    components = manifest.get("components") or {}
    if not isinstance(components, dict):
        sys.exit("gen-substvars: 'components' must be a mapping")

    resolved: dict[str, str] = {}
    missing: list[str] = []
    for substvar, key in SUBSTVARS.items():
        version = components.get(key)
        if not version:
            missing.append(key)
            continue
        resolved[substvar] = str(version).strip()

    if missing:
        sys.exit(
            "gen-substvars: manifest declares no version for: "
            + ", ".join(sorted(missing))
        )

    return release, channel, resolved


def write_substvars(debian_dir: Path, resolved: dict[str, str]) -> None:
    for package, wanted in PACKAGE_SUBSTVARS.items():
        target = debian_dir / f"{package}.substvars"
        existing = []
        if target.exists():
            existing = [
                line
                for line in target.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("drumee:")
            ]
        lines = existing + [f"{name}={resolved[name]}" for name in wanted]
        target.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"gen-substvars: wrote {target.name} ({len(wanted)} pins)")


def write_release_file(target: Path, release: str, channel: str) -> None:
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "\n".join(
            [
                f"DRUMEE_RELEASE={release}",
                f"DRUMEE_CHANNEL={channel}",
                f"DRUMEE_BUILD_DATE={stamp.isoformat()}",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"gen-substvars: wrote {target}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--debian-dir", type=Path)
    parser.add_argument("--release-file", type=Path)
    args = parser.parse_args()

    if not args.debian_dir and not args.release_file:
        parser.error("give --debian-dir, --release-file, or both")

    manifest = load_manifest(args.manifest)
    release, channel, resolved = resolve(manifest)

    if args.debian_dir:
        write_substvars(args.debian_dir, resolved)
    if args.release_file:
        write_release_file(args.release_file, release, channel)


if __name__ == "__main__":
    main()
