# `debian.sh` — the native bootstrap and its interactive flow

`scripts/debian.sh` is the entry point for a native install:

```bash
curl -fsSL https://apt.drumee.net/debian.sh | sudo bash     # interactive
sudo PRESEED=install.conf bash debian.sh                    # unattended
```

It adds the signed APT repository, ensures Node 22 and BIND9, asks for every
setting `drumee-infra` accepts, preseeds the answers into debconf, then runs
`apt install drumee`.

## Why the script asks, and not debconf

Two structural reasons, both worth keeping in mind before moving a question:

- On the documented `curl … | sudo bash` path **stdin is the script itself**.
  debconf only asks when it has a terminal, so every question would silently take
  its default. All prompts therefore read `/dev/tty`, and apt is handed
  `<"$TTY"` too so dependencies with questions of their own (postfix) still work.
- `infra/debian/config` asks `db_dir`, `data_dir`, `backup_location`,
  `exchange_location` and the WireGuard ports at **medium/low** priority, which
  the default debconf priority never displays. They were unreachable
  interactively however good the terminal was.

A question answered here is marked *seen*, so debconf does not ask it again. The
order, the branch conditions and the defaults mirror `infra/debian/config` and
`infra/debian/templates` — if the two drift, the difference lands silently in the
rendered configuration rather than as an error.

## Three modes

| | Trigger | Behaviour |
|---|---|---|
| Unattended (preseed) | `PRESEED=<install.conf>` | no prompts at all; the preseed decides everything |
| Unattended (defaults) | `DRUMEE_NONINTERACTIVE` set to anything other than `0` | no prompts; env values, else defaults |
| Interactive | `DRUMEE_NONINTERACTIVE` unset or `0`, and `/dev/tty` exists | prompts for everything |

Setting any `DRUMEE_*` / `WIREGUARD_*` variable answers that one question and
skips its prompt, so a partially-scripted install is just a matter of exporting
the answers you already know. The full list is in the script's header comment.

Without a terminal — cron, cloud-init, a piped `bash` with no tty — the script
falls back to defaults rather than blocking on a prompt nothing can answer.

## Network topology decides the shape of the install

Before asking anything, the script enumerates the host's global-scope addresses
and classifies them. That classification picks one of three branches:

| Branch | Condition | Serving address | `tls_method` | `local_mode` | Domain default |
|---|---|---|---|---|---|
| **wan** | at least one public address | asked, defaults to the first public one | asked: `acme-dns-server` (default), `acme-dns-api`, `caddy`, `own` | `false` | `example.com` |
| **lan** + `dns` | no public, at least one private | asked, defaults to the first private one | `self-signed`, not asked | `true` | `drumee.lan` |
| **lan** + `wireguard` | as above | as above | asked: `acme-dns-api` (default), `caddy`, `own`, `self-signed` | `false` | `example.com` |
| **localhost** | neither | not asked | `self-signed`, not asked | `true` | `localhost` |

### The lan branch asks how it should be reached

A private-address box has two useful shapes, and they are **mutually exclusive by
construction** rather than by preference — `config/render.mjs:210` rejects
`wireguard.enabled` together with `instance.local_mode`, and
`infra/debian/config:106` skips the WireGuard questions entirely when `local_mode`
is true. So the choice is made once, up front, and the domain, the certificate and
`local_mode` all follow from it:

- **`dns`** (default) — LAN only. BIND9 runs here and serves the zone, so the name
  resolves for every client pointed at this host; nothing else on the network knows
  it. Self-signed certificate, because no authority can validate a name that is
  delegated nowhere. `local_mode=true`, WireGuard off.
- **`wireguard`** — reachable from outside with no router port opened, through the
  coordination server. `local_mode=false`, WireGuard on, and a **real certificate
  becomes possible** over DNS-01, which is also outbound-only. Domain defaults to a
  public one and the administrator address to `admin@example.com`.

`acme-dns-server` is deliberately **absent** from the wireguard menu: it answers
the challenge from a BIND9 the CA must reach on inbound udp/53, which is exactly
what this box does not have. Offering it would be offering a choice that cannot
succeed. `DRUMEE_LAN_MODE=dns|wireguard` presets the answer.

What counts as private: RFC1918 (`10/8`, `172.16/12`, `192.168/16`), CGNAT
(`100.64/10`), and IPv6 ULA (`fc00::/7`). Loopback and link-local are excluded by
asking the kernel for `scope global` in the first place. Everything else counts as
public, including IPv6 global unicast (`2000::/3`).

