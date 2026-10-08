# FMD2 Linux Port — Build, Install, Troubleshooting & Limitations

**Status**: in progress — T005, T023, T026 done; T043/T047/T053/T055 sections filled 2026-10-08 (fixture/headless validation + ready-to-run checklists; interactive desktop rows marked ⬜); T027 (Plasma Wayland manual install/launch/uninstall) still open

## Requirements

Verified on Arch via `scripts/check-deps.sh` (T005, 2026-10-08): **21 ok, 0 missing, exit 0**.

| Category | Packages (Arch) | Status |
|---|---|---|
| Toolchain | `fpc` 3.2.2-11, `lazarus` 4.8-1, `qt6pas` 6.2.10-4 | ✅ |
| Runtime libs | `openssl` 3.6.5-1, `sqlite` 3.53.4-1, `pcre2` 10.49-1, `libwebp` 1.6.0-2, `brotli` 1.2.0-1, `zstd` 1.5.7-3, `lua` 5.5.1-1 | ✅ |
| External CLI | `7zip` 26.03-1 (`/usr/bin/7z`) | ✅ |
| Shared libs | `libssl.so.3`, `libcrypto.so.3`, `libsqlite3.so`, `libpcre2-8.so`, `libwebp.so`, `libbrotlidec.so`, `libzstd.so` | ✅ |
| Optional | `imagemagick` (`magick`), `xvfb` (`Xvfb`) | ✅ |
| Optional missing | `xdotool` (headless GUI tests), `lazarus-qt6` (precompiled Qt6 LCL units; base `lazarus` compiles them on demand) | ⬜ |

Notes:
- LCL Extensions (`lclextensions_package.lpk`), LCL, LazControls, TAChart, RunTimeTypeInfoControls ship with the `lazarus` package — no separate install.
- Third-party packages (InternetTools, DCPCrypt, RichMemo, MultiLog, VirtualTreeView, MetaDarkStyle, Lazarus_CustomControls, Synapse) are fetched pinned by `scripts/build-deps.sh` into `3rd/` (T006).
- `sudo` requires a password in this environment: install the two optional packages manually with `sudo pacman -S --needed xdotool lazarus-qt6` when needed.
- Re-run 2026-10-08 (T055): `check-deps.sh` → **23 ok, 0 missing, exit 0** (`xdotool`/`lazarus-qt6` still absent as optional).
- **Dependency gap found (T055)**: the binary links `liblua5.4.so.5.4` (Arch package `lua54`), not the `lua` (5.5) package listed in the table/PKGBUILD — a system with only `lua` installed would fail to start. Install `lua54`; PKGBUILD `depends` fix pending (see Troubleshooting).

## Upstream dependency issues (Linux build) — task T016

All 11 external packages compile on Linux/Qt6 after the patches below (applied automatically and idempotently by `scripts/build-deps.sh`):

| # | Package | Issue | Fix in build-deps.sh |
|---|---|---|---|
| UP1 | `virtualtreeview_package` | `units/$(LCLWidgetType)` has no `qt6` dir → `FakeActiveX` not found | append `units/qt;units/gtk2` to OtherUnitFiles |
| UP1b | `virtualtreeview_package` | `include/intf/$(LCLWidgetType)` has no `qt6` dir → `vtgraphicsi.inc` not found | append `include/intf/qt;include/intf/gtk2` |
| UP1c | `virtualtreeview_package` | `include/intf/qt/vtgraphicsi.inc` uses dead unit `qt4` | retarget `uses` to `qt6, qtobjects` |
| UP2 | `internettools` | synapse (`httpsend`) used but not declared as package dependency | add `laz_synapse` to RequiredPkgs |
| UP3 | `virtualtreeview_package` | 3 unqualified 3-arg `Move(FPositionToIndex…)` calls resolve to 2-arg `Classes.Move` under FPC 3.2.2 on Linux | qualify `System.Move` |

Additionally: `laz_synapse` is generated over FMD's **vendored** `baseunits/synapse` (external forks such as `hakansimsek/synapse4lazarus` fail: `synsock.inet_addr` missing); Windows-only synapse units (`Crypt32`, `ssl_openssl_capi`, `ssl_sbb*`, `ssl_cryptlib`, `ssl_libssh2`, `ssl_streamsec`) are excluded from the generated package (audit §6.3, not referenced by FMD).

