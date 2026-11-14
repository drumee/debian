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
is a separate task. Exact final references and qualification links will be
recorded when the native matrix and applicable hosted checks complete.

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
