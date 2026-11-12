#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — fetch the Chromium tree at the pinned revision and apply
# the Bare Browser patch series.
#
# Modelled on iNWEB-Browser's scripts/fetch_chromium.sh (proven on a GitHub
# runner) and Bare Browser's docs/patches.md + BUILDING.md (both read in full).
#
# Run from the repository root. Idempotent: if the tree is already at the
# pinned commit and the patches are already applied (marker file), it
# verifies and exits 0 instead of re-fetching.
#
# Layout (all under $WORKSPACE, default $PWD/chromium; gitignored, never
# committed):
#   $WORKSPACE/depot_tools     pinned depot_tools (iNWEB's validated pin)
#   $WORKSPACE/chromium/src    Chromium checkout at the pinned commit
#   $WORKSPACE/bare            Bare Browser clone at the pinned revision
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$REPO_ROOT/config/chromium/BASELINE" ] || { echo "ERROR: run from the repository root (config/chromium/BASELINE not found)" >&2; exit 2; }
[ -f "$REPO_ROOT/build/args.gn" ] || { echo "ERROR: run from the repository root (build/args.gn not found)" >&2; exit 2; }

WORKSPACE="${DAF_WORKSPACE:-$REPO_ROOT/chromium}"
MARKER="$WORKSPACE/.daf-fetch-done"

# --- pinned revisions (single source of truth: config/chromium/BASELINE) -----
CHROMIUM_VERSION="$(sed -n 's/^CHROMIUM_VERSION=//p' "$REPO_ROOT/config/chromium/BASELINE" | tr -d '[:space:]')"
CHROMIUM_COMMIT="$(sed -n 's/^CHROMIUM_COMMIT=//p' "$REPO_ROOT/config/chromium/BASELINE" | tr -d '[:space:]')"
BARE_REPO="$(sed -n 's/^BARE_REPO=//p' "$REPO_ROOT/config/chromium/BASELINE" | tr -d '[:space:]')"
BARE_REV="$(sed -n 's/^BARE_REV=//p' "$REPO_ROOT/config/chromium/BASELINE" | tr -d '[:space:]')"
BARE_PATCHES="$(sed -n 's/^BARE_PATCHES=//p' "$REPO_ROOT/config/chromium/BASELINE" | tr -d '[:space:]')"
[ -n "$CHROMIUM_COMMIT" ] && [ -n "$BARE_REPO" ] && [ -n "$BARE_REV" ] || { echo "ERROR: BASELINE is missing CHROMIUM_COMMIT / BARE_REPO / BARE_REV" >&2; exit 2; }

# depot_tools pinned revision — iNWEB's validated pin (their fetch ran on a
# GitHub-hosted runner with this exact revision).
DEPOT_TOOLS_URL="https://chromium.googlesource.com/chromium/tools/depot_tools.git"
DEPOT_TOOLS_PINNED_REV="73fc5a4d6bd051f1fd58404e62dfb83f734b0cfa"

