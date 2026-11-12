#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — configure the build (gn gen) with the minimal release
# config, plus DAF's own version overrides.
#
# Follows Bare Browser's BUILDING.md: android_override_version_code and
# android_override_version_name are plain declare_args in
# build/config/android/config.gni. They are appended to out/<dir>/args.gn
# and gn gen is re-run; no patch is needed for versioning.
#
# Run from the repository root, after scripts/fetch.sh.
# Usage: scripts/configure.sh [out-dir-name]   (default: daf-release)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$REPO_ROOT/config/chromium/BASELINE" ] || { echo "ERROR: run from the repository root" >&2; exit 2; }
[ -f "$REPO_ROOT/build/args.gn" ] || { echo "ERROR: build/args.gn not found" >&2; exit 2; }

WORKSPACE="${DAF_WORKSPACE:-$REPO_ROOT/chromium}"
OUT_NAME="${1:-daf-release}"
OUT_DIR="$WORKSPACE/chromium/src/out/$OUT_NAME"

[ -d "$WORKSPACE/chromium/src" ] || { echo "ERROR: Chromium tree not found — run scripts/fetch.sh first" >&2; exit 2; }
[ -d "$WORKSPACE/depot_tools" ] && export PATH="$WORKSPACE/depot_tools:$PATH"
command -v gn >/dev/null || { echo "ERROR: gn not found (depot_tools not on PATH and no gn installed)" >&2; exit 2; }

# --- DAF version (VERSION file; Bare's convention) ---------------------------
MAJOR="$(sed -n 's/^MAJOR=//p' "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
MINOR="$(sed -n 's/^MINOR=//p' "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
PATCH="$(sed -n 's/^PATCH=//p' "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
BUILD="$(sed -n 's/^BUILD=//p' "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
[ -n "$MAJOR" ] && [ -n "$MINOR" ] && [ -n "$PATCH" ] && [ -n "$BUILD" ] || { echo "ERROR: VERSION is missing MAJOR/MINOR/PATCH/BUILD" >&2; exit 2; }

# Version code: DAF's own base (100000000) + MAJOR*1000000 + MINOR*10000 +
# PATCH*100 + BUILD*10 + ABI, where ABI is Chromium's own digit (5 = arm64).
# The formula shape follows Bare's (their base is 800000000 for Bare's own
# numbering); DAF uses its own base so the two products never collide.
# versionName is MAJOR.MINOR.PATCH.
VERSION_CODE=$((100000000 + MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + BUILD * 10 + 5))
VERSION_NAME="$MAJOR.$MINOR.$PATCH"
echo "DAF version: $VERSION_NAME (versionCode $VERSION_CODE, arm64)"

# --- gn gen ------------------------------------------------------------------
# Step 1: generate with the base config in build/args.gn.
gn gen "$OUT_DIR" --args="$(cat "$REPO_ROOT/build/args.gn")" || {
  echo "FATAL: gn gen failed on the base config (see the error above)" >&2
  exit 4
}
# Step 2: append the version overrides and re-generate (Bare's documented flow).
{
  echo ""
  echo "# DAF version overrides (appended by scripts/configure.sh from VERSION)."
  echo "android_override_version_code = $VERSION_CODE"
  echo "android_override_version_name = \"$VERSION_NAME\""
} >> "$OUT_DIR/args.gn"
gn gen "$OUT_DIR" || {
  echo "FATAL: gn gen failed after appending the version overrides" >&2
  exit 4
}

# --- verify the args that decide the hinge -----------------------------------
echo "--- args that decide the hinge (must read as below) ---"
gn args "$OUT_DIR" --list --short 2>/dev/null | grep -E "^(target_os|target_cpu|is_debug|is_component_build|symbol_level|blink_symbol_level|v8_symbol_level|use_thin_lto|chrome_pgo_phase|concurrent_links|enable_extensions|is_official_build|android_override_version_code|android_override_version_name) = " || echo "(warning: could not list args — check the gn version)"
echo "CONFIGURE: PASS (out dir: $OUT_DIR)"
