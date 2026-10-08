# FMD2 — Phase 1 Technical Assessment (Linux Port)

**Feature**: 001-fmd2-linux-port | **Status**: T001–T012 complete (2026-10-08)
**Rule (FR-001, SC-001)**: This assessment was produced **before any application source modification** (checkpoint T012 verified: `git status` shows only new docs/scripts/tests/spec files).

## 1. Repository & version verification (T002)

| Item | Result |
|---|---|
| Authoritative repo | `https://github.com/dazedcat19/FMD2` |
| Snapshot source | Working copy at `/home/hanekawa/fmd2`, README badges & `latest_version.json` → release **2.0.34.5** |
| Verification method | Clone of upstream `master`, `git archive` of baseline compared with `diff -rq` against working copy |
| Upstream HEAD checked | `ad3a5b6` (2026-10-04) "Tapas: Fixed all (#3281)" |
| Result | **Application source is byte-identical to upstream HEAD.** Only differences: upstream-only `.gitattributes`, `.github/`, `.gitmodules`; our `.gitignore` (upstream's + `.opencode/` + OS-noise + `3rd/`) |
| Baseline tag | `upstream-2.0.34.5` (pristine, 1074 files) |

**Important discovery**: upstream declares a git submodule `3rd/internettools` → `https://github.com/benibela/internettools.git` (`.gitmodules`). Our snapshot lacks `3rd/`; InternetTools is fetched pinned by `scripts/build-deps.sh` (T006).

## 2. License (T011)

- `license.txt` is the verbatim **GNU GPL v2, June 1991**; README: "released under the GPLv2 license". `licenses/GPL-2.0.txt` duplicates it.
- Third-party notices bundled upstream: `licenses/THIRD-PARTY-LICENSE.txt` + per-library files (7-Zip, Brotli, Duktape, LibWebP, Lua, OpenSSL, PCRE, Zstandard, LGPL-2.1, MPL-1.1). These travel with the port unchanged (FR-016).
- **Terms applied to this port**: derivative work is permitted under GPLv2 — modified sources offered under GPLv2, all license/notice files preserved, original project credited; no additional restrictions may be added (consistent with FR-010: no credential embedding, no telemetry, notices preserved).
- **Community Linux ports**: none found (research R2/R8) — GitHub + AUR searches surfaced no FMD2 Linux port and no FMD2 AUR package; AUR manga tools (`houdoku`, `yomikiru-bin`, `mangodl-git`, `comic-dl`) are unrelated applications and out of scope. Prior art is limited to upstream's own `{$IFDEF UNIX}` conditionals (md.lpr, naturalsortunit, synapse, image DLL names).

## 3. Architecture map (T009)

| Subsystem | Key files (file:role) | Notes |
|---|---|---|
| Entry point | `mangadownloader/md.lpr` | LCL program; already has `{$IFDEF UNIX} cthreads`, `simpleipc` single-instance, loads `ssl_openssl3`, `sqlite3dyn`, `MultiLog`/`FileChannel` logging, dark style (`uDarkStyle*`) |
| Project/packaging | `mangadownloader/md.lpi` | 15 required packages; build modes win32/win64 only; 36 project files; `OtherUnitFiles` reaches `../baseunits` (+ `synapse`, `lua`, `modules`, `animatedgifs`, `SimpleException`) |
| GUI shell | `mangadownloader/forms/frmMain.pas`+`.lfm` (215 KB/301 KB) + 17 sibling forms (`frmDropTarget`, `frmAccountManager`, `frmCheckModules`, `frmLogger`, `frmNewChapter`, …) | Console/logger window, menus, trays, tab views |
| Website modules | `baseunits/WebsiteModules.pas`, `WebsiteModulesSettings.pas`, `baseunits/lua/LuaWebsiteModules.pas`, **`lua/modules/` (52 `.lua` scrapers)**, `lua/templates`, `lua/extras` | Scrapers are Lua scripts + Pascal `TModuleContainer` registry; portable (FR-007) |
| HTTP/network | `baseunits/httpsendthread.pas`, `httpcookiemanager.pas`, vendored **synapse** (`baseunits/synapse/`, incl. `ssl_openssl3`), `XQueryEngineHTML.pas` (InternetTools HTML/XPath) | Synapse proven cross-platform (`ssfpc.inc`/`sslinux.inc`/`sswin32.inc`); InternetTools from `3rd/` |
| Download engine | `baseunits/uDownloadsManager.pas` (58 KB) — `TTaskContainer`/`TTaskContainers` queue, worker threads; `uSilentThread`, `uGetMangaInfosThread`, `uUpdateThread` | Concurrency via FPC threads; portable |
| Storage | `SQLiteData.pas`, `DBDataProcess.pas`, `FavoritesDB.pas`, `DownloadsDB.pas`, `DownloadedChaptersDB.pas`, `uFavoritesManager.pas` | SQLite via `sqlite3dyn` (system lib) — portable; **paths** must move to XDG (FR-005) |
| Configuration | `baseunits/FMDOptions.pas`, `FMDVars.pas` | Default dir = exe folder (`FMDOptions.pas:315-316`) → XDG shim (T017); `ZIP_EXE='7za.exe'` (`:33`); `{$IFDEF WINDOWS}` at `:36` |
| Image/archive pipeline | `uPacker.pas` (zip via 7z exe), `Img2Pdf.pas`, `uEpub.pas`, `imagemagickmanager.pas`, `webp.pas`/`webp` loader, `animatedgifs/`, `ImagePuzzle.pas` | 7z already cross-platform (R4); ImageMagick has bare-`magick` fallback; webp/brotli/zstd `.so` names already branched |
| Update | `SelfUpdater.pas`, `CheckUpdate.pas`, `DBUpdater.pas`, `uUpdateThread.pas`, `updater/`, `updaterslim/` (Windows exe projects) | FR-023: disable in-app self-update on Linux; package-manager updates only |
| Logging | `MultiLog` + `FileChannel` (external pkg `multiloglaz`) + `SimpleException/` crash handler | FR-025: original logging + per-user log file |
| i18n | `SimpleTranslator.pas`, `languages/fmd.*.po` (12 languages), `*.lrj` form resources | FR-022/SC-014: all 12 preserved; PO format is portable |
| Crypto/misc | `BaseCrypto.pas`, `Duktape.pas`/`Duktape.Api.pas` (JS bypass), `pcre2.pas`, `BrotliDec.pas`, `ZstdDec.pas`, `naturalsortunit.pas` | Duktape `.so` name already branched (`Duktape.Api.pas:38`) |

## 4. Subsystem portability classification (T010)

| Classification | Subsystems |
|---|---|
| **Linux-compatible (no change)** | Lua website modules (52 scripts), SQLite storage layer, download engine core (FPC threads), i18n/PO machinery, synapse HTTP (per-OS includes), TAChart/VirtualTree widgets via LCL, log framework (MultiLog `FileChannel` → file), JSON/INI config format, PDF/EPUB builders, PCRE2/Brotli/Zstd (`.so` branches already present) |
| **Minor-change** | `FMDOptions.pas` path defaults → XDG (`~/.config/fmd2`, `~/.local/share/fmd2`, `~/.cache/fmd2`) + `7za`→`7z` (T017–T020); `md.lpi`/build: add `linux_x64_64`-style build mode, widgetset qt6 (T015); launcher shell script + `.desktop` (T022); PKGBUILD (T025); self-updater disabled on Linux (T021); `imagemagickmanager.pas` registry/PATH scan → `FindDefaultExecutablePath` (T019); `VirtualPropertyGridEditLink.pas` drop `Windows, Messages` units (LCL `PostMessage`/`LMessages` already in uses) |
| **Linux-specific (new code)** | XDG dirs & portable-path resolver; log file location; install/uninstall desktop integration; Windows→Linux config/data migration doc+tool (T026); headless GUI test harness (Xvfb+xdotool, T036) |
| **Substantial-redesign** | Drag & drop: `frmDropTarget.pas` implements COM `IDropTarget` (OleInitialize/RegisterDragDrop/RevokeDragDrop, `frmDropTarget.pas:15,259,278`) → replace with LCL `AllowDropFiles`/`OnDropFiles` (T044); window-subclassing hooks in `frmMain.pas:1229-1231,1451-1453` (`SetWindowLongPtr` WNDPROC) → delete/no-op on Linux (guard exists, T045) |
| **Blocked / disabled by design** | In-app self-updater (`SelfUpdater.pas`, `updater.exe`, `updaterslim/`) — never runs on Linux (FR-023); OLE clipboard/drag COM paths; `WinAPI.pas` unit (LoadLibrary Windows API shim — excluded from Linux build, consumers already `{$ifdef windows}`-guarded: `frmMain.pas:1026-1048`); Windows-only synapse units (`Crypt32`, `ssl_openssl_capi`, `ssl_sbb*`, `synaser`) — not referenced outside synapse and not selected on UNIX |

## 5. Porting strategy comparison & recommendation (T012)

| Option | Effort | Functionality parity (FR-001) | Verdict |
|---|---|---|---|
| **A. Direct LCL/Qt6 port** — keep codebase, add Linux build mode, replace Windows seams | Medium (est. ~40 files touched, most behind existing `{$IFDEF}`) | Full: all 12 languages, all 52 Lua modules, full GUI feature set | ✅ **Chosen (research R3)** — upstream already structured for this (`{$IFDEF UNIX}`, cross-platform synapse/LCL) |
| B. Rewrite on new stack (e.g. GTK/Qt-native, Electron) | Very high | High ceiling but new bugs; loses upstream fixes | ❌ violates effort and parity goals; future upstream merges impossible |
| C. Wine wrapper around Windows build | Low | Near-full but fragile, poor KDE/GNOME integration, contradicts "native" goal | ❌ not native; FR goal violated |
| D. Hybrid (native UI + Wine download engine) | High | Complexity of both | ❌ worst of both |

**Recommendation: Option A**, phased as the task plan already sequences it:

1. **Phases 1–2 (done)**: baseline, verification, deps, assessment — no app source touched.
2. **US1 checkpoint (T012)**: this document; gate for code changes.
3. **US2 (build & run)**: `linux_64` build mode + qt6 widgetset, XDG path shim, 7z name, disable updater, launcher — first launch.
4. **US3–US5 (config, storage, i18n)**: migrations, data dirs, all 12 translations.
5. **US6 (Windows-specific UI)**: drag-drop, window hooks, ImageMagick discovery, packaging.
6. **US7 (tests)**: unit/integration/e2e under Xvfb; mocked network only (FR-020).
7. **US8 (docs/release)**: LINUX_PORT.md, PKGBUILD finalization, LIMITATIONS.

## 6. Windows API audit (T008)

Method: case-insensitive scan of every `uses` clause (and Windows-unit identifiers) across `mangadownloader/` and `baseunits/` (`*.pas`, `*.lpr`, `*.inc`), excluding comments and the vendored synapse tree (audited separately). Seeds confirmed: `frmDropTarget.pas:8`, `frmMain.pas:1027`, `baseunits/WinAPI.pas`.

### 6.1 Unguarded Windows units in first-party code (hard compile blockers)

| file:line | Windows units | Usage | Fix (task) |
|---|---|---|---|
| `baseunits/imagemagickmanager.pas:8` | `Windows, Registry` | `TRegistry.Create(KEY_READ)` at `:255,289` (find ImageMagick install), PATH scan `:306` | Drop units; use `FindDefaultExecutablePath`/file-existence (T019) |
| `mangadownloader/forms/frmDropTarget.pas:8` | `Windows, ActiveX, comobj` | `TFormDropTarget = class(TForm, IDropTarget)` `:15`, `OleInitialize` `:259`, `RegisterDragDrop` `:260`, `RevokeDragDrop` `:278` | Replace with LCL `AllowDropFiles`/`OnDropFiles` (T044) |
| `baseunits/VirtualPropertyGridEditLink.pas:8` | `Windows, Messages` | Only `PostMessage(..., WM_KEYDOWN, ...)` `:115`; `LMessages, LCLType` already in uses | Drop both units, verify identifier resolution at compile (T045) |
| `baseunits/WinAPI.pas:1,8` | whole unit = `windows` API shim (`LoadLibrary`, …) | Consumers already guarded: `frmMain.pas:1026-1048` | Exclude unit from Linux build; add `{$IFDEF WINDOWS}`-style guard or omit from project (T045) |

### 6.2 Conditionally guarded Windows code (needs Linux branch where behavior differs)

| file:line(s) | What | Linux status |
|---|---|---|
| `md.lpr:10-11,33,59,190-196,228` | `windows` unit; `Get/SetEnvironmentVariable('PATH',…)` on restart; `--dorestart-pid` | Windows-only restart helper; UNIX path already uses `cthreads` — restart simply not offered (T045) |
| `frmMain.pas:15-16,1026-1048,1229-1231,1451-1453` | `ActiveX, windows`; `WinAPI` import; WNDPROC subclassing via `SetWindowLongPtr` | No-op on Linux (guard exists) — verify no lost functionality; sleep-inhibition hooks `:2001-2019,2564` need `SetThreadExecutionState` equivalent or drop |
| `uBaseUnit.pas:16-17,236,666,882,1477,1483,3099,3111,3131` | `Windows` guarded; path-length/shell helpers | Existing `{$ELSE}` branches; verify at compile |
| `uDownloadsManager.pas:71,476,531,543,758,765` | guarded process/file handles | Existing else-branches; verify |
| `uMisc.pas:8-9,327-495` | `ShellApi, Windows`; `ShellExecuteExW` `:416` with `{$ifndef windows}` alt at `:425` (open URL/file) | Alt branch = `xdg-open`-style; verify |
| `naturalsortunit.pas:37-38,55-409` | `Windows` sort API fallback with explicit non-Windows path | Portable |
| `SimpleException.pas:40-41,212-228` + `SimpleExceptionForm.pas:28-29,81` | `Windows, win32proc` guarded; `'Windows '` string at `:228` | Portable; Linux branch reports kernel name |
| `FMDOptions.pas:36` | guarded Windows default-path block | Replace default with XDG (T017) |
| `BrotliDec.pas:12`, `ZstdDec.pas:12`, `Duktape.Api.pas:38,58` | `{$IFDEF WINDOWS}` DLL names with `{$ELSE}` `.so` names | Already portable |
| `imagemagickmanager.pas:288,306` | comments describing registry/PATH steps | Covered by 6.1 fix |

### 6.3 Vendored synapse (`baseunits/synapse/`) — audit result

- **Portable**: `ssl_openssl_lib/11/3_lib.pas`, `pingsend.pas`, `synachar.pas`, `synaser.pas` etc. all wrap Windows imports in `{$IFDEF MSWINDOWS}`/`{$ELSE}`; OS selected via `ssfpc.inc` / `sslinux.inc` / `sswin32.inc` includes.
- **Windows-only units** `Crypt32.pas:52`, `ssl_openssl_capi.pas:134`, `ssl_sbb.pas:67`, `ssl_sbb16.pas:146`: referenced **only from within synapse** (grep outside `/synapse/` = 0 hits) and not selected by FMD (`md.lpr` uses `ssl_openssl3`). No action beyond excluding them from any package compilation.
- Comment-only "Windows" matches in `blcksock/imap/pop3/smtp/nntp/ftp/mimepart/jedi.inc` are documentation, not code.

**Conclusion**: 4 unguarded first-party compile blockers (§6.1), all already-planned tasks T019/T044/T045; everything else is guarded with existing `{$ELSE}` branches or vendor-internal. Scope matches research R3/R4 estimates — no additional blockers surfaced beyond known seeds.