## Build (source)

```sh
./scripts/check-deps.sh      # verify fpc, lazbuild, Qt6, sqlite3, pcre2, …
./scripts/build-deps.sh      # fetch+patch+compile the 11 pinned packages into 3rd/
lazbuild --lazarusdir=/usr/lib/lazarus --build-mode=Linux --widgetset=qt6 mangadownloader/md.lpi
# → bin/x86_64-linux/fmd  (+ fmd.dbg debug symbols; 0 missing libs in ldd)
```

Notes from the first successful full build (T023):

- **FPC 3.2.2 workaround**: `SQLiteData.pas` — `FlushSQL` decl lost `inline`
  (delphi-mode inline call across units made fpc 3.2.2 abort with an internal
  error at `uFavoritesManager.pas:796`).
- **Platform guards**: Windows-only const block in `uBaseUnit.pas`
  (`MAX_PATHDIR`/`FMDMaxImageFilePath`), `var` block in `imagemagickmanager.pas`,
  `frmMain` darkmode gating, `md.lpr` dark-style block + `g_buildNumber`
  (MetaDarkStyle is WinAPI-only; Linux Qt6 uses the system/KDE theme).
- **cthreads** must be the first unit under `{$IFDEF UNIX}` (runtime error 232
  otherwise).
- **pcre2**: system lib is `libpcre2-8.so` (Arch has no `libpcre2.so`).
- **duktape**: Arch's libduktape lacks the `require()` extra
  (`duk_module_duktape_init`), which FMD's Lua needs (`utils/crypto-js.min.js`
  via `Duktape.ExecJS`). `build-deps.sh` pins and compiles the extra into
  `3rd/duktape-module/duk_module_duktape.o`, linked into the exe on Unix.
- **Linux build mode** keeps `GenerateDebugInfo=True` + external `fmd.dbg`
  so gdb backtraces stay symbolized after stripping the runtime binary.

Runtime fixes validated by `tests/e2e/first_launch` (all PASS, runs headless
with `QT_QPA_PLATFORM=offscreen`):

- `SETTINGS_FILE` now resolves to `${XDG_CONFIG_HOME}/fmd2/settings.json`
  (contract `config-paths.md`; it used to land in the data dir). Created
  eagerly on first launch (`SetIniFiles` → `UpdateFile`), because FMD2
  otherwise only flushes settings at graceful close.
- `uBackupSettings.pas`: `poNewConsole` is Windows-only — on Unix FPC
  interprets it as "run inside a new xterm" (`TProcess.MakeCommand` →
  `DetectXTerm` → `EProcess: Could not detect X-Terminal program`), which
  aborted the startup/hourly settings backup.
- Startup guard in `md.lpr`: if `Screen.Width < 100` the app exits with a
  clear message instead of crashing inside LCL's `TPopupNotifier` (range check
  on a negative `Constraints.MaxWidth` when Qt reports a 0-size screen).

**Display requirement**: a Qt screen with a real size is required for the GUI.
A session whose outputs are all disconnected (e.g. KWin with
`xrandr --listactivemonitors` = 0 / no `wl_output`) makes every new Qt process
see `Screen.Width=0`; the guard turns that into a diagnosable error. Headless
runs must set `QT_QPA_PLATFORM=offscreen`.

## Install (PKGBUILD)

```sh
cd packaging/arch
makepkg -si          # build + install (or: makepkg -f && sudo pacman -U fmd2-*.pkg.tar.zst)
fmd                  # /usr/bin/fmd launcher, or start "FMD2" from the application menu
```

- Package layout: binary `/usr/lib/fmd2/fmd` (+ `fmd.dbg`), launcher
  `/usr/bin/fmd` (sets `FMD_DIRECTORY=/usr/share/fmd2`, honours an existing
  `FMD2_CONFIG_DIR`), desktop entry `/usr/share/applications/fmd2.desktop`,
  icons `/usr/share/icons/hicolor/{48,64,128,256}x{…}/apps/fmd2.png`,
  read-only data (`images/`, `languages/`, `lua/` module templates,
  `changelog.txt`, `readme.rtf`) under `/usr/share/fmd2/`, licenses under
  `/usr/share/licenses/fmd2/`.
