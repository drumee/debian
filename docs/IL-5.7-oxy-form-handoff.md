# IL-5.7 — conditions for Oxy-form OF-01R resumption

This is a handoff proposal, not an Oxy-form code change, OF-02 execution or
production authorization. The unchanged consumer report at Oxy-form
`7f368473d4f350a88e844b841f97a175b53921b8` still says BLOCKED_DISTRIBUTION.
It audited Infra alpha.2; no compatible replacement has been selected there.
Do not declare that status resolved by writing this document.

## Available compatible inputs versus pending selection

- Canonical IL-5 source already exists at Infra
  `c6ef6e9b8d33921ffa39c289490067adfc63a8b0`, publicly downloadable by immutable
  commit archive, SRI
  `sha512-/XFgDPrCJkuk9sEbLf5GGJ1Z55mueK85t77swiB4i/0s6OvdlrGqd9MUE9e8AnyMOi0nBUOl+W2h8FlqDZdX2Q==`.
  Debian explicitly selects it. Published alpha.2 does not implement this contract.
- Infra PR #2 HEAD `de4b34e99370bf3b9f0d17399db4b2ea3d107677` has identical
  shipped payload; its local alpha.3 tarball and installed-consumer checks pass.
  Alpha.3 is not currently published. Owner review includes the additional
  SonarCloud reserve described in the final validation report.
- Debian's qualified application assembly source is
  `cfb993dd3979122e4ff7915b8627ff669ef90a96`; executable profile/selector/config
  code is identical at the IL-5.6 reviewed HEAD
  `86f68a735096a070aa9aa77bc0d79cf0cd1f47af`. Later IL-5.7 commits are documentation
  only. Consume an explicitly reviewed immutable Debian revision, not a moving
  branch name as deployment provenance.
- Runtime remains published alpha.4, source f961f621… and lockfile SRI. The
  reference host uses its native dispatcher/authorizer; protected operations
  remain denied without their owning adapters.

Thus an immutable development source is available, but selection and validation
by Oxy-form remain pending. The Oxy-form owner must explicitly choose either the
reviewed source/SRI path or a subsequently authorized verified npm alpha.3
release. Update the consumer's own evidence/lock/profile through an authorized
OF-01R task. No automatic version migration or branch switch occurs here.

## Required application/proxy preparation

1. Select `minimal-application` explicitly in existing drumee-ctl dispatch.
   Supply owned deployment/project identity, persistent and backup roots,
   UID/GID, immutable image, plugin inventory, required resources/secrets and
   native healthcheck. Empty capabilities install no SQL/Redis/DNS/Hub/MFS/Finder
   or container gateway. SMTP/TLS resources appear only when explicitly selected.
2. Build/archive the actual Oxy-form native plugin in its owning repository.
   Its archive needs native server/acl descriptors, bundled dependencies,
   immutable revision and verified SRI. Use the distribution's existing archive
   validation and image assembly; no second installer/dispatcher or qualification
   test plugin is an application substitute. The public reference host does not
   install a second identity/session system; validate Oxy-form's actual native
   permission descriptors and public/denied service behavior.
3. Keep the host's existing Nginx and existing HTTPS certificates under their
   current owner. Prepare the profile's proxy-config fragment for review; it does
   not install/reload the host proxy. The only Drumee HTTP prefix remains `/-/`,
   with native RPC `/-/svc/`. proxy_pass must preserve the complete request URI.
4. Choose an explicit high host port, matching internal listener and strict
   127.0.0.1 binding. Inspect actual Docker ports and host sockets, then use a
   separate LAN client with a positive control route to prove the runtime is
   unreachable through non-loopback interfaces. Repeat on the actual target
   engine; the previous Docker 29.2 qualification is not universal proof.
5. Verify external HTTPS CA/SAN and native public RPC plus protected RPC denial
   through the real host proxy. Production proxy changes need separate deployment
   authorization; none is performed on oxymot.fr by this handoff.

## Required SMTP integration inputs and evidence

Use the existing Infra Layer Postfix/DKIM capability, not an Oxy-form-specific
SMTP stack. The Oxy-form dossier selects its native Messenger path to that
relay; its consumer compatibility still requires actual OF-01R validation.

