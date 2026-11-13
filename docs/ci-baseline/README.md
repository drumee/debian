# CI baseline remediation

Base: `ff6e6b399128e6332c984fc2e8e60f660bd5f881` (`feat/container-distribution`).
This dedicated change repairs the inherited required CI checks without changing their thresholds, exclusions or jobs. MAIL02 carries these commits to make its required checks green; the mail-native FROM correction is separate.

The pinned ShellCheck action `00b27aa7cb85167568cb48a3838b75f4265f2bca`, ShellCheck0.11.0 and warning severity report91 diagnostics on both this exact base and MAIL02 `54773065d6d9c348e601e2f2366b3fb614235297`. Comparison keys are rule/file/cause, not line numbers. Packaging on the same pinned Trixie toolchain reports11 inherited mutable FROM instructions and one global npm install. MAIL02 adds a twelfth mutable FROM in `profiles/mail/Dockerfile.native`; comparing to an older MAIL02 head previously obscured that addition.

| Rule | Count | Files |
| --- | --- | --- |
| SC1087 | 1 | `tests/config-parity.sh` |
| SC1090 | 3 | `admin/build.sh`, `server/usr/share/drumee/admin/templates/.bashrc` |
| SC2034 | 15 | `admin/build.sh`, `builder/build.sh`, `infra/build.sh`, `schemas-patch/build.sh`, `schemas/build.sh`, `scripts/containers.sh`, `server/usr/share/drumee/admin/admin.sh`, `server/usr/share/drumee/admin/create-server`, `static/build.sh`, `ui/build.sh` |
| SC2037 | 1 | `schemas-patch/bin/patch-from-manifest.sh` |
| SC2045 | 11 | `admin/build.sh`, `infra/build.sh`, `meta/build.sh`, `schemas-patch/build.sh`, `schemas/build.sh`, `server/build.sh`, `server/usr/share/drumee/bin/db-patch-scan.sh`, `server/usr/share/drumee/sbin/log-history.sh`, `server/usr/share/drumee/sbin/log-rotate.sh`, `static/build.sh`, `ui/build.sh` |
| SC2046 | 20 | `bootstrap/usr/lib/drumee/entrypoint/schemas`, `schemas-patch/bin/patch-from-file`, `schemas-patch/bin/patch-from-manifest.sh`, `scripts/publish-images.sh`, `server/usr/share/drumee/admin/admin.sh`, `server/usr/share/drumee/admin/create-server`, `server/usr/share/drumee/sbin/log-rotate.sh`, `utils/functions.sh` |
| SC2048 | 1 | `server/system/usr/sbin/drumee` |
| SC2089 | 1 | `builder/build.sh` |
| SC2090 | 5 | `builder/build.sh` |
| SC2128 | 2 | `scripts/release-status.sh` |
| SC2148 | 7 | `infra/sample.sh`, `infra/var/lib/drumee/utils/functions.sh`, `schemas-patch/patch.sh`, `server/usr/share/drumee/admin/templates/.bashrc`, `server/usr/share/drumee/admin/templates/.profile`, `utils/env.sh`, `utils/functions.sh` |
| SC2154 | 2 | `admin/build.sh`, `schemas-patch/bin/patch-from-manifest.sh` |
| SC2155 | 1 | `schemas-patch/bin/patch-from-manifest.sh` |
| SC2164 | 11 | `admin/opt/drumee/schemas/patch.sh`, `schemas-patch/bin/patch-from-manifest.sh`, `schemas-patch/patch.sh`, `scripts/containers.sh`, `server/system/usr/sbin/drumee`, `server/usr/share/drumee/bin/make-zip.sh`, `server/usr/share/drumee/sbin/log-history.sh`, `server/usr/share/drumee/sbin/log-rotate.sh`, `tests/native/control-deps.sh`, `tests/run-all.sh`, `tests/wizard-install.sh` |
| SC2166 | 3 | `infra/var/lib/drumee/utils/cron/tmp-files-cleaner`, `schemas-patch/build.sh`, `utils/functions.sh` |
| SC2178 | 1 | `scripts/release-status.sh` |
| SC2215 | 1 | `scripts/build-seed.sh` |
| SC2221 | 2 | `bin/drumee-plugin`, `server/usr/sbin/drumee-plugin` |
| SC2222 | 2 | `bin/drumee-plugin`, `server/usr/sbin/drumee-plugin` |
| SC3043 | 1 | `bootstrap/usr/lib/drumee/entrypoint/lib.sh` |

Corrections address the actual causes: explicit shell declarations, POSIX-compatible credential guards preserving fatal exit, quoted/array arguments, fail-closed directory changes, safe globs, valid manifest option arrays, and the seed build line continuation. Legacy accepted-but-unused options remain accepted without pretending to implement them. Native generated/cloned `*/src/` trees are untouched.

All public legacy base tags are pinned to their resolved manifest digests. Source-derived child images now require a valid immutable SERVER_DIGEST and, in local mode, a loaded parent matching the server just built. Local builds fail rather than falling back to a mutable tag. The publishing script resolves the digest after its explicitly requested server publication; no publishing operation is executed by this maintenance task. PM2 is installed from the authoritative node-runtime package-lock into a local prefix; its CLI is exposed through PATH, with no global npm install or duplicate module manifest.

Validation: ShellCheck0.11.0 at warning severity has zero diagnostics; unchanged `scripts/check-packaging.sh` passes. `tests/run-all.sh` passes332 checks, including eight controlled regression cases for argument boundaries, absent/invalid/different parents, disabled optional tags, seed command construction, missing credentials and log retention with filenames containing spaces. The locked PM2 runtime is built using synthetic server input and reports5.4.3. Tests use Docker command doubles for publishing paths; no artifact is uploaded.

The detailed base/PR logs, rule comparison, tool versions, pins and hosted receipts are retained in the MAIL02 qualification dossier. Legacy Dockerfile changes are not a production deployment qualification. The canonical mail-native image consumes its separately locked OCI base, not these legacy Dockerfiles.
