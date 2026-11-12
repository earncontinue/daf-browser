#!/usr/bin/env bash
# =============================================================================
# DAF Browser fork — ONE time-boxed ninja run (a single chained hop's build).
#
# Plain ninja, NOT siso and NOT autoninja. iNWEB proved siso's incremental
# records do not survive an out/ transfer (hops 4-7, ~14 h lost), while plain
# ninja rests on mtime/size restat, which the transferred state satisfies
# (tree mtimes normalised to a fixed epoch by the workflow; out/ artifact
# mtimes preserved by tar).
#
# Two details from iNWEB's hop 13 that this script must not lose:
#  - AUTONINJA_BUILD_ID: Chromium's android build_server steps hard-require
#    it even under plain ninja. With the ID set and no AUTONINJA_STDOUT_NAME,
#    server_utils.MaybeRunCommand falls back to normal local execution.
#  - The exit code is the contract. timeout(1) returns 124 when the time box
#    expires: that is EXPECTED (the hop ran out of time, state is packaged
#    and the chain continues). Any other non-zero exit is a real failure
#    (gn error, compile error, missing input) and must never be reported as
#    a successful hop.
#
# Usage: scripts/build-hop.sh <out-dir> <minutes> [ninja-jobs] [target]
#   out-dir : e.g. chromium/src/out/daf-release
#   minutes : time box for the ninja run (iNWEB used 265 inside a 6 h job)
#   jobs    : ninja -j parallelism (default 6; 4 vCPU / 16 GB — higher risks
#             compile OOM)
#   target  : ninja target (default: chrome_public_apk)
# Env: DRYRUN=1 -> plan only (ninja -n), report the would-build count, no
#   compile and no state change (iNWEB's probe-dryrun).
#
# Exit codes: 0 = target built; 124 = time box expired (expected, continue);
#   1 = real build failure. Prints a BUILD_STATUS= line as its last line.
# =============================================================================
set -uo pipefail

[ $# -ge 2 ] || { echo "Usage: $0 <out-dir> <minutes> [ninja-jobs] [target]" >&2; exit 2; }
OUT_DIR="$1"
MINUTES="$2"
JOBS="${3:-6}"
TARGET="${4:-chrome_public_apk}"

[ -d "$OUT_DIR" ] || { echo "ERROR: out dir not found: $OUT_DIR (run scripts/configure.sh first)" >&2; exit 2; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${DAF_WORKSPACE:-$REPO_ROOT/chromium}"
[ -d "$WORKSPACE/depot_tools" ] && export PATH="$WORKSPACE/depot_tools:$PATH"
command -v ninja >/dev/null || { echo "ERROR: ninja not found (depot_tools not on PATH and no ninja installed)" >&2; exit 2; }

export AUTONINJA_BUILD_ID="${AUTONINJA_BUILD_ID:-daf-${GITHUB_RUN_ID:-local}-$$-$(date +%s)}"
echo "build tool: plain ninja -j $JOBS, target $TARGET, time box ${MINUTES}m"
echo "AUTONINJA_BUILD_ID=$AUTONINJA_BUILD_ID"

if [ "${DRYRUN:-0}" = "1" ]; then
  ninja -C "$OUT_DIR" -n "$TARGET" > "$OUT_DIR/ninja_dryrun.txt"
  echo "ninja dry-run: $(wc -l < "$OUT_DIR/ninja_dryrun.txt") commands would run"
  head -20 "$OUT_DIR/ninja_dryrun.txt"
  echo "BUILD_STATUS=dryrun"
  exit 0
fi

set +e
timeout "${MINUTES}m" ninja -C "$OUT_DIR" -j "$JOBS" "$TARGET"
EC=$?
set -e

if [ "$EC" -eq 0 ]; then
  echo "BUILD_STATUS=ok"
elif [ "$EC" -eq 124 ]; then
  echo "BUILD_STATUS=timeout"
  echo "Time box expired (${MINUTES}m) — expected on a chained hop; state will be packaged and the chain continues."
else
  echo "BUILD_STATUS=failed"
  echo "Build failed with exit code $EC — a real failure, not a timeout."
fi
exit "$EC"
