# Committed keyrings

Repository signing keys used by the image builds. They are **committed**, never
fetched at build time — `scripts/check-packaging.sh` fails a Dockerfile that pipes
`curl` into `bash`, `sh` or `gpg --dearmor`, for two reasons:

- a key fetched during a build is trusted because it arrived over TLS from a host
  that happened to answer, which is not the same as being the key you intended;
- the build stops being reproducible: the same Dockerfile can pull a different key
  tomorrow and nothing in the image records which one it used.

Keys are dearmored (`gpg --dearmor`), which is the form `Signed-By:` expects.

## Present

| File | Key | Fingerprint |
|---|---|---|
| `nodesource.gpg` | NodeSource (Node 22) | `6F71F525282841EEDAF851B42F59B5F99B1BE0B4` |

Recorded so that a replacement is visible in review rather than silent. To check
what is committed here:

```bash
gpg --show-keys docker/keyrings/nodesource.gpg
```

NodeSource is needed because **Trixie ships nodejs 20.19.2**, while
`drumee-node-runtime` and `drumee-role-app` require `nodejs (>= 22)` — see
`docs/distribution.md` §9.5.

## Missing, deliberately

`drumee-archive-keyring.gpg` is **not** here yet: the project signing key does not
exist. `docs/distribution.md` §4 requires a dedicated project key with the master
offline and only a signing subkey in CI, and notes that the currently published
repository is signed with a local build key that must be re-signed before launch.

Committing today's throwaway test key instead would be worse than the gap: the
base image would ship trust in a key generated on a developer's laptop.

Until it exists, the base image configures **no** Drumee APT source. Role images
supply the repository URI and keyring at build time — `scripts/apt-repo-local.sh`
generates both for local work — via `/usr/local/sbin/drumee-apt-source`, which the
base image provides so the sources stanza is written in one place rather than
repeated per role.

Once the project key exists: put its dearmored public half here, add it to the
table above with its fingerprint, and have the base image copy it to
`/usr/share/keyrings/`. From then on the `drumee-archive-keyring` package keeps it
current, which is what makes rotation an `apt` operation rather than a rebuild.
