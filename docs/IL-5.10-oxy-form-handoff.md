# IL-5.10 — Oxy-form resumption handoff

This is a prerequisite dossier, not execution of OF-01R/OF-02 or a production
deployment. Oxy-form remains read-only at
`7f368473d4f350a88e844b841f97a175b53921b8`, branch
feat/of-01-canonical-audit, with its existing BLOCKED_DISTRIBUTION report intact.
Its static site and disabled forms are not modified or enabled.

## Canonical capability now available

The earlier alpha.2 contract could not compose a supplied Runtime behind host
Nginx without a managed gateway. IL-5 adds the explicit application distribution
and host-loopback contract; Infra PR #2 is now merged into canonical main.
This supplies the missing generic composition capability. It does not itself
select artifacts in Oxy-form, qualify its target or change its recorded status.
A distinct owner-authorized OF-01R resumption must choose and test the consumer.

| Reference | Exact selection or role |
| --- | --- |
| Canonical Infra main integration | `9e4166618ca519e5d9b9e58f5191d37c5fd56462` |
| Existing operational Debian Infra pin | `aa9057f224f4ae5cf80d777e3cb2fad092193fb1`, reachable through canonical main ancestry |
| Debian integrated distribution | `1ff957fac41f158346974d0b290b9396fefb44b6`, feat/container-distribution |
| Qualified Debian executable tree | `ccaa839bf13ab163025e868b21f16516c87d1ff9` |
| Debian delivery/evidence HEAD | `490c4b0a28ffb35da6ff248402139b5f600c793f`, byte-identical merged tree |
| Runtime | Exact `@drumee/server-runtime@0.1.0-alpha.4`, unchanged locked integrity |
| npm Infra candidate | `0.1.0-alpha.3`, locally qualified and still unpublished |

Debian's active archive is
`https://codeload.github.com/drumee/infra-layer/tar.gz/aa9057f224f4ae5cf80d777e3cb2fad092193fb1`
with source SRI
`sha512-faoNlMWBO05FM+ozsuGu9tqFgq/IYc9WJwb4KCyZcZiTlEIrgJ9QLqLxslTADdipaItg02r2f6qFG07HDxhVqA==`.
The canonical merge's archive has different source metadata/SRI, while all 225
source files and the 40 npm members match. The npm candidate separately has SRI
`sha512-ZZIxqtHsFA0tCwAR6vcGa3iOttFYTkHCS4rKN4UtPApLPDkq41FJ0xJWKfWLEWVUlvM3JZldb1aGrhyKMiM9Pw==`.
Neither is a substitute for the existing Debian archive integrity. Do not install
an assumed published alpha.3 or rewrite this lock implicitly.

