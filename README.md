# pdfcraft-catalina

Compila [PdfCraft](https://github.com/storytold/pdfcraft) para **macOS 10.15 Catalina (Intel)** con GitHub Actions, sin mantener un fork.

Upstream exige macOS 11.0, pero eso es una decisión de empaquetado, no un requisito del código:

- El código propio prohíbe `unsafe`; las APIs de Apple solo llegan por dependencias.
- **wgpu** soporta macOS 10.13+ y comprueba en tiempo de ejecución cada función de macOS 11+.
- **winit** (parcheado en `vendor/`) cuida el enlazado en macOS < 10.14.
- Los frameworks de macOS 11+ que aparecen en `Cargo.lock` (UniformTypeIdentifiers, etc.) solo los arrastra `objc2-ui-kit`, que es exclusivo de iOS.

## Cómo funciona

1. Clona `storytold/pdfcraft` en el tag `PDFCRAFT_REF` (de momento `v0.8.0`).
2. `patch.sh` cambia `MACOSX_DEPLOYMENT_TARGET` y `LSMinimumSystemVersion` de 11.0 a 10.15. Falla si upstream cambió esos archivos, para no generar un binario a medio parchear.
3. Ejecuta el script oficial `packaging/macos/package.sh --arch x86_64` con firma ad-hoc, sin notarizar.
4. `check-binaries.sh` confirma tres cosas:
   - `minos` = 10.15 y arquitectura x86_64 en la app y el CLI;
   - ningún framework enlazado es de macOS 11+;
   - el `Info.plist` final dice 10.15.
5. Sube como artifact `pdfcraft-<versión>-macos-x86_64.dmg` y `pdfcraft-cli-<versión>-macos-x86_64.zip`.

## Uso

1. Crea un repo en GitHub (puede ser privado) y sube estos archivos tal cual.
2. Ve a **Actions → Build PdfCraft for Catalina → Run workflow**. También se lanza solo con un push a `main` que toque el workflow o los scripts.
3. Al terminar, descarga el artifact desde la página de la ejecución. Dura 30 días.

La primera compilación es la más lenta (LTO con `codegen-units = 1`); las siguientes usan caché.

**Para actualizar a otra versión:** cambia `PDFCRAFT_REF` en `.github/workflows/build.yml`. Revisa también `CRAFT_FONTS_REF`, que es el que fija el `release.yml` de upstream para ese tag.

## Instalar en la Mac

La app tiene firma ad-hoc, así que Gatekeeper la bloquea la primera vez:

```sh
# Tras arrastrar PdfCraft.app a Aplicaciones:
xattr -dr com.apple.quarantine /Applications/PdfCraft.app
```

También puedes hacer clic derecho → **Abrir** → **Abrir**.

Para el CLI:

```sh
unzip pdfcraft-cli-*-macos-x86_64.zip
xattr -d com.apple.quarantine pdfcraft-cli-*/pdfcraft-cli
./pdfcraft-cli-*/pdfcraft-cli --version
```

## Si la ventana no se dibuja bien

PdfCraft usa wgpu (Metal) y, si no arranca, reinicia solo con OpenGL. Si Metal arranca pero dibuja mal en tu GPU, fuerza OpenGL:

```sh
PDFCRAFT_RENDERER=gl /Applications/PdfCraft.app/Contents/MacOS/PdfCraft
```

## Limitaciones

- Solo Intel (x86_64): Catalina no existe en Apple Silicon.
- Sin notarización: requiere el paso de `xattr` o clic derecho → Abrir.
- Nadie prueba upstream en 10.15. Si alguna función concreta usa una API de macOS 11+ sin comprobar disponibilidad, fallará al usar esa función, no al abrir la app. Revisa `~/Library/Application Support/PdfCraft/logs/pdfcraft.log` o ejecuta el binario desde Terminal para ver el error.
