#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — package the current out/ directory as resumable state
# for the next chained hop.
#
# Modelled on iNWEB's verdict packaging: tar.zstd the out/ folder, split
# into <=4 GiB parts, sha256 manifest. mtimes are preserved by tar, which is
# what makes plain ninja resume cleanly on the next hop (the tree mtimes are
# normalised to a fixed epoch by the workflow; out/ artifact mtimes must
# survive the transfer untouched).
#
# The 8-part cap (32 GiB) is iNWEB's: their workflow uploads part-00..07 as
# separate artifacts. More than 8 parts means the state no longer fits the
# upload scheme — that is a BLOCKED hop, not a failed build, and it must be
# reported as such (exit 2), never silently truncated.
#
# Usage: scripts/package-state.sh <out-dir> <state-out-dir>
#   out-dir       : e.g. chromium/src/out/daf-release
#   state-out-dir : directory to write part-* + manifest.sha256 into
# Exit 0 = packaged; 2 = BLOCKED (too many parts); 1 = error.
# =============================================================================
set -euo pipefail

[ $# -eq 2 ] || { echo "Usage: $0 <out-dir> <state-out-dir>" >&2; exit 2; }
OUT_DIR="$1"
STATE_OUT="$2"

[ -d "$OUT_DIR" ] || { echo "ERROR: out dir not found: $OUT_DIR" >&2; exit 1; }
OUT_PARENT="$(dirname "$OUT_DIR")"
OUT_NAME="$(basename "$OUT_DIR")"

mkdir -p "$STATE_OUT"
echo "Packaging $OUT_DIR as resumable state..."
tar --zstd -cf "$STATE_OUT/state.tar.zst" -C "$OUT_PARENT" "$OUT_NAME"
split -b 4G -d "$STATE_OUT/state.tar.zst" "$STATE_OUT/part-"
rm -f "$STATE_OUT/state.tar.zst"
(cd "$STATE_OUT" && sha256sum part-* > manifest.sha256)
N="$(ls "$STATE_OUT"/part-* 2>/dev/null | wc -l)"
echo "state parts: $N (4 GiB each)"
ls -lh "$STATE_OUT/"

if [ "$N" -gt 8 ]; then
  echo "STATE: BLOCKED — $N parts exceed the 8-part (32 GiB) upload capacity" >&2
  echo "  The state no longer fits the artifact scheme. Do not proceed: the" >&2
  echo "  next hop would have no state to resume from." >&2
  exit 2
fi
echo "STATE: PACKAGED ($N parts)"
exit 0
