#!/usr/bin/env bash
# Comprueba que lo empaquetado sirve para macOS 10.15:
#   1. Cada ejecutable (el del .app y todo macos-package/bin/) es solo x86_64 con minos = 10.15.
#   2. Ningún framework enlazado es de macOS 11 o posterior.
#   3. Ningún símbolo importado de frameworks de Apple, enlazado de forma fuerte (no weak), está
#      anotado en el SDK como disponible solo desde macOS 11 o posterior. dyld se niega a abrir la
#      app entera si falta uno ("Symbol not found"), aunque la función nunca se use.
#   4. LSMinimumSystemVersion del Info.plist final = 10.15.
#
# Lo que esto NO detecta: métodos Objective-C de macOS 11+ llamados por selector (objc2 los
# resuelve en tiempo de ejecución). Esos solo fallan al usar esa función concreta.
#
# Compatible con bash 3.2 (el /bin/bash de macOS).
# Uso: check-binaries.sh <ruta-a-la-app> <Nombre del .app, p. ej. PdfCraft>
set -euo pipefail

ROOT="${1:?uso: check-binaries.sh <ruta-a-la-app> <Nombre>}"
NAME="${2:?uso: check-binaries.sh <ruta-a-la-app> <Nombre>}"
WORK="${CARGO_TARGET_DIR:-$ROOT/target}/macos-package"
APP="$WORK/$NAME.app"
EXPECTED=10.15
EXPECTED_NUM=1015

NEWER_FRAMEWORKS='UniformTypeIdentifiers|AppTrackingTransparency|MLCompute|Virtualization|ScreenTime|ScreenCaptureKit|ShazamKit|GroupActivities|ExtensionKit|SwiftData|Observation'
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FW_ROOT="$SDK/System/Library/Frameworks"

