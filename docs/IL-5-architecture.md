# IL-5.0 — minimal application distribution architecture

Status: additive architecture implemented. Measured results and remaining gates
are recorded in [qualification](IL-5-qualification.md).

## Inspected baseline and ownership

- Infra Layer main / published alpha.2: `bef9a379754bcf9a46fed8bcb6f88fe1f775c739`.
- Debian `feat/container-distribution`: `3fb32d86ce336c886235c23b9632a140a2dc3045`.
- Server Runtime alpha.4: `f961f6214432c2e6dbbcde2b926544c076935950` (read only).
- Oxy-form `feat/of-01-canonical-audit`: `7f368473d4f350a88e844b841f97a175b53921b8`
  (read only), including OF-01R distribution, reconciliation, SMTP and D0 dossiers.

Supporting trees are clean. Debian's existing server/UI changelog edits and
untracked AGENTS.md are excluded. No Infra Layer/Oxy-form AGENTS file exists;
Debian and Runtime instructions were read. IL-2/IL-3/IL-4 reports retain their
historical scope; SMTP spool recovery is not qualified by those reports.

## Confirmed missing capability

`lifecycle/composition.js` accepts only infrastructure/kernel. Infrastructure
rejects supplied applications, while kernel requires enabled managed HTTP,
nonempty gateway asset/file views and a kernel-to-gateway readiness dependency.
Supplied `listener_ports` describe container listeners, never host publication.
The v2 planner can already express an empty infrastructure plan or isolated
SMTP/DKIM; it must not gain an application-specific duplicate planner.

Activation already iterates the composition's ordered services and verifies
image/mount/port/process identity. Stop, cold backup, isolated restore and
configuration rollback are generic. The existing native HTTP adapter/descriptor
dispatcher supports public and denied RPC without Hub/MFS/SQL/Redis. Runtime
source and dispatcher contracts need no modification.

## Decision

Add `Distribution.profile: application`, with a required application service and
an explicit external-gateway contract. Reuse the existing supplied-service
implementation, resource projections, ownership and lifecycle. A kernel variant
that silently removed its gateway would change the qualified kernel semantic;
allowing applications in infrastructure would erase its established boundary.
The additional profile therefore makes the missing intent explicit while
preserving both historical profiles and their canonical representations.

The application declares immutable image, non-root UID/GID, command, explicit
dependencies/listeners, healthcheck, scoped resource/secret mounts and plugin
artifact identities. Plugin metadata is inventory, not a new plugin loader:
the distribution host loads native Runtime descriptors/workers.

`external_gateway` declares host-loopback access, exact IPv4 `127.0.0.1`, an
explicit unprivileged host TCP port and matching declared container listener,
HTTP protocol, native RPC readiness path, `/-/` and `/-/svc/` prefixes, and
external HTTPS termination. The reverse proxy's upstream is derived from this
binding. Wildcards, other interfaces/loopback aliases, host networking, extra
publications and conflicting bindings are refused before activation.
IPv6 publication is deliberately unsupported in this initial contract.

The v2 requirements can additionally select declared opaque secret references;
the canonical provider gains a generic application-secret type. This permits
application secrets with no invented DB/Redis/SMTP dependency and reuses the
existing private store/generations/consumer projection. Absent new fields,
existing plan normalization is unchanged.

Application activation orders explicitly selected infrastructure and SMTP/DKIM
before jobs/application. SMTP remains independently optional. An application
that declares mail as a readiness dependency must also require SMTP; omitting
that dependency permits HTTP readiness with optional mail diagnostics. SMTP
TLS, CIDR/SASL relay policy, queue, DKIM-only control network and declared upstream
remain canonical. No direct MX transport or production email is introduced.

## Debian boundary

An explicitly selected `minimal-application` profile consumes public Infra Layer
APIs. It declares no gateway/DB/Redis/DNS/Hub/MFS/Finder by default. It supplies
a small native Runtime composition host, immutable image/plugin inventory,
configuration validation, an external Nginx configuration artifact (never host
installation) and existing drumee-ctl dispatch. Optional SMTP uses Infra Layer's
unchanged capability and tool-image recipe. Application plugins and their
artifacts are explicit; no Oxy-form source or configuration is imported.

No second planner, identity/enrollment SQL, session engine, ACL engine, SMTP
stack or lifecycle is implemented. Minimal-kernel source/dependencies remain
unchanged. Runtime and Oxy-form remain read-only. Production is out of scope.

## Qualification gates

1. Positive/negative pure contracts and unchanged legacy units.
2. Real canonical prepare/activate/inspect/stop/restart/interruption/failure/
   rollback and owned-resource guards, then isolated installed-tarball consumer.
3. Real native RPC allow/deny, exact Docker bindings plus host socket observation
   and a separate network client's denied non-loopback access. Host-only HTTP
   success alone is insufficient. Test the external Nginx as a host process,
   with isolated configuration/certificates and unchanged `/-/` proxy paths.
4. Optional SMTP/DKIM network/isolation and controlled capture evidence; no
   Internet deliverability, recipient/SPF/DMARC or spool recovery claim without
   its distinct actual proof. Unsupported spool restore fails closed.
5. Clean-checkout Debian image/dependency/CLI acceptance and retained IL-4
   minimal-kernel qualification. Preserve exact per-suite counts, failures and
   skips; never replace required network evidence with simulation.

Branches: Infra Layer `feat/il5-external-gateway`, Debian
`feat/il5-minimal-application`. Push review PRs only; no merge, npm/image publish,
production operation, Oxy-form modification or Oxymotion D0 execution.
