#!/bin/bash
# Build a signed *flat* APT repository from the built .deb files.
#
# The output is a flat directory (no dists/pool tree) served from the document
# root of apt.drumee.net (see scripts/deploy-apt-repo.sh). Clients point apt at
# the site root:
#
#   deb [signed-by=/etc/apt/keyrings/drumee.asc] https://apt.drumee.net/ ./
#
# Usage:
#   scripts/publish-apt.sh --debs=DIR --out=REPO_DIR --key=EMAIL_OR_KEYID
#
# --key is required: it must be the key clients already trust. See the check below.
#
# Requires: apt-utils (apt-ftparchive), gpg with the signing secret key.
set -euo pipefail

DEBS="" OUT="" KEY=""
for arg in "$@"; do
  case $arg in
    --debs=*)  DEBS="${arg#*=}" ;;
    --out=*)   OUT="${arg#*=}" ;;
    --key=*)   KEY="${arg#*=}" ;;
    --suite=*) ;;  # accepted for back-compat, ignored (flat repo has no suite)
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done
[ -n "$DEBS" ] && [ -d "$DEBS" ] || { echo "error: --debs=DIR (with .deb files) required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "error: --out=REPO_DIR required" >&2; exit 2; }
command -v apt-ftparchive >/dev/null || { echo "error: install apt-utils" >&2; exit 1; }
command -v gpg >/dev/null || { echo "error: gpg required for signing" >&2; exit 1; }
# Checked here, before several hundred MB of packages are copied, and required
# rather than defaulted: without --key, gpg signs with whatever its default key is
# and `--export` with an empty selector exports EVERY public key in the keyring.
# The result is a repository signed by a key no client trusts, published beside a
# keyring full of strangers — every existing installation then fails apt update
# with NO_PUBKEY, on machines nobody touched. A worse outage than whatever the
# publish was fixing, one forgotten flag away.
[ -n "$KEY" ] || {
  echo "error: --key=EMAIL_OR_KEYID is required." >&2
  echo "  It must be the key clients already trust, or their next apt update fails" >&2
  echo "  with NO_PUBKEY. Secret keys available here:" >&2
  gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep -E '^(sec|uid)' | sed 's/^/    /' >&2
  exit 2
}

mkdir -p "$OUT"
echo "==> Collecting packages"
cp -v "$DEBS"/*.deb "$OUT"/

echo "==> Generating flat Packages index"
( cd "$OUT" && apt-ftparchive packages . > Packages )   # -> Filename: ./drumee-*.deb
gzip -kf "$OUT/Packages"

echo "==> Generating Release"
cat > /tmp/apt-release.conf <<EOF
APT::FTPArchive::Release::Origin "Drumee";
APT::FTPArchive::Release::Label "Drumee";
APT::FTPArchive::Release::Architectures "all";
APT::FTPArchive::Release::Components "main";
EOF
( cd "$OUT" && apt-ftparchive -c /tmp/apt-release.conf release . > Release )

echo "==> Signing Release"
KEYARG=(--local-user "$KEY")
( cd "$OUT"
  gpg "${KEYARG[@]}" --batch --yes --clearsign -o InRelease Release
  gpg "${KEYARG[@]}" --batch --yes -abs -o Release.gpg Release
)

echo "==> Exporting public key to $OUT/drumee-archive-keyring.{asc,gpg}"
gpg "${KEYARG[@]}" --armor --export "$KEY" > "$OUT/drumee-archive-keyring.asc"
# The dearmored form too, even though this flat repository does not itself need
# it: the pool/dists layout shares the document root and its deb822 stanza
# points Signed-By at the .gpg. This deploy mirrors the root with --delete, so a
# flat publish that omitted the file would delete the one the pool deploy had
# uploaded — measured, not hypothetical. Same key, so one file serves both.
gpg "${KEYARG[@]}" --export "$KEY" > "$OUT/drumee-archive-keyring.gpg"

cat <<MSG

Done. Deploy the repo with:

  scripts/deploy-apt-repo.sh                      # defaults to debian@apt.drumee.net
  scripts/deploy-apt-repo.sh --host=USER@VPS_HOST  # or somewhere else

Or upload every file in $OUT to your web server's document root. Clients then run:

  curl -fsSL https://apt.drumee.net/drumee-archive-keyring.asc \\
    | sudo tee /etc/apt/keyrings/drumee.asc >/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/drumee.asc] https://apt.drumee.net/ ./" \\
    | sudo tee /etc/apt/sources.list.d/drumee.list
  sudo apt update && sudo apt install drumee
MSG
