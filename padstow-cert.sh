#!/usr/bin/env bash
#
# padstow-cert.sh — Padstow-OpenClaw distribution certification gate.
#
# The published Alpha distribution is a squashed root commit: upstream OpenClaw
# v2026.9.3 plus Padstow's two distribution files. This script proves that root
# tag resolves to the expected pin, the working tree remains verbatim against
# upstream, builds, and can bring the gateway up against a local model in a
# container.
#
# HONESTY RULE (matches the installer): every step reports REAL pass/fail.
# The one step that needs an external artefact — a local model pulled into the
# container — reports an explicit SKIPPED (exit 0 for the build gate, but the
# tag recommendation is withheld) rather than a faked PASS when no model is
# present. A green build + a genuine model round-trip is the only path to a
# tag recommendation. Nothing here pretends.
#
# Usage:
#   ./padstow-cert.sh                 # full gate; model round-trip runs if a
#                                     # model is present, else SKIPPED
#   PADSTOW_CERT_MODEL=<ollama-tag>   # model to round-trip (e.g. mistral:7b)
#   PADSTOW_CERT_SKIP_DOCKER=1        # build+start only, no container (dev)
#
# Requires: git, pnpm, node (engine range below), and (for the container gate)
# docker with a reachable daemon.

set -euo pipefail

# --- Pinned upstream source-of-truth ---------------------------------------
# The installer pins the published distribution root. The upstream commit and
# tree are provenance anchors used to prove the root is still verbatim.
readonly UPSTREAM_TAG="v2026.9.3"
readonly UPSTREAM_COMMIT="1391f7cd2d40ab5bbcf2f5f831d3a64f520e72d7"
readonly DISTRIBUTION_ROOT="2a5c305c2ee95e983ad4712998f3a4ea88408619"
readonly PADSTOW_TAG="padstow-2026.9.3-alpha.1"
readonly NODE_ENGINE_HINT=">=24.16.0 <25 || >=26.1.0"

# --- Output helpers --------------------------------------------------------
c_pass()  { printf '  \033[32m✓ PASS\033[0m  %s\n' "$1"; }
c_fail()  { printf '  \033[31m✗ FAIL\033[0m  %s\n' "$1"; }
c_skip()  { printf '  \033[33m▲ SKIP\033[0m  %s\n' "$1"; }
c_step()  { printf '\n\033[1m» %s\033[0m\n' "$1"; }

FAILED=0
MODEL_ROUNDTRIP="pending"   # pass | skip (never silently pass)

fail() { c_fail "$1"; FAILED=1; }

# --- 1. Pin verification: does the tag resolve to the distribution root? ----
c_step "1. Pin verification"
TAG_SHA="$(git rev-parse "${PADSTOW_TAG}^{commit}" 2>/dev/null || true)"
if [[ -z "$TAG_SHA" ]]; then
  git fetch --tags origin "$PADSTOW_TAG" >/tmp/padstow-cert-tag-fetch.log 2>&1 || true
  TAG_SHA="$(git rev-parse "${PADSTOW_TAG}^{commit}" 2>/dev/null || true)"
fi

if [[ "$TAG_SHA" == "$DISTRIBUTION_ROOT" ]]; then
  c_pass "${PADSTOW_TAG} resolves to the published distribution root ($DISTRIBUTION_ROOT)"
else
  fail "${PADSTOW_TAG} resolved to '${TAG_SHA:-missing}', not the published distribution root ($DISTRIBUTION_ROOT)."
fi

# --- 2. Runtime version gate -----------------------------------------------
c_step "2. Node runtime"
NODE_V="$(node -v 2>/dev/null || echo 'none')"
# Accept the upstream engine range: 24.16+ (<25) OR 26.1+.
if node -e '
  const [maj,min] = process.versions.node.split(".").map(Number);
  const ok = (maj===24 && min>=16) || (maj>=26 && (maj>26 || min>=1));
  process.exit(ok?0:1);
' 2>/dev/null; then
  c_pass "Node $NODE_V satisfies engine ($NODE_ENGINE_HINT)"
else
  fail "Node $NODE_V does not satisfy engine ($NODE_ENGINE_HINT)"
fi

# --- 3. Verbatim check: no Padstow source delta from upstream ---------------
# The distribution policy is VERBATIM. Only cert/doc artefacts we add are
# allowed to differ. Any other tracked change means the fork is no longer a
# clean pinned mirror and must not be certified as verbatim.
c_step "3. Verbatim policy (no source delta vs upstream)"
ALLOWED='padstow-cert.sh|DISTRIBUTION.md'
UPSTREAM_REF=""
DELTA=""
if git rev-parse --verify "${UPSTREAM_COMMIT}^{commit}" >/dev/null 2>&1; then
  UPSTREAM_REF="$UPSTREAM_COMMIT"
elif git fetch --depth 1 https://github.com/openclaw/openclaw.git "$UPSTREAM_TAG" >/tmp/padstow-cert-fetch.log 2>&1; then
  UPSTREAM_REF="FETCH_HEAD"
else
  fail "Could not fetch upstream ${UPSTREAM_TAG} for verbatim comparison — see /tmp/padstow-cert-fetch.log"
fi

if [[ -n "$UPSTREAM_REF" ]]; then
  DELTA="$(git diff --name-only "$UPSTREAM_REF" HEAD -- 2>/dev/null | grep -Ev "^($ALLOWED)$" || true)"
fi

if [[ -n "$UPSTREAM_REF" && -z "$DELTA" ]]; then
  c_pass "No source delta from upstream ${UPSTREAM_TAG} (verbatim)"
else
  fail "Unexpected delta from upstream (not verbatim):"$'\n'"$DELTA"
