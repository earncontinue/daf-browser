# DAF Browser — Chromium fork ($0 experiment)

A Chromium fork that builds `chrome_public_apk` with extensions enabled,
at **$0 on GitHub Actions free runners**. The goal is a real extension
browser for Android — the thing the current DAF Browser app (a WebView shim)
cannot be.

**Status: EXPERIMENT. No date is promised.** The hinge (below) is unproven
and the release build is unproven. This repository is the scaffolding for
the experiment: the CI workflows, the build scripts, and the pinned
configuration. No build has run yet.

The current DAF Browser app (WebView shim, `com.dafbrowser.app`) is a
separate codebase and is **not** part of this repository. Nothing from it
is copied here, and nothing here touches it.

## The hinge

The hinge is the first milestone and the gate for everything else. It
proves one thing: **the stripped release link of `chrome_public_apk`
completes on a GitHub free runner** (4 vCPU / 16 GB RAM, 6-hour job cap).

Run it from the Actions tab: **"Hinge — stripped release link on a free
runner" → Run workflow**. It fetches Chromium at the pinned commit,
applies the Bare patch series, configures the minimal release build
(arm64-only), and builds `chrome_public_apk` in one job with a 265-minute
time box.

Three outcomes (the verdict is uploaded as the `daf-verdict` artifact):

| Verdict | Meaning |
|---|---|
| `HINGE_PASSED` | The link completed on a free runner. The $0 path is **proven**. The APK is signed (if the keystore secrets exist) and uploaded. |
| `HINGE_TIMEOUT` | The 265-minute time box expired before the link finished. **Expected** for a full Chromium build — iNWEB needed 14 chained hops. Not a failure, not dead: the partial state is packaged and the chained build resumes from it. |
| `HINGE_DEAD` | A real build failure (not a timeout), or the state no longer fits the upload scheme (`HINGE_BLOCKED`). The $0 path is **dead in this form**. The chained build workflow refuses to run. |

## After the hinge

**If the hinge passes:** the APK is in the hinge run's artifacts
(`daf-release-apk`, signed if the secrets exist). No chain is needed for
this version.

**If the hinge times out (the expected case):** run the chained build,
one hop at a time, from the Actions tab: **"DAF fork — chained release
build" → Run workflow**, with `prev_run_id` = the run ID of the hinge run
(hop 1) or of the previous hop, and `hop_number` = this hop's number.
Each hop builds for ~265 minutes, packages `out/` as state, and the next
hop resumes from it. Never run two hops in parallel — the state would fork.
The chain's final hop produces the APK; its link completing is the same
proof the hinge was after.

**Signing:** a release APK is never signed with the Chromium debug
keystore (it is checked into Chromium and public — anyone could replace
the APK). Add these four repository secrets first (see BUILDING.md):
`DAF_RELEASE_KEYSTORE_BASE64`, `DAF_KEYSTORE_PASS`, `DAF_KEY_ALIAS`,
`DAF_KEY_PASS`. Without them the workflow uploads the APK unsigned and
says so in the verdict.

**Publishing:** the signed APK is a workflow artifact. Creating the
GitHub Release and attaching it is a manual step for now.

## The patch series

The starting reference is the **Bare Browser** patch series
([BareBrowser/bare-browser](https://github.com/BareBrowser/bare-browser),
branch `main`, pinned revision `c98b94e77781f9d6c3bb42af3a34664f22b4c45d`,
Chromium 157.0.8103.46, 298 patches). The pins live in
`config/chromium/BASELINE`. Bare's patches are applied with
`git apply --index` (not `git am` — the files from `0000195.patch` on are
plain diffs). Bare's bundled uBlock Origin `.crx` must be copied into the
tree before building; the fetch script fails clearly if it is absent.

This repo does **not** vendor Bare's patches — they are fetched from the
Bare clone at the pinned revision during the build. See
`patches/README.md` for the policy on DAF's own patches.

## Repo layout

```
.github/workflows/hinge.yml   the hinge (runs first, gates everything)
.github/workflows/build.yml   the chained release build (one hop per run)
scripts/fetch.sh               Chromium at the pinned commit + Bare patches
scripts/configure.sh           gn gen, minimal release config + DAF version
scripts/build-hop.sh           one time-boxed ninja run (plain ninja, -j6)
scripts/restore-state.sh       verify + extract a previous hop's state
scripts/package-state.sh       package out/ as state (<=4 GiB parts + manifest)
scripts/package-release.sh     sign the APK with the DAF release keystore
scripts/build.sh               local driver: same steps, same order (see BUILDING.md)
config/chromium/BASELINE       pinned Chromium + Bare revisions (single source of truth)
build/args.gn                  the minimal release GN config
VERSION                        DAF version (MAJOR.MINOR.PATCH.BUILD)
patches/README.md              patch policy
BUILDING.md                    full build documentation
```

## Open questions

- **Stripped config + `is_official_build=true`?** The hinge tests the
  stripped, non-official release config (`is_official_build = false`).
  Whether GN accepts this stripped config WITH `is_official_build=true`
  is a separate, later experiment — it is NOT what the hinge answers.
- **Cost of `enable_extensions=true`?** No source was found for what
  this flag costs in build time or RAM. The hinge measures the real
  build; it does not assume the cost.
- **Artifact storage on a public repo.** The state scheme assumes the
  state parts upload and survive 90 days. The first chained hop will
  confirm or refute that.

## Honest limits

- **No date promised.** A Chromium build is months of engineering after
  the repo and CI exist; the hinge is unproven.
- **Public repository = visible source and patches.** This repo must be
  public for the free minutes. Everything in it is visible to everyone.
- **Rebase every 2 weeks.** Chromium moves fast; the patch series is
  rebased onto each new stable (Cobalt measured a 58% conflict rate for
  a 4-weekly cadence on a similar series).
- **$0 only.** No paid runner, no paid service, no trial that costs money
  later. If the link does not fit a free runner, the $0 path is dead.
- **The build is unproven.** The workflows are written from iNWEB's
  proven recipe and Bare's documented build, but no DAF build has run.
  The first run will find things this scaffolding got wrong.
