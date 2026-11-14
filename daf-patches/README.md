# DAF's own patches — applied after the Bare series

This directory holds **DAF's own patches**: fixes that neither upstream nor
Bare has made at the pinned revision. They are applied by `scripts/fetch.sh`
(step 5b), after the Bare series, with the same mechanism
(`git apply --index` in the Chromium checkout). A DAF patch that conflicts
with a Bare patch fails there, clearly, instead of hours later at build time.

The Bare series itself is NOT vendored here (see `patches/README.md` — the
298 Bare patches are fetched from the Bare repository at build time). DAF
patches are few and fork-specific, so they live in this repo.

## daf-0001-remove-circular-includes-usages.patch (run #17 fix)

**Root cause (hinge run #17, 13 Nov 2026):** `gn gen` fails at
`//chrome/test/BUILD.gn:3620` — "Usage of allow_circular_includes_from is
not allowed here". The usage sits in `test("unit_tests")`. On Android the
`test()` template expands it into a shared_library named
`unit_tests__library` (`testing/test.gni:546`), forwarding the annotation.
GN validates the EXPANDED label against
`allow_circular_includes_from_allowlist` (`.gn`), and the allowlist holds
`//chrome/test:unit_tests` but not `//chrome/test:unit_tests__library`.

**What was ruled out (all verified from pinned sources, 14 Nov 2026):**
- No Bare patch touches `chrome/test/BUILD.gn`, the `.gni` allowlists,
  `.gn`, `BUILDCONFIG.gn`, or anything under `build/` (grep over all 298
  patches at `c98b94e`).
- The pinned tree is pristine upstream: line 3620 IS the usage upstream,
  and `//chrome/test:unit_tests` IS in the allowlist (line 215).
- The gn binary is the DEPS-pinned CIPD gn (`buildtools/linux64/gn`,
  `gn_version` `git_revision:00359618…`) — confirmed from run #17's log.
- So the pinned commit is in a broken window for Android `gn gen`, and
  upstream fixed it the same way: current main has zero
  `allow_circular_includes_from` usages in `chrome/test/BUILD.gn` and none
  of the five entries in `build/circular_includes_untriaged.gni`.

**What the patch does:** removes all 11 usages from `chrome/test/BUILD.gn`
(the failing one is `unit_tests:3620`; the rest are removed in the same
pass to match upstream main) and the 5 matching allowlist entries
(`browser_tests`, `interactive_ui_tests`, `test_support`,
`test_support_ui`, `unit_tests`). `chrome_test_utils` stays. The annotation
only affects `gn check`, never compilation, so the removal cannot break the
ninja build. `gn check --fix` was not run (no checkout here) — upstream
main is the reference.

**Honest limit:** if `gn gen` then fails at the next file with the same
error (another `test()` usage elsewhere in the tree), that file gets the
same treatment in a follow-up DAF patch — the run log names it.
