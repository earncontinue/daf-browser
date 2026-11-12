# The patch series — fetched, not vendored

This directory holds **no patch files**. The patch series is fetched from the
Bare Browser repository at build time, at the exact revision pinned in
`config/chromium/BASELINE`, and applied to a clean Chromium checkout.

## Why not vendored

- The series is 298 files / ~47,000 insertions across 873 files (Bare 2.0.3).
  Vendoring it would duplicate Bare's repository inside this one and freeze
  the copy the moment Bare moves.
- The reference is a revision, not a copy: `BARE_REV` in
  `config/chromium/BASELINE` names the exact commit the fork was verified
  against. A rebase decision changes that one line, and the fetch script
  pulls the new revision.

## The pinned reference (verified live, 12 Nov 2026)

- Repository: https://github.com/BareBrowser/bare-browser
  (HTTP 200; default branch `main`; BSD-3-Clause; not archived)
- Pinned revision: `c98b94e77781f9d6c3bb42af3a34664f22b4c45d`
  (main, 2026-11-12T15:30:31Z, "barefilter-contributing")
- Bare version: 2.0.3. Chromium base: 157.0.8103.46
  (commit `800628ad1ca1fd0c51e3b43b5b2bca081e81c3f6`).
- Series: `patches/0000001.patch` … `patches/0000326.patch`, 298 files,
  numbered in the order they apply (verified by listing the directory:
  298 unique files, first `0000001.patch`, last `0000326.patch`).

## Gaps in the numbering (from Bare's docs/patches.md, read in full)

- `0000210.patch` is not in the series: that number belongs to the Google
  Play build, which compiles the update check out. The GitHub build keeps
  the check.
- `0000117.patch` is also missing: Chromium 157 removed the code it changed.
- `0000298.patch` to `0000323.patch` are not in this series either; those
  numbers belong to the 2.1 line.

## How they are applied (scripts/fetch.sh)

From a clean Chromium checkout at the pinned revision, in one command:

```bash
git apply --index "$BARE_DIR/patches/"*.patch
```

The shell expands the glob in filename order, which is the order that
matters. Use `git apply`, not `git am`: the files from `0000195.patch` on
are plain diffs without a mail header, which `git am` rejects.
(Bare's docs/patches.md.)

## The bundled-extension decision (open, recorded here)

Bare ships uBlock Origin inside its APK. Its `.crx` is kept out of the patch
series (a 4 MB signed third-party binary; base64 in a patch would be
unreviewable) and is copied into the Chromium tree before building:

```bash
cp third_party/ublock_origin/uBlockOrigin-1.75.0.crx \
   "$CHROMIUM_SRC/chrome/browser/resources/bare/ublock_origin.crx"
```

Without it the assets target has no input and the build fails at packaging
(Bare's BUILDING.md). `scripts/fetch.sh` therefore copies it from the Bare
clone and **fails clearly if it is absent** — a missing asset must never
fail silently at packaging time, hours later.

Whether DAF keeps Bare's bundled uBlock Origin or drops that patch and its
asset is a **product decision for the fork owner**, not a build decision.
The default in this scaffolding is to keep Bare's series as-is (so the build
succeeds exactly as Bare's does) and record the decision here when it is made.
