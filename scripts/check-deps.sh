#!/usr/bin/env bash
# check-deps.sh — verify FMD2 Linux build/runtime dependencies (tasks T004/T005)
set -u

ok=0; miss=0
check() { # check <type> <name>
  local type="$1" name="$2"
  case "$type" in
    cmd)
      if command -v "$name" >/dev/null 2>&1; then
        printf 'OK   cmd    %-14s %s\n' "$name" "$(command -v "$name")"; ok=$((ok+1))
      else
        printf 'MISS cmd    %s\n' "$name"; miss=$((miss+1))
      fi ;;
    pkg)
      if pacman -Qi "$name" 2>/dev/null | grep -q "^Name"; then
        printf 'OK   pkg    %-14s %s\n' "$name" "$(pacman -Qi "$name" 2>/dev/null | awk -F': ' '/^Version/{print $2}')"; ok=$((ok+1))
      else
        printf 'MISS pkg    %s\n' "$name"; miss=$((miss+1))
      fi ;;
    so)
      if ldconfig -p 2>/dev/null | grep -q "$name"; then
        printf 'OK   so     %s\n' "$name"; ok=$((ok+1))
      else
        printf 'MISS so     %s\n' "$name"; miss=$((miss+1))
      fi ;;
  esac
}

echo "== Commands =="
check cmd fpc
check cmd lazbuild
check cmd 7z

echo "== Arch packages =="
for p in fpc lazarus qt6pas openssl sqlite pcre2 libwebp brotli zstd lua 7zip duktape; do
  check pkg "$p"
done

echo "== Shared libraries =="
for so in libssl.so.3 libcrypto.so.3 libsqlite3.so libpcre2-8.so libwebp.so libbrotlidec.so libzstd.so libduktape.so; do
  check so "$so"
done

echo "== Optional =="
for c in magick Xvfb xdotool lazarus-qt6; do
  if command -v "$c" >/dev/null 2>&1; then
    printf 'OK   opt    %s\n' "$c"
  else
    printf 'MISS opt    %s (optional)\n' "$c"
  fi
done

echo
echo "Result: $ok ok, $miss missing"
[ "$miss" -eq 0 ]
