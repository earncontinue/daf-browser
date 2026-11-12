# BUILDING.md — DAF Browser Chromium fork

How to build the fork, locally and on GitHub Actions. The workflows in
`.github/workflows/` and the scripts in `scripts/` are the same steps in
the same order — the local driver exists so the sequence can be read,
reviewed, and run on a machine that can hold the build.

## Prerequisites

- **Disk: ~100 GB free.** The checkout is ~30 GB; the build output and
  toolchains take the rest. The workflows free disk on the runner first
  (removing the hosted .NET/Android/GHC/CodeQL toolchains — the build uses
  Chromium's own Android SDK from the checkout).
- **RAM: 16 GB** for the link (the stripped release link needs 4–6 GB
  with `concurrent_links=1`; the CI adds 14 GiB of swap on top).
- **OS: Ubuntu 24.04** (the CI runner image; the local driver assumes
  the same).
- **Tools:** `git`, `python3`, `curl`, `tar`, `zstd`, `ninja` (depot_tools
  provides `gn` and `ninja` after the fetch), and `sudo` for
  `install-build-deps.sh`.

## The CI path (the $0 path)

1. **Create a public GitHub repository** and push these files to it.
   The repo must be **public**: a private repo gets 2,000 free minutes a
   month, and one chained build is ~2,700 minutes. Public repos get
   unlimited free minutes on the standard runners.
2. **Run the hinge** (Actions → "Hinge — stripped release link on a free
   runner" → Run workflow). Read its `daf-verdict` artifact:
   `HINGE_PASSED` (proven), `HINGE_TIMEOUT` (expected — go to step 3),
   or `HINGE_DEAD` (stop; the $0 path is dead in this form).
3. **Run the chain, one hop at a time** (Actions → "DAF fork — chained
   release build" → Run workflow) with `prev_run_id` = the hinge run's ID
   (hop 1) or the previous hop's run ID, and `hop_number` = this hop's
   number. Each hop resumes from the previous hop's state and builds for
   ~265 minutes. Never run two hops in parallel.
4. **The final hop produces the APK.** If the keystore secrets are set it
   is signed; otherwise it is uploaded unsigned and the verdict says so.

## The local path

`scripts/build.sh` runs the same steps in the same order:
fetch → install-build-deps → configure → chained hops → package + sign.

It **does not run in the authoring sandbox** (no disk or RAM for a
Chromium checkout). Run it on a machine with ~100 GB free and 16 GB RAM.
It refuses to run a full local build until `HINGE_PASSED` exists in the
repository root, unless `DAF_ALLOW_UNHINGED=1` is set explicitly for
review — the hinge is what proves the $0 path, and a local full build
before it passes would be work on an unproven path.

Locally the `out/` directory persists between hops, so there is no
artifact round-trip: `ninja` resumes from `out/` directly. Signing
needs the keystore by path:

```sh
DAF_KEYSTORE_PATH=/path/to/daf-release.keystore \
DAF_KEYSTORE_PASS='...' DAF_KEY_ALIAS='...' DAF_KEY_PASS='...' \
bash scripts/build.sh
```

Never commit the keystore or the credentials.

## Signing secrets (GitHub)

The release keystore never lives in this repository. Add four repository
secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `DAF_RELEASE_KEYSTORE_BASE64` | The release keystore file, base64-encoded (`base64 -w0 keystore.jks`) |
| `DAF_KEYSTORE_PASS` | The keystore password |
| `DAF_KEY_ALIAS` | The key alias |
| `DAF_KEY_PASS` | The key password |

The workflow decodes the keystore into a temporary file, signs with it,
and deletes it in the same step. A release APK is **never** signed with
the Chromium debug keystore (it is checked into Chromium and public).

## Versioning

`VERSION` holds `MAJOR.MINOR.PATCH.BUILD` (DAF's own numbering, following
Bare's convention of a plain `VERSION` file). `scripts/configure.sh`
derives the Android version from it:

- `versionName` = `MAJOR.MINOR.PATCH`
- `versionCode` = 100000000 + MAJOR×1,000,000 + MINOR×10,000 + PATCH×100
  + BUILD×10 + 5, where 5 is Chromium's own ABI digit for arm64.
  The base (100000000) is DAF's own, so DAF's version codes never collide
  with Bare's (base 800000000).

The overrides are appended to `out/daf-release/args.gn` and `gn gen` is
re-run — Bare's documented flow, no patch needed for versioning.

## The state scheme (how the chain resumes)

Each hop's `out/` directory is the build state. It is transferred as:

- `tar --zstd` of the `out/` folder, split into **≤4 GiB parts**
  (`part-00` … `part-07`), each uploaded as its own artifact
  (`daf-state-part-NN`), plus a `manifest.sha256` artifact.
- **8-part cap (32 GiB).** More than 8 parts means the state no longer
  fits the upload scheme — that is a BLOCKED hop (exit 2 from
  `scripts/package-state.sh`), reported as `HINGE_BLOCKED` / `HOP_BLOCKED`,
  and the chain stops. It is not silently truncated.
- The next hop downloads the parts + manifest **from the previous run's
  ID** (`actions/download-artifact` with an explicit `run-id` — the
  default would fetch the *current* run's artifacts, which burned iNWEB
  one 4h41m hop), verifies the manifest with `sha256sum -c`, and extracts
  into `chromium/src/out/`. A state whose manifest does not verify is
  never resumed from.

## Why plain ninja, and the details that must not be lost

These come from iNWEB's proven recipe (their `b001-build-hop.yml`,
14 chained hops, ~45 h). Each one cost them a hop when it was wrong:

- **Plain ninja, NOT siso and NOT autoninja.** siso's incremental
  records do not survive an `out/` transfer (hops 4–7, ~14 h lost).
  Plain ninja rests on mtime/size restat, which the transferred state
  satisfies.
- **`AUTONINJA_BUILD_ID` is required even under plain ninja.**
  Chromium's Android build_server steps hard-require it; with the ID set
  and no `AUTONINJA_STDOUT_NAME`, the server steps fall back to normal
  local execution. `scripts/build-hop.sh` sets it.
- **Mtime normalisation to 2020-01-01.** A freshly cloned tree has every
  file stamped "now", which makes ninja rebuild everything on a resume
  hop. The workflows normalise the tree (excluding `.git`) before the
  state is restored, so the transferred `out/` artifacts stay newer.
  The normalisation runs *before* the restore — never after.
- **`-j6` + 14 GiB swap** on the 4 vCPU / 16 GB runner. Higher
  parallelism risks compile OOM.
- **Shallow fetch.** `fetch --no-history android`, then
  `gclient sync --no-history --shallow`. The pinned commit is fetched
  with `git fetch --depth 1 origin <commit>`.
- **depot_tools pinned** to `73fc5a4d6bd051f1fd58404e62dfb83f734b0cfa`
  (iNWEB's validated pin), bootstrapped with `ensure_bootstrap` without
  updating it (the first real fetch failed with
  `python3_bin_reldir.txt not found` until this was added).
- **The exit code is the contract.** `timeout(1)` returns 124 when the
  time box expires — expected, the chain continues. Any other non-zero
  exit is a real failure and must never be reported as a successful hop.
  `scripts/build-hop.sh` exits 0 / 124 / 1 and prints a `BUILD_STATUS=`
  line.

## The minimal release config

`build/args.gn` (arm64-only, stripped release):

```
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_component_build = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
use_thin_lto = false
chrome_pgo_phase = 0
concurrent_links = 1
enable_extensions = true
is_official_build = false
```

Link budgets (from Chromium's `concurrent_links.gni`): a stripped
release link needs 4–6 GB; a debug link 25 GB; an official ThinLTO link
30–60 GB. That is why the hinge exists: if the stripped release link
does not fit a free runner, the $0 path is dead.

## Failure modes

| Symptom | Meaning | What to do |
|---|---|---|
| `HINGE_DEAD` / `HOP_FAILED` | A real build failure (not a timeout) | Read the uploaded build log. Do not resume — re-running the same step fails again. Fix the cause, then re-run the hinge. |
| `HINGE_BLOCKED` / `HOP_BLOCKED` | The state exceeds 8 parts (32 GiB) | The state no longer fits the artifact scheme. The $0 path is blocked in this form; the state scheme has to change (fewer objects, or a different transfer). |
| Manifest verification fails on restore | Corrupt or incomplete state transfer | The hop refuses to resume. Re-run the previous hop (its state is still in its run's artifacts) or restart from the hinge. |
| `fetch.sh` fails on the uBlock `.crx` | Bare's bundled extension asset is absent | See `patches/README.md` — the fork must decide on bundled extensions before the build can proceed with Bare's series as-is. |
| `gn gen` fails on the base config | The config or the checkout is wrong | The configure step exits 4. Check the GN args against `build/args.gn` and the Chromium commit in `config/chromium/BASELINE`. |