| Pending input | Required controlled evidence |
| --- | --- |
| Upstream relay endpoint and port | Explicit canonical relay endpoint; STARTTLS required and actual upstream CA/hostname verification. No inferred direct-MX delivery or unverified TLS fallback. |
| Submission identity/secret | Separate dedicated identity and protected canonical secret reference/projected consumer resource; verify correct and wrong authentication. Do not put passwords in config, CLI arguments, logs or image layers. |
| Upstream identity/secret | Distinct authorized relay credential reference and upstream account; verify authenticated upstream handoff without exposing its secret. |
| Sender authorization | Approved envelope/header sender and domain; account/provider permission and DKIM signing identity verified. |
| Qualification mailboxes | Controlled recipients with permission to inspect reception; correlate message IDs, body/headers and actual delivery, not just a successful SMTP accept. |
| SPF/DKIM/DMARC DNS | Authorized DNS owner, exact selector/public key and alignment policy; validate real receiver authentication results. No DNS changes are performed here. |
| Delivery/failure behavior | Actual inbox reception, rejection, timeout, deferred queue/retry and controlled bounce/DSN observations. Capture-only tests do not establish Internet behavior. |
| Network isolation | No unintended SMTP/DKIM host publication, DKIM-only private control network, bounded trusted client CIDRs and explicit SASL policy. A trusted CIDR and SASL are distinct authorization paths. |
| Optional/required readiness | Declare whether the app requires mail. Optional failure retains HTTP readiness with diagnostics; required SMTP failure makes deployment readiness false. |

The application should receive only its authorized submission credential and
public SMTP CA when needed. Never mount the store root, issuer private CA key,
DKIM private key or host HTTPS key into the application. Use the owning secret
provider's persistence/rotation contracts; do not regenerate/reset credentials
as an installation retry workaround.

## Recovery limit and owner decision

`SMTP_RECOVERY_UNQUALIFIED` still applies to application backup **and restore
when mail is composed**, including optional mail. No-SMTP cold backup/isolated
restore is qualified separately. Persistent queue ownership across restart and
backend failure is not transactional spool backup/restore qualification.

The Oxy-form owner must resolve or explicitly assess this operational limitation
before claiming recoverability of its SMTP-bearing deployment. A complete spool
recovery contract needs its own canonical work and actual queue/duplicate/delivery
consistency tests. Do not copy a spool manually, omit it silently or disable the
canonical rejection to manufacture a passing backup.

## Completion boundary

After reference selection, OF-01R must record actual plugin/runtime/proxy/SMTP
compatibility, isolated lifecycle/failure/recovery behavior and recipient/DNS
results. Only its own evidence can change its blocked status. OF-02 and any
production deployment remain separate authorized work.

Transferable IL-5 proof is limited to the explicit private application ingress,
native RPC allow/deny, owned lifecycle, immutable acquisition and qualified
SMTP composition/trust/isolation. It does not qualify Oxymotion D0, Hub/MFS/Finder,
crawling, agents, application business rules or Internet mail delivery. D0 is
neither started nor declared validated.

## IL-5.9-B — updated candidate inputs (2026-10-18)

The original references above describe the IL-5.7 observation. The newly qualified
Debian **minimal-application** consumer now pins Infra Layer
`aa9057f224f4ae5cf80d777e3cb2fad092193fb1` at
`https://codeload.github.com/drumee/infra-layer/tar.gz/aa9057f224f4ae5cf80d777e3cb2fad092193fb1`,
source SRI
`sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==`.
Debian executable/image source is
`ccaa839bf13ab163025e868b21f16516c87d1ff9` on the existing PR #7 feature branch;
subsequent evidence/docs commits preserve its executable tree. The distribution
profile remains version `0.0.0-il5`; Runtime is exactly `0.1.0-alpha.4`.
[Qualification](IL-5.9-B-qualification.md) and its image receipts identify the
actual local application/tools images and verified disposable plugin. Those
images are not Oxy-form images and have not been published. The npm alpha.3
candidate remains a future release choice, not the selected registry dependency.

Future OF-01R must explicitly choose this compatible distribution/revision,
package and verify its own plugin, select a free loopback host port and connect
its existing host Nginx/certificates to it. Preserve `/-/` and `/-/svc/` without
rewrites. Use the existing commands documented in
[the operator guide](IL-5-distribution.md): `bin/drumee-ctl --profile
minimal-application validate|plan|proxy-config|install|status|doctor|stop|start|
restart|backup|restore|rollback --config OWNED_CONFIG`, with `--execute` for
mutations and `--recover` only after investigated interrupted activation.
Install/build instructions and immutable source receipts must travel together.
No Hub/MFS/Finder/SQL/Redis/DNS or containerized HTTP gateway is implicit.

The real qualification demonstrates independent LAN denial plus a positive LAN
witness, host Nginx/verified HTTPS, native public/denied RPC, restart, SIGKILL and
explicit recovery, rollback and isolated no-SMTP restoration. Optional SMTP/DKIM
is composed canonically with STARTTLS/SASL, private DKIM networking and no host
mail publication. Application failure preserves an isolated queued message and
secret fingerprints. This is not upstream Internet mail qualification.

Still required separately: verified upstream TLS and authorized sender, distinct
submission/upstream secrets, controlled inboxes, SPF/DKIM/DMARC observations,
actual reception and bounces. SMTP spool recovery remains explicitly unsupported
(SMTP_RECOVERY_UNQUALIFIED). No production secret value belongs in this handoff.
Infra #2 then Debian #7 integration decisions remain separate. Oxy-form is not
modified or declared unblocked/accepted; OF-02 and Oxymotion D0 are not started.