- `source=()` builds from the working tree; a release PKGBUILD pins a source
  tarball in `source=()`/`sha256sums=()`. Third-party Lazarus packages are
  commit-sha pinned inside `scripts/build-deps.sh` (T006/T016).
- Update: rebuild+`pacman -U`, or `pacman -Syu` once published (no in-app
  updater on Linux, FR-023). Uninstall: `sudo pacman -R fmd2` removes all
  package files (binary, launcher, desktop entry, icons, `/usr/share/fmd2`,
  licenses); user data under `~/.config/fmd2`, `~/.local/share/fmd2`,
  `~/.cache/fmd2` is **never** touched by the package (SC-011).

## Windows data migration

Copy the Windows FMD2 folders into the XDG locations (FR-009, contract rule 4):

| From (Windows FMD2 install dir) | To (Linux) |
|---|---|
| `config.json` | `~/.config/fmd2/config.json` |
| `userdata/settings.json` | `~/.config/fmd2/settings.json` *(config dir on Linux — see contract)* |
| `userdata/*.db` (accounts, downloads, downloadedchapters, favorites) | `~/.local/share/fmd2/userdata/` |
| `userdata/modules.json`, `lua.json`, `lua_repo.json` | `~/.local/share/fmd2/userdata/` |
| `backup/` (if kept) | `~/.local/share/fmd2/backup/` |

Windows-style absolute paths (`C:\…`) in `download_directory` are reported as
invalid in the UI and never used silently — set the download directory again
after migrating (contract rule 2). Formats are unchanged: the Linux build
reads Windows-written files as-is.

### Validation (T043, 2026-10-08)

**No real Windows FMD2 export is available in this environment**, so the copy
procedure was validated against a *fixture* under a sandboxed HOME/XDG
(`mktemp -d`, `QT_QPA_PLATFORM=offscreen`, binary `bin/x86_64-linux/fmd`,
short `timeout` runs; the real `~/.config/fmd2` / `~/.local/share/fmd2` were
never touched). Fixture:

- `config.json` = the genuine upstream Windows-release file `dist/config.json`
  (byte-identical copy, incl. its `GitHub` section).
- `userdata/settings.json` = synthetic Windows-shaped settings with
  `saveto.SaveTo = C:\Users\Public\Downloads\FMD2`, `general.OneInstanceOnly=false`,
  `logger.Enabled=true` (both observable headless), a UserAgent marker, language `de`.
- `userdata/{favorites,downloads,downloadedchapters}.db` = same-version SQLite
  files (formats are identical across platforms per contract), with one seeded
  favorite row whose `saveto` is the Windows path.

Results (19/19 checks passed):

| Check | Result |
|---|---|
| Files placed per the copy table above → app starts with them | ✅ |
| `settings.json` read: `OneInstanceOnly=false` honored (second launch stays alive, 2 concurrent processes) | ✅ |
| `settings.json` read: `logger.Enabled=true` → log file appears in `${XDG_CACHE_HOME}/fmd2/fmd.log` | ✅ |
| Windows `SaveTo` preserved verbatim, not rewritten/remapped on startup | ✅ |
| `config.json` byte-identical after launch (read, not rewritten) | ✅ |
| No `C:\…`-style path materialized anywhere in the sandbox | ✅ |
| Migrated DBs pass `PRAGMA integrity_check`, seeded favorite row still present after run | ✅ |
| App survives startup exceptions (log continues, no fatal marker) | ✅ |

Still pending — needs a real Windows export and/or a display (mark ⬜, do not
claim): running against `userdata/` actually written by a Windows build of
FMD2; restoring a Windows `backup/*.7z` archive; the UI showing the Windows
path as *invalid* (headless runs only prove it is preserved and never used);
favorites/settings visibly loaded in the GUI; extra files a real export may
contain (`accounts.db`, `modules.json`, `lua.json`, `lua_repo.json` — on Linux
these are created on demand, so they were not exercised).

