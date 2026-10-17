# IL-5 canonical application contract

Infra Layer owns the public contract, validation, composition, projections and
lifecycle. The complete contract is maintained in
[Infra Layer IL-5 contract](https://github.com/drumee/infra-layer/blob/feat/il5-external-gateway/docs/IL-5-contract.md)
and its public declarations. Debian consumes immutable source
`c6ef6e9b8d33921ffa39c289490067adfc63a8b0`; published alpha.2 lacks this extension.

`Distribution.profile: application` requires an immutable non-root supplied
application, explicit plugin inventory, resources/secrets/dependencies/health,
and `external_gateway`. The gateway contract distinguishes the single internal
listener from Docker TCP publication: exactly `127.0.0.1`, an explicit high host
port and matching container port, HTTP upstream, `/-/`, `/-/svc/` and externally
owned TLS. Wildcard/LAN/IPv6/alias bindings and managed-gateway conflicts fail
before activation. No capability is implicitly installed.

Debian adds only owner-bound operator policy: explicit profile, private root and
separate backup location/retention, identity agreement, operator-state resource,
immutable host/plugin code, protected revision snapshots and execution consent.
Nested Infra contracts are delegated to public validators and composition.
The reference image composes published Runtime alpha.4 with native descriptors
and authorization. Its default context is anonymous; protected services fail
closed without their owning adapters. It introduces no identity/session/ACL
implementation. The default example has no qualification plugin or test identity.

SMTP is explicitly selected through canonical Infra TLS/mail/secret/resource
inputs. Its application mounts contain only the authorized submission credential
and public CA, never the issuer key/store root. Optional SMTP failure and required
SMTP failure retain their distinct readiness semantics. No SMTP/DKIM host port
is needed. SMTP spool backup/restore returns `SMTP_RECOVERY_UNQUALIFIED`.
No-SMTP cold backup and isolated restore are separately tested.

See [operator distribution](IL-5-distribution.md),
[qualification](IL-5-qualification.md) and [handoff](IL-5-release-handoff.md).