# "11.0" -> 1100, "10.15" -> 1015, "10_9" -> 1009
vnum() {
  local v="${1//_/.}" major minor
  major="${v%%.*}"
  minor="${v#*.}"
  [ "$minor" = "$v" ] && minor=0
  minor="${minor%%.*}"
  echo $((10#$major * 100 + 10#$minor))
}

# Menor versión de macOS con la que el SDK anota la declaración de $1 en los headers bajo $2.
# Toma la línea con el símbolo (fuera de comentarios) hasta el ';' o '{' que la cierra, más la
# línea anterior si es una anotación suelta. Vacío si no hay anotación. Con varias declaraciones
# se queda con la menor: así una mención en otra declaración no da un falso positivo.
sdk_min_version() {
  local sym="$1" dir="$2" files
  files="$(grep -rlw -- "$sym" "$dir" --include='*.h' 2>/dev/null || true)"
  [ -n "$files" ] || return 0
  # shellcheck disable=SC2086
  awk -v sym="$sym" '
    function scan(text,   rest, m, v, best) {
      best = ""
      rest = text
      while (match(rest, /mac(os|osx)\([0-9]+(\.[0-9]+)*\)/)) {
        m = substr(rest, RSTART, RLENGTH); sub(/^[^(]*\(/, "", m); sub(/\)$/, "", m)
        v = m; if (best == "" || cmp(v, best) < 0) best = v
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = text
      while (match(rest, /__MAC_[0-9]+_[0-9]+/)) {
        m = substr(rest, RSTART + 6, RLENGTH - 6); gsub(/_/, ".", m)
        if (best == "" || cmp(m, best) < 0) best = m
        rest = substr(rest, RSTART + RLENGTH)
      }
      rest = text
      while (match(rest, /NS_AVAILABLE(_MAC)?\([0-9]+_[0-9]+/)) {
        m = substr(rest, RSTART, RLENGTH); sub(/^[^(]*\(/, "", m); gsub(/_/, ".", m)
        if (best == "" || cmp(m, best) < 0) best = m
        rest = substr(rest, RSTART + RLENGTH)
      }
      return best
    }
    function cmp(a, b,   pa, pb, na, nb) {
      split(a, pa, "."); split(b, pb, ".")
      na = pa[1] * 100 + pa[2]; nb = pb[1] * 100 + pb[2]
      return na - nb
    }
    FNR == 1 { prev = ""; collecting = 0 }
    {
      line = $0
      if (collecting) {
        if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*@(end|interface|protocol)/) { finish(); collecting = 0; prev = line; next }
        buf = buf " " line; n++
        if (line ~ /[;{]/ || n >= 6) { finish(); collecting = 0 }
        prev = line; next
      }
      if (line ~ /^[ \t]*(\/\/|\*|\/\*)/) { prev = line; next }
      if (line ~ ("(^|[^A-Za-z0-9_])" sym "([^A-Za-z0-9_]|$)")) {
        buf = line; n = 1
        if (prev ~ /^[ \t]*(API_AVAILABLE|API_DEPRECATED|__OSX_AVAILABLE|NS_AVAILABLE|NS_CLASS_AVAILABLE|AVAILABLE_MAC)/) buf = prev " " buf
        # Una clase o protocolo: su anotación va en la misma línea o en la anterior, no más abajo.
        if (line ~ /[;{]/ || line ~ /@(interface|protocol)/) finish(); else collecting = 1
      }
      prev = line
    }
    function finish(   v) {
      v = scan(buf)
      if (v != "" && (found == "" || cmp(v, found) < 0)) found = v
    }
    END { if (found != "") print found }
  ' $files
}

# Directorio del framework $1 en el SDK (incluye subframeworks, p. ej. CoreServices/LaunchServices),
# con caché en un archivo: bash 3.2 no tiene arreglos asociativos.
FW_CACHE="$(mktemp)"
trap 'rm -f "$FW_CACHE"' EXIT
framework_dir() {
  local fw="$1" hit dir
  hit="$(grep -m1 "^$fw=" "$FW_CACHE" || true)"
  if [ -n "$hit" ]; then echo "${hit#*=}"; return 0; fi
  dir="$(find "$FW_ROOT" -maxdepth 3 -type d -name "$fw.framework" 2>/dev/null | head -1)"
  echo "$fw=$dir" >>"$FW_CACHE"
  echo "$dir"
}

check_symbols() {
  local bin="$1" bad=0 line sym fw dirs v count=0
  # nm -m: "(undefined) external _VTSessionSetProperty (from VideoToolbox)"; los weak dicen "weak".
  while IFS= read -r line; do
    case "$line" in *"(undefined)"*"(from "*) ;; *) continue ;; esac
    case "$line" in *" weak "*) continue ;; esac
    fw="${line##*(from }"; fw="${fw%)}"
    case "$fw" in lib*) continue ;; esac
    sym="$(echo "$line" | awk '{for (i = 1; i <= NF; i++) if ($i == "external") { print $(i + 1); exit }}')"
    sym="${sym#_}"
    case "$sym" in OBJC_CLASS_\$_*) sym="${sym#OBJC_CLASS_\$_}" ;; OBJC_METACLASS_\$_*) continue ;; esac
    [ -n "$sym" ] || continue
    dirs="$(framework_dir "$fw")"
    [ -n "$dirs" ] || continue
    count=$((count + 1))
    v="$(sdk_min_version "$sym" "$dirs")"
    if [ -n "$v" ] && [ "$(vnum "$v")" -gt "$EXPECTED_NUM" ]; then
      echo "error: $sym ($fw) existe desde macOS $v y está enlazado de forma fuerte" >&2
      bad=1
    fi
  done < <(nm -m -u "$bin" 2>/dev/null)
  echo "símbolos de frameworks revisados contra el SDK: $count"
  return "$bad"
}

fail=0
bins=("$APP/Contents/MacOS/$NAME")
for f in "$WORK"/bin/*; do [ -f "$f" ] && bins+=("$f"); done

for bin in "${bins[@]}"; do
  echo "== $bin"
  [ -f "$bin" ] || { echo "error: no existe" >&2; fail=1; continue; }

  if [ "$(lipo -archs "$bin")" != "x86_64" ]; then
    echo "error: se esperaba solo x86_64, hay: $(lipo -archs "$bin")" >&2
    fail=1
  fi

  minos="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{f=1} f && $1=="minos"{print $2; exit}')"
  [ -n "$minos" ] || minos="$(otool -l "$bin" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f && $1=="version"{print $2; exit}')"
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

  check_symbols "$bin" || fail=1
done

plist_min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
echo "LSMinimumSystemVersion: $plist_min"
if [ "$plist_min" != "$EXPECTED" ]; then
  echo "error: LSMinimumSystemVersion debería ser $EXPECTED" >&2
  fail=1
fi

if [ "$fail" = 0 ]; then echo "ok: $NAME listo para macOS $EXPECTED"; fi
exit "$fail"
