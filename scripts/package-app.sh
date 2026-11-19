#!/usr/bin/env bash
# Package the lazbuild output (bin/x86_64-darwin/fmd.app) into FMD2.app:
# bundle the Mojave-built dylibs in Contents/Frameworks, ship the program
# data (lua/, languages/, images/) next to the executable — FMDOptions
# resolves program files relative to the exe dir and seeds the lua tree
# into the user's XDG data dir on first run — rewrite every non-system
# load command to @rpath form, and ad-hoc sign.
#
# Expects the Mojave-targeted dylibs in $HOME/mojave-libs (built by the
# mojave-build workflow) and liblua5.3.dylib in /usr/local/lib.
set -euo pipefail

LIBS="$HOME/mojave-libs"
SRC_APP="bin/x86_64-darwin/fmd.app"
APP="FMD2.app"
EXE="$APP/Contents/MacOS/fmd"
FW="$APP/Contents/Frameworks"

rm -rf "$APP"
cp -R "$SRC_APP" "$APP"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.heavysighs.fmd2" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.0.34.5" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 2.0.34.5" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 10.14" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 10.14" "$PLIST"

mkdir -p "$FW"
cp "$LIBS/libcrypto.3.dylib" "$LIBS/libssl.3.dylib" "$LIBS/libduktape.dylib" \
   "$LIBS/libpcre2-8.dylib" /usr/local/lib/liblua5.3.dylib "$FW/"

cp -R lua languages images "$APP/Contents/MacOS/"

# Rewrite any load command that names one of the bundled libraries (by
# whatever path the linker recorded) to its @rpath canonical name.
fix_refs() {
  local bin="$1" dep base
  otool -L "$bin" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    base="$(basename "$dep")"
    case "$base" in
      libcrypto.3.dylib|libssl.3.dylib|liblua5.3.dylib|libpcre2-8.dylib)
        [ "$dep" = "@rpath/$base" ] || install_name_tool -change "$dep" "@rpath/$base" "$bin"
        ;;
      libduktape*)
        [ "$dep" = "@rpath/libduktape.dylib" ] || install_name_tool -change "$dep" "@rpath/libduktape.dylib" "$bin"
        ;;
      libpcre2-8*)
        [ "$dep" = "@rpath/libpcre2-8.dylib" ] || install_name_tool -change "$dep" "@rpath/libpcre2-8.dylib" "$bin"
        ;;
    esac
  done
}

for dylib in "$FW"/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib"
  install_name_tool -add_rpath @loader_path "$dylib" 2>/dev/null || true
  fix_refs "$dylib"
done

install_name_tool -add_rpath @executable_path/../Frameworks "$EXE" || true
fix_refs "$EXE"

codesign --force --deep --sign - "$APP"
echo "packaged $APP:"
otool -L "$EXE"
