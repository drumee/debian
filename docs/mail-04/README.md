# MAIL-04 application client qualification

This branch starts at draft Debian PR15
`442fb6553c7c3fa88352e998a2f1db0f2a5e00d8` and consumes draft Infra PR39
`1b60818f4f60cc6b54976184dbd6f0585b717a68`. It does not change the mail engine,
CLI, package receipt, image, quota module, native configuration generator or
network amendment B. The paired Oxymot `feat/mail-04-ghost` branch starts at
`a570952426e266ec4181390c21ee051735d914b3` and owns Ghost's protected client
configuration, laboratory drivers, evidence and MAIL-05 handoff.

No Oxy-form configuration, queue, ledger or deduplication key is changed. The
Oxymotion proof uses an independent synthetic SMTP client; application integration
is a separate task. The [paired qualification dossier](https://github.com/somanos/oxymot/pull/121)
records native PASS evidence, immutable identities and reproduction commands.
The complete runtime replay uses Oxymot freeze
`5de6eb84de4c852814bd21481e7743065cd4eb82`; subsequent changes seal public
evidence and add a supplemental-only exporter mode. Final applicable hosted
checks must pass before declaring MAIL-04 qualified.

## Future Oxymotion client descriptor

The following target values are proposals, not a target activation receipt:

```json
{
  "contract": "drumee.mail-client/1",
  "service_id": "oxymot-mail",
  "host": "mail.oxymot.fr",
  "port": 1587,
  "tls_mode": "starttls",
  "server_name": "mail.oxymot.fr",
  "ca_ref": "secret:oxymotion-mail/ca",
  "account_id": "oxymotion",
  "credential_ref": "secret:oxymotion-mail/submission",
  "required": true
}
```

Use `profiles/mail/private-client.cjs CONFIG CLIENT_ADDRESS` to render the exact
mail-owned external network attachment and endpoint. Assign a distinct approved
static frontal IP; keep the application's backend independently owned. TLS peer
and name verification, authentication and explicit sender grants are mandatory.
No server TLS/DKIM private key, mailbox credential or other application's SMTP
password belongs in this projection. A readiness check authenticates without
MAIL FROM/DATA and never proves delivery.

`SMTP_RECOVERY_UNQUALIFIED` remains for coordinated replacement-storage restores.
Publication, merge, target deployment, real-recipient SMTP and production network
or DNS/PTR changes remain separate owner decisions.

## Ghost-owned TCP connector

Directly attaching a web application to the mail front can expose its HTTP/Admin
listener there. The paired [Oxymot PR121](https://github.com/somanos/oxymot/pull/121)
records the actual HTTP200 failure and its refinement before adoption. Ghost keeps
its existing backend/egress and HTTP bindings. A bounded, unprivileged, read-only
TCP connector owned by the Ghost project consumes its reviewed frontal attachment
and binds only a reserved application-backend address. It holds no credentials,
private keys or mail state and performs no SMTP acceptance, TLS termination or
retry. Its namespace has IPv4 forwarding explicitly disabled.

Ghost's TCP host becomes the connector's backend name; the expected TLS peer name
remains mail.oxymot.fr. Native TLS and AUTH terminate only at the autonomous mail
service. A synthetic SMTP-only client with no listener may use the canonical front
directly. A future web application needs this pattern or a separately qualified
interface binding, including proof that its HTTP/Admin ports are not exposed on
the mail front. The server's network/source/identity contract is unchanged.

Connector outage or recreation is an application dependency event. Mail owns every
message it accepted, and a lost final acknowledgement remains uncertain. Never
stop/restore the mail service or reset an application ledger as client rollback.
