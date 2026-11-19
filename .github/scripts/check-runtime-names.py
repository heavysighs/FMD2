#!/usr/bin/env python3
"""Runtime-names gate for FMD2.app: scan the main executable's printable
strings for library file names the app could ask dyld for at runtime
(dlopen/LoadLibrary targets are invisible to the Mach-O load-command
gate). Fail if any name is a Windows (.dll) or Linux (.so) name, or a
.dylib that is neither bundled in Contents/Frameworks nor a library
macOS 10.14 itself ships.

This is the check whose absence let the first FMD2 delivery reach a real
Mojave machine still asking for "libwebp.dll"."""
import os
import re
import sys

# .dylib leaf names macOS 10.14 provides (system or dyld-shared-cache).
MOJAVE_SYSTEM = {
    "libsqlite3.dylib",
    "libsqlite3.0.dylib",
    "libiconv.dylib",
    "libiconv.2.dylib",
    "libcharset.1.dylib",
    "libSystem.B.dylib",
    "libSystem.dylib",
    "libobjc.A.dylib",
    "libc++.1.dylib",
    "libc++abi.dylib",
    "libz.1.dylib",
    "libbz2.1.0.dylib",
    "libxml2.2.dylib",
    "libresolv.9.dylib",
}

TOKEN = re.compile(rb"[A-Za-z0-9_@+/.\-]+\.(?:dll|so|dylib)(?![A-Za-z0-9])")
PRINTABLE = re.compile(rb"[ -~]{4,}")


def main():
    app = sys.argv[1]
    exe = os.path.join(app, "Contents", "MacOS", "fmd")
    frameworks = os.path.join(app, "Contents", "Frameworks")
    bundled = set(os.listdir(frameworks)) if os.path.isdir(frameworks) else set()

    with open(exe, "rb") as fh:
        data = fh.read()
    names = set()
    for chunk in PRINTABLE.findall(data):
        for token in TOKEN.findall(chunk):
            names.add(token.decode("ascii", "replace"))

    failures = []
    for name in sorted(names):
        base = os.path.basename(name)
        if name.endswith(".dll"):
            failures.append(f"Windows library name in Darwin binary: {name}")
        elif name.endswith(".so"):
            failures.append(f"Linux library name in Darwin binary: {name}")
        elif base in bundled or base in MOJAVE_SYSTEM:
            print(f"OK    {name}")
        else:
            failures.append(f"unresolved runtime library name: {name}")

    if failures:
        print("RUNTIME-NAMES GATE FAILED:")
        for failure in failures:
            print(" -", failure)
        sys.exit(1)
    print(f"RUNTIME-NAMES GATE PASSED: {len(names)} library names, all resolved")


if __name__ == "__main__":
    main()