[Infra integration report](https://github.com/drumee/infra-layer/blob/da42c0f3e1ce46419ec4895815a540f592e6b4d8/docs/IL-5.10-B-infra-integration.md)
and [fresh candidate qualification](https://github.com/drumee/infra-layer/blob/da42c0f3e1ce46419ec4895815a540f592e6b4d8/docs/IL-5.10-D-alpha3-release-candidate.md)
record canonical source and artifact equivalence. The package has zero production
dependencies; Runtime and consumer/plugin dependencies remain explicit.

## Consumer selection and image assembly

Use the existing Debian minimal-application operator/profile, not an installer
or planner fork in Oxy-form. Freeze the Debian commit and verify its locks/source
receipt. Package the real Oxy-form native plugin and all its declared dependencies
as a verified immutable artifact; select its actual revision/SRI in build input.
Set the real owner UID/GID, project, owned persistent/backup roots, image, plugin
inventory, resources and secret references explicitly. Keep acceptance=false in
an ordinary deployment. No fixture plugin, disposable credential or test account
belongs in it. Images use explicit immutable identities and provenance labels.

Existing qualification image IDs are evidence only:
application sha256:d44327e37d37c612257822684a870d05d7f90fdae649b2dcbfb8e9f0566e7955
and native tools sha256:075a3c53d14f9a71c827f285564518dde41e29faa0cc9e58f4cc126cd3dda4cd.
The application contains the disposable qualification plugin, not Oxy-form.
Build and qualify the actual consumer image; no image has been published here.

The profile adds no implicit SQL/Redis/DNS/Hub/MFS/Finder or containerized HTTP
gateway. A plugin's real dependencies must be justified and explicitly declared.
Preserve native descriptor/dispatcher/authorizer behavior; do not add another
RPC router, session/password system or transport stack. Oxy-form retains form
business rules, validation and message-template ownership.

## Target topology and acceptance gate

Keep existing host Nginx, host HTTPS/certificates, current static site and disabled
forms. Future reviewed integration should proxy the complete `/-/` path to the
explicit private Runtime upstream; RPC stays `/-/svc/module.method`. Keep
proxy_pass without a URI rewrite/suffix. Host 127.0.0.1 publication, the container
listener and the reverse-proxy upstream are separate declared values. Select
available ports after host inspection; test fixture ports/LAN addresses are not
production allocations. Do not modify host resolver, firewall or trust settings
as a shortcut. No oxymot.fr access or modification is part of this mission.

On an authorized isolated target, prove actual container image/port/mount evidence,
loopback host sockets, independent-client LAN refusal with an accessible positive
witness, native health/public RPC/protected denial, real host Nginx and CA/SAN
verification. Repeat restart, failed startup, SIGKILL/explicit recovery, rollback,
foreign-resource refusal and no-SMTP isolated restore for the actual plugin.
Preserve its existing site/forms until its full consumer qualification succeeds.
The generic Infra/Debian test success is not acceptance of the Oxy-form service.

Owner-bound commands are the existing interface:

```sh
bin/drumee-ctl --profile minimal-application validate --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application plan --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application proxy-config --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application install --execute --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application status --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application doctor --config OWNED_CONFIG
bin/drumee-ctl --profile minimal-application restart --execute --config OWNED_CONFIG
```

Stop/start, backup/restore and rollback retain the same explicit profile/config
and execution authorization. Recovery is an investigated owner operation; never
steal an unknown lock or recreate secret generations. See the
[operator guide](IL-5-distribution.md) for backup destination, separate restore
config and verified rollback revision inputs.

## SMTP/DKIM prerequisites still unresolved

Compose canonical Infra Postfix/DKIM only; keep its private application/control
networks and no host SMTP/DKIM publication. Project only the authorized submission
credential and public CA trust to the application; do not mount the root secret
store or existing HTTPS private keys. Restrict trusted CIDRs separately from SASL.
Use mandatory STARTTLS with CA/name validation, including upstream verified TLS;
do not introduce a direct-MX fallback or bypass trust for qualification.

The owning Oxy-form report selects its existing Server Essentials Messenger
integration, not a replacement SMTP implementation. Its recorded Reply-To
contract limitation is not fixed by IL-5.10 and must be resolved by the owner,
not bypassed with a homemade transport. Capture-mode tests are not a mailbox or
Internet-delivery qualification.

Before enabling forms, the consumer owner must supply/approve:

- The actual upstream SMTP endpoint, port, certificate name and verified CA/TLS
  policy; no assumed provider account is selected here.
- Distinct private submission and upstream credentials with allowed consumers,
  an authorized sender and required application-level reply/routing contract.
- Controlled qualification inboxes and explicit permission for real delivery.
- SPF/DKIM/DMARC publication/receiver observations under authorized DNS control.
- Actual form → native RPC → Messenger → relay → upstream → inbox evidence,
  negative/abuse/auth tests, queue retry, recipient rejection and bounce handling.
- Target resource ownership, secret preservation, optional/required mail readiness
  and recovery/runbook decisions.

SMTP spool restoration stays explicitly unsupported by this application profile:
SMTP_RECOVERY_UNQUALIFIED. Queue preservation through an application failure is
not spool recovery, exactly-once delivery or receipt by the final inbox.
Do not enable production forms on the strength of the generic capture evidence.

## Decisions outside this handoff

No npm/image/tag publication, Oxy-form install/code/branch/report modification,
production secret change, OF-02 or Oxymotion D0 is performed. The main convergence
of Debian remains a separate migration decision with its own broad test/debt
scope. Infra's broader legacy Sonar inventory and HTTP 403 global Security/
Dependabot visibility remain owner-review inputs; they are not blanket-waived
by the four accepted logical findings. This handoff makes artifact selection and
remaining work concrete without declaring the consumer unblocked or accepted.