## Desktop behavior matrix (Wayland/GNOME) — task T047 (quickstart §6, SC-009)

Interactive manual testing **cannot be executed in this environment**: no user
session access, `xdotool` not installed, XTEST/ydotool synthetic input broken,
offscreen Qt platform has no window manager. Rows below marked
"⬜ not run — manual" are a ready-to-execute checklist: run them once in a real
Plasma Wayland and a real GNOME session, then fill the cells.

Legend: ✅ executed & passed · ❌ executed & failed · ⬜ not yet run.

| Check | Plasma Wayland | GNOME | Evidence / how to run |
|---|---|---|---|
| File dialogs (open/save/directory picker, native Qt dialogs) | ⬜ not run — manual | ⬜ not run — manual | open any browse/save button, verify dialog appears, navigates, returns a path |
| Clipboard (copy/paste into search & settings fields, copy URL) | ⬜ not run — manual | ⬜ not run — manual | Ctrl+C/Ctrl+V inside the app + from an external app |
| Notifications (completion/failure popups, `TPopupNotifier`) | ⬜ not run — manual | ⬜ not run — manual | finish or fail a download, check DE notification center |
| Window management (minimize/maximize/raise/focus, WM independence) | ⬜ not run — manual | ⬜ not run — manual | incl. focus/raise when a second launch signals `BringToFront` |
| Drag & drop URL/file into the window | ⬜ not run — manual | ⬜ not run — manual | code path verified statically (LCL `AllowDropFiles`/`OnDropFiles`, T044) |
| Single instance: second launch exits and first keeps running | ✅ (offscreen, DE-neutral) | ✅ (offscreen, DE-neutral) | `tests/e2e/desktop_behavior`: 2nd process exits rc=0 ≤10 s, exactly 1 process remains; independently reproduced by a separate sandbox run (4/4 checks) |
| Second launch *focuses* the first window | ⬜ not run — manual | ⬜ not run — manual | needs a live WM (`BringToFront` IPC is sent; raise not observable headless) |
| Clean shutdown, zero orphans (SC-010) | ✅ (offscreen, DE-neutral) | ✅ (offscreen, DE-neutral) | `tests/e2e/desktop_behavior` + `queue_controls`: SIGTERM → 0 `fmd` processes, relaunch OK |
| Desktop entry present/valid (`fmd2.desktop`, icons, `Exec=fmd %U`) | ✅ (static) | ✅ (static) | `tests/e2e/desktop_entry` 9/9 PASS (`desktop-file-validate`); icons 48/64/128/256 present in tree + package |
| Launch from application menu | ⬜ not run — manual (needs `pacman -U`, sudo) | ⬜ not run — manual | install package, launch "FMD2" from menu, no terminal/env fiddling |
| No X11-only requirement on Wayland | partial ✅ | partial ✅ | runs with `QT_QPA_PLATFORM=offscreen` and no `DISPLAY`; Qt platform plugins `libqwayland.so`/`libqxcb.so`/`libqoffscreen.so` present; binary links `libX11`/`libxcb` only transitively via Qt6Gui. Real-session launch still ⬜ |
| Uninstall removes package files only (SC-011) | ⬜ not run — manual (sudo) | ⬜ not run — manual | static evidence: package file list is entirely under `/usr` (`bsdtar -tf fmd2-*.pkg.tar.zst`); `sudo pacman -R fmd2` not runnable here (no sudo) |

Notes:
- Scriptable rows were run headless on 2026-10-08 with sandboxed HOME/XDG;
  they are display-server-neutral and apply to both desktops, but they do
  **not** substitute for the interactive rows.
- Single-instance IPC (`/tmp/_FreeMangaDownloaderInstance_`) is system-global,
  so concurrent sandboxed test runs must not overlap (tests skip themselves if
  another `fmd` is running).

## Troubleshooting — task T053 (FR-021)

### Install / build

