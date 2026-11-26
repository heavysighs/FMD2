# FMD2 for macOS 10.14 Mojave — build guide

This fork builds **FMD2 (Free Manga Downloader 2)** as a native macOS app
that runs on **macOS 10.14.6 Mojave** (x86_64), the last version a 2009
iMac can run. Upstream FMD2 ships Windows builds only.

Everything Mojave-specific lives in a small number of obvious places —
this file is the map. If something breaks, start here.

## How the build works

One GitHub Actions workflow: `.github/workflows/mojave-build.yml`
(runs on an Intel macOS runner, triggered by any push to `mojave-fix`).

1. **Install the toolchain** — FPC 3.2.4rc1 + Lazarus 4.6 from the
   official SourceForge packages (Homebrew's Lazarus is too old; FMD2
   needs LCL ≥ 3.8). The downloads are slow, so they are fetched in
   parallel chunks and cached between runs.
2. **Patch the LCL** — `scripts/patch-lcl.py` (one patch, see below).
3. **Fetch + build the dependencies** — `scripts/build-deps.sh` clones
   the pinned Lazarus packages into `3rd/`, generates a package over
   FMD's vendored synapse, applies every package patch via
   **`scripts/patch-deps.py`**, and compiles the packages with lazbuild
   for the Cocoa widgetset.
4. **Build FMD2** — `lazbuild --build-mode=Darwin --widgetset=cocoa`.
   The `Darwin` build mode (in `mangadownloader/md.lpi`) targets
   x86_64-darwin with `-WM10.14` and links the native libraries below.
5. **Build the native libraries for 10.14** — Homebrew bottles target
   newer macOS, so OpenSSL 3, Duktape, PCRE2, Brotli, Zstd, WebP, Lua 5.3
   and 7-Zip (`7zz`) are all compiled from source with
   `-mmacosx-version-min=10.14`. A Mozilla CA bundle (`cacert.pem`) is
   downloaded for TLS verification.
6. **Package** — `scripts/package-app.sh` assembles `FMD2.app`: the
   binary, the 10 dylibs (install names rewritten to `@rpath`), `7zz`
   beside the binary, `cacert.pem`, `config.json`, and the `lua/`,
   `languages/`, `images/` data folders.
7. **Gate** — two checks run on the finished bundle and fail the build
   if anything would not load on Mojave:
   - `.github/scripts/check-mojave.py` — every Mach-O binary declares a
     minimum macOS ≤ 10.14 and every library it loads is bundled or
     present in Mojave's system libraries.
   - `.github/scripts/check-runtime-names.py` — every library *name*
     embedded in the binary (including ones loaded at runtime, which
     the first gate cannot see) resolves to a bundled or Mojave-system
     library; any Windows `.dll` or Linux `.so` name fails the build.

The result is the `fmd2-mojave-app` artifact: a zip containing
`FMD2-mojave.zip`, ready to unzip and drag into /Applications.

## Source changes vs upstream

The app itself is upstream FMD2 (master @ 9c8020d7) plus the Linux port,
plus a short list of Darwin fixes. Each fix is one small, commented
change; `git log` on this branch tells the same story commit by commit.

