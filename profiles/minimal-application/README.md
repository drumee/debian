# Explicit minimal application profile

Owner-bound native Server Runtime composition behind an externally managed HTTPS
proxy. No gateway/DB/Redis/DNS/Hub/MFS/Finder is implicit. Runtime alpha.4 is
unchanged; Infra Layer's immutable IL-5 source owns all lifecycle operations.

Read [architecture](../../docs/IL-5-architecture.md) and
[operator/build/recovery guide](../../docs/IL-5-distribution.md).
Example: `config/drumee.minimal-application.example.json`.

```sh
npm ci --ignore-scripts --no-audit --no-fund --prefix profiles/minimal-application
node --test profiles/minimal-application/test/*.test.js
python3 tests/minimal-application/plugin-artifact.test.py
```

Qualification and review handoff are recorded separately; no npm/image publication
or production/Oxy-form/D0 operation is performed by this profile.
