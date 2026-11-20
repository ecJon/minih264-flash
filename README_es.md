<div align="center">

# minih264-flash

**Pequeño pero vertiginoso ⚡ codificador H.264/SVC de cabecera única — ~10× más rápido en ESP32-S3**

*Unidad vectorial EE de Xtensa + ensamblador escrito a mano · bit-exacto con la referencia en C*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-plataformas-soportadas)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | **Español** | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 Demostración en el dispositivo (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 fotogramas @ 160x120 — movimiento / estático+P-skip / movimiento*

</div>

---
## 📖 Introducción

**minih264-flash** es un fork de [lieff/minih264](https://github.com/lieff/minih264) — un excelente codificador H.264/SVC minimalista, biblioteca C de cabecera única escrita en C portable (con rutas SIMD SSE/NEON opcionales), publicado en el dominio público (CC0). Toda la arquitectura y el diseño del codificador son obra del autor original — este proyecto simplemente se apoya en sus hombros.

Sobre esa base sólida, este fork porta los caminos críticos del codificador a la **unidad vectorial EE** del ESP32-S3, como ensamblador Xtensa escrito a mano — la codificación de un fotograma completo a 720p pasa de ~2400 ms a **263 ms, ~10× más rápido**. Cada kernel se valida con una **puerta A/B bit-exacta** frente a la referencia en C — la ruta SIMD cambia la *velocidad*, nunca la *salida*.

> ⚠️ Al igual que el original, el código es altamente experimental: la sofisticación del codificador se intercambia por tamaño y velocidad (ver [Limitaciones](#-limitaciones)).

## ✨ Características

- 📄 **Cabecera única, cero dependencias** — solo `#include "minih264e.h"`
- ⚡ **Unidad vectorial EE del ESP32-S3** — los 5 kernels más calientes (transformación directa, cuantización, reconstrucción, SAD, copia de filas) portados a ASM vectorial de 128 bits; ~94 % del código sigue siendo C
- 🔁 **C siempre es el respaldo** — cada kernel ASM tiene su gemelo en C puro; `-DH264E_FORCE_PLAIN_C` desactiva el ASM en tiempo de compilación (el backend C es además la referencia bit-exacta de la puerta A/B)
- 🎯 **Arquitectura P-skip** — una banda configurable de filas de MB se fuerza a skip para codificación de región sucia: un fotograma de UI estático cuesta **~34 ms / 30 bytes** en lugar de un I-frame completo
- 🧵 **Codificación de doble hilo** (MT de 2 bandas) con un pool de reserva en serie
- 🔧 **Ganchos en tiempo de ejecución** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, interruptor de perfilado por segmentos
- 🆓 **Licencia CC0** — usar, modificar, vender; sin atribución

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · I-frame completo:

| | C de referencia @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| tiempo de codificación | ~2400 ms | **263 ms (9,1× más rápido)** |
| tamaño | — | cabecera única + ensamblador a mano |

Cadena de P-frames (modo región sucia, contenido UI estático): **~34 ms / 30 bytes** por fotograma estático; codificación completa ~263 ms.

> Para la comparación con x264 en x86 (velocidad, tamaño, PSNR), consulte el [README original](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Primeros pasos

### Componente ESP-IDF

Copie este repositorio en su proyecto como `components/minih264`, o añádalo como submódulo — el `CMakeLists.txt` incluido registra automáticamente los kernels ASM de Xtensa:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Compilación en host (referencia / pruebas A/B)

En macOS/Linux, compile con `-DH264E_FORCE_PLAIN_C` para forzar el backend C puro — todo el flujo se mantiene reproducible fuera del dispositivo.

### Ejecutar la demo

```bash
cd demo
make test        # puerta A/B autoritativa: binario SIMD vs binario C puro,
                 # flujos binarios comparados byte a byte con cmp(1)
./minih264_demo  # clip de tres fases (movimiento / estático+P-skip / movimiento)
                 # -> out.h264 (Annex-B); reproducción: ffplay out.h264
```

Un ejemplo para ESP32-S3 vive en `examples/idf_demo` (ESP-IDF v5.x):

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

Codifica el mismo clip **en el chip** (160x120, funciona sin PSRAM) y luego ejecuta la puerta A/B en el dispositivo: ensamblador Xtensa EE vs C puro, conmutado en tiempo de ejecución mediante `H264E_select_backend`.

## 🚀 Uso

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* cadena de P-frames */
par.max_threads = 2;    /* multihilo de 2 bandas */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* el más rápido */
    .qp_min  = 12,
    .qp_max  = 24,
    .desired_frame_bytes = 40000
};
H264E_io_yuv_t in = {
    .yuv    = { y_plane, u_plane, v_plane },   /* I420 */
    .stride = { 1280, 640, 640 }
};
unsigned char *coded; int coded_len;
H264E_encode(persist, scratch, &rp, &in, &coded, &coded_len);
/* `coded` es válido hasta la siguiente llamada a H264E_encode */
```

### Codificación de región sucia (P-skip)

```c
/* Las filas de MB [y0, y1) se fuerzan a skip: copia sin pérdida
 * desde el fotograma de referencia (coste≈0, skip_run).
 * La fila y1 es una fila de guarda para el deblocking. */
extern int h264e_skip_y0, h264e_skip_y1;   /* banda de filas MB, global */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... codificar como siempre con H264E_encode(...) */
```

### Controles específicos del fork

| símbolo | significado |
|---|---|
| `h264e_sps_id` | id SPS escrito en el flujo emitido (flujo imitado vs. flujo propio) |
| `h264e_log2_max_frame_num_minus4` | anchura en bits de frame_num |
| `h264e_skip_y0 / h264e_skip_y1` | banda forzada P-skip `[y0, y1)` (ver arriba) |

## ✅ Metodología de verificación

Cada kernel ASM debe superar una **puerta A/B bit-exacta**: el mismo fotograma de entrada se codifica una vez con el backend C y otra con el backend Xtensa, y ambos flujos binarios se comparan byte a byte. Las compilaciones en host usan `-DH264E_FORCE_PLAIN_C` para que el lado de referencia se ejecute en cualquier entorno. Puede reproducir la puerta en cualquier host con `cd demo && make test`; el ejemplo de ESP32-S3 ejecuta la misma puerta en el chip mediante `H264E_select_backend`.

## 🌍 Plataformas soportadas

| backend | estado |
|---|---|
| ESP32-S3 Xtensa + ASM vectorial EE | producción |
| C puro (cualquier MCU de 32 bits+ / host) | referencia & puerta A/B |
| x86 SSE / ARM NEON del original | heredado (sin probar en este fork) |

## ⚠️ Limitaciones

Heredadas del original — frente a una compilación *baseline* de x264, minih264 no implementa:

- cuantización Trellis
- selección de modo de predicción basada en SATD
- compensación de movimiento 4×4

Además, los backends x86 SSE / ARM NEON del original se conservan tal cual, pero **no están probados en este fork**.

## 🙏 Créditos y agradecimientos

- [lieff/minih264](https://github.com/lieff/minih264) — el codificador original de cabecera única. Este fork no existiría sin él.

## 🔗 Enlaces interesantes

- [x264](https://www.videolan.org/developers/x264.html) — el codificador H.264 open source de referencia
- [openh264](https://github.com/cisco/openh264) — códec H.264 open source de Cisco
- [kvazaar](https://github.com/ultravideo/kvazaar) — codificador HEVC académico
- [JM](http://iphome.hhi.de/suehring/tml/) — software de referencia H.264/AVC (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — decodificador H.264 compacto
- [jcodec](https://github.com/jcodec/jcodec) — códec H.264 en Java puro

## 🤝 Contribuir

¡Se aceptan PR! Una sola regla: **cada kernel ASM debe superar la puerta A/B bit-exacta** — codifique la misma entrada con el backend C y con el backend Xtensa, y compare los flujos binarios byte a byte.

## 📄 Licencia

CC0-1.0 — dedicación al dominio público. Usar, modificar, vender; sin atribución.

> Nota: CC0 no otorga derechos de patente. Las patentes industriales de H.264 son un asunto aparte, independiente de la implementación del codificador.