### Why the branch matters more than it looks

The three branches are not cosmetic — they decide whether this host can hold a
public certificate at all:

- **wan** is the only branch where ACME can succeed. Drumee needs a *wildcard*
  certificate, which only a DNS-01 challenge can issue (see the TLS section of
  `CLAUDE.md`), and each method answers that challenge differently.
- **lan** cannot get a public certificate: nothing delegates `drumee.lan`, so no
  CA can validate it. It gets `self-signed` plus a local BIND9 that actually
  serves the zone — on a LAN the nameserver *is* the product, because no upstream
  resolver will ever answer for that name. Point the LAN at this host afterwards
  (the router's DHCP "DNS server" option, or per client).
- **localhost** has no address to serve to anyone else, so it takes the same
  self-signed path with no address question at all.

`local_mode=true` on the last two also skips the WireGuard questions: NAT
traversal is meaningless for a box that is only reachable on its own LAN.

## The questions, in order

1. `reconfigure_existing` — only when `/etc/drumee/drumee.json` already names a
   non-empty domain, i.e. only when there is a configuration to lose. Declining
   keeps the running configuration; accepting re-renders it and overwrites hand
   edits under `/etc/drumee`, `/etc/nginx`, `/etc/bind`, Prosody and Postfix.
   Passwords are reused either way.
2. `description` — a label for the instance.
3. **Serving address** (`ip4`/`public_ip4`, `ip6`/`public_ip6`) — skipped entirely
   on the localhost branch. `-` declines a family, which leaves it unset exactly
   as before this flow existed.
4. `domain` — branch-defaulted as in the table above.
5. `local_mode` — asked on the local branches, forced `false` otherwise, and
   **always preseeded either way**. drumee-infra 1.2.26 writes the value itself too,
   so the two agree; stating it here is what keeps this script correct against an
   older drumee-infra, where the template defaulted to `true` and an unanswered
   `local_mode` therefore meant *LAN-only* — `config` read that back and forced
   `tls_method=self-signed` over whatever had been chosen, without ever showing the
   TLS question. On the non-local branches `service` is asked instead.
6. `admin_email` — the administrator login and where technical mail goes.
   Defaults to `admin@example.com` on wan, and to `$SUDO_USER@localhost` (falling
   back to `whoami`) on lan and localhost.
7. Storage paths: `db_dir` (`/srv/db`), `data_dir` (`/data`),
   `backup_location` (no default — a backup should sit on a different partition),
   `exchange_location` (`/exchangearea`).
8. `tls_method` — asked on wan only, then whatever that method needs:
   `own` → `own_ssl_path`; `acme-dns-api` → `acme_env_file`;
   `caddy` → `caddy_domain`, `caddy_dns_provider`, `caddy_dns_api_key`;
   and `acme_email` for any ACME or Caddy method, defaulting to the admin email.
9. WireGuard — `wireguard_enabled` and, when enabled, the coordinator host and
   the two ports. Skipped when `local_mode` is true.

The DNS provider token is read with echo disabled and is written by the postinst
to a 0600 file; it is never printed back.

## Where the addresses go

`infra/debian/config` does not ask for the public addresses, but
`infra/debian/postinst` reads them: the `ip4`/`ip6` answer *is* the address unless
it reads `other`, in which case the free-text `public_ip4`/`public_ip6` carries
it. This script preseeds that pair. Before it did, the interactive path always
left them empty and `infra.js` skipped its entire public branch — no nginx
`01-public.conf`, no public or reverse BIND zones, no postfix/opendkim.

The detected address is only ever offered as an *interactive* default. Unattended
runs leave it unset unless `DRUMEE_PUBLIC_IP4`/`DRUMEE_PUBLIC_IP6` says otherwise,
because the address of the default route is usually the LAN one and preseeding it
as *public* would quietly change the meaning of every existing unattended install.

## Changing an answer later

```bash
sudo dpkg-reconfigure drumee-infra
```

Every question above is a debconf question, so this is the supported way to
revisit one — including the ones this script asks on debconf's behalf.

## Related

- `CLAUDE.md` — "debian.sh owns the interaction", and the TLS/DNS-01 section
  that explains why `tls_method` decides two things at once.
- `docs/native-channel.md` — the preseed route and `render.mjs debconf`.
- `infra/debian/config`, `infra/debian/templates` — the authority this flow
  mirrors.
