# craft-catalina

Compila las 13 apps de la **Craft App Suite** (`storytold/*`) para **macOS 10.15 Catalina en Intel** con GitHub Actions, sin mantener forks:

| Clásicas | Nuevas (incluye ofimática) |
|---|---|
| PhotoCraft, VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft | WordCraft, DeckCraft, GridCraft, CADCraft, SoundCraft, FigCraft |

El **ArtCraft Launcher** no está incluido a propósito. No compila nada: descarga los DMG oficiales de cada release, que exigen macOS 11, así que en Catalina instalaría apps que no abren. Aquí cada app se compila por separado.

## Por qué es posible

Las 13 apps fijan macOS 11.0 en los mismos dos sitios: `MACOSX_DEPLOYMENT_TARGET` en `packaging/macos/package.sh` y `LSMinimumSystemVersion` en `Info.plist.in`. Es una decisión de empaquetado, no un requisito del código:

- **winit** y **wgpu** soportan versiones anteriores y comprueban en tiempo de ejecución las funciones de macOS 11+.
- Los frameworks nuevos que aparecen en los `Cargo.lock` son solo de iOS.
- **FilmCraft** ya resuelve con `dlsym` la única constante de VideoToolbox de macOS 13 que usa.

## Archivos

Todos van en la **raíz** del repo:

- **`.github/workflows/build.yml`:** el workflow. Lo lanzas a mano y eliges una app o `todas`.
- **`apps.json`:** cada app con el tag de upstream y el commit de `craft-fonts` que fija su propio release.
- **`patch.sh`:** baja las dos fijaciones de 11.0 a 10.15. Falla si upstream cambió esos archivos.
- **`check-binaries.sh`:** verifica cada ejecutable del `.app` y el CLI:
  - que sea solo x86_64 con `minos` 10.15;
  - que no enlace frameworks inexistentes en 10.15;
  - que ningún símbolo importado de frameworks de Apple esté anotado en el SDK como de macOS 11+. Si falta un símbolo así, dyld no abre la app;
  - que el `Info.plist` diga 10.15.

## Configuración

1. **Crea el repo como público.** En repos privados cada minuto de runner macOS cuenta 10 veces contra tu cuota gratuita, y 13 apps la agotan enseguida. En repos públicos los runners estándar son gratis.
2. **Sube los archivos con git.** Al arrastrar desde el navegador no se sube la carpeta oculta `.github`:
   ```sh
   unzip craft-catalina.zip && cd craft-catalina
   git init -b main && git add . && git commit -m "Workflow Craft apps para Catalina"
   git remote add origin git@github.com:<usuario>/craft-catalina.git
   git push -u origin main
   ```
3. **Verifica que las acciones estén permitidas.** En **Settings → Actions → General**, debe permitirse ejecutar acciones, incluidas las de terceros (`dtolnay/rust-toolchain`, `Swatinem/rust-cache`).
4. **Lanza el workflow.** Ve a **Actions → Build Craft apps for Catalina → Run workflow** y elige la app, o `todas`.
5. **Descarga el resultado.** Cada app genera un artifact `<app>-<tag>-catalina-x86_64` con el `.dmg` y el `.zip` del CLI. Dura 30 días.

Con `todas`, GitHub corre como máximo 5 jobs macOS a la vez en cuentas gratuitas y encola el resto. Cada app puede tardar entre 30 y 90 minutos la primera vez.

## Actualizar versiones

- **Una versión puntual:** al lanzar el workflow elige la app y escribe el tag en `ref`.
- **De forma permanente:** cambia `ref` en `apps.json`. Si cambias de versión, revisa también `fonts`: es el `craft-fonts-ref` (o `CRAFT_FONTS_REF`) del `.github/workflows/release.yml` de esa app en ese tag. Vacío significa que la app no usa `craft-fonts`.

## Instalar en la Mac

Las apps tienen firma ad-hoc y no están notarizadas:

```sh
xattr -dr com.apple.quarantine /Applications/<App>.app
```

También puedes hacer clic derecho → **Abrir** → **Abrir**.

Si la ventana se dibuja mal, las apps basadas en wgpu suelen aceptar forzar OpenGL. En PdfCraft es `PDFCRAFT_RENDERER=gl`; revisa el README de cada app para el equivalente.

## Qué puede fallar aunque compile

`check-binaries.sh` detecta lo que impediría **abrir** la app. No detecta métodos Objective-C de macOS 11+ llamados en tiempo de ejecución: esos solo fallan al usar esa función concreta. Puntos a vigilar:

- **FilmCraft:** codificar H.265 o AV1 usa solo codificadores por hardware. Muchos Macs Intel compatibles con Catalina no tienen HEVC por hardware, y ninguno tiene AV1. H.264 sí funciona.
- **LightCraft:** las funciones de IA (segmentación) usan candle sobre Metal. En GPUs antiguas pueden fallar o ir lentas; el resto de la app no depende de eso.
- **En general:** si algo falla, ejecuta el binario desde Terminal (`/Applications/<App>.app/Contents/MacOS/<App>`) para ver el error, o revisa el log de la app en `~/Library/Application Support/<App>/`.

Si un job queda en rojo en el paso de verificación, el DMG se sube igual. El log indica qué símbolo o comprobación falló.
