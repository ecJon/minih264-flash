<div align="center">

# minih264-flash

**Klein, aber brachialschnell ⚡ H.264/SVC-Encoder-Single-Header-Bibliothek — ~10× schneller auf dem ESP32-S3**

*Xtensa-EE-Vektoreinheit + handgeschriebene Assemblierung · bit-exakt zur C-Referenz*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-unterstützte-plattformen)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | **Deutsch** | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 Demo auf dem Gerät (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 Frames @ 160x120 — Bewegung / statisch+P-Skip / Bewegung*

</div>

---
## 📖 Einführung

**minih264-flash** ist ein Fork von [lieff/minih264](https://github.com/lieff/minih264) — einer exzellenten, minimalistischen H.264/SVC-Encoder-Bibliothek in portablen C (mit optionalen SSE/NEON-SIMD-Pfaden) und einer einzigen Header-Datei, veröffentlicht als gemeinfreies Werk (CC0). Die gesamte Architektur und das Design des Encoders gehen auf das Konto des Upstream-Autors — dieses Projekt steht auf den Schultern dieser Arbeit.

Auf diesem soliden Fundament aufbauend, portiert dieser Fork die Hot Paths des Encoders in die **EE-Vektoreinheit** des ESP32-S3 — als handgeschriebene Xtensa-Assemblierung. Die 720p-Vollframe-Kodierung fällt von ~2400 ms auf **263 ms (~10× schneller)**. Jeder Kernel besteht ein **bit-exaktes A/B-Gate** gegen die C-Referenz — der SIMD-Pfad ändert die *Geschwindigkeit*, niemals die *Ausgabe*.

> ⚠️ Wie beim Original gilt: Der Code ist hochgradig experimentell – Raffinesse des Encoders wird gegen Größe und Geschwindigkeit eingetauscht (siehe [Einschränkungen](#-einschränkungen)).

## ✨ Funktionen

- 📄 **Single Header, null Abhängigkeiten** — einfach `#include "minih264e.h"`
- ⚡ **ESP32-S3-EE-Vektoreinheit** — die 5 heißesten Kernel (Vorwärtstransformation, Quantisierung, Rekonstruktion, SAD, Zeilenkopie) auf 128-Bit-Vektor-ASM portiert; ~94 % des Codes bleiben C
- 🔁 **C ist immer der Fallback** — jeder ASM-Kernel hat ein rein-C-Pendant; `-DH264E_FORCE_PLAIN_C` deaktiviert den ASM zur Compilezeit (das C-Backend ist zugleich die bit-exakte Referenz des A/B-Gates)
- 🎯 **P-Skip-Architektur** — ein konfigurierbarer MB-Zeilenbereich wird forciert übersprungen (Dirty-Region-Kodierung): eine statische UI-Frame kostet **~34 ms / 30 Bytes** statt eines vollständigen I-Frames
- 🧵 **Zwei-Thread-Kodierung** (2-Band-MT) mit seriellem Fallback-Pool
- 🔧 **Laufzeit-Hooks** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, Profilingschalter auf Segmentebene
- 🆓 **CC0-Lizenz** — nutzen, ändern, verkaufen; ohne Namensnennung

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · vollständiges I-Frame:

| | baseline C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| Kodierungszeit | ~2400 ms | **263 ms (9,1× schneller)** |
| Umfang | — | Single Header + handgeschriebene Assemblierung |

P-Frame-Kette (Dirty-Region-Modus, UI-artige statische Inhalte): statische Frame **~34 ms / 30 Bytes**; vollständige Frame ~263 ms.

> Für den x86-Vergleich mit x264 (Geschwindigkeit, Größe, PSNR) siehe das [Upstream-README](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Erste Schritte

### ESP-IDF-Komponente

Kopieren Sie dieses Repository als `components/minih264` in Ihr Projekt oder fügen Sie es als Submodul hinzu — die beiliegende `CMakeLists.txt` registriert die Xtensa-ASM-Kernel automatisch:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Host-Build (Referenz / A/B-Tests)

Unter macOS/Linux erzwingt `-DH264E_FORCE_PLAIN_C` das reine-C-Backend — die gesamte Pipeline bleibt ohne Gerät reproduzierbar.

### Demo ausführen

```bash
cd demo
make test        # maßgebliches A/B-Gate: SIMD-Binary vs. reines-C-Binary,
                 # Bitströme werden mit cmp(1) byteweise verglichen
./minih264_demo  # Drei-Phasen-Clip (Bewegung / statisch+P-Skip / Bewegung)
                 # -> out.h264 (Annex-B); Wiedergabe: ffplay out.h264
```

Ein ESP32-S3-Beispiel liegt in `examples/idf_demo` (ESP-IDF v5.x):

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

Es kodiert denselben Clip **auf dem Chip** (160x120, läuft auch ohne PSRAM) und führt danach das A/B-Gate auf dem Gerät aus: Xtensa-EE-Assemblierung vs. reines C, zur Laufzeit über `H264E_select_backend` umgeschaltet.

## 🚀 Verwendung

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P-Frame-Kette */
par.max_threads = 2;    /* 2-Band-Multithreading */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* am schnellsten */
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
/* `coded` ist bis zum nächsten H264E_encode-Aufruf gültig */
```

### Dirty-Region-Kodierung (P-Skip)

```c
/* MB-Zeilen [y0, y1) werden forciert übersprungen: verlustfreie
 * Kopie aus dem Referenzframe (Kosten≈0, skip_run).
 * Zeile y1 ist eine Deblocking-Schutzzeile. */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB-Zeilenbereich, global */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... wie gewohnt H264E_encode(...) aufrufen */
```

### Fork-spezifische Stellschrauben

| Symbol | Bedeutung |
|---|---|
| `h264e_sps_id` | SPS-ID im erzeugten Stream (mimic-stream vs. eigener Stream) |
| `h264e_log2_max_frame_num_minus4` | Bitbreite von frame_num |
| `h264e_skip_y0 / h264e_skip_y1` | P-Skip-Erzwingungsbereich `[y0, y1)` (siehe oben) |

## ✅ Verifikationsmethode

Jeder ASM-Kernel muss ein **bit-exaktes A/B-Gate** bestehen: derselbe Eingabeframe wird einmal mit dem C-Backend und einmal mit dem Xtensa-Backend kodiert, und die beiden Ausgabebitströme werden byteweise verglichen. Host-Builds verwenden `-DH264E_FORCE_PLAIN_C`, sodass die Referenzseite des Gates überall läuft. Das Gate lässt sich auf jedem Host mit `cd demo && make test` reproduzieren; das ESP32-S3-Beispiel führt dasselbe Gate auf dem Chip über `H264E_select_backend` aus.

## 🌍 Unterstützte Plattformen

| Backend | Status |
|---|---|
| ESP32-S3 Xtensa + EE-Vektor-ASM | Produktion |
| Reines C (beliebige 32-Bit+-MCUs / Host) | Referenz & A/B-Gate |
| x86 SSE / ARM NEON aus dem Upstream | geerbt (in diesem Fork ungetestet) |

## ⚠️ Einschränkungen

Aus dem Upstream geerbt — gegenüber einem x264-*baseline*-Build implementiert minih264 nicht:

- Trellis-Quantisierung
- SATD-basierte Vorhersagemodusauswahl
- 4×4-Bewegungskompensation

Außerdem werden die x86-SSE-/ARM-NEON-Backends des Upstreams unverändert mitgeführt, sind in diesem Fork jedoch **ungetestet**.

## 🙏 Danksagungen

- [lieff/minih264](https://github.com/lieff/minih264) — der ursprüngliche Single-Header-Encoder. Ohne ihn gäbe es diesen Fork nicht.

## 🔗 Interessante Links

- [x264](https://www.videolan.org/developers/x264.html) — der Referenz-Open-Source-H.264-Encoder
- [openh264](https://github.com/cisco/openh264) — Ciscos Open-Source-H.264-Codec
- [kvazaar](https://github.com/ultravideo/kvazaar) — akademischer HEVC-Encoder
- [JM](http://iphome.hhi.de/suehring/tml/) — H.264/AVC-Referenzsoftware (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — kompakter H.264-Decoder
- [jcodec](https://github.com/jcodec/jcodec) — reiner Java-H.264-Codec

## 🤝 Mitwirken

PRs sind willkommen! Eine Regel: **Jeder ASM-Kernel muss das bit-exakte A/B-Gate bestehen** — dieselbe Eingabe mit dem C-Backend und dem Xtensa-Backend kodieren und die Bitströme byteweise vergleichen.

## 📄 Lizenz

CC0-1.0 — Gemeinfrei-Weihung. Nutzen, ändern, verkaufen; keine Namensnennung erforderlich.

> Hinweis: CC0 gewährt keinerlei Patentrechte. Branchenpatente zu H.264 sind eine eigenständige Angelegenheit, unabhängig von der Encoder-Implementierung.
