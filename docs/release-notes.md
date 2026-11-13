## 🍃 Featherpix

🇬🇧 Make your images and videos much lighter without anyone noticing: WebP, AVIF or JPEG for images; MP4 or WebM for videos. Drag and drop. Free, open source, offline.
🇪🇸 Aligera tus imágenes y tus vídeos sin que se note: WebP, AVIF o JPEG para imágenes; MP4 o WebM para vídeos. Con arrastrar y soltar. Gratis, de código abierto y sin conexión.

### New in 2.1 · Novedades de la 2.1

🇬🇧 **WebM export** (VP9 + Opus audio): the lightest format for the web. By default Featherpix also writes an MP4 fallback for older browsers, and the `<video>` snippet lists both (WebM first). Uses a small LGPL ffmpeg built from source (no GPL parts, no network access); H.264 and HEVC still come from macOS.
🇪🇸 **Exportar a WebM** (VP9 + audio Opus): el formato más ligero para la web. Por defecto Featherpix añade también una copia MP4 para navegadores antiguos, y el código `<video>` incluye las dos (WebM primero). Usa un ffmpeg reducido con licencia LGPL compilado desde su código fuente (sin piezas GPL y sin acceso a la red); H.264 y HEVC siguen saliendo de macOS.

🇬🇧 Source for the bundled LGPL ffmpeg (and libvpx, opus): see the `*-source.tar.gz` assets below.
🇪🇸 Código fuente del ffmpeg LGPL incluido (y de libvpx y opus): ver los archivos `*-source.tar.gz` de abajo.

### New in 2.0 · Novedades de la 2.0

🇬🇧 **Videos tab**: drop an MP4, MOV or M4V and get a light MP4 (H.264 or HEVC) for the web — including a silent hero loop with a poster image and a ready-to-paste `<video>` tag. New interface with a mood per tab and an animated savings figure. Also: visible formats, credits and `featherpix-cli video`.
🇪🇸 **Pestaña Vídeos**: suelta un MP4, MOV o M4V y obtén un MP4 ligero (H.264 o HEVC) para la web, incluida una portada en bucle sin audio con su imagen fija y el código `<video>` listo para pegar. Interfaz nueva con un ambiente por pestaña y una cifra de ahorro animada. Además: formatos visibles, firma y `featherpix-cli video`.

### Download · Descarga

| | |
|---|---|
| **Featherpix-macOS.pkg** | Double-click installer · Instalador de doble clic (macOS 13+, Intel + Apple Silicon) |
| **Featherpix-macOS.zip** | The app on its own · La app suelta |

### ⚠️ First launch · Primera vez

🇬🇧 Featherpix isn't signed with a paid Apple certificate, so macOS warns once that it can't verify the developer.
- macOS 13–14: **right-click → Open → Open**.
- macOS 15+: open it once, then **System Settings → Privacy & Security → Open Anyway**.

🇪🇸 Featherpix no está firmado con un certificado de Apple de pago, así que macOS avisa una vez de que no puede verificar al desarrollador.
- macOS 13 y 14: **clic derecho → Abrir → Abrir**.
- macOS 15 o superior: ábrelo una vez y luego ve a **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**.

🇬🇧 Verify the files · 🇪🇸 Verifica los archivos: `gh attestation verify Featherpix-macOS.pkg -R vasyl-pavlyuchok/featherpix`

### Measured · Medido

325 real design images · 325 imágenes de diseño reales, 30.98 MB → **8.85 MB (−71 %)** with *Smallest* · con *Máxima reducción* (AVIF 40 · 1200 px). Full benchmark: [docs/benchmark.md](https://github.com/vasyl-pavlyuchok/featherpix/blob/main/docs/benchmark.md)
