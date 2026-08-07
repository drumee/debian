#!/bin/bash
# Deploy the flat APT repository to a VPS running nginx.
#
# Uploads the repo files (Packages, Release, InRelease, .deb files, keyring)
# and installs an nginx config to serve them over HTTPS.
#
# Prerequisites on the VPS:
#   - nginx installed and running
#   - certbot (or other ACME client) for TLS on apt.drumee.net
#   - SSH access as the deploy user
#
# Provisioning (creating the doc root, writing the nginx vhost) needs passwordless
# sudo on the VPS and is a one-time step. Pass --no-provision for repeat publishes
# and for CI, where the deploy user should have write access to the doc root and
# nothing more.
#
# Usage:
#   scripts/deploy-apt-repo.sh [--host=USER@HOST] [--repo-dir=DIR] [--domain=DOMAIN]
#                              [--layout=flat|pool] [--no-provision]
#
# --host defaults to debian@apt.drumee.net, the production repo host. Pass it
# explicitly to publish elsewhere (a staging VPS, a mirror).
#
# --layout=flat (default) uploads the flat repository built by publish-apt.sh:
#   Packages/Release/InRelease and the .deb files, all at the document root.
#
# --layout=pool uploads the dists/pool tree built by publish-pool.sh. It is
# deliberately ADDITIVE — the flat repository stays where it is, because boxes
# already installed carry the flat stanza in their sources.list.d and would
# otherwise break on the next `apt update`. Two rules make that safe:
#
#   dists/  is mirrored WITH --delete. Indices are generated, and a stale index
#           left behind advertises packages that are no longer there.
#   pool/   is uploaded WITHOUT --delete. Its contents are immutable artifacts
#           that older indices may still reference.
#
# What is never uploaded: reprepro's conf/ and db/. They live in the same base
# directory as dists/ and pool/, so uploading that directory wholesale would put
# the signing configuration and the internal database on a public web server.
# This script names the two subdirectories explicitly for that reason — do not
# "simplify" it back to uploading the base directory.
#
# Env:
#   APT_LOCAL_DIR   local repo dir to upload (default: apt-repo, or apt-pool
#                   when --layout=pool)
set -euo pipefail

DOMAIN="apt.drumee.net"
REPO_DIR="/var/www/apt.drumee.net"
HOST="debian@apt.drumee.net"
PROVISION=1
LAYOUT="flat"
APT_LOCAL_DIR_SET="${APT_LOCAL_DIR:-}"

for arg in "$@"; do
  case $arg in
    --host=*)       HOST="${arg#*=}" ;;
    --repo-dir=*)   REPO_DIR="${arg#*=}" ;;
    --domain=*)     DOMAIN="${arg#*=}" ;;
    --layout=*)     LAYOUT="${arg#*=}" ;;
    --no-provision) PROVISION=0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

case "$LAYOUT" in
  flat) APT_LOCAL_DIR="${APT_LOCAL_DIR_SET:-apt-repo}" ;;
  pool) APT_LOCAL_DIR="${APT_LOCAL_DIR_SET:-${DRUMEE_POOL_DIR:-apt-pool}}" ;;
  *) echo "error: --layout must be flat or pool" >&2; exit 2 ;;
esac

[ -n "$HOST" ] || { echo "error: --host= was given an empty value" >&2; exit 2; }
echo "==> Target: $HOST:$REPO_DIR (domain $DOMAIN, layout $LAYOUT)"
[ -d "$APT_LOCAL_DIR" ] || { echo "error: local repo dir not found: $APT_LOCAL_DIR" >&2; exit 2; }

if [ "$LAYOUT" = "pool" ]; then
  [ -d "$APT_LOCAL_DIR/dists" ] && [ -d "$APT_LOCAL_DIR/pool" ] \
    || { echo "error: $APT_LOCAL_DIR has no dists/ and pool/ — run scripts/publish-pool.sh first" >&2; exit 2; }
else
  [ -f "$APT_LOCAL_DIR/InRelease" ] \
    || { echo "error: $APT_LOCAL_DIR does not look like a flat APT repo (no InRelease)" >&2; exit 2; }
fi

if [ "$PROVISION" = 1 ]; then
  echo "==> Creating remote directory $REPO_DIR"
  ssh "$HOST" "sudo mkdir -p $REPO_DIR && sudo chown \$(whoami): $REPO_DIR"
fi

if [ "$LAYOUT" = "pool" ]; then
  # pool/ first: an index must never be published before the files it points at,
  # or a client that updates in between resolves a package to a 404.
  echo "==> Uploading pool/ (additive, no --delete)"
  rsync -avz "$APT_LOCAL_DIR/pool/" "$HOST:$REPO_DIR/pool/"
  echo "==> Uploading dists/ (mirrored, --delete)"
  rsync -avz --delete "$APT_LOCAL_DIR/dists/" "$HOST:$REPO_DIR/dists/"
  echo "==> Uploading keyring"
  rsync -avz "$APT_LOCAL_DIR/drumee-archive-keyring.asc" \
             "$APT_LOCAL_DIR/drumee-archive-keyring.gpg" "$HOST:$REPO_DIR/"