command -v git >/dev/null || { echo "ERROR: git is required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 2; }

echo "DAF pinned Chromium: $CHROMIUM_VERSION ($CHROMIUM_COMMIT)"
echo "DAF pinned Bare revision: $BARE_REV"

# --- idempotency: already fetched + patched? ---------------------------------
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$CHROMIUM_COMMIT:$BARE_REV" ]; then
  echo "Fetch already done for $CHROMIUM_COMMIT:$BARE_REV — verifying only."
  HEAD_SHA="$(git -C "$WORKSPACE/chromium/src" rev-parse HEAD 2>/dev/null || echo none)"
  [ "$HEAD_SHA" = "$CHROMIUM_COMMIT" ] || { echo "ERROR: marker present but HEAD is $HEAD_SHA, expected $CHROMIUM_COMMIT" >&2; exit 1; }
  echo "FETCH: VERIFIED (already done)"
  exit 0
fi

mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# --- 1. depot_tools at the pinned revision ------------------------------------
if [ ! -d depot_tools ]; then
  echo "Cloning depot_tools..."
  git clone "$DEPOT_TOOLS_URL" depot_tools
fi
(
  cd depot_tools
  git fetch origin main --quiet
  git checkout --quiet "$DEPOT_TOOLS_PINNED_REV"
)
export PATH="$WORKSPACE/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0
export DEPOT_TOOLS_METRICS=0
# Bootstrap the pinned depot_tools (CIPD-managed python + wrappers) WITHOUT
# updating it. (iNWEB: the first real fetch failed with
# "python3_bin_reldir.txt not found" until this bootstrap was added.)
( cd depot_tools && ./ensure_bootstrap )

# --- 2. Chromium checkout at the pinned commit -------------------------------
# `fetch --nohooks android` is the upstream-documented entry point. The tree
# is then moved to the pinned commit and DEPS are synced shallow, so the
# checkout stays as small as a full Chromium tree can be (~30 GB; the
# 100 GB floor in the docs covers checkout + build output + toolchains).
if [ ! -d chromium/src ]; then
  echo "Fetching Chromium (this is the long step)..."
  fetch --no-history --nohooks android
fi
cd chromium/src
git fetch --depth 1 origin "$CHROMIUM_COMMIT" --quiet
git checkout --quiet "$CHROMIUM_COMMIT"
echo "Checked out Chromium $CHROMIUM_COMMIT"
gclient sync --no-history --shallow --nohooks
gclient runhooks
cd "$WORKSPACE"

# --- 3. Bare Browser clone at the pinned revision ----------------------------
if [ ! -d bare ]; then
  echo "Cloning Bare Browser..."
  git clone "$BARE_REPO" bare
fi
(
  cd bare
  git fetch origin "$BARE_REV" --quiet
  git checkout --quiet "$BARE_REV"
)
echo "Checked out Bare $BARE_REV"

# --- 4. Bundled uBlock Origin asset (Bare's BUILDING.md) ----------------------
# Bare ships uBlock Origin inside its APK. The .crx is kept out of the patch
# series and must be copied into the Chromium tree before building; without
# it the assets target has no input and the build fails at packaging.
# Fail here, clearly, if it is absent — never hours later at packaging.
UBLOCK_SRC="$WORKSPACE/bare/third_party/ublock_origin/uBlockOrigin-1.75.0.crx"
UBLOCK_DST="$WORKSPACE/chromium/src/chrome/browser/resources/bare/ublock_origin.crx"
[ -s "$UBLOCK_SRC" ] || {
  echo "ERROR: bundled uBlock .crx not found at $UBLOCK_SRC" >&2
  echo "  The DAF fork must decide on bundled extensions (see patches/README.md)." >&2
  echo "  Until then the build cannot proceed with Bare's series as-is." >&2
  exit 1
}
mkdir -p "$(dirname "$UBLOCK_DST")"
cp "$UBLOCK_SRC" "$UBLOCK_DST"
echo "Bundled uBlock .crx copied ($(stat -c%s "$UBLOCK_DST") bytes)"

# --- 5. Apply the Bare patch series ------------------------------------------
# From a clean Chromium checkout at the pinned revision, in one command.
# Use `git apply`, not `git am`: the files from 0000195.patch on are plain
# diffs without a mail header, which `git am` rejects. (Bare docs/patches.md)
PATCH_COUNT="$(ls "$WORKSPACE/bare/patches/"*.patch 2>/dev/null | wc -l)"
[ "$PATCH_COUNT" = "$BARE_PATCHES" ] || {
  echo "ERROR: expected $BARE_PATCHES patches, found $PATCH_COUNT in bare/patches/" >&2
  exit 1
}
echo "Applying $PATCH_COUNT Bare patches..."
(
  cd "$WORKSPACE/chromium/src"
  git apply --index "$WORKSPACE/bare/patches/"*.patch
)
echo "Patches applied (staged, not committed)."

# --- 6. Verify ---------------------------------------------------------------
HEAD_SHA="$(git -C "$WORKSPACE/chromium/src" rev-parse HEAD)"
VERSION="$(sed -n 's/^MAJOR=//p;s/^MINOR=//p;s/^BUILD=//p;s/^PATCH=//p' "$WORKSPACE/chromium/src/chrome/VERSION" 2>/dev/null | paste -sd. || true)"
STAGED="$(git -C "$WORKSPACE/chromium/src" diff --cached --numstat | wc -l)"
echo "HEAD=$HEAD_SHA chrome_version=$VERSION staged_files=$STAGED"
[ "$HEAD_SHA" = "$CHROMIUM_COMMIT" ] || { echo "ERROR: HEAD is $HEAD_SHA, expected $CHROMIUM_COMMIT" >&2; exit 1; }
[ "$VERSION" = "$CHROMIUM_VERSION" ] || { echo "ERROR: chrome/VERSION is $VERSION, expected $CHROMIUM_VERSION" >&2; exit 1; }
[ "$STAGED" -gt 0 ] || { echo "ERROR: no staged changes after applying the patch series" >&2; exit 1; }

echo "$CHROMIUM_COMMIT:$BARE_REV" > "$MARKER"
echo "FETCH: PASS"
