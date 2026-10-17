#!/usr/bin/env bash
# Baja el target de despliegue de PdfCraft de macOS 11.0 a 10.15.
#
# Upstream fija 11.0 en dos sitios que deben coincidir:
#   packaging/macos/package.sh     MACOSX_DEPLOYMENT_TARGET (lo que ve el linker: minos del binario)
#   packaging/macos/Info.plist.in  LSMinimumSystemVersion   (lo que revisa Finder al abrir la app)
#
# Falla si alguno de los dos no está como se espera: si una versión nueva cambia esos archivos,
# es mejor enterarse aquí que generar un binario a medio parchear.
#
# Uso: patch.sh <ruta-a-pdfcraft>
set -euo pipefail

ROOT="${1:?uso: patch.sh <ruta-a-pdfcraft>}"
TARGET=10.15
SCRIPT="$ROOT/packaging/macos/package.sh"
PLIST="$ROOT/packaging/macos/Info.plist.in"

replace_once() {
  local file="$1" from="$2" to="$3" count
  count="$(grep -cF -- "$from" "$file" || true)"
  if [ "$count" != 1 ]; then
    echo "error: se esperaba exactamente una línea '$from' en $file y hay $count" >&2
    exit 1
  fi
  # sed -i.bak funciona igual en BSD sed (macOS) y GNU sed.
  sed -i.bak "s|$(printf '%s' "$from" | sed 's/[.[\*^$|]/\\&/g')|$to|" "$file"
  rm -f "$file.bak"
  grep -qF -- "$to" "$file" || { echo "error: el reemplazo no quedó en $file" >&2; exit 1; }
  echo "ok: $file: '$from' -> '$to'"
}

replace_once "$SCRIPT" "export MACOSX_DEPLOYMENT_TARGET=11.0" "export MACOSX_DEPLOYMENT_TARGET=$TARGET"

# En el plist el valor va en la línea siguiente a la clave; se reemplaza ese <string> en concreto.
if [ "$(grep -c '<key>LSMinimumSystemVersion</key>' "$PLIST")" != 1 ]; then
  echo "error: LSMinimumSystemVersion no aparece exactamente una vez en $PLIST" >&2
  exit 1
fi
awk -v target="$TARGET" '
  prev ~ /<key>LSMinimumSystemVersion<\/key>/ {
    if ($0 !~ /<string>11\.0<\/string>/) { print "error: valor inesperado: " $0 > "/dev/stderr"; exit 1 }
    sub(/11\.0/, target)
  }
  { print; prev = $0 }
' "$PLIST" >"$PLIST.new"
mv "$PLIST.new" "$PLIST"
grep -A1 '<key>LSMinimumSystemVersion</key>' "$PLIST" | grep -qF "<string>$TARGET</string>" \
  || { echo "error: LSMinimumSystemVersion no quedó en $TARGET" >&2; exit 1; }
echo "ok: $PLIST: LSMinimumSystemVersion -> $TARGET"
