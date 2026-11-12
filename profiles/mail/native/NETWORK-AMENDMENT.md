# Private source preservation: amendment before adoption

The routed Docker26 experiment at package .9 exposes1587 but reveals a second
cause. Native Postfix logs show both authorized48 and forbidden49 clients as
10.243.47.1. Docker's client-bridge POSTROUTING MASQUERADE runs after the host
DNAT to47.3:1587. The namespace filter therefore sees the same gateway for both.
The accepted counter increases and the drop counter stays zero. Merely making
the acceptance edge routed is insufficient, and trusting the gateway is unsafe.

Proposed transport amendment, recorded before implementing it:

- Keep the canonical mail-owned edge, exact host-gateway binding and private1587
  interface. Control network remains internal. No foreign backend attachment.
- Independent clients use a dedicated SMTP frontal bridge with
  com.docker.network.bridge.enable_ip_masquerade=false. This is distinct from their
  ordinary application/backend networks, which retain their existing behavior.
  It preserves real sources on the routed path to the gateway. The service-owned
  CIDR allowlist applies to these frontal addresses; applications still need TLS,
  verified hostname and separate credentials. Client project/network recreation
  must preserve this network option and its declared subnet. Their lifecycle does
  not own or stop the mail project.
- Explicitly reject the mail edge gateway source on1587 before all allowed ranges,
  in both packet and SMTP source policy. A default masqueraded bridge must fail
  closed even if its hidden original address was authorized. Do not indiscriminately
  allow a proxy/NAT address. Operators connecting from the host's gateway address
  cannot use this private path; use an explicitly declared preserved-source client.
- A canonical read-only client-network renderer supplies the required frontal
  network definition. It creates nothing and does not modify any application
  backend. Actual Ghost/Oxy deployment/integration remains MAIL04.
- Qualification uses only the disconnected VM for routed bridges and checks
  original48/49 source addresses, kernel accept/drop counters, exact binding,
  dropped startup capabilities, mandatory STARTTLS/auth and persistence across
  normal recreation/reboot. No daemon-wide NAT switch, host network mode or host
  firewall edit is part of this proposal.

This makes explicit the source-preservation precondition missing from the earlier
MAIL01 private-IP contract. It changes the client transport network requirement,
not authentication/sender grants, existing capture/relay contracts, or production
network authorization. Retain .9's failed positive/negative evidence. If any
platform cannot preserve the declared source identity, refuse that integration.

## Superseding amendment B: explicit shared frontal endpoint

The no-masquerade-only experiment is insufficient on Docker26: packets hit its
inter-bridge isolation before the mail namespace (all private counters remain0).
It is not adopted as a qualified route. No host firewall exception is proposed.

The replacement proposal, before implementation, is a mail-owned frontal bridge
with an explicit stable Postfix address, derived as the last usable edge-subnet
address (or first usable if that is the gateway). `plan.private_endpoint` declares
that address, hostname, port and mail-owned network name. The existing gateway
bind remains explicit for host/external routes, but Docker application clients use
the frontal endpoint directly, without DNAT/proxy/masquerade. A network alias for
the verified hostname is owned by Postfix. This adds computed plan metadata, not
another secret or an application backend attachment.

Each independent client project retains its own backend network and joins the
mail-owned frontal network as external, at its declared static frontal address.
The client cannot create/delete that external network through its project lifecycle.
The service joins no client backend. Private CIDRs apply to observed frontal
addresses. The server's own stable address is allowed for endpoint health probes;
the gateway remains explicitly denied. Unknown frontal sources are dropped by the
namespace packet filter before SMTP. TCP/1587 TLS/auth/grants remain mandatory.

The read-only canonical client renderer emits this external-network attachment
and verified private endpoint. Qualification checks separate backend projects,
real frontal addresses, exact static server binding, recreation, normal reboot,
packet counters, credential failures and unchanged mail lifecycle. A masqueraded
host-gateway path remains denied. Application deployment remains MAIL04. The
subnet must have capacity for its gateway, server and clients; too-small subnets
are rejected. This explicitly amends MAIL01's Docker client path; it does not
silently disable Docker isolation or weaken source enforcement.
