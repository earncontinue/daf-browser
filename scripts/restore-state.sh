#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — verify and extract a previous hop's build state.
#
# The state is the previous hop's out/ directory, transferred as tar.zstd
# split into <=4 GiB parts with a sha256 manifest (see scripts/package-state.sh
# and the workflow's download steps). The download itself is done by the
# workflow (actions/download-artifact with an explicit run-id — the default
# would fetch the CURRENT run's artifacts, which burned iNWEB one 4h41m hop);
# this script verifies and extracts what was downloaded.
#
# Usage: scripts/restore-state.sh <state-dir> <out-parent-dir>
#   state-dir      : directory holding manifest.sha256 + part-* files
#   out-parent-dir : the directory the out/ folder is extracted into
#                    (e.g. chromium/src/out — the tar holds daf-release/)
# Exit 1 on any failure, with a clear message. Never resumes from a state
# whose manifest does not verify.
# =============================================================================
set -euo pipefail

[ $# -eq 2 ] || { echo "Usage: $0 <state-dir> <out-parent-dir>" >&2; exit 2; }
STATE_DIR="$1"
OUT_PARENT="$2"

[ -f "$STATE_DIR/manifest.sha256" ] || { echo "RESUME: FAIL — manifest.sha256 missing in $STATE_DIR" >&2; exit 1; }
ls -lh "$STATE_DIR/" || true

echo "Verifying state manifest..."
(cd "$STATE_DIR" && sha256sum -c manifest.sha256) || {
  echo "RESUME: FAIL — manifest verification failed; refusing to resume from corrupt state" >&2
  exit 1
}

echo "Extracting state..."
cat "$STATE_DIR"/part-* > "$STATE_DIR/state.tar.zst"
mkdir -p "$OUT_PARENT"
tar --zstd -xf "$STATE_DIR/state.tar.zst" -C "$OUT_PARENT"
rm -f "$STATE_DIR/state.tar.zst"

echo "RESUME: PASS"
echo "--- resumed out/ size / object count ---"
du -sh "$OUT_PARENT"/* 2>/dev/null || true
find "$OUT_PARENT" -name '*.o' 2>/dev/null | wc -l
