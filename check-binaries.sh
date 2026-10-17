#!/usr/bin/env bash
# Comprueba que lo empaquetado sirve para macOS 10.15:
#   1. minos de cada ejecutable (LC_BUILD_VERSION) = 10.15 y arquitectura x86_64
#   2. ningún framework enlazado es de macOS 11 o posterior (dyld no abriría la app en Catalina)
#   3. LSMinimumSystemVersion del Info.plist final = 10.15
#
# Uso: check-binaries.sh <ruta-a-pdfcraft>
set -euo pipefail

ROOT="${1:?uso: check-binaries.sh <ruta-a-pdfcraft>}"
WORK="${CARGO_TARGET_DIR:-$ROOT/target}/macos-package"
APP="$WORK/PdfCraft.app"
BINS=("$APP/Contents/MacOS/PdfCraft" "$WORK/bin/pdfcraft-cli")
EXPECTED=10.15

# Frameworks del sistema que no existen en Catalina (aparecieron en macOS 11+).
NEWER_FRAMEWORKS='UniformTypeIdentifiers|AppTrackingTransparency|MLCompute|Virtualization|ScreenTime|ScreenCaptureKit|ShazamKit|GroupActivities|ExtensionKit|SwiftData|Observation'

fail=0
for bin in "${BINS[@]}"; do
  echo "== $bin"
  [ -f "$bin" ] || { echo "error: no existe" >&2; fail=1; continue; }

  lipo -info "$bin"
  if [ "$(lipo -archs "$bin")" != "x86_64" ]; then
    echo "error: se esperaba solo x86_64" >&2
    fail=1
  fi

  minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f && $1=="minos"{print $2; exit}')"
  if [ -z "$minos" ]; then
    # Binarios para targets antiguos usan LC_VERSION_MIN_MACOSX en lugar de LC_BUILD_VERSION.
    minos="$(otool -l "$bin" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f && $1=="version"{print $2; exit}')"
  fi
  echo "minos: ${minos:-desconocido}"
  if [ "$minos" != "$EXPECTED" ]; then
    echo "error: minos debería ser $EXPECTED" >&2
    fail=1
  fi

  echo "bibliotecas enlazadas:"
  otool -L "$bin" | tail -n +2
  if otool -L "$bin" | grep -E "/($NEWER_FRAMEWORKS)\.framework/" >/dev/null; then
    echo "error: enlaza un framework que no existe en macOS 10.15" >&2
    fail=1
  fi
done

plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
echo "LSMinimumSystemVersion: $plist_min"
if [ "$plist_min" != "$EXPECTED" ]; then
  echo "error: LSMinimumSystemVersion debería ser $EXPECTED" >&2
  fail=1
fi

[ "$fail" = 0 ] && echo "ok: binarios listos para macOS $EXPECTED"
exit "$fail"
