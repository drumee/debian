# IL-5.3 — minimal-application operator distribution

Implemented profile: `profiles/minimal-application`, selected explicitly with
`bin/drumee-ctl --profile minimal-application`. Team remains the default and
minimal-kernel source/dependency pins remain unchanged. Clean-checkout acceptance and limits are recorded in
[qualification](IL-5-qualification.md); no production installation or publication
is performed by this work.

## Inputs and canonical ownership

`config/drumee.minimal-application.example.json` is a lossless JSON configuration
(also accepted by the shared configuration reader). Copy it to an owned path;
do not overwrite the Team source configuration. Set owner UID/GID, logical
instance/project identity, owned persistent and backup roots, retention, image
and provenance intentionally. Zero image/source IDs are placeholders, not
usable artifacts. Existing `config/drumee.yaml` remains the default config path.

`infrastructure` contains the exact public Infra Layer spec, requirements and
Docker adapter input; `manifest` contains the public Distribution descriptor.
Debian validates the outer owner/storage policy, then delegates nested semantics
to pinned public `validateSpec`, `planInfrastructure` and `composeDeployment`.
No private Infra module, second planner or forked lifecycle is imported.
The root JSON Schema selects this profile structurally; Infra Layer is the
authority for the complete nested capability contracts.

With the example's explicit empty capabilities/services/secrets/jobs, only the
application container exists. No gateway, Hub/MFS/Finder, SQL, Redis or DNS is
installed. The private Docker network uses the canonical internal role name
`kernel`; its configured resource name is application-specific and does not
install kernel capabilities. `operator-state` is an explicit persistent resource
for protected revision-bound configuration snapshots and coordinated backup.
Application resources and secret references are separately explicit. The existing
canonical supplied-service policy bounds memory to 512 MiB and PIDs to 128, with
a read-only root, dropped capabilities and private temporary storage. Persistent
resource UID/GID and backup mappings are operator inputs; this profile adds no
parallel resource allocator.