| Symptom | Cause | Fix |
|---|---|---|
| `check-deps.sh` reports missing packages | toolchain/deps not installed | `sudo pacman -S --needed fpc lazarus qt6pas openssl sqlite pcre2 libwebp brotli zstd lua54 lua duktape 7zip git`; optional: `imagemagick xvfb xdotool lazarus-qt6` |
| `lazbuild` fails on 3rd-party packages ("unit not found", `FakeActiveX`, `vtgraphicsi.inc`) | upstream packages have no `qt6` unit dirs | run `./scripts/build-deps.sh` — it fetches pinned commits and applies patches UP1–UP3 (see *Upstream dependency issues*) |
| FPC internal error 232 at startup unit | `cthreads` not first unit under `{$IFDEF UNIX}` | already fixed in `md.lpr`; do not reorder units |
| FPC internal error in `uFavoritesManager.pas` / `SQLiteData.pas` | `inline` decl lost across units on FPC 3.2.2 | already fixed (Build notes, T023) |
| Link warnings `crtbeginS.o / crtendS.o not found` | FPC/Lazarus driver emits them even on successful links | harmless — binary links and `ldd` resolves (verified exit 0, 0 missing libs) |
| `makepkg` refuses to run / `pacman -U` asks for root | `makepkg` must not run as root; install needs sudo | `makepkg -f` as user, then `sudo pacman -U fmd2-*.pkg.tar.zst` |
| `git clone` of upstream lacks `3rd/` | upstream declares a submodule that is absent from the snapshot | `./scripts/build-deps.sh` fetches the pinned sources |

### Runtime

| Symptom | Cause | Fix |
|---|---|---|
| `error while loading shared libraries: liblua5.4.so.5.4` | **known packaging gap**: the binary links `liblua5.4` (`lua54` package) while PKGBUILD/`check-deps.sh` currently list `lua` (5.5) | `sudo pacman -S lua54` (PKGBUILD `depends` fix pending — tracked here, not silently ignored) |
| Exits immediately: "screen too small / no display" guard, or Qt abort | session has no connected outputs (`Screen.Width=0`), or no reachable display server | run inside a real session; headless runs must set `QT_QPA_PLATFORM=offscreen` (required by every test script here) |
| Core dump when launching with `env -i …` exactly as quickstart §2 | stripped environment has no `XDG_RUNTIME_DIR`/display; Qt cannot connect to Wayland/X11 | add `QT_QPA_PLATFORM=offscreen` (verified: same command then starts and creates the XDG dirs), or keep `XDG_RUNTIME_DIR` + a real session |
| `EProcess: Could not detect X-Terminal program` at startup | old build ran the settings backup with `poNewConsole` (Windows-only; Unix means "new xterm") | fixed in `uBackupSettings.pas` (T023-era); rebuild if present |
| Log entry `LUA>DoInit("MangaPlus.lua") … module 'pb' not found` on every start | Windows ships `dist/*/pb.dll` (Lua-protobuf); no Linux `.so` is packaged | MangaPlus source stays unavailable until a `pb.so` is built from `starwing/lua-protobuf` and installed into the Lua cpath (see *Known limitations*) |
| Zip/7z operations fail | `7z`/`7zz` not on PATH | `sudo pacman -S 7zip` (Windows `7za.exe` is gone by design, T020) |
| ImageMagick-based conversion/thumbnailing absent | ImageMagick optional | `sudo pacman -S imagemagick` (binary is bare `magick`) |
| No log file although something failed | logging is off by default | enable `logger.Enabled` in settings → `${XDG_CACHE_HOME:-~/.cache}/fmd2/fmd.log` (severity-tagged, MultiLog) |
| Startup seems to hang / hits GitHub rate limit in log | app contacts the GitHub API during startup (`TGitHubRepo` — module/Lua-repository sync, observed live in the log) | needs network; rate-limit refresh time is logged — app behavior, not a test hitting manga sites |
| Tests report "⬜ not run — another fmd instance is already running" | single-instance IPC is system-global (`/tmp/_FreeMangaDownloaderInstance_`) | stop other `fmd` processes (incl. other sandboxes) before running the e2e scripts |
| `desktop-file-validate` hint about `Categories` | `Network;Utility;` lists two main categories (menu may show it twice) | cosmetic only; test passes — pick one main category if it bothers you |
| No GUI automation possible (xdotool/XTEST) | headless environment, no synthetic input | interactive rows of the desktop matrix stay ⬜ — run them manually in a real session |

