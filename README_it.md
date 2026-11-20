<div align="center">

# minih264-flash

**Piccolo ma fulmineo ⚡ encoder H.264/SVC single-header — ~10× più veloce su ESP32-S3**

*Unità vettoriale EE Xtensa + assembly scritto a mano · bit-exatto rispetto al riferimento C*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-piattaforme-supportate)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | **Italiano** | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 Dimostrazione sul dispositivo (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 frame @ 160x120 — moto / statico+P-skip / moto*

</div>

---
## 📖 Introduzione

**minih264-flash** è un fork di [lieff/minih264](https://github.com/lieff/minih264) — un eccellente encoder H.264/SVC minimalista, libreria C single-header scritta in C portabile (con percorsi SIMD SSE/NEON opzionali), rilasciata nel pubblico dominio (CC0). Tutta l'architettura e la progettazione dell'encoder sono merito dell'autore originale — questo progetto si colloca semplicemente sulle sue spalle.

Su queste solide fondamenta, questo fork porta i percorsi caldi dell'encoder nell'**unità vettoriale EE** dell'ESP32-S3, come assembly Xtensa scritto a mano — la codifica di un frame completo a 720p scende da ~2400 ms a **263 ms, ~10× più veloce**. Ogni kernel è accettato tramite un **gate A/B bit-exatto** rispetto al riferimento C — il percorso SIMD cambia la *velocità*, mai l'*output*.

> ⚠️ Come a monte, il codice è altamente sperimentale: la sofisticazione dell'encoder è scambiata con dimensioni e velocità (vedi [Limitazioni](#-limitazioni)).

## ✨ Funzionalità

- 📄 **Single header, zero dipendenze** — basta `#include "minih264e.h"`
- ⚡ **Unità vettoriale EE dell'ESP32-S3** — i 5 kernel più caldi (trasformata diretta, quantizzazione, ricostruzione, SAD, copia di righe) portati ad ASM vettoriale a 128 bit; ~94% del codice resta C
- 🔁 **Il C resta sempre il fallback** — ogni kernel ASM ha un gemello in C puro; `-DH264E_FORCE_PLAIN_C` disattiva l'ASM in fase di compilazione (il backend C è anche il riferimento bit-exatto del gate A/B)
- 🎯 **Architettura P-skip** — una banda configurabile di righe MB viene forzata in skip per la codifica dirty-region: un frame UI statico costa **~34 ms / 30 byte** invece di un I-frame completo
- 🧵 **Codifica a doppio thread** (MT a 2 bande) con pool di fallback seriale
- 🔧 **Hook a runtime** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, interruttore di profiling a segmenti
- 🆓 **Licenza CC0** — usare, modificare, vendere; nessuna attribuzione richiesta

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · I-frame completo:

| | C di riferimento @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| tempo di codifica | ~2400 ms | **263 ms (9,1× più veloce)** |
| ingombro | — | single header + assembly scritto a mano |

Catena di P-frame (modalità dirty-region, contenuti UI statici): **~34 ms / 30 byte** per frame statico; codifica di un frame completo ~263 ms.

> Per il confronto con x264 su x86 (velocità, dimensioni, PSNR), vedere il [README a monte](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Per iniziare

### Componente ESP-IDF

Copiare questo repository nel progetto come `components/minih264`, oppure aggiungerlo come submodule — il `CMakeLists.txt` incluso registra automaticamente i kernel ASM Xtensa:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Build su host (riferimento / test A/B)

Su macOS/Linux, compilare con `-DH264E_FORCE_PLAIN_C` per forzare il backend C puro — l'intera pipeline resta riproducibile fuori dal dispositivo.

### Eseguire la demo

```bash
cd demo
make test        # gate A/B autorevole: binario SIMD vs binario C puro,
                 # bitstream confrontati byte per byte con cmp(1)
./minih264_demo  # clip in tre fasi (moto / statico+P-skip / moto)
                 # -> out.h264 (Annex-B); riproduzione: ffplay out.h264
```

Un esempio per ESP32-S3 si trova in `examples/idf_demo` (ESP-IDF v5.x):

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

Codifica lo stesso clip **sul chip** (160x120, funziona senza PSRAM) e poi esegue il gate A/B sul dispositivo: assembly Xtensa EE vs C puro, commutato a runtime tramite `H264E_select_backend`.

## 🚀 Utilizzo

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* catena di P-frame */
par.max_threads = 2;    /* multithreading a 2 bande */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* il più veloce */
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
/* `coded` è valido fino alla successiva chiamata H264E_encode */
```

### Codifica dirty-region (P-skip)

```c
/* Le righe MB [y0, y1) sono forzate in skip: copia senza perdita
 * dal frame di riferimento (costo≈0, skip_run).
 * La riga y1 è una riga di guardia per il deblocking. */
extern int h264e_skip_y0, h264e_skip_y1;   /* banda di righe MB, globale */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... codificare come al solito con H264E_encode(...) */
```

### Parametri specifici del fork

| simbolo | significato |
|---|---|
| `h264e_sps_id` | id SPS scritto nel flusso emesso (flusso imitato vs flusso proprio) |
| `h264e_log2_max_frame_num_minus4` | larghezza in bit di frame_num |
| `h264e_skip_y0 / h264e_skip_y1` | banda forzata P-skip `[y0, y1)` (vedi sopra) |

## ✅ Metodologia di verifica

Ogni kernel ASM deve superare un **gate A/B bit-esatto**: lo stesso frame di input viene codificato una volta con il backend C e una con il backend Xtensa, e i due bitstream in uscita vengono confrontati byte per byte. Le build su host usano `-DH264E_FORCE_PLAIN_C`, così il lato di riferimento gira ovunque. Il gate è riproducibile su qualsiasi host con `cd demo && make test`; l'esempio ESP32-S3 esegue lo stesso gate sul chip tramite `H264E_select_backend`.

## 🌍 Piattaforme supportate

| backend | stato |
|---|---|
| ESP32-S3 Xtensa + ASM vettoriale EE | produzione |
| C puro (qualsiasi MCU a 32 bit+ / host) | riferimento & gate A/B |
| x86 SSE / ARM NEON di monte | ereditato (non testato in questo fork) |

## ⚠️ Limitazioni

Ereditate da monte — rispetto a una build *baseline* di x264, minih264 non implementa:

- quantizzazione Trellis
- selezione della modalità di predizione basata su SATD
- compensazione del movimento 4×4

Inoltre, i backend x86 SSE / ARM NEON di monte vengono trasportati così come sono ma **non sono testati in questo fork**.

## 🙏 Ringraziamenti

- [lieff/minih264](https://github.com/lieff/minih264) — l'encoder single-header originale. Questo fork non esisterebbe senza di esso.

## 🔗 Link interessanti

- [x264](https://www.videolan.org/developers/x264.html) — l'encoder H.264 open source di riferimento
- [openh264](https://github.com/cisco/openh264) — codec H.264 open source di Cisco
- [kvazaar](https://github.com/ultravideo/kvazaar) — encoder HEVC accademico
- [JM](http://iphome.hhi.de/suehring/tml/) — software di riferimento H.264/AVC (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — decoder H.264 compatto
- [jcodec](https://github.com/jcodec/jcodec) — codec H.264 in Java puro

## 🤝 Contribuire

Le PR sono benvenute! Una sola regola: **ogni kernel ASM deve superare il gate A/B bit-esatto** — codificare lo stesso input con il backend C e con quello Xtensa, quindi confrontare i bitstream byte per byte.

## 📄 Licenza

CC0-1.0 — dedication al pubblico dominio. Usare, modificare, vendere; nessuna attribuzione richiesta.

> Nota: CC0 non concede alcun diritto di brevetto. I brevetti industriali legati a H.264 sono una questione a parte, indipendente dall'implementazione dell'encoder.