## Dependency and image acquisition

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-application
node profiles/minimal-application/scripts/build.js /owned/artifacts/build-input.json
```

Production npm dependency is only published Runtime alpha.4; its SRI is verified
against the lock. Infra Layer is a development/operator dependency pinned to
immutable source `aa9057f224f4ae5cf80d777e3cb2fad092193fb1`, with archive SRI in
the lock. Published alpha.2 does not implement this new application contract.
No sibling source tree or local file dependency is required by npm ci.

Build input is explicit:

```json
{
  "tools": false,
  "plugins": [
    {
      "id": "example",
      "archive": "/owned/artifacts/example-plugin.tgz",
      "integrity": "sha512-REPLACE_WITH_VERIFIED_NPM_ARCHIVE_SRI",
      "revision": "REPLACE_WITH_IMMUTABLE_40_OR_64_DIGIT_ARTIFACT_REVISION"
    }
  ]
}
```

An explicit empty plugin list builds a health-only host. Plugins are standard
packed npm archives with `server/acl/*.json` descriptors and native worker code.
All plugin dependencies must be bundled in the archive (`bundledDependencies`);
the builder neither downloads unrecorded dependencies nor runs plugin scripts.
SRI, members, bounds, native ACL presence and bundle completeness are checked.
Traversal, links/devices, duplicate paths, credential/provenance injection and
unbounded archives fail before Docker receives the context. Generated plugin
inventory binds ID, root and immutable revision to the resulting image.

The base image uses pinned Node 22 Bookworm and a locked `npm ci --omit=dev`.
Profile source must be committed before assembly. The build receipt at
`profiles/minimal-application/.cache/images.json` records source, runtime and
Infra integrity, immutable image IDs and plugin identities. Copy its image and
plugins into the deployment manifest and its source revision into provenance.
No image is pushed. `tools: true` explicitly builds the unchanged canonical
Infra Layer native-tools recipe for selected SMTP/DKIM, not a second mail stack.

The reference host composes `DescriptorRegistry`, `ServiceDispatcher`,
`createAuthorizer` and `createServiceServer` from published Runtime alpha.4.
It validates image plugin inventory, registers native plugin ACL directories
and supplies `health.ready`. It retains Runtime's anonymous default context and
fails closed for protected scopes without their canonical adapters. This is a
public-RPC reference composition, not a second password/session system. Use
native numeric permissions; symbolic permission conversion requires its owning
adapter rather than an invented converter. No application identity is created.

## Plan and install

```sh
bin/drumee-ctl --profile minimal-application validate --config /owned/application.json
bin/drumee-ctl --profile minimal-application plan --config /owned/application.json
bin/drumee-ctl --profile minimal-application install --execute --config /owned/application.json
```

The operator prepares through Infra Layer, snapshots the non-secret
configuration inside the owned operator resource, then explicitly activates and
checks native application readiness. Unknown roots/resources, mutable/missing
images, wrong identity and ownership are refused. Build artifacts and private
imports must exist where explicitly declared. Secrets are only references and
protected imports; no password is accepted on the command line.

## External Nginx

The manifest's `external_gateway` requires HTTP host-loopback publication at
exactly 127.0.0.1, an explicit high host port, its matching internal listener,
`/-/` and `/-/svc/`, and external HTTPS ownership. IPv6/public/wildcard aliases
are refused. The native host listens in its private container network; Docker
publishes only the declared loopback upstream.

```sh
bin/drumee-ctl --profile minimal-application proxy-config --config /owned/application.json
```

This returns a JSON `content` fragment for operator review and inclusion inside
an already managed HTTPS server. It applies nothing, reads no HTTPS private key,
and does not configure/reload Nginx or modify firewall/resolver/trust settings.
The `proxy_pass` has no URI suffix, preserving the complete `/-/` request path.
External certificates and their renewal remain the external proxy owner's work.

## Operations and recovery

```sh
bin/drumee-ctl --profile minimal-application status --config /owned/application.json
bin/drumee-ctl --profile minimal-application doctor --config /owned/application.json
bin/drumee-ctl --profile minimal-application stop --execute --config /owned/application.json
bin/drumee-ctl --profile minimal-application start --execute --config /owned/application.json
bin/drumee-ctl --profile minimal-application restart --execute --config /owned/application.json
bin/drumee-ctl --profile minimal-application backup --execute --config /owned/application.json --backup /owned/backups/prechange
bin/drumee-ctl --profile minimal-application restore --execute --config /owned/restored.json --backup /owned/backups/prechange
bin/drumee-ctl --profile minimal-application rollback --execute --config /owned/application.json --revision VERIFIED_PREPARED_REVISION
```

All state/diagnostics are JSON. Mutations require execute authorization and exact
host UID/GID. Stop/restart/backup require the active configuration; no adoption
of unknown deployments. Initial creation is distinct from start. `--recover`
acknowledges a known interrupted activation; exclusive crashed locks require
explicit owner investigation and are never automatically stolen.

No-SMTP backup delegates canonical writer quiescence, cold resources, configuration
snapshots and secrets. Retention is recorded; pruning is a separate explicit
owner operation. Restore chooses a different project, new owned root and free
loopback high port while preserving logical instance identity and exact resource
mapping. Infra restores without activation; this explicitly executed operator
then activates and verifies RPC health. It does not claim full business recovery
or kernel/Hub/MFS validation. Application acceptance must repeat its own RPC/ACL
checks. Rollback preserves compatible resources, schema and secret generations;
image/engine/schema downgrade is unsupported and fails closed.

## Optional SMTP/DKIM

Declare canonical `spec.tls`, `spec.mail`, references, requirements, adapter native
image, queue resource and imports explicitly. There is no implicit mail install.
Application STARTTLS uses the CA-only `tls-ca-bundle` projection and an explicitly
authorized submission credential; the root store/private CA/HTTPS keys are not
mounted into the application. DKIM has only its canonical internal control
network, while mail shares the application network and has no host publication.
If the application requires `mail`, SMTP must be a required capability. Otherwise
mail is independently optional and failures are diagnosed without claiming its
protocol is healthy. Trusted CIDRs and SASL are distinct relay authorization
paths; declaring SASL does not negate trusted CIDR grants.

SMTP spool backup/restore is deliberately unsupported with this application
profile (`SMTP_RECOVERY_UNQUALIFIED`). Runtime restart and queue persistence are
not spool recovery. Infra Layer retains its declared upstream TLS policy and
adds no direct-MX transport. Real Internet delivery, recipient control, SPF/DKIM/
DMARC alignment, bounces and consumer integration remain future acceptance work.
Oxy-form remains read-only and Oxymotion D0 is not started or qualified by IL-5.

## IL-5.9-B provenance update

The original IL-5 consumer used `c6ef6e9b8d33921ffa39c289490067adfc63a8b0`.
The current source selection and separate source/npm integrity receipts are in
[IL-5.9-B source selection](IL-5.9-B-source-selection.md);
[the integrated qualification](IL-5.9-B-qualification.md) records the new images
and actual acceptance. Earlier reports retain their original references.
