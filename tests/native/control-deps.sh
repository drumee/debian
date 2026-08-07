#!/bin/bash
# Validate the NATIVE channel's packaging metadata (deterministic, no Docker):
#
#   1. inter-package Depends encode the required config order
#      (apt/dpkg configure a package only after its Depends — so correct edges
#       + an acyclic graph == correct install/configuration order):
#         infra → schemas → static → server-pod → ui-pod
#   2. the `drumee` metapackage pulls all five components
#   3. every debconf key in the rendered preseed has a matching package Template
#
# This tests the packaging we control. Full install validation (postinst running
# as root, services starting) still requires a disposable Debian VM — see
# docs/native-channel.md.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$root"
pass=0; fail=0
ok(){ printf '  \033[1;32mPASS\033[0m %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=$((fail+1)); }

# drumee-* tokens in a component's Depends (own name excluded)
deps(){ awk '/^Depends:/{f=1} f{print} /^Description:/{f=0}' "$1/debian/control" \
  | tr '\n' ' ' | grep -oE 'drumee-[a-z-]+' | grep -vx "$2" | sort -u | paste -sd' ' - ; }
has(){ echo " $1 " | grep -q " $2 "; }   # has "<set>" <member>

printf '\033[1;36m── native: inter-package Depends are the MINIMUM\033[0m\n'
# This used to assert the opposite — that static Depends infra, server Depends schemas
# and static, and ui Depends server-pod. Those were single-box assumptions: on a native
# install the metapackage pulls everything anyway, so they cost nothing and nobody
# questioned them.
#
# They cost the container channel everything. drumee-role-web asks for ui-pod + static +
# nginx and resolved to 508 packages — every Drumee component, mariadb-server,
# redis-server, LibreOffice, ffmpeg — because static dragged in infra and ui-pod dragged
# in server-pod. Worse, the role image could not BUILD: drumee-infra's postinst rightly
# refuses to configure without an answered domain, so the whole transaction failed and
# five packages were left unconfigured. Measured, not predicted.
#
# So the rule is inverted: a component may Depend on another only when it genuinely needs
# it CONFIGURED. Exactly one does.
S=$(deps schemas drumee-schemas); T=$(deps static drumee-static)
V=$(deps server drumee-server-pod); U=$(deps ui drumee-ui-pod); I=$(deps infra drumee-infra)
# schemas' postinst restores MariaDB from the seed using the credentials infra renders,
# so infra must be configured first. This one is real.
has "$S" drumee-infra   && ok "schemas Depends infra (needs the rendered credentials)" \
                        || no "schemas must Depend infra (got: $S)"
[ -z "$T" ]             && ok "static has no component Depends" \
                        || no "static must not Depend on any component (got: $T)"
[ -z "$U" ]             && ok "ui-pod has no component Depends" \
                        || no "ui-pod must not Depend on any component (got: $U)"
[ -z "$I" ]             && ok "infra has no component Depends (it is the base)" \
                        || no "infra should be the base (got: $I)"
has "$V" drumee-schemas && no "server-pod must NOT Depend on schemas — it drags mariadb-server into the app role" \
                        || ok "server-pod does not Depend on schemas"
has "$V" drumee-static  && no "server-pod must NOT Depend on static — 181 MB of assets belong to the web role" \
                        || ok "server-pod does not Depend on static"

printf '\033[1;36m── native: nothing installable in an image may Depend on infra\033[0m\n'
# drumee-infra's postinst refuses to configure without an answered domain question, which
# is correct for a host and fatal for a `docker build`. Any component that Depends on it
# is therefore uninstallable in an image, and so is every role that reaches it.
for c in static ui server; do
  d=$(deps $c "drumee-$( [ $c = server ] && echo server-pod || echo ${c/ui/ui-pod} )")
  has "$d" drumee-infra && no "$c Depends infra — it cannot be installed in an image" \
                        || ok "$c does not reach infra"
done

printf '\033[1;36m── native: what replaced those Depends\033[0m\n'
# Two mechanisms now carry what the dependencies used to. Both must exist, or dropping
# them silently regresses a from-scratch install.
#
# 1. Completeness: the metapackage pins every component exactly (checked below too).
# 2. Start order: server-pod's self-interest dpkg trigger, which dpkg fires once every
#    other package in the transaction is configured — regardless of the graph. This is
#    what made `ui-pod Depends server-pod` redundant; the trigger's own comment names
#    that dependency as one of the two bugs it works around.
[ -f server/debian/drumee-server-pod.triggers ] \
  && grep -q 'interest-noawait drumee-server-pod-start' server/debian/drumee-server-pod.triggers \
  && ok "server-pod declares the start trigger" \
  || no "server-pod must declare interest-noawait drumee-server-pod-start"
grep -q 'dpkg-trigger --no-await drumee-server-pod-start' server/debian/postinst \
  && ok "server-pod postinst activates the trigger" \
  || no "server-pod postinst must activate its start trigger"
# 3. And dropping schemas/static is only safe because this postinst needs neither
#    configured: both uses are guarded.
grep -q 'if \[ -f /etc/drumee/drumee.sh \]' server/debian/postinst \
  && ok "server-pod postinst guards its use of the rendered environment" \
  || no "server-pod postinst must tolerate /etc/drumee being absent"
grep -qE 'if \[ -x \$?\{?patch' server/debian/postinst \
  && ok "server-pod postinst guards the patch step" \
  || no "server-pod postinst must tolerate no pending patches"
# 4. No maintainer script may reach the network for a Node global — that is what
#    drumee-node-runtime is for, and an unpinned `npm install -g` in a postinst cannot
#    work on a box without egress.
# Comments are stripped first — the comment where that call used to be explains why it
# is forbidden, and scanning prose made this check fail on the very change that fixed it.
# check-packaging.sh's scan() strips comments for the same reason.
grep -vE '^[[:space:]]*#' server/debian/postinst | grep -q 'npm install -g' \
  && no "server-pod postinst still runs npm install -g" \
  || ok "server-pod postinst does not npm install -g"

printf '\033[1;36m── native: metapackage pulls all five\033[0m\n'
M=$(awk '/^Depends:/{f=1} f{print} /^Description:/{f=0}' meta/debian/control | grep -oE 'drumee-[a-z-]+' | sort -u | paste -sd' ' -)
for c in drumee-infra drumee-schemas drumee-static drumee-server-pod drumee-ui-pod; do
  has "$M" "$c" && ok "meta Depends $c" || no "meta missing $c"
done

printf '\033[1;36m── native: drumee-infra registers debconf + bridges to env\033[0m\n'
[ -f infra/debian/templates ] && grep -q '^Template: drumee-infra/domain' infra/debian/templates \
  && ok "infra ships debconf templates" || no "infra/debian/templates missing drumee-infra/domain"
[ -x infra/debian/config ]                 && ok "infra ships an executable config script" || no "infra/debian/config missing or not executable"
grep -q 'db_get drumee-infra/domain' infra/debian/postinst \
  && ok "postinst reads debconf drumee-infra/domain" || no "postinst does not read the debconf domain"
grep -q 'export DRUMEE_DOMAIN_NAME=' infra/debian/postinst \
  && ok "postinst exports DRUMEE_DOMAIN_NAME for infra.js" || no "postinst does not export DRUMEE_DOMAIN_NAME"
grep -q 'setup-infra/bin/install' infra/debian/postinst \
  && ok "postinst runs bin/install after bridging" || no "postinst does not run bin/install"
# Every debconf-sourced var the bootstrap wizard exports is also exported by the
# postinst bridge. IP vars are excluded: the wizard scans/prompts for them, but
# the metapackage path lets infra.js auto-detect addresses (getAddresses).
miss=0
for v in $(grep -oE 'export [A-Z_0-9]+' builder/src/setup/menu/install.sh | awk '{print $2}' | sort -u); do
  case "$v" in PUBLIC_IP*|PRIVATE_IP*) continue;; esac
  grep -q "export $v" infra/debian/postinst || { no "postinst missing export $v (wizard sets it)"; miss=1; }
