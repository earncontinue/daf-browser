#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — sign the built APK with the DAF release keystore and
# verify the signature.
#
# The keystore NEVER lives in this repository and is never hardcoded here.
# It arrives as GitHub Secrets (base64-encoded keystore + passwords), is
# decoded by the workflow into a temporary file, passed here by path, and
# deleted by the workflow after signing. Locally, pass the keystore path and
# credentials as arguments / environment — never commit them.
#
# A release APK is NEVER signed with the Chromium debug keystore: that
# keystore is checked into Chromium and public, so anything signed with it
# can be replaced by an APK anyone can build (Bare's BUILDING.md). If no
# release keystore is supplied, this script fails clearly instead of
# silently producing a debug-signed "release".
#
# Usage:
#   scripts/package-release.sh <out-dir> <keystore-path> <output-apk>
# Env (required): DAF_KEYSTORE_PASS, DAF_KEY_ALIAS, DAF_KEY_PASS
#   APKSIGNER: path to apksigner (default: apksigner on PATH; the workflow
#   sets it to the Android SDK build-tools binary from the checkout).
# Exit 0 = signed + verified; 1 = error (APK missing, keystore missing, or
#   apksigner failed).
# =============================================================================
set -euo pipefail

[ $# -eq 3 ] || { echo "Usage: $0 <out-dir> <keystore-path> <output-apk>" >&2; exit 2; }
OUT_DIR="$1"
KEYSTORE="$2"
OUTPUT_APK="$3"

APK="$OUT_DIR/apks/ChromePublic.apk"
[ -f "$APK" ] || { echo "ERROR: APK not found: $APK (the build did not produce one)" >&2; exit 1; }
[ -f "$KEYSTORE" ] || {
  echo "ERROR: release keystore not found: $KEYSTORE" >&2
  echo "  Add the DAF release keystore as GitHub Secrets (see BUILDING.md) —" >&2
  echo "  a release APK is never signed with the public Chromium debug key." >&2
  exit 1
}
: "${DAF_KEYSTORE_PASS:?ERROR: DAF_KEYSTORE_PASS is not set}"
: "${DAF_KEY_ALIAS:?ERROR: DAF_KEY_ALIAS is not set}"
: "${DAF_KEY_PASS:?ERROR: DAF_KEY_PASS is not set}"

APKSIGNER="${APKSIGNER:-apksigner}"
command -v "$APKSIGNER" >/dev/null || { echo "ERROR: apksigner not found: $APKSIGNER" >&2; exit 1; }

echo "Signing $APK ..."
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-pass "pass:$DAF_KEYSTORE_PASS" \
  --ks-key-alias "$DAF_KEY_ALIAS" \
  --key-pass "pass:$DAF_KEY_PASS" \
  --out "$OUTPUT_APK" \
  "$APK"

echo "Verifying signature..."
"$APKSIGNER" verify --verbose --print-certs "$OUTPUT_APK"
echo "--- signed APK ---"
ls -lh "$OUTPUT_APK"
sha256sum "$OUTPUT_APK"
echo "PACKAGE-RELEASE: PASS"
