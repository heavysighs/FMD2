#!/usr/bin/env python3
"""Mojave gate for FMD2.app: fail if any Mach-O binary inside the bundle
declares a minimum macOS version above 10.14, loads a library by an
absolute path that Mojave does not ship, or loads an @rpath/@loader_path
library that is missing from the bundle."""
import os
import plistlib
import sys

import lief

TARGET = (10, 14, 0)

# /usr/lib libraries that macOS 10.14 itself ships (dyld cache). Anything
# else under /usr/lib (e.g. libpcre2-8.0.dylib, which only newer macOS
# versions carry) must be bundled and referenced via @rpath instead.
MOJAVE_USR_LIB = {
    "libSystem.B.dylib",
    "libSystem.dylib",
    "libiconv.2.dylib",
    "libcharset.1.dylib",
    "libobjc.A.dylib",
    "libc++.1.dylib",
    "libc++abi.dylib",
    "libz.1.dylib",
    "libbz2.1.0.dylib",
    "libxml2.2.dylib",
    "libxslt.1.dylib",
    "libresolv.9.dylib",
    "libedit.3.dylib",
    "libncurses.5.4.dylib",
    "libsqlite3.dylib",
    "libsqlite3.0.dylib",
}


def min_os_versions(binary):
    results = []
    for cmd in binary.commands:
        cname = cmd.__class__.__name__
        if cname == "BuildVersion":
            results.append(tuple(cmd.minos))
        elif cname == "VersionMin":
            v = cmd.version
            if isinstance(v, (list, tuple)):
                results.append(tuple(v))
            else:
                v = int(v)
                results.append(((v >> 16) & 0xFFFF, (v >> 8) & 0xFF, v & 0xFF))
    return results


LOAD_TYPES = {
    "LOAD_DYLIB",
    "LOAD_WEAK_DYLIB",
    "REEXPORT_DYLIB",
    "LAZY_LOAD_DYLIB",
    "LOAD_UPWARD_DYLIB",
}


def load_names(binary):
    """Real library load commands only. LIEF also exposes the LC_ID_DYLIB
    identity command and the LC_LOAD_DYLINKER command (/usr/lib/dyld) with
    a name attribute; neither is a dependency."""
    names = []
    for cmd in binary.commands:
        if cmd.__class__.__name__ != "DylibCommand":
            continue
        ctype = str(getattr(cmd, "command", "")).split(".")[-1]
        if ctype in LOAD_TYPES:
            names.append(cmd.name)
    return names


def rpath_list(binary):
    out = []
    for cmd in binary.commands:
        if "path" in cmd.__class__.__name__.lower() and getattr(cmd, "path", None):
            out.append(cmd.path)
    return out


def iter_binaries(path):
    try:
        parsed = lief.parse(path)
    except Exception:
        return
    if parsed is None:
        return
    if isinstance(parsed, lief.MachO.FatBinary):
        yield from parsed
    elif isinstance(parsed, lief.MachO.Binary):
        yield parsed


def main():
    app = sys.argv[1]
    failures = []
    checked = 0

    plist_path = os.path.join(app, "Contents", "Info.plist")
    with open(plist_path, "rb") as fh:
        plist = plistlib.load(fh)
    ls_min = plist.get("LSMinimumSystemVersion")
    if ls_min:
        parts = tuple(int(p) for p in str(ls_min).split("."))
        parts = parts + (0,) * (3 - len(parts))
        if parts > TARGET:
            failures.append(f"Info.plist LSMinimumSystemVersion {ls_min} > 10.14")
        print(f"Info.plist LSMinimumSystemVersion: {ls_min}")

    binaries = []
    for root, _dirs, files in os.walk(app):
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                continue
            for binary in iter_binaries(path):
                binaries.append((path, root, binary))

    for path, _root, binary in binaries:
        checked += 1
        for version in min_os_versions(binary):
            if version > TARGET:
                failures.append(
                    f"{os.path.relpath(path, app)} declares min macOS "
                    f"{'.'.join(map(str, version))} > 10.14"
                )
    print(f"Mach-O binaries checked: {checked}")

    # Dependency closure + absolute-path audit.
    for path, root, binary in binaries:
        rel = os.path.relpath(path, app)
        rpaths = rpath_list(binary)
        for dep in load_names(binary):
            if dep.startswith("@loader_path/"):
                target = os.path.normpath(
                    os.path.join(root, dep[len("@loader_path/"):])
                )
                if not os.path.exists(target):
                    failures.append(f"{rel} loads missing {dep}")
            elif dep.startswith("@rpath/"):
                leaf = dep[len("@rpath/"):]
                found = None
                for rp in rpaths:
                    cand = rp.replace("@loader_path", root).replace(
                        "@executable_path",
                        os.path.join(app, "Contents", "MacOS"),
                    )
                    cand = os.path.normpath(os.path.join(cand, leaf))
                    if os.path.exists(cand):
                        found = cand
                        break
                if found is None:
                    failures.append(f"{rel} loads unresolvable {dep}")
            elif dep.startswith("/System/Library/"):
                continue  # macOS frameworks, present on Mojave if min-OS passes
            elif dep.startswith("/usr/lib/"):
                leaf = os.path.basename(dep)
                if leaf not in MOJAVE_USR_LIB:
                    failures.append(
                        f"{rel} loads /usr/lib/{leaf}, not shipped with Mojave"
                    )
            elif dep.startswith("/"):
                failures.append(f"{rel} loads non-system absolute path {dep}")

    if failures:
        print("MOJAVE GATE FAILED:")
        for failure in failures:
            print(" -", failure)
        sys.exit(1)
    print("MOJAVE GATE PASSED: min macOS <= 10.14, all loads resolvable on Mojave")


if __name__ == "__main__":
    main()