| Area | Change | Why |
|---|---|---|
| `md.lpi` | `Darwin` build mode (x86_64-darwin, `-WM10.14`, explicit `-k` link flags) | FPC emits no `-l` flags for unit-level externals on Darwin |
| Library name constants (lua53, BaseCrypto, Duktape, pcre2) | Darwin `.dylib` names | The units only knew Windows/Linux names |
| `webp.pas` | Darwin name `libwebp.dylib` | It fell through to `libwebp.dll` — the first crash on device |
| `naturalsortunit.pas`, `SimpleException.pas` | Darwin compile guards / `PtrUInt` casts | Darwin type differences |
| `httpsendthread.pas` | On Darwin, verify TLS against the bundled `cacert.pem` (fallback: `/etc/ssl/cert.pem`) | OpenSSL never reads the macOS keychain; without a CA file every HTTPS request failed |
| `FMDOptions.pas` | Materialize `config.json` on first run; merge-copy bundled Lua modules into the data dir; find `7zz` beside the executable first | The module updater read an empty config (no GitHub coordinates); bundled module updates never reached existing installs; no `7z` exists on a stock Mac |
| `frmLuaModulesUpdater` config (`dist/config.json`) | Module updates point at this fork's `mojave-fix` branch | Module fixes ship through the built-in updater |
| `LuaWebsiteModules.pas` | Per-file exception guard in the loader threads; bounds check inside the lock; scan logging | One bad file used to kill a loader thread and silently strand ~2/3 of the website modules |
| `frmWebsiteOptionCustom.pas` | Build the options form with alignment deferred; pin it to its content height (`alTop`) | Cocoa WMSize loop exception storm (900+ in one session) |
| `SimpleException.pas` | On Darwin, show a plain system alert instead of the report dialog | The dialog's memo itself aborted (NSRangeException) while displaying a report |
| `frmMain.pas` | File logging forced on for Darwin builds; `ViewMangaInfo` adds its "Loading…" line before reading text attributes | Field diagnostics land in `~/.cache/fmd2/fmd.log`; defense-in-depth for the GetDict fix (UP4) |

## The patches (the part most likely to need fixing)

Patches to code this repo does not own live in exactly two files. Both
are idempotent, print one line per patch, and assert their anchors — if
an upstream update changes the code around a patch, the build fails at
the patch step with the patch's name, instead of shipping broken.

### `scripts/patch-deps.py` — patches to the pinned packages in `3rd/`

| Patch | File | Symptom → fix |
|---|---|---|
| UP1/UP1b/UP1c/UP3 | virtualtreeview | qt6 unit paths missing; a `Move()` ambiguity → add fallback paths, retarget qt4→qt6, qualify `System.Move` (from the Linux port) |
| UP2 | internettools.lpk | synapse used but not declared → add the generated `laz_synapse` dependency |
| UP4 | richmemo `cocoarichmemo.pas` `GetDict` | Reading attributes of an **empty** memo computed index −1 → NSRangeException abort on every title view → return nil (defaults) for empty text |
| UP5 | richmemo range helpers | `TextLen = -1` ("to the end") passed through as an NSRange length → abort in `addAttribute` → treat negative as to-end, clamp the start |
| UP6 | richmemo `FindFont` | Retry loop never incremented its counter → an unmatched font **hung** the info panel forever → increment, fall back to the system font, cache the match |

### `scripts/patch-lcl.py` — patch to the installed Lazarus 4.6

`TCocoaContext.Destroy` in `lcl/interfaces/cocoa/cocoagdiobjects.pas`
restores the graphics state once per flag, but `ClearClipping` restores
without clearing its flag, so restores can outnumber saves. Mojave
aborts on the extra restore (`CGGStackRestore` assertion); newer macOS
ignores it. The patch skips the restores for **bitmap** contexts only —
they own their graphics context, which is released immediately after.
This fired when the Downloads page's transfer-rate chart freed a bitmap
canvas on Download.

## Updating

- **New upstream FMD2**: merge/rebase upstream master onto `mojave-fix`.
  The Darwin changes above are the only app-level deltas to re-check.
- **New Lazarus/FPC**: update the SourceForge URLs in the workflow;
  re-check `scripts/patch-lcl.py` (its assert will say if the LCL code
  moved).
- **New package pins**: update the commits in `scripts/build-deps.sh`;
  each patch in `patch-deps.py` asserts its anchor and names itself in
  the failure.

## Known non-issues

- **ImageMagick** is optional: if `magick` is on PATH, image conversion
  features use it; absent, they quietly stay unavailable. Not bundled.
- The `poweroff` shutdown-after-downloads option cannot work on macOS
  (no such command); worst case is an error dialog if enabled.
- Self-update is disabled by upstream on non-Windows builds. Module
  updates still arrive through the built-in module updater.
