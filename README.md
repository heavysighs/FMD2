# FMD2 for Linux

A native **Linux port of [FMD2 — Free Manga Downloader 2](https://github.com/dazedcat19/FMD2)**,
the free, open-source manga manager and downloader written in Object Pascal
(Lazarus / Free Pascal).

It runs on Linux with the Qt6 widgetset, keeps its data in the usual XDG
locations, and ships with an Arch package and a desktop entry.

> [!IMPORTANT]
> **This is a port, not an actively maintained fork.** It works — it builds,
> packages and runs — but I might not keep maintaining it. Use it as-is;
> issues and pull requests may go unanswered.

## Credits

All credit for the original application goes to **dazedcat19** and the
Free Manga Downloader contributors:

- Original project: [github.com/dazedcat19/FMD2](https://github.com/dazedcat19/FMD2)
- This repository only contains the Linux port changes on top of FMD2 2.0.34.5.

FMD2 is released under the **GPLv2** — see [license.txt](license.txt) and
[licenses/THIRD-PARTY-LICENSE.txt](licenses/THIRD-PARTY-LICENSE.txt).

## Requirements

- Arch Linux (or any distro with FPC ≥ 3.2.2, Lazarus ≥ 4.8 and the Qt6
  bindings `qt6pas`)
- Libraries: sqlite, openssl, pcre2, libwebp, brotli, zstd, lua54, duktape, 7zip

On Arch:

```sh
sudo pacman -S --needed fpc lazarus qt6pas sqlite openssl pcre2 libwebp \
  brotli zstd lua54 duktape 7zip
```

## Build

```sh
./scripts/build-deps.sh    # fetch + patch pinned third-party Lazarus packages (once)
lazbuild --lazarusdir=/usr/lib/lazarus --build-mode=Linux --widgetset=qt6 mangadownloader/md.lpi
./bin/x86_64-linux/fmd
```

### Arch package

```sh
cd packaging/arch
makepkg -si
fmd
```

## Continuous integration

Every push and pull request runs [.github/workflows/build.yml](.github/workflows/build.yml)
on an Arch Linux container: it builds the pinned third-party packages,
compiles `fmd`, produces the Arch package, and uploads both as workflow
artifacts.

## What changed for Linux

- XDG config/data/cache paths (`~/.config/fmd2`, `~/.local/share/fmd2`)
- Qt6 widgetset, correct process spawning and path handling on Linux
- OpenSSL 3 dynamic TLS (certificate verification stays enabled)
- Lua website modules loaded from the XDG data directory
- Arch packaging, `.desktop` entry and icons

Port details live in [docs/LINUX_PORT.md](docs/LINUX_PORT.md).
