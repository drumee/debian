#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$root/profiles/minimal-kernel/scripts/sources.js"
node "$root/profiles/minimal-kernel/scripts/build.js"
