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

## daf-0002-drop-app-service-dep.patch (run #18 fix)

**Root cause (hinge run #18, 14 Nov 2026):** `gn gen` fails in 4s with
`ERROR at //chrome/browser/apps/app_service/BUILD.gn:7:1: Assertion failed.
assert(!is_android)`, included from `//chrome/test/BUILD.gn:231`. That line
is the deps entry `"//chrome/browser/apps/app_service"` in
`static_library("test_support")`, inside `if (enable_extensions)`. With
`enable_extensions=true` on Android, test_support pulls in the desktop-only
App Service directory, whose BUILD.gn asserts `!is_android` at its top.
Upstream Android (`enable_extensions=false`) never takes the dep; upstream
main removed it (0 bare app_service deps in main's `chrome/test/BUILD.gn`).
The assert itself stays — it is correct for the desktop-only directory.
No Bare patch touches `app_service` or `chrome/test/BUILD.gn` (re-verified
over all 298 patches).

**What the patch does:** removes ONLY that one dep line. The other bare
app_service line (test_support_ui, inside `if (!is_android)`) is untouched
— it is never evaluated on Android. The remaining deps in the
`enable_extensions` block (web_applications, web_package, webapps, ...) are
Android-compatible and stay. Applies AFTER daf-0001 (its diff is against
the daf-0001-patched file); fetch.sh applies daf-patches in filename order.

**Honest limit:** if `gn gen` then fails on a further desktop-only dep,
the run log names it and it gets the same one-line treatment.
