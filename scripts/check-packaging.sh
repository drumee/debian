#!/usr/bin/env bash
# Encode the packaging invariants as a test.
#
# CLAUDE.md is context, not a constraint. This script is the constraint.
# Wire it into ci.yml and run it before declaring any task complete.
#
#   scripts/check-packaging.sh [repo-root]

set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 2

fail=0
note() { printf '  %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
ok() { printf 'ok    %s\n' "$1"; }

# Scan only what is under version control. `find` also walks build output
# (infra/build, meta/build), staging trees and vendored upstream code
# (infra/src/acme), none of which the increments can fix — noise there would
# drown the real debt. Tracked files are exactly the ones code review governs.
#
# A gate that silently scans nothing is worse than one that fails, so refuse to
# run rather than report a vacuous pass when git cannot list files.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'FATAL  not a git work tree (or git missing): cannot scope the scan.\n' >&2
  printf '       The invariants are checked against tracked files only.\n' >&2
  exit 2
fi

# Vendored upstream code, tracked but not ours to change: target/ is the
# pre-built artifact tree for drumee-installer (it carries upstream acme.sh,
# whose own installer is a `curl … | sh`), and builder/src/setup is a checkout of
# the setup repo. Fixing either here would mean forking upstream. ci.yml's
# ShellCheck step already skips exactly these two paths — same reasoning.
VENDORED='^(target|builder/src)/'

tracked() { # tracked <basename-regex>   -> paths of tracked files whose basename matches
  git ls-files | grep -Ev "$VENDORED" | grep -E "$1"
}

dockerfiles() { tracked '(^|/)Dockerfile[^/]*$'; }
control_files() { tracked '(^|/)debian/control$'; }

# Comments often explain the prohibition itself, so scanning them would
# produce false positives. Read instructions only.
scan() { # scan <extended-regex>
  local f
  while IFS= read -r f; do
    grep -vE '^[[:space:]]*#' "$f" | grep -nE "$1" | sed "s|^|$f:|"
  done < <(dockerfiles)
}

# --- Dockerfiles --------------------------------------------------------------

check_no_clone() {
  local hits
  hits=$(scan 'git clone|REPO_BASE')
  if [[ -n "$hits" ]]; then
    bad "sources fetched by cloning at build time"
    note "$hits"
  else
    ok "no git clone / REPO_BASE in any Dockerfile"
  fi
}

check_from_digest() {
  local hits
  hits=$(scan '^[[:space:]]*FROM[[:space:]]' | grep -vE '@\$|@sha256:|AS builder')
  if [[ -n "$hits" ]]; then
    bad "FROM without a digest - the base image will drift silently"
    note "$hits"
  else
    ok "every FROM is pinned by digest"
  fi
}

check_no_remote_exec() {
  local hits
  hits=$(scan 'curl[^|]*\|[[:space:]]*(bash|sh|gpg)')
  if [[ -n "$hits" ]]; then
    bad "remote script or key executed at build time"
    note "$hits"
  else
    ok "no curl piped into bash/sh/gpg"
  fi
}

check_update_install_same_layer() {
  # A RUN "apt-get update" with no install in the same logical command leaves
  # a cached index facing a newer install, which makes installs fail
  # erratically. Rejoin line continuations before judging.
  local hits
  hits=$(dockerfiles | while IFS= read -r f; do
    awk -v F="$f" '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*RUN[[:space:]]/ {
        buf = $0
        while (buf ~ /\\[[:space:]]*$/) { if ((getline nx) <= 0) break; buf = buf " " nx }
        if (buf ~ /apt-get[[:space:]]+update/ && buf !~ /install/)
          print F ":" NR ": apt-get update stands alone"
      }
    ' "$f"
  done)
  if [[ -n "$hits" ]]; then
    bad "apt-get update in a layer separate from its install"
    note "$hits"
  else
    ok "apt-get update always paired with its install"
  fi
}

check_no_recommends() {
  local hits
  hits=$(scan 'apt-get[[:space:]]+install' | grep -v -- '--no-install-recommends')
  if [[ -n "$hits" ]]; then
    bad "apt-get install without --no-install-recommends"
    note "$hits"
  else
    ok "--no-install-recommends used throughout"
  fi
}

check_no_npm_global() {
  local hits
  hits=$(scan 'npm[[:space:]]+install[[:space:]].*-g')
  if [[ -n "$hits" ]]; then
    bad "npm install -g - use drumee-node-runtime instead"
    note "$hits"
  else
    ok "no npm install -g"
  fi
}

check_no_build_tooling() {
  local hits
  hits=$(scan '(build-essential|node-gyp|default-jdk|[^-]g\+\+)' | grep -v 'builder')
  if [[ -n "$hits" ]]; then
    bad "build tooling present in a runtime image"
    note "$hits"
  else
    ok "no build tooling in runtime images"
  fi
}

check_drumee_pins() {
  local hits
  hits=$(scan 'apt-get[[:space:]]+install.*drumee-' | grep -Fv '=${' | grep -v '=[0-9]')
  if [[ -n "$hits" ]]; then
    bad "Drumee package installed without an exact version"
    note "$hits"
  else
    ok "Drumee packages always pinned"
  fi
}

