# idf_demo — minih264-flash on ESP32-S3

Encodes the deterministic demo clip on the chip itself, prints per-frame
size/timing over the serial monitor, then runs the **on-chip A/B gate**:
the same frames are encoded through the Xtensa EE-vector ASM backend and
the plain-C backend (`H264E_select_backend`) and compared byte-for-byte.
The ESP32-S3 production build is always a dual-backend configuration, so
this gate validates exactly what ships.

The demo source is shared with the host build:
[`demo/minih264_demo.c`](../../demo/minih264_demo.c) (compiled here with
`__xtensa__`, which pulls in the FreeRTOS worker pool and the real
`esp_timer`).

## Requirements

- ESP-IDF v5.x (`idf.py --version`)
- ESP32-S3 board; the demo defaults target 8/16 MB octal-PSRAM modules
  (N8R8 / N16R8). Boards without PSRAM: lower the resolution in
  `demo_defaults()` inside `demo/minih264_demo.c`.

## Build, flash, run

```bash
idf.py set-target esp32s3
idf.py -p <PORT> build flash monitor
```

Expected monitor output: three phases (motion / static+P-skip band /
motion), then `[gate] PASS (N/N frames byte-identical)` from the on-chip
A/B gate.
