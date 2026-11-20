<div align="center">

# minih264-flash

**Small, but blazingly fast ⚡ H.264/SVC encoder single-header library — ~10× faster on ESP32-S3**

*Xtensa EE vector unit + hand-written assembly · bit-exact with the C reference*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-supported-platforms)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

**English** | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 On-device demo (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 frames @ 160x120 — motion / static+P-skip / motion*

</div>

---
## 📖 Introduction

**minih264-flash** is a fork of [lieff/minih264](https://github.com/lieff/minih264) — an excellent, minimalist single-header H.264/SVC encoder in portable C (with optional SSE/NEON SIMD paths), released into the public domain (CC0). All credit for the encoder's architecture and design belongs to the upstream author — this project simply stands on their shoulders.

Standing on that solid foundation, this fork ports the encoder hot paths to the ESP32-S3's **EE vector unit** as hand-written Xtensa assembly — 720p full-frame encoding drops from ~2400 ms to **263 ms, ~10× faster**. Every kernel is accepted through a **bit-exact A/B gate** against the C reference — the SIMD path changes *speed*, never *output*.

> ⚠️ Like upstream, the code is highly experimental: it trades encoder sophistication for size and speed (see [Limitations](#-limitations)).

## ✨ Features

- 📄 **Single header, zero dependencies** — just `#include "minih264e.h"`
- ⚡ **ESP32-S3 EE vector unit** — the 5 hottest kernels (forward transform, quantization, reconstruction, SAD, row copy) ported to 128-bit vector ASM; ~94% of the code is still C
- 🔁 **C is always the fallback** — every ASM kernel has a plain-C twin; `-DH264E_FORCE_PLAIN_C` disables ASM at compile time (the C backend is also the bit-exact reference of the A/B gate)
- 🎯 **P-skip architecture** — force-skip a configurable MB-row band for dirty-region encoding: a static UI frame costs **~34 ms / 30 bytes** instead of a full I-frame
- 🧵 **Dual-thread encoding** (2-band MT) with a serial fallback pool
- 🔧 **Runtime hooks** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, segment-level profiling switch
- 🆓 **CC0** — use, modify, sell; no attribution required

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · full I-frame:

| | baseline C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| encode time | ~2400 ms | **263 ms (9.1× faster)** |
| footprint | — | single header + hand-written Xtensa ASM |

P-frame chain (dirty-region mode, UI-style static content): **~34 ms / 30 bytes** per static frame; full-frame encode ~263 ms.

> For an x86 comparison against x264 (speed, size, PSNR), see the [upstream README](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Getting Started

### ESP-IDF component

Copy this repository into your project as `components/minih264`, or add it as a submodule — the bundled `CMakeLists.txt` registers the Xtensa ASM kernels automatically:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Host build (reference / A/B tests)

On macOS/Linux, build with `-DH264E_FORCE_PLAIN_C` to force the plain-C backend — the whole pipeline stays reproducible off-device.

### Run the demo

```bash
cd demo
make test        # authoritative A/B gate: SIMD binary vs plain-C binary,
                 # bitstreams byte-compared with cmp(1)
./minih264_demo  # three-phase clip (motion / static+P-skip / motion)
                 # -> out.h264 (Annex-B); play with: ffplay out.h264
```

An ESP32-S3 example lives in `examples/idf_demo` (ESP-IDF v5.x):

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

It encodes the same clip **on the chip** (160x120, fits PSRAM-less boards) and then runs the A/B gate on-device: Xtensa EE ASM vs plain C, switched at runtime through `H264E_select_backend`.

## 🚀 Usage

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P-frame chain */
par.max_threads = 2;    /* 2-band multi-threading */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* fastest */
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
/* `coded` is valid until the next H264E_encode call */
```

### Dirty-region encoding (P-skip)

```c
/* MB rows [y0, y1) are force-skipped: losslessly copied from the
 * reference frame (~0 cost, skip_run). Row y1 is a deblock guard row. */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB-row band, global */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... encode as usual with H264E_encode(...) */
```

### Fork-specific knobs

| symbol | meaning |
|---|---|
| `h264e_sps_id` | SPS id written into the emitted stream (mimic-stream vs own-stream) |
| `h264e_log2_max_frame_num_minus4` | frame_num bit width |
| `h264e_skip_y0 / h264e_skip_y1` | P-skip forced band `[y0, y1)` (see above) |

## ✅ Verification Methodology

Every ASM kernel must pass a **bit-exact A/B gate**: the same input frame is encoded once with the C backend and once with the Xtensa backend, and the two output bitstreams are compared byte-for-byte. Host builds use `-DH264E_FORCE_PLAIN_C` so the reference side of the gate runs anywhere. You can reproduce the gate on any host with `cd demo && make test`; the ESP32-S3 example runs the same gate on-chip through `H264E_select_backend`.

## 🌍 Supported Platforms

| backend | status |
|---|---|
| ESP32-S3 Xtensa + EE vector ASM | production |
| Plain C (any 32-bit+ MCU / host) | reference & A/B gate |
| upstream x86 SSE / ARM NEON | inherited from upstream (untested in this fork) |

## ⚠️ Limitations

Inherited from upstream — relative to an x264 *baseline* build, minih264 does not implement:

- Trellis quantization
- SATD-based prediction mode selection
- 4×4 motion compensation

Additionally, the upstream x86 SSE / ARM NEON backends are carried along unchanged but are **untested in this fork**.

## 🙏 Credits & Acknowledgments

- [lieff/minih264](https://github.com/lieff/minih264) — the upstream single-header encoder. This fork would not exist without it.

## 🔗 Interesting Links

- [x264](https://www.videolan.org/developers/x264.html) — the reference open-source H.264 encoder
- [openh264](https://github.com/cisco/openh264) — Cisco's open-source H.264 codec
- [kvazaar](https://github.com/ultravideo/kvazaar) — academic HEVC encoder
- [JM](http://iphome.hhi.de/suehring/tml/) — H.264/AVC reference software (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — compact H.264 decoder
- [jcodec](https://github.com/jcodec/jcodec) — pure-Java H.264 codec

## 🤝 Contributing

PRs are welcome! One rule: **every ASM kernel must pass the bit-exact A/B gate** — encode the same input with the C backend and the Xtensa backend, then compare the bitstreams byte-for-byte.

## 📄 License

CC0-1.0 — public domain dedication. Use, modify, sell; no attribution required.

> Note: CC0 does not grant any patent rights. H.264 industry patents are a separate matter, independent of the encoder implementation.
