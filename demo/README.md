# minih264-flash demo

A self-contained demo for the minih264-flash encoder. It generates a
deterministic synthetic clip (static gradient + travelling box, integer math
only), encodes it end-to-end and prints per-frame size/timing — no external
files or codecs needed. The same source file builds on POSIX hosts and on
the ESP32-S3 (`examples/idf_demo`).

## What it shows

Normal mode runs a three-phase clip that tells the whole story of the fork:

1. **full motion** — normal P-frame sizes;
2. **static content + P-skip band** — set `h264e_skip_y0/y1` to a MB-row band,
   freeze the content, and watch frames collapse to **tens of bytes**
   (dirty-region encoding);
3. **full motion again** — sizes recover.

`--ab` runs the project's bit-exact A/B gate in-process: the same frames are
encoded through two backends (NEON/SSE/Xtensa vs plain C) and compared
byte-for-byte.

## Build & run (host)

```bash
cd demo
make            # SIMD (NEON on arm64 / SSE2 on x86-64) single-config build
./minih264_demo # -> out.h264 (Annex-B); play with: ffplay out.h264

make test       # authoritative A/B gate: SIMD binary vs plain-C binary,
                # bytestreams compared with cmp(1)
```

`make test` prints `[gate] PASS` when the SIMD and plain-C bitstreams are
byte-identical. That is the project's core quality bar, reproducible on any
host.

### Options

```
./minih264_demo [-w W] [-h H] [-n FRAMES] [-g GOP] [-t THREADS] [-o FILE]
                [--ab] [--no-skip]
```

## ESP32-S3

See [`examples/idf_demo`](../examples/idf_demo). The device build is always
a dual-backend configuration (Xtensa ASM + plain C), so the demo runs the
on-chip A/B gate through `H264E_select_backend` automatically after the
clip.

## Known issues

**arm64 host, `-O2`: inlining-sensitive bitstream divergence.**
The encoder dispatches kernels either directly (`MAP_NAME(name)` →
`name##_neon`, single-config builds) or through a global function-pointer
table (`g_vft`, dual-backend "VFT" builds). On Apple clang / arm64 at
`-O2`, the two dispatch modes produce **different — though each internally
consistent and decodable — bitstreams** for the same input:

| build | dispatch | frame 0 size |
|---|---|---|
| single config, `-O2` | direct call, inlined | 5929 |
| single config, `-O0` | direct call | 5929 |
| dual-backend VFT, `-O2` | indirect call | 7702 |
| single config, `-O2 -fno-inline-functions` | indirect-equivalent | 7702 |

Everything agrees at `-O0`. The signature (inlining-dependent output on an
otherwise deterministic pipeline) strongly suggests an uninitialized-read-
style bug somewhere in the kernel/C code that only manifests when kernels
are *not* inlined. Single-config `-O2` builds agree with `-O0`, so the
inlined path is self-consistent.

Practical consequences:

- The authoritative host gate is `make test` (two single-config binaries),
  not the in-process `--ab` (VFT dispatch).
- The ESP32-S3 production build is itself a VFT build; the on-chip gate
  compares Xtensa vs plain C *within* that configuration and remains
  self-consistent.
- Fixing the root cause means touching `include/minih264e.h` (upstream +
  fork code) — tracked separately; out of scope for the demo.

## Findings from the on-chip gate (ESP32-S3, 160x120)

Final state: **`[gate] PASS (60/60 frames byte-identical)`**, `=== demo PASSED ===`,
after fixing two real hardware-level hazards below. The chase also retired
one EE kernel pending a deeper root cause.

### 1. EE store → CPU load hazard (fixed with `nop`)

Values written with `ee.vst.128.ip` are **not immediately visible to CPU
loads** (`l16si`/`l32i`) of the same addresses. The SAD kernel dumps its
accumulators with a `vst` and immediately horizontal-sums them with `l16si`
— reading stale stack bytes and silently corrupting the quadrant sums.
**Fix:** one `nop` between the EE store and the first CPU read. Applied to
the SAD extraction, fwd_xform2's nbuf unpack, recon's out unpack and
quant_block16's qacc dump (same pattern in all four).

### 2. Core migration corrupts the EE register file (fixed by pinning)

With the demo task unpinned, pass-0 vs pass-1 outputs diverged
non-deterministically while a both-passes-identical control run passed —
the EE q-register state does not survive a FreeRTOS core migration.
**Fix:** every task that touches EE kernels is pinned
(`xTaskCreatePinnedToCore(..., 0)`). Consequence: do **not** run the
2-band multi-thread EE encode across cores; the demo's MT showcase is
host-only, the device build runs `threads = 1`.

### 3. sad8 EE kernel retired (temporary)

Even with 1+2 fixed, the on-chip gate failed with the EE SAD active while a
plain-C-vs-plain-C control gate passed 60/60, and an on-device SAD unit
test (4096 random blocks, byte-exact, see `demo_sad_selftest`) contradicts
the gate result — some EE micro-timing effect specific to the real encode
path is still unexplained. The table entry now routes SAD to the C
reference (functional, bit-exact; ~48 fps @ 160x120 on device, motion
search in C). Re-enable with `H264E_BISECT_SAD_ASM` and re-run both
verifications (sadtest + on-chip gate).

### Verified EE facts for future kernel work (probed on rev v0.2 silicon)

- `ee.vzip.8 qA, qB` is a **normal full byte interleave per 64-bit half**:
  qA ← [a0,b0,a1,b1,a2,b2,a3,b3 | a4,b4,…,a7,b7],
  qB ← [a8,b8,…,b11 | a12,b12,…,b15]. (Earlier probe notes claiming a
  "first 4 bytes per half" behaviour are wrong.)
- `ee.vld.128.ip` → `ee.vst.128.ip` roundtrip is byte-identical.
- `ee.zero.q` immediately followed by `vzip` on the zeroed register is
  hazard-free (probe-verified).

## Pulling the encoded stream off the device

A sample stream encoded on the board is committed at
[`assets/esp32_demo_160x120.mp4`](assets/esp32_demo_160x120.mp4) (60 frames
@ 160x120: motion / static+P-skip / motion):

![ESP32-S3 on-device demo](assets/esp32_demo_160x120.mp4)

The device demo dumps every encoded frame over the UART as base64. Capture
a monitor run and decode it on the host:

```bash
idf.py -p PORT monitor > capture.txt        # while the demo runs
python3 demo/uart_h264_extract.py capture.txt device.h264
ffplay device.h264                          # or:
ffmpeg -r 30 -f h264 -i device.h264 -c copy device.mp4
```

## Device notes (board used for validation)

- Board is marked ESP32-S3 N16R8, chip revision **v0.2**, 16 MB flash
  detected correctly, but PSRAM does not respond in OCTAL or QUAD mode at
  40/80 MHz — likely no/faulty PSRAM on the module. The demo therefore
  defaults to 160x120 @ threads=1, which fits the ~380 KiB internal heap
  (persist 93 KB + scratch 102 KB + frame store).
- `H264E_encode` runs band 0 on the *calling* task's stack: give the demo
  task 16 KiB (the IDF main task's 3.5 KiB stack overflows immediately).
- End the task with `vTaskDelete(NULL)` — a returning FreeRTOS task aborts
  and reboots the board.
- Observed performance at 160x120 (SAD in C): ~48 fps end-to-end for the
  60-frame clip; static + P-skip frames cost **10-13 bytes / ~6 ms**.
- The host demo defaults to **1280x720** — the resolution used for the
  project's upstream comparisons; on PSRAM-equipped boards raise the
  device resolution to match.
