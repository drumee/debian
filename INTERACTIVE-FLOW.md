# Implementation brief — INTERACTIVE MODE FOR baremetal.sh



---

## Increment 0 — set up the context

No implementation. Understant the full picture.
- Three different branches : wan, lan and localhost.
  1.wan when there is at least one public IP
  2.lan when no public IP and atleast one pirvate IP
  3.localhost neither 
- all prompts shall propose a default value
- Add `docs/baremetal.md`.

---

## Increment 1 — Select the IP address that will serve Drumee

- branch wan: prompt for the IP address that will serve Drumee. Use the first detected public IP as default
- branch lan: prompt for the IP address that will serve Drumee. Use the first detected private IP as default
- branch localhost no prompt. 
---

## Increment 2 — tls_mode
- branch wan: dsn, caddy, acme, own_ssl, default=dns
- branch lan: dns
- branch localhost: seilf-signed

+ prompt every var required for each mode, example caddy

## Increment 3 — domain name
- branch wan: any valid domain name, default=examaple.org
- branch lan: drumee.lan, default=drumee.lan
- branch localhost: localhoast

## Increment 4 — admin_email
- branch wan: if TLS option not own_ssl, ask for acme/caddy email account (default=admin_email)
- branch lan: use `whoami`@localhost
- branch localhost: use `whoami`@localhost

## Increment 5 — data location (applicaple to all branches)
- data_dir, default /data
- db_dir, default /srv/db
- backup_location, default /backup
- exchange_location, default /exchanges
- 