**Update path**: there is no in-app updater on Linux — `sudo pacman -Syu`
(rebuild+`pacman -U` for local builds) is the update mechanism (FR-023).

## Quickstart validation report (T055, 2026-10-08) — FR-011, FR-021

Full pass over `specs/001-fmd2-linux-port/quickstart.md` in this environment
(headless container, no user session, no sudo, no network tests).
Legend as in quickstart: ✅ executed & passed · ❌ executed & failed · ⬜ not yet run.

| § | Step | Status | Result / reason |
|---|---|---|---|
| 1 | Build | ✅ | `lazbuild --lazarusdir=/usr/lib/lazarus --build-mode=Linux --widgetset=qt6 mangadownloader/md.lpi` → exit 0, 886 lines in 3.1 s, `bin/x86_64-linux/fmd` (16.2 M), `ldd`: 49 libs, 0 missing; only the 2 known `crtbeginS.o/crtendS.o` warnings (link succeeds) |
| 2 | First launch, clean system | ❌ → ✅* | as written (`env -i …`, no offscreen) **core-dumps here** — no reachable display/`XDG_RUNTIME_DIR`; the same command with `QT_QPA_PLATFORM=offscreen` creates both XDG dirs. Test `tests/e2e/first_launch`: **5/5 PASS** (config+data dirs, `settings.json`, no writes outside `$HOME`, no strays) |
| 3 | Search & download, mocked network | ⬜ | `./tests/run-tests.sh` does not exist (T050), `tests/unit/` + `tests/integration/` empty (T028–T031 pending). Nothing to execute; no live-site fallback used |
| 4 | Queue controls | ✅ / ⬜ | `tests/e2e/queue_controls`: **21 PASS** — seeded 3-item queue survives start/restart, `taskstatus=1` honored, no partial files, 3× clean SIGTERM (0 orphans). **5 explicit not-run**: GUI pause/resume/cancel/retry, widget progress readout, live concurrency sampling (needs mock source, T028/T029) |
| 5 | Persistence & migration | ⬜ / ✅ | `tests/e2e/persistence` missing (T041) → settings/favorites restart loop ⬜. Migration half **executed**: fixture validation **19/19 PASS** (see *Windows data migration → Validation*); real Windows export still pending |
| 6 | Desktop integration | ✅ / ⬜ | `makepkg -f --skipinteg` **exit 0, no sudo** → `fmd2-2.0.34.5-1-x86_64.pkg.tar.zst`; file list enumerated (binary+`fmd.dbg`, `/usr/bin/fmd`, desktop entry, 4 icons, `/usr/share/fmd2/{images,languages,lua,changelog,readme.rtf}`, licenses — **nothing outside `/usr`**). `tests/e2e/desktop_entry` **9/9 PASS** (+1 cosmetic `Categories` hint). `tests/e2e/desktop_behavior` **14 PASS** (single-instance, clean shutdown, relaunch). ⬜: `pacman -U`/`pacman -R` (sudo unavailable), menu launch, `fmd2-launch-test.sh` (does not exist), interactive matrix rows (T047 above) |
| 7 | Filesystem edge cases | ⬜ | `tests/e2e/unicode-paths` does not exist (owner task open) |
| 8 | Shutdown & idle | ✅ / ⬜ | zero orphaned processes after SIGTERM in **every** run (10 shutdowns across `first_launch`/`queue_controls`/`desktop_behavior`/T043 fixture/independent repro); ⬜ close-mid-download (no mock downloads yet) and ⬜ 1-hour idle (T054) |
| 9 | Localization | ⬜ | inventory only: **11** `languages/fmd.*.po`, same file set as baseline `upstream-2.0.34.5` (name-level check via `git ls-tree`; contents are being extended with Linux-specific strings by T052 as this report was written) — quickstart/spec say **12** languages, discrepancy unresolved (T052). Switching all languages in the GUI needs a display → not run |
| 10 | Test reporting | ⬜ | `./tests/run-tests.sh all --report` does not exist (T050). This section is the interim passed/failed/**not-run** report; nothing unexecuted is claimed as passed (SC-012) |

\* §2: failed exactly as written, passed with the documented offscreen
substitution — the intent (clean-system first launch, XDG creation, no stray
writes) is ✅ via `tests/e2e/first_launch`; the literal headless failure is a
test-harness/environment issue, not an app defect on a real desktop.

Scriptable evidence actually executed on 2026-10-08 (all with sandboxed
HOME/XDG, `QT_QPA_PLATFORM=offscreen`, short timeouts, no sudo, no live-site
tests): `scripts/check-deps.sh` (re-run: 23 ok / 0 missing), full `lazbuild`,
`makepkg -f`, `tests/e2e/first_launch`, `tests/e2e/desktop_entry`,
`tests/e2e/queue_controls`, `tests/e2e/desktop_behavior`, T043 migration
fixture (19 checks), independent single-instance reproduction (4 checks).

## Preserved / modified / unsupported features (T055) — FR-011, FR-021

Status reflects the **port's code**, not test coverage; "validation" says what
was actually verified here. Upstream feature set = FMD2 2.0.34.5 (assessment
`PHASE1_ASSESSMENT.md` §3–§4).

### Preserved (behavior kept as upstream)

| Feature | Validation |
|---|---|
| 52 Lua website modules + templates/utils (search, series, chapters) | module tree copied to XDG data dir at first run; modules initialize at startup (log) — *MangaPlus exception below* |
| Search/browse/download core, queue engine, concurrency, pause/resume/cancel/retry logic | code paths unchanged (`uDownloadsManager.pas`); runtime behavior ⬜ (mock tests T028–T031, GUI parts of T038 not run) |
| Favorites / download history / queue state (SQLite `favorites.db`, `downloads.db`, `downloadedchapters.db`) | schema + format unchanged; migration fixture: DBs intact, favorite row survives startup |
| Settings format (`settings.json` JSON-ini) and all options | round-trip proven (fixture markers preserved verbatim) |
| Filename templates, chapter organization, ZIP/CBZ/PDF/EPUB packing, duplicate handling | code reused (`uPacker`/`uEpub`/`Img2Pdf`); ⬜ end-to-end output validation (T035) |
| HTTP error / rate-limit / malformed-response handling, TLS verification on | synapse `ssl_openssl3` (T032); ⬜ mocked failure cases (T030) |
| All 11 upstream UI languages (`fmd.*.po` file set matches baseline) | inventory ✅; Linux-specific strings being added (T052, in progress); GUI switching ⬜ |
| Upstream CLI args (`--lua-dofile`, `--no-commit-queue`, `--max-*-queue`, `--backup-interval`) | preserved (contract); + additive `--config-dir` |
| Single-instance policy (`simpleipc`, second launch exits) | ✅ e2e (desktop_behavior, independent repro) |
| Open-URL / open-folder actions | via LCL `OpenURL`/`OpenDocument` (Linux: `xdg-open` path) — static ✅ |
| Logging content (MultiLog, severity levels) | preserved; location moved (below). Startup settings backup runs (observed `backup/fmdbackup_*.7z`) |
| Clean shutdown, no orphaned processes | ✅ (10 SIGTERM shutdowns, 0 orphans) |

### Modified (same feature, Linux-specific change)

| Feature | Change |
|---|---|
| Config/data/cache locations | XDG: config → `~/.config/fmd2/` (incl. `settings.json`, moved out of `userdata/`), data → `~/.local/share/fmd2/`, logs/cache → `~/.cache/fmd2/` |
| Default download directory | `$XDG_DOWNLOAD_DIR` (via `xdg-user-dir`) else `~/Downloads`; existing absolute setting always wins |
| Windows-style path in settings | never mapped/created; preserved verbatim and unusable on Linux (contract rule 2) — GUI "invalid" indication ⬜ manual |
| Zip tool | bundled `7za.exe` → system `7z`/`7zz` from PATH |
| Settings/backup location | `backup/` → `${XDG_DATA_HOME}/fmd2/backup/` (startup backup observed) |
| Log file | program dir → `${XDG_CACHE_HOME}/fmd2/fmd.log` (absolute, severity-tagged) |
| Drag & drop implementation | COM `IDropTarget` (ActiveX) → LCL `AllowDropFiles`/`OnDropFiles` (T044) — behavior preserved, ⬜ interactive DnD |
| ImageMagick discovery | Windows registry/PATH scan → `FindDefaultExecutablePath('magick')` |
| Dark theme | MetaDarkStyle (WinAPI) disabled → system/KDE theme on Qt6 |
| Portable mode | no longer the default (data-next-to-exe); opt-in via `--config-dir`/`FMD2_CONFIG_DIR`, packaged installs are XDG (contract rule 5) |
| Launcher | double-click `fmd.exe` → `.desktop` entry + `/usr/bin/fmd` wrapper (`FMD_DIRECTORY=/usr/share/fmd2`) |

### Unsupported on Linux (with the documented equivalent — nothing dropped silently)

| Windows feature | Linux equivalent / reason |
|---|---|
| In-app self-updater (`updater.exe`, `updaterslim/`) | package manager only: `sudo pacman -Syu` (or rebuild + `pacman -U`) — FR-023 |
| `--dorestart-pid` restart helper | normal re-launch; argument not accepted (contract) |
| Keep-awake during downloads (`SetThreadExecutionState`, `frmMain.pas:2198`) | none built in — Windows-only block; use `systemd-inhibit` if needed |
| OLE/COM clipboard & drag APIs, `WinAPI.pas` shim | LCL equivalents (`AllowDropFiles`, LCL clipboard); unit excluded from build |
| Windows-only synapse SSL backends (`Crypt32`, `ssl_openssl_capi`, `ssl_sbb*`, …) | OpenSSL 3 backend (`ssl_openssl3`), cert verification stays on |
| `7za.exe`, Windows runtime DLLs in `dist/` | distro packages (`7zip`, `lua54`, `duktape`, `openssl`, `sqlite`, …) via PKGBUILD deps |
| Registry-based ImageMagick install lookup | PATH lookup (`magick`) |
| **MangaPlus source** (needs `pb` Lua-protobuf; Windows ships `dist/*/pb.dll`) | ⚠ **currently unavailable** — startup logs `module 'pb' not found`, app continues. Fix path: build `pb.so` from `starwing/lua-protobuf` and place it on the Lua cpath (not packaged yet) |
| 12th UI language claimed by spec/quickstart | repo ships **11** `fmd.*.po` (file set matches upstream baseline) — discrepancy open (T052), not silently accepted |

## Known limitations — tasks T053/T055 (FR-011, FR-021)

- **No in-app updater** — updates via pacman only (FR-023, by design).
- **MangaPlus source unusable** until a Linux `pb.so` is packaged (see table above); every other Lua module initialized normally in observed runs.
- **No sleep-inhibition while downloading** (Windows-only API) — system may idle-sleep; `systemd-inhibit` is the manual workaround.
- **Dark mode**: MetaDarkStyle not used on Linux; app follows the desktop theme.
- **Desktop matrix is incomplete**: interactive rows (file dialogs, clipboard, notifications, window management, DnD, focus-on-second-launch, menu launch, uninstall) are ⬜ — this environment has no user session and no working synthetic input (T047 checklist above, SC-009 not yet claimed).
- **Automated coverage gaps**: mock HTTP search/download tests (T028–T031), persistence restart loop (T041), unicode-path suite (SC-007), test runner/report (T050) do not exist yet → quickstart §3/§5/§7/§10 ⬜.
- **Real Windows export not validated** — fixture-based only (T043 pending list).
- **PKGBUILD dependency gap**: `depends=('lua')` but the binary links `liblua5.4` → install `lua54` until the PKGBUILD is corrected (troubleshooting above).
- **Single-instance IPC is machine-global** (`/tmp/_FreeMangaDownloaderInstance_`), not scoped per config dir — parallel sandboxed runs interfere.
- **Spec discrepancy**: "12 languages" vs 11 shipped `.po` files (matches upstream) — needs resolution before SC-014 can be claimed.
- **Idle-resource verification** (1-hour, SC-013) and close-mid-download orphan check are owned by T054 — not run here.
