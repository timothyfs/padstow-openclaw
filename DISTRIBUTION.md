# Padstow-OpenClaw Distribution

This repository is the **Padstow-owned, pinned, certified distribution of
OpenClaw** that the Padstow installer pulls. It exists so that "pull OpenClaw
from an approved Padstow distribution" (installer step 5) and the "hello world"
liveness (installer step 6) are backed by a specific, reproducible, tested
artefact — not a moving upstream branch.

## Policy: verbatim

The distribution is **verbatim**. We carry **zero source patches** against
upstream. The only files this repository adds on top of the pinned upstream
tree are distribution artefacts:

- `padstow-cert.sh` — the certification gate (below)
- `DISTRIBUTION.md` — this file

`padstow-cert.sh` step 3 enforces this: any tracked change to a file other than
those two, relative to the pinned commit, fails certification as "not verbatim".

If we ever need to diverge (a security backport, say), it stops being verbatim.
At that point the delta must be recorded here as an explicit, reviewed patch
list and the cert allow-list widened deliberately — never silently.

## Pin: commit, not branch, not tag object

The distribution is pinned to an exact **upstream commit SHA**, not a branch and
not the tag object.

| Field            | Value                                        |
| ---------------- | -------------------------------------------- |
| Upstream repo    | `github.com/openclaw/openclaw`               |
| Upstream tag     | `v2026.9.3`                                   |
| **Pinned commit**| `1391f7cd2d40ab5bbcf2f5f831d3a64f520e72d7`    |
| Padstow tag      | `padstow-2026.9.3-alpha.1`                    |
| package.json ver | `2026.9.3`                                     |
| Node engine      | `>=24.16.0 <25 \|\| >=26.1.0`                  |

### Why the commit and not the tag

`v2026.9.3` is an **annotated tag object** (`a69d657b…`) that *wraps* the release
commit (`1391f7c…`). The npm build metadata short-SHA matches the **commit**,
not the tag object. Pinning the commit removes that ambiguity and is immune to a
tag being moved or re-cut upstream. `padstow-cert.sh` step 1 asserts
`HEAD == 1391f7c…` before it will recommend a tag.

### Verifying the pin

```bash
git rev-parse HEAD          # must equal the pinned commit
git cat-file -t v2026.9.3   # 'tag' (annotated); its target is the pinned commit
```

## Certification: the gate before any tag

A Padstow tag (`padstow-<upstreamver>-alpha.N`) is **only** cut after
`./padstow-cert.sh` exits 0 **and** reports `CERTIFIED` (not just
`BUILD-CERTIFIED`). The script proves, in order:

1. **Pin** — `HEAD` is exactly the pinned commit.
2. **Node runtime** — the running Node satisfies the upstream engine range.
3. **Verbatim** — no source delta vs the pinned commit (only cert/doc added).
4. **Build** — `pnpm install --frozen-lockfile && pnpm build` (pnpm, never npm —
   the repo is a pnpm workspace and a plain `npm install` at root is unsupported).
5. **Container build** — `docker build` of the deploy target (the installer
   deploys into Docker in Alpha).
6. **Gateway liveness** — brings the gateway up **inside the container against a
   real local model** and asserts `openclaw gateway status` reports ready. This
   is the same liveness the installer re-runs on the target machine.

### The honesty rule

Step 6 needs an external artefact: a local model present in the environment.
When one is **not** present the script does **not** fake a pass — it prints an
explicit `SKIP`, ends with `BUILD-CERTIFIED, LIVENESS UNPROVEN`, and **withholds
the tag recommendation**. Only a green build *and* a genuine gateway-up signal
produce `CERTIFIED` and a tag recommendation. The gate never lies; a skip is
visible and blocks the tag.

The CLI surface used for liveness (`openclaw gateway` / `openclaw gateway
status`) is the real upstream surface from the pinned README. There is
deliberately **no invented one-shot prompt subcommand** — if upstream adds a
first-class one-shot prompt command, step 6 is the single place to tighten.

### Running it

```bash
# Build gate only (no model on this box) — reports SKIP for liveness, no tag:
./padstow-cert.sh

# Full certification with a real model present:
PADSTOW_CERT_MODEL=mistral:7b ./padstow-cert.sh

# Dev: skip the container entirely (build + version + verbatim only):
PADSTOW_CERT_SKIP_DOCKER=1 ./padstow-cert.sh
```

On `CERTIFIED`, the script prints the exact signed-tag commands to run.

## Cutting a distribution tag (outbound — requires explicit go)

These steps push to a Padstow-owned remote and are **not** run automatically.
They happen only on an explicit decision:

```bash
# 1. Create the Padstow-owned repo (once):
gh repo create timothyfs/padstow-openclaw --private --source=. --remote=origin

# 2. Certify (must report CERTIFIED, not just BUILD-CERTIFIED):
PADSTOW_CERT_MODEL=<model> ./padstow-cert.sh

# 3. Cut + push the signed tag the cert script recommends:
git tag -s padstow-2026.9.3-alpha.1 1391f7cd2d40ab5bbcf2f5f831d3a64f520e72d7 \
  -m "Padstow-OpenClaw padstow-2026.9.3-alpha.1 (verbatim, certified)"
git push origin padstow-2026.9.3-alpha.1
```

The installer's `PADSTOW_OPENCLAW_PIN` references the Padstow tag; the pull step
resolves it to the pinned commit SHA and **verifies the SHA** before use.

## Update / bump procedure

To move the distribution to a newer upstream release:

1. Fetch the new upstream tag; identify its **release commit SHA** (not the tag
   object) — cross-check against npm build metadata as we did for `1391f7c`.
2. Update `UPSTREAM_TAG`, `PINNED_COMMIT`, and `PADSTOW_TAG` in
   `padstow-cert.sh` and the table above.
3. Re-run `./padstow-cert.sh` with a real model → must report `CERTIFIED`.
4. Cut the next `padstow-<newver>-alpha.N` tag.
5. Bump `PADSTOW_OPENCLAW_PIN` in the installer (`Padstow` repo,
   `padstow-app/electron/main.ts`) and re-verify the installer build.

Keep this verbatim: bumps change the pin, never the source.