else
  # --delete mirrors the document root, so the pool tree must be excluded or a
  # flat publish silently removes the repository the other layout just deployed.
  # The two coexist by design; only this exclusion makes that true in practice.
  echo "==> Uploading repo files (flat; dists/ and pool/ left untouched)"
  rsync -avz --delete --exclude='dists/' --exclude='pool/' \
        "$APT_LOCAL_DIR/" "$HOST:$REPO_DIR/"
fi

if [ "$PROVISION" = 0 ]; then
  echo "==> Deployed to $HOST:$REPO_DIR (provisioning skipped)"
  exit 0
fi

# A 443 server block, but only when a certificate actually exists for this domain.
#
# This used to emit port 80 only, with a commented-out redirect and a note to
# "uncomment after certbot has run" — so nothing ever served TLS for the repository.
# nginx then had no 443 server_name matching apt.drumee.net, every TLS connection
# fell through to the only other 443 block on the host, and clients were answered
# with a certificate for a different domain entirely. `curl https://apt.drumee.net/…`
# failed on hostname mismatch, which broke the documented
# `curl -fsSL https://apt.drumee.net/debian.sh | sudo bash` bootstrap at its very
# first step.
#
# The certificate is acme.sh's, not certbot's: the host issues and renews with
# `acme.sh --cron --home /usr/share/acme`, and its layout is
# <certs>/<domain>_ecc/{fullchain.cer,<domain>.key}. Absent, this stays http-only
# and says so rather than emitting a block that would fail `nginx -t`.
ACME_CERTS="${ACME_CERTS:-/usr/share/acme/certs}"
CERT_DIR="$ACME_CERTS/${DOMAIN}_ecc"
TLS_BLOCK=""
if ssh "$HOST" "sudo test -s '$CERT_DIR/fullchain.cer' && sudo test -s '$CERT_DIR/${DOMAIN}.key'"; then
  echo "==> Certificate found ($CERT_DIR) — provisioning http + https"
  TLS_BLOCK=$(cat <<NGINXTLS

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_DIR}/fullchain.cer;
    ssl_certificate_key ${CERT_DIR}/${DOMAIN}.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;

    root ${REPO_DIR};
    autoindex off;

    location / {
        try_files \$uri =404;
    }

    location ~* \.(deb)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    location ~* (Packages|Packages\.gz|Release|InRelease|Release\.gpg)\$ {
        expires 5m;
        add_header Cache-Control "public, must-revalidate";
    }
}
NGINXTLS
)
else
  echo "==> WARNING: no certificate at $CERT_DIR — provisioning http only." >&2
  echo "    Clients using https:// will fail, including scripts/debian.sh, whose" >&2
  echo "    APT_URL and KEYRING_URL both default to https://${DOMAIN}." >&2
  echo "    Issue one with acme.sh, then re-run this without --no-provision." >&2
fi

echo "==> Installing nginx config"
# No http->https redirect, deliberately: apt verifies the repository signature
# itself, both schemes are in circulation among existing clients, and a redirect
# would make any TLS fault take the working http path down with it.
NGINX_CONF=$(cat <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Redirect to HTTPS (uncomment after certbot has run)
    # return 301 https://\$host\$request_uri;

    root ${REPO_DIR};
    autoindex off;

    # APT clients fetch these paths
    location / {
        # Allow .deb downloads and repo metadata
        try_files \$uri =404;
    }

    # Cache-control: metadata changes on every publish, .debs are immutable
    location ~* \.(deb)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    location ~* (Packages|Packages\.gz|Release|InRelease|Release\.gpg)$ {
        expires 5m;
        add_header Cache-Control "public, must-revalidate";
    }
}
NGINX
)

# Piped in over stdin rather than interpolated into the remote command line. The
# previous `ssh "$HOST" "echo '$NGINX_CONF' | …"` embedded the whole config inside a
# single-quoted string in a double-quoted argument, so one apostrophe anywhere in it
# would have ended the quote and handed the rest to the remote shell.
printf '%s\n%s\n' "$NGINX_CONF" "$TLS_BLOCK" \
  | ssh "$HOST" "sudo tee /etc/nginx/sites-available/${DOMAIN} > /dev/null"
ssh "$HOST" "sudo ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/"
# Keep a backup and roll back rather than leaving nginx holding a config it rejected:
# a failed reload here would take the repository offline for every client.
ssh "$HOST" "sudo nginx -t && sudo systemctl reload nginx"

cat <<MSG

==> Deployed to $HOST:$REPO_DIR

TLS: the port-443 block is written automatically when a certificate exists at
${CERT_DIR}. This host issues and renews with acme.sh, not certbot
(root cron: acme.sh --cron --home /usr/share/acme, DNS-01 via dns_ovh), so if the
warning above said "no certificate", issue one and re-run this command:

  sudo /usr/share/acme/acme.sh --issue -d ${DOMAIN} --home /usr/share/acme \\
       --config-home /usr/share/acme/configs --cert-home ${ACME_CERTS} \\
       --dns dns_ovh

Both http and https are served, with no redirect between them: apt verifies the
repository signature itself, and existing clients are configured with both schemes.

Clients can then install with:

  curl -fsSL https://${DOMAIN}/drumee-archive-keyring.asc \\
    | sudo tee /etc/apt/keyrings/drumee.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/drumee.asc] https://${DOMAIN}/ ./" \\
    | sudo tee /etc/apt/sources.list.d/drumee.list
  sudo apt update && sudo apt install drumee-server-pod drumee-ui-pod drumee-static

MSG