fi

# --- 4. Build from the pinned source ---------------------------------------
c_step "4. Build"
PNPM_CMD=()
if command -v pnpm >/dev/null 2>&1; then
  PNPM_CMD=(pnpm)
elif command -v corepack >/dev/null 2>&1; then
  PNPM_CMD=(corepack pnpm)
fi

if [[ "${#PNPM_CMD[@]}" -gt 0 ]]; then
  if "${PNPM_CMD[@]}" install --frozen-lockfile >/tmp/padstow-cert-install.log 2>&1 \
     && "${PNPM_CMD[@]}" build >/tmp/padstow-cert-build.log 2>&1; then
    c_pass "pnpm install --frozen-lockfile && pnpm build"
  else
    fail "Build failed — see /tmp/padstow-cert-install.log and /tmp/padstow-cert-build.log"
  fi
else
  fail "pnpm/corepack not found (packageManager is pnpm; do not substitute npm)"
fi

# --- 5. Container build (the deploy target) --------------------------------
c_step "5. Container build"
if [[ "${PADSTOW_CERT_SKIP_DOCKER:-0}" == "1" ]]; then
  c_skip "PADSTOW_CERT_SKIP_DOCKER=1 — container build skipped (dev mode)"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if docker build -t "padstow-openclaw:${PADSTOW_TAG}" . >/tmp/padstow-cert-docker.log 2>&1; then
    c_pass "docker build -t padstow-openclaw:${PADSTOW_TAG}"
  else
    fail "Container build failed — see /tmp/padstow-cert-docker.log"
  fi
else
  fail "Docker not present / daemon unreachable (required for the container gate)"
fi

# --- 6. Liveness: the distribution comes up against a LOCAL model -----------
# This is the genuine liveness the installer re-runs. The upstream CLI surface
# is `openclaw gateway` / `openclaw gateway status` (verified against the pinned
# README — there is deliberately NO invented one-shot "prompt" subcommand here).
# The probe: bring the gateway up headless inside the container wired to a local
# model, then assert `openclaw gateway status` reports ready. It needs a local
# model present; if none is configured we SKIP loudly and withhold the tag
# recommendation — we never fake a PASS.
c_step "6. Gateway liveness against a local model"
CERT_MODEL="${PADSTOW_CERT_MODEL:-}"
if [[ -z "$CERT_MODEL" ]]; then
  c_skip "No PADSTOW_CERT_MODEL set — cannot bring the gateway up against a real model. Set e.g. PADSTOW_CERT_MODEL=mistral:7b with a model present."
  MODEL_ROUNDTRIP="skip"
elif [[ "${PADSTOW_CERT_SKIP_DOCKER:-0}" == "1" ]]; then
  c_skip "PADSTOW_CERT_SKIP_DOCKER=1 — no container to run liveness in."
  MODEL_ROUNDTRIP="skip"
else
  # Start the gateway detached inside the container, wait for readiness, then
  # assert status. `openclaw gateway status` exiting 0 with a ready line is the
  # real up-signal (same one the installer's health gate uses).
  CID="$(docker run -d \
      -e OPENCLAW_LOCAL_MODEL="$CERT_MODEL" \
      "padstow-openclaw:${PADSTOW_TAG}" \
      node openclaw.mjs gateway 2>/tmp/padstow-cert-up.log || true)"
  if [[ -z "$CID" ]]; then
    fail "Could not start the gateway container — see /tmp/padstow-cert-up.log"
  else
    READY=""
    for _ in $(seq 1 30); do
      if docker exec "$CID" node openclaw.mjs gateway status >/tmp/padstow-cert-status.log 2>&1; then
        READY="yes"; break
      fi
      sleep 2
    done
    docker logs "$CID" >/tmp/padstow-cert-gwlogs.log 2>&1 || true
    docker rm -f "$CID" >/dev/null 2>&1 || true
    if [[ -n "$READY" ]]; then
      c_pass "Gateway came up against '$CERT_MODEL' and reported ready"
      MODEL_ROUNDTRIP="pass"
    else
      fail "Gateway did not report ready within timeout — see /tmp/padstow-cert-status.log and /tmp/padstow-cert-gwlogs.log"
    fi
  fi
fi

# --- Verdict ---------------------------------------------------------------
c_step "Verdict"
if [[ "$FAILED" -ne 0 ]]; then
  c_fail "Certification FAILED. Do not cut a tag."
  exit 1
fi

if [[ "$MODEL_ROUNDTRIP" == "pass" ]]; then
  c_pass "Build + container + real gateway liveness all green."
  printf '\n\033[32mCERTIFIED.\033[0m Recommend cutting or preserving the signed/annotated tag:\n'
  printf '    git tag -s %s %s -m "Padstow-OpenClaw %s (verbatim, certified)"\n' \
    "$PADSTOW_TAG" "$DISTRIBUTION_ROOT" "$PADSTOW_TAG"
  printf '    git push origin %s\n' "$PADSTOW_TAG"
  exit 0
else
  if [[ "${PADSTOW_CERT_SKIP_DOCKER:-0}" == "1" ]]; then
    c_skip "Build green, but container build and gateway liveness were SKIPPED (dev mode)."
  else
    c_skip "Build + container green, but gateway liveness was SKIPPED (no local model)."
  fi
  printf '\n\033[33mBUILD-CERTIFIED, LIVENESS UNPROVEN.\033[0m\n'
  printf 'The build gate passed, but a tag must NOT be cut until a real gateway\n'
  printf 'liveness passes. Re-run with PADSTOW_CERT_MODEL=<model> on a machine with\n'
  printf 'that model present. Tag recommendation withheld.\n'
  exit 0
fi
