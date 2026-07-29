#!/bin/bash
# Publish a release to both install hosts:
#   1. build a signed flat APT repo and rsync it to apt.drumee.net (the VPS)
#   2. deploy the Pages content to get.drumee.com (installers, renderer, CLIs)
# The two targets are independent: (1) needs SSH access to the VPS, (2) needs a
# token with contents:write on PAGES_REPO. Each is skipped, with a notice, when
# its credentials are absent — so a partial credential set still publishes what
# it can instead of failing the release.
#
#   APT_SSH_HOST=deploy@vps GH_TOKEN=<token> scripts/publish-site.sh --debs=out-debs [--key=KEYID]
#
# Env:
#   APT_SSH_HOST  (optional) USER@HOST for the apt.drumee.net VPS; unset = skip apt
#   APT_REPO_DIR  (default /var/www/apt.drumee.net) doc root on the VPS
#   APT_DOMAIN    (default apt.drumee.net) used only in the printed client snippet
#   PAGES_REPO    (default drumee/get-drumee-pages)
#   GH_TOKEN      (optional) token with write access to PAGES_REPO; unset = skip Pages
#   REF_NAME      (optional) release label for the commit message
set -euo pipefail

DEBS="out-debs"; KEY=""
for a in "$@"; do case $a in --debs=*) DEBS="${a#*=}";; --key=*) KEY="${a#*=}";; *) echo "unknown arg $a" >&2; exit 2;; esac; done
PAGES_REPO="${PAGES_REPO:-drumee/get-drumee-pages}"
APT_SSH_HOST="${APT_SSH_HOST:-}"
APT_REPO_DIR="${APT_REPO_DIR:-/var/www/apt.drumee.net}"
APT_DOMAIN="${APT_DOMAIN:-apt.drumee.net}"
GH_TOKEN="${GH_TOKEN:-}"
REF_NAME="${REF_NAME:-${GITHUB_REF_NAME:-manual}}"
[ -n "$APT_SSH_HOST" ] || [ -n "$GH_TOKEN" ] || {
  echo "error: set APT_SSH_HOST and/or GH_TOKEN — nothing to publish to" >&2; exit 2; }
[ -d "$DEBS" ] || { echo "error: --debs dir not found: $DEBS" >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"

# Build the flat repo once; both targets consume it.
flat="$(mktemp -d)/apt"
bash "$root/scripts/publish-apt.sh" --debs="$DEBS" --out="$flat" ${KEY:+--key="$KEY"}

# The bare-metal bootstrap is served from the apt host too, so `curl
# https://apt.drumee.net/baremetal.sh | sudo bash` works without Pages.
cp "$root/scripts/baremetal.sh" "$flat/baremetal.sh"
# install-native.sh is the name this script was published under before the rename;
# keep serving it so bootstrap commands already in the wild (and older docs) do not
# 404. Drop this line once that URL is no longer referenced anywhere.
cp "$root/scripts/baremetal.sh" "$flat/install-native.sh"

# 1) flat repo -> apt.drumee.net ----------------------------------------------
if [ -n "$APT_SSH_HOST" ]; then
  echo "==> deploying flat repo to $APT_SSH_HOST:$APT_REPO_DIR"
  APT_LOCAL_DIR="$flat" bash "$root/scripts/deploy-apt-repo.sh" \
    --host="$APT_SSH_HOST" --repo-dir="$APT_REPO_DIR" --domain="$APT_DOMAIN" --no-provision
else
  echo "==> APT_SSH_HOST not set — skipping apt.drumee.net deploy"
fi

# 2) deploy the Pages content -------------------------------------------------
if [ -n "$GH_TOKEN" ]; then
  export GH_TOKEN
  work="$(mktemp -d)/site"
  git clone --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/${PAGES_REPO}.git" "$work"
  mkdir -p "$work/config" "$work/bin"
  cp "$root/scripts/containers.sh"  "$work/install"
  cp "$root/scripts/baremetal.sh"   "$work/native"
  cp "$root/config/render.mjs"          "$work/config/render.mjs"
  cp "$root/config/drumee.schema.json"  "$work/config/drumee.schema.json"
  cp "$root/config/drumee.example.yaml" "$work/config/drumee.example.yaml"
  cp "$root/bin/drumee-ctl"             "$work/bin/drumee-ctl"
  cp "$root/bin/drumee-plugin"          "$work/bin/drumee-plugin"
  cp "$flat/drumee-archive-keyring.asc" "$work/drumee-archive-keyring.asc"
  chmod +x "$work/install" "$work/native" "$work/bin/"*
  ( cd "$work"
    git add -A
    if git diff --cached --quiet; then echo "==> Pages content already up to date"; else
      git -c user.name=drumee-ci -c user.email=ci@drumee.org commit -q -m "publish: installers for $REF_NAME"
      git push -q
      echo "==> deployed Pages content"
    fi )
else
  echo "==> GH_TOKEN not set — skipping $PAGES_REPO Pages deploy"
fi

cat <<MSG

Done. Clients install with:

  curl -fsSL https://${APT_DOMAIN}/drumee-archive-keyring.asc \\
    | sudo tee /etc/apt/keyrings/drumee.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/drumee.asc] https://${APT_DOMAIN}/ ./" \\
    | sudo tee /etc/apt/sources.list.d/drumee.list
  sudo apt update && sudo apt install drumee
MSG