done
[ "$miss" = 0 ] && ok "postinst exports every debconf-sourced var the wizard does"

printf '\033[1;36m── native: schemas postinst guards the factory pool\033[0m\n'
grep -q "area='pool'" schemas/debian/postinst \
  && ok "schemas postinst checks the factory pool" || no "schemas postinst missing pool check"
grep -q 'EMPTY_FACTORY' schemas/debian/postinst \
  && ok "schemas postinst reports the EMPTY_FACTORY remedy" || no "schemas postinst missing EMPTY_FACTORY guidance"

printf '\033[1;36m── native: debconf preseed keys all have templates\033[0m\n'
tmpl=$(grep -rhoE '^Template: [^[:space:]]+' */debian/templates 2>/dev/null | awk '{print $2}' | sort -u)
cfg=$(mktemp); cat > "$cfg" <<YAML
instance:
  description: T
  domain: example.com
  admin_email: a@b.co
tls:
  mode: acme
  acme_email: a@b.co
YAML
preseed=$(node config/render.mjs debconf --config "$cfg" 2>/dev/null | awk 'NF>=3 && $1 ~ /^drumee/{print $2}' | sort -u)
rm -f "$cfg"
miss=0
for k in $preseed; do echo "$tmpl" | grep -qx "$k" || { no "preseed key has no Template: $k"; miss=1; }; done
[ "$miss" = 0 ] && [ -n "$preseed" ] && ok "all $(echo "$preseed" | wc -w) preseed keys have matching Templates"

printf '\n\033[1m== native control-deps: %d passed, %d failed ==\033[0m\n' "$pass" "$fail"
[ "$fail" = 0 ]
