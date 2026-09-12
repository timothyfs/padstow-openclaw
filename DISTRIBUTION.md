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

`padstow-cert.sh` step 3 enforces this: it compares the published distribution
root with upstream `v2026.9.3` and fails certification if any tracked file other
than those two has changed.

If we ever need to diverge (a security backport, say), it stops being verbatim.
At that point the delta must be recorded here as an explicit, reviewed patch
list and the cert allow-list widened deliberately — never silently.

## Pin: distribution root, with upstream provenance

The installer pins an exact **Padstow distribution root SHA**, not a branch and
not a tag object. The upstream commit and tree are recorded as provenance
anchors so the verbatim claim remains independently provable.

| Field                 | Value                                          |
| --------------------- | ---------------------------------------------- |
| Upstream repo         | `github.com/openclaw/openclaw`                 |
| Upstream tag          | `v2026.9.3`                                    |
| Upstream commit       | `1391f7cd2d40ab5bbcf2f5f831d3a64f520e72d7`     |
| Upstream tree         | `bcf3cbd25e981139b015f41f9605be8577304b0b`     |
| **Distribution root** | `2a5c305c2ee95e983ad4712998f3a4ea88408619`     |
| **Padstow tag**       | `padstow-2026.9.3-alpha.1` → distribution root |
| package.json ver      | `2026.9.3`                                     |
| Node engine           | `>=24.16.0 <25 \|\| >=26.1.0`                  |

### Squashed verbatim root (why the pin is the distribution root, not upstream's commit)

This repository is a **squashed verbatim root**: a single parentless commit
(`2a5c305…`) whose tree is upstream `v2026.9.3` **plus only** `padstow-cert.sh`
and `DISTRIBUTION.md`. Upstream's 90k-commit history is intentionally dropped —
a pinned distribution never walks it, and carrying it bought nothing but ~1.7 GB.

The pin is therefore the **distribution root SHA** (`2a5c305…`), which the
installer resolves the tag to and SHA-verifies. Upstream's commit `1391f7c…` and
tree `bcf3cbd2…` are recorded above as the **provenance anchor**.

The verbatim guarantee is not weakened — it is _provable by diff_: clone upstream
at `v2026.9.3` and diff its tree against this root. The only delta is the two
added files. That is stronger than trusting an opaque commit hash.

### Verifying verbatim provenance

```bash
# In a fresh upstream clone at the tag, from inside this distribution repo:
git fetch https://github.com/openclaw/openclaw.git v2026.9.3
git diff --name-status 1391f7cd2d40ab5bbcf2f5f831d3a64f520e72d7 HEAD --
#   → A  DISTRIBUTION.md
#   → A  padstow-cert.sh          (and nothing else = verbatim)

git rev-parse HEAD    # 2a5c305… the distribution root the Padstow tag resolves to
```

> Note: because history is squashed, `padstow-cert.sh` step 1 ("HEAD is the
> pinned commit `1391f7c`") no longer applies to this published root and is a
> known SKIP/FAIL against the distribution repo. It still governs a _fresh
> upstream clone_ during a re-certification/bump (below), where HEAD genuinely
> is the upstream commit before squashing. Treat step 1 as a bump-time gate.

## Certification status

Current tag status:

- `padstow-2026.9.3-alpha.1` is a public, annotated **BUILD-CERTIFIED /
  provenance** tag for installer pull-path testing.
- Full **CERTIFIED** status still requires the local-model gateway liveness pass
  below. Do not claim full runtime certification until that evidence exists.

`./padstow-cert.sh` proves, in order:

1. **Pin** — the Padstow tag resolves to the published distribution root.
2. **Node runtime** — the running Node satisfies the upstream engine range.
3. **Verbatim** — no source delta vs upstream (only cert/doc added).
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
explicit `SKIP` and ends with `BUILD-CERTIFIED, LIVENESS UNPROVEN`. Only a green
build _and_ a genuine gateway-up signal produce `CERTIFIED`. The gate never
lies; a skip is visible and blocks any claim of full runtime certification.

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

## Publishing a distribution tag (outbound — requires explicit go)

These steps push to a Padstow-owned remote and are **not** run automatically.
They happen only on an explicit decision:

```bash
# 1. Create the Padstow-owned repo (once):
gh repo create timothyfs/padstow-openclaw --public --source=. --remote=origin

# 2. Certify:
PADSTOW_CERT_MODEL=<model> ./padstow-cert.sh

# 3. Cut + push the signed tag when a signing key is configured:
git tag -s padstow-2026.9.3-alpha.1 2a5c305c2ee95e983ad4712998f3a4ea88408619 \
  -m "Padstow-OpenClaw padstow-2026.9.3-alpha.1 (verbatim, certified)"
git push origin padstow-2026.9.3-alpha.1

# If no signing key is configured, use an annotated tag and record that fact:
git tag -a padstow-2026.9.3-alpha.1 2a5c305c2ee95e983ad4712998f3a4ea88408619 \
  -m "Padstow-OpenClaw padstow-2026.9.3-alpha.1 (verbatim, build-certified)"
git push origin padstow-2026.9.3-alpha.1
```

The installer's `PADSTOW_OPENCLAW_PIN` references the Padstow tag; the pull step
resolves it to the pinned commit SHA and **verifies the SHA** before use.

## Update / bump procedure

To move the distribution to a newer upstream release:

1. Fetch the new upstream tag; identify its **release commit SHA** (not the tag
   object) — cross-check against npm build metadata as we did for `1391f7c`.
2. Rebuild the squashed distribution root from that upstream tree plus
   `padstow-cert.sh` and `DISTRIBUTION.md`.
3. Update `UPSTREAM_TAG`, `UPSTREAM_COMMIT`, `DISTRIBUTION_ROOT`, and
   `PADSTOW_TAG` in `padstow-cert.sh` and the table above.
4. Re-run `./padstow-cert.sh` with a real model → must report `CERTIFIED` before
   claiming runtime certification.
5. Cut the next `padstow-<newver>-alpha.N` tag.
6. Bump `PADSTOW_OPENCLAW_PIN` in the installer (`Padstow` repo,
   `padstow-app/electron/main.ts`) and re-verify the installer build.

Keep this verbatim: bumps change the pin, never the source.