# --- Packages -----------------------------------------------------------------

check_role_exclusion() {
  local missing=""
  for c in $(control_files); do
    awk -v file="$c" '
      /^Package:[[:space:]]*drumee-role-/ { pkg=$2; prov=0; conf=0; anchor=0; next }
      pkg && /^Provides:.*drumee-role([^-]|$)/ { prov=1 }
      pkg && /^Conflicts:.*drumee-role([^-]|$)/ { conf=1 }
      pkg && /drumee-release \(= \$\{binary:Version\}\)/ { anchor=1 }
      pkg && /^$/ {
        if (!prov || !conf) print file ": " pkg " lacks Provides/Conflicts drumee-role"
        if (!anchor) print file ": " pkg " lacks the drumee-release anchor"
        pkg=""
      }
      END {
        if (pkg) {
          if (!prov || !conf) print file ": " pkg " lacks Provides/Conflicts drumee-role"
          if (!anchor) print file ": " pkg " lacks the drumee-release anchor"
        }
      }
    ' "$c"
  done > /tmp/role-check.$$ 2>/dev/null
  missing=$(cat /tmp/role-check.$$); rm -f /tmp/role-check.$$
  if [[ -n "$missing" ]]; then
    bad "role packages declared incorrectly"
    note "$missing"
  else
    ok "mutual exclusion and version anchor declared on every role"
  fi
}

check_no_hardcoded_versions() {
  local hits
  # meta/debian/control is exempt: it is GENERATED from release-manifest.yaml by
  # meta/make-control.sh, and release.yml runs `make-control.sh --check` to prove
  # it is in sync. The versions in it are the manifest's, materialised — flagging
  # it would penalise the mechanism this invariant exists to require.
  hits=$(control_files | grep -v '^meta/debian/control$' | tr '\n' '\0' \
    | xargs -0 -r grep -nE 'drumee-[a-z-]+ \(= [0-9]' 2>/dev/null)
  if [[ -n "$hits" ]]; then
    bad "component version hardcoded - it must come from release-manifest.yaml"
    note "$hits"
  else
    ok "no hardcoded component version in any control file"
  fi
}

check_arch_matches_payload() {
  local hits="" c pkgdir arch ships
  # Architecture: all promises the payload is identical on every architecture.
  # A payload assembled from node_modules breaks that promise silently: the tree
  # carries compiled .node addons, and packages whose NAME encodes the platform
  # (@img/sharp-linux-x64, @msgpackr-extract/...-linux-x64). Such a .deb built on
  # amd64 installs cleanly on arm64 and then fails at require() — no dpkg error,
  # no startup error until the first call. See docs/distribution.md §9.1.
  #
  # Checked from source rather than from a built .deb: the artifacts are
  # gitignored and usually absent in CI, so an artifact-based check would pass by
  # doing nothing. Copying node_modules into the staging tree is the decisive act,
  # and it is visible in the build script. Merely referencing node_modules is not
  # (ui/build.sh only puts .bin on PATH), hence the copy verb in the pattern.
  while IFS= read -r c; do
    pkgdir="${c%/debian/control}"
    arch=$(awk '/^Architecture:/{print $2; exit}' "$c")
    [[ "$arch" == "all" ]] || continue
    ships=$(git ls-files "$pkgdir" 2>/dev/null | grep -E '(^|/)build\.sh$' \
      | tr '\n' '\0' | xargs -0 -r grep -nE '(rsync|cp|install|tar)[^|]*node_modules' 2>/dev/null)
    # Shipping node_modules is a signal, not a verdict: a pure-JavaScript tree is
    # legitimately Architecture: all. A package may say so in
    # debian/arch-independent-payload, which must state the evidence AND be backed
    # by a build-time check that refuses a payload containing compiled objects —
    # drumee-node-runtime is the worked example. Without that file the claim is
    # unverified, and unverified is what ships an amd64 binary to an arm64 host.
    if [[ -n "$ships" && -f "$pkgdir/debian/arch-independent-payload" ]]; then
      continue
    fi
    if [[ -n "$ships" ]]; then
      hits+="$c: Architecture: all, but the payload ships node_modules"$'\n'"$ships"$'\n'
    fi
  done < <(control_files)
  if [[ -n "$hits" ]]; then
    bad "Architecture: all on a package carrying native code"
    note "$hits"
  else
    ok "Architecture matches the payload"
  fi
}

check_manifest_present() {
  if [[ -f release-manifest.yaml ]]; then
    ok "release-manifest.yaml present"
  else
    bad "release-manifest.yaml missing"
  fi
}

# --- Run ----------------------------------------------------------------------

printf 'Packaging invariants - %s\n\n' "$ROOT"
check_no_clone
check_from_digest
check_no_remote_exec
check_update_install_same_layer
check_no_recommends
check_no_npm_global
check_no_build_tooling
check_drumee_pins
check_role_exclusion
check_no_hardcoded_versions
check_arch_matches_payload
check_manifest_present

printf '\n'
if (( fail )); then
  printf 'Invariants violated. See docs/distribution.md.\n'
  exit 1
fi
printf 'All invariants hold.\n'
