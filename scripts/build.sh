#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — LOCAL driver: fetch -> deps -> configure -> chained hops
# -> package + sign. The same order the GitHub workflows run, for review and
# for a real build host.
#
# THIS DOES NOT RUN IN THE AUTHORING SANDBOX. A Chromium checkout needs
# ~100 GB free and the link needs ~16 GB RAM; the sandbox has neither. This
# script exists so the exact sequence can be read, reviewed, and run on a
# machine that can hold the build — and so the CI workflows and the local
# path never drift apart (both call the same scripts/fetch.sh,
# scripts/configure.sh and scripts/build-hop.sh).
#
# The hinge gate applies here too: a full local build refuses to run until
# HINGE_PASSED exists in the repository root, unless DAF_ALLOW_UNHINGED=1
# is set explicitly for review. The hinge is what proves the $0 path; a
# local full build before it passes would be work on an unproven path.
#
# Signing: the release keystore is passed by path, never committed.
#   DAF_KEYSTORE_PATH, DAF_KEYSTORE_PASS, DAF_KEY_ALIAS, DAF_KEY_PASS
#   (all required at the packaging step; see scripts/package-release.sh)
# Env: HOP_MINUTES (default 265), NINJA_JOBS (default 6), DAF_WORKSPACE.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f HINGE_PASSED ] && [ "${DAF_ALLOW_UNHINGED:-0}" != "1" ]; then
  echo "BLOCKED: the hinge has not passed (no HINGE_PASSED in the repo root)." >&2
  echo "  Run the hinge workflow first (.github/workflows/hinge.yml)." >&2
  echo "  To review this driver without the gate, set DAF_ALLOW_UNHINGED=1." >&2
  exit 1
fi

WORKSPACE="${DAF_WORKSPACE:-$REPO_ROOT/chromium}"
OUT_DIR="$WORKSPACE/chromium/src/out/daf-release"
HOP_MINUTES="${HOP_MINUTES:-265}"
JOBS="${NINJA_JOBS:-6}"

echo "=== 1. fetch (Chromium at the pinned commit + Bare patches) ==="
bash scripts/fetch.sh

echo "=== 2. install Android build dependencies (needs sudo on Ubuntu) ==="
sudo bash "$WORKSPACE/chromium/src/build/install-build-deps.sh" --android --no-arm

echo "=== 3. configure (gn gen, minimal release config) ==="
bash scripts/configure.sh

echo "=== 4. chained hops (time-boxed ninja, state stays in out/) ==="
echo "  Locally the out/ directory persists between hops, so there is no"
echo "  artifact round-trip: ninja resumes from out/ directly."
HOP=0
while true; do
  HOP=$((HOP + 1))
  echo "--- hop $HOP (time box ${HOP_MINUTES}m) ---"
  set +e
  bash scripts/build-hop.sh "$OUT_DIR" "$HOP_MINUTES" "$JOBS"
  EC=$?
  set -e
  if [ "$EC" -eq 0 ]; then
    if [ -f "$OUT_DIR/apks/ChromePublic.apk" ]; then
      echo "=== 5. package + sign ==="
      : "${DAF_KEYSTORE_PATH:?ERROR: DAF_KEYSTORE_PATH is not set (see scripts/package-release.sh)}"
      MAJOR="$(sed -n 's/^MAJOR=//p' VERSION | tr -d '[:space:]')"
      MINOR="$(sed -n 's/^MINOR=//p' VERSION | tr -d '[:space:]')"
      PATCH="$(sed -n 's/^PATCH=//p' VERSION | tr -d '[:space:]')"
      bash scripts/package-release.sh "$OUT_DIR" "$DAF_KEYSTORE_PATH" \
        "DAF-Browser-fork-$MAJOR.$MINOR.$PATCH-arm64.apk"
      echo "BUILD: PASS — signed APK ready."
      exit 0
    fi
    echo "ninja exited 0 but no APK was produced — investigate before continuing." >&2
    exit 1
  elif [ "$EC" -eq 124 ]; then
    echo "Hop $HOP timed out — resuming from out/ (persistent locally)."
    continue
  else
    echo "Build failed with exit code $EC — see the log above." >&2
    exit 1
  fi
done
