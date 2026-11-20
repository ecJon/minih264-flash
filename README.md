<div align="center">

# minih264-flash

**Minimalistic H.264 encoder, deeply optimized for ESP32-S3**

*Xtensa EE vector unit + hand-written assembly, bit-exact verified against C*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#supported-platforms)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)

[English](#english) | [简体中文](#简体中文)

</div>

---

<div align="center">

# minih264-flash

**极简 H.264 编码器，ESP32-S3 深度优化版**

*编码热路径下沉至 Xtensa EE 向量单元 + 手写汇编，与 C 参考逐位一致*

[English](#english) | [简体中文](#简体中文)

</div>

---

<a name="english"></a>

# English

Single-header minimalistic H.264 (baseline) encoder, forked from
[lieff/minih264](https://github.com/lieff/minih264) (CC0). This fork ports the
encoder hot paths to the ESP32-S3 **EE vector unit** and hand-written Xtensa
assembly. Every kernel is verified **bit-exact against the C reference**
(memcmp A/B gate) — the SIMD path changes speed, never output.

## Features

- Single-header library, no dependencies (`#include "minih264e.h"`)
- ESP32-S3 EE vector unit: 6 encoder kernels moved to 128-bit vector ASM
- **P-skip architecture**: forced-skip MB row bands (dirty-region encoding —
  static UI frames cost ~34 ms / 30 bytes instead of a full I-frame)
- Dual-thread encoding (2-band MT) with a serial fallback pool
- Runtime hooks: `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`,
  segment-level profiling switch
- CC0: use, modify, sell — no attribution required

## Performance

ESP32-S3 @ 240 MHz, 1280×720, full I-frame:

| | baseline C @160 MHz | this fork @240 MHz |
|---|---|---|
| encode time | ~2400 ms | **263 ms (9.1×)** |
| binary size | — | single header + 6 asm kernels |

P-frame chain (dirty-region mode, UI-style static content):
**~34 ms / 30 bytes** per static frame; full-frame encode ~263 ms.

## Supported platforms

| backend | status |
|---|---|
| ESP32-S3 Xtensa + EE vector ASM | production |
| Plain C (any 32-bit+ MCU / host) | reference & A/B gate |
| upstream x86 SSE / ARM NEON | inherited from upstream (untested in this fork) |

## Usage

```c
#include "minih264e.h"

H264E_create_param_t par = {0};
par.width = 1280; par.height = 720;
par.gop = 30;                    /* P-frame chain */
par.max_threads = 2;             /* 2-band MT */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t  *enc     = malloc(szp);
H264E_scratch_t  *scratch = malloc(szs);
H264E_init(enc, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,           /* fastest */
    .qp_min = 12, .qp_max = 24,
    .desired_frame_bytes = 40000
};
H264E_io_yuv_t in = {
    .yuv    = { y_plane, u_plane, v_plane },   /* I420 */
    .stride = { 1280, 640, 640 }
};
unsigned char *coded; int coded_len;
H264E_encode(enc, scratch, &rp, &in, &coded, &coded_len);
/* `coded` is valid until the next H264E_encode call */
```

### Dirty-region encoding (P-skip)

```c
extern int h264e_skip_y0, h264e_skip_y1;   /* MB-row band, global */

h264e_skip_y0 = 20;    /* rows [20, 31) are force-skipped (lossless
h264e_skip_y1 = 31;    /* reference copy); row 31 = deblock guard row */
/* rows outside the band cost ~0 (skip_run); encode → H264E_encode(...) */
```

### Fork-specific knobs

| symbol | meaning |
|---|---|
| `h264e_sps_id` | SPS id in the emitted stream (mimic-stream vs own-stream) |
| `h264e_log2_max_frame_num_minus4` | frame_num bit width |
| `h264e_skip_y0/y1` | P-skip forced band (see above) |

## Integration (ESP-IDF component)

Copy this directory into your project as `components/minih264`, or add it as
a submodule. `CMakeLists.txt` registers the ASM kernels automatically.

## Verification methodology

Every ASM kernel must pass a **bit-exact A/B gate**: the same input frame is
encoded once with the C backend and once with the Xtensa backend; the output
bitstreams are compared byte-for-byte. Host (macOS/Linux) builds use
`-DH264E_FORCE_PLAIN_C` so the whole pipeline is reproducible off-device.

## Differences from upstream

- added: ESP32-S3 EE/ASM backends, P-skip band architecture, fork knobs above
- unchanged: API surface, SVC code paths, upstream limitations
  (baseline profile: no Trellis, no SATD mode decision, no 4x4 MC)

## License

CC0-1.0 — public domain dedication. Use, modify, sell; no attribution
required. CC0 does not grant any patent rights (H.264 industry patents are a
separate matter, independent of the encoder implementation).

---

<a name="简体中文"></a>

# 简体中文

单头文件极简 H.264（baseline）编码器，fork 自
[lieff/minih264](https://github.com/lieff/minih264)（CC0）。本 fork 将编码
热路径下沉到 ESP32-S3 的 **EE 向量单元**与手写 Xtensa 汇编。所有内核以
**与 C 参考逐位一致（memcmp A/B 门）**验收——SIMD 路径只改变速度，
不改变输出。

## 特性

- 单头文件、零依赖（`#include "minih264e.h"`）
- ESP32-S3 EE 向量单元：6 个编码内核迁移至 128-bit 向量汇编
- **P-skip 架构**：强制 skip MB 行带（脏区编码——静止 UI 帧仅 ~34 ms /
  30 字节，替代全量 I 帧）
- 双线程编码（2-band MT），附串行回退池
- 运行时钩子：`h264e_sps_id`、`h264e_log2_max_frame_num_minus4`、
  分段计时开关
- CC0：随便用、随便改、可商用、无需署名

## 性能

ESP32-S3 @ 240 MHz，1280×720，全 I 帧：

| | 基线 C @160 MHz | 本 fork @240 MHz |
|---|---|---|
| 编码耗时 | ~2400 ms | **263 ms（9.1×）** |
| 体积 | — | 单头文件 + 6 个汇编内核 |

P 帧链（脏区模式，静止类 UI 内容）：静止帧 **~34 ms / 30 字节**；
全帧编码 ~263 ms。

## 支持平台

| 后端 | 状态 |
|---|---|
| ESP32-S3 Xtensa + EE 向量汇编 | 生产 |
| 纯 C（任意 32 位+ MCU / 宿主） | 参考实现 + A/B 门 |
| 上游 x86 SSE / ARM NEON | 继承自上游（本 fork 未测） |

## 使用方法

```c
#include "minih264e.h"

H264E_create_param_t par = {0};
par.width = 1280; par.height = 720;
par.gop = 30;                    /* P 帧链 */
par.max_threads = 2;             /* 2-band MT */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t  *enc     = malloc(szp);
H264E_scratch_t  *scratch = malloc(szs);
H264E_init(enc, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,           /* 极限速度 */
    .qp_min = 12, .qp_max = 24,
    .desired_frame_bytes = 40000
};
H264E_io_yuv_t in = {
    .yuv    = { y_plane, u_plane, v_plane },   /* I420 */
    .stride = { 1280, 640, 640 }
};
unsigned char *coded; int coded_len;
H264E_encode(enc, scratch, &rp, &in, &coded, &coded_len);
/* `coded` 有效期至下一次 H264E_encode 调用 */
```

### 脏区编码（P-skip）

```c
extern int h264e_skip_y0, h264e_skip_y1;   /* MB 行带，全局 */

h264e_skip_y0 = 20;    /* [20, 31) 行强制 skip（无损参考拷贝）；
h264e_skip_y1 = 31;    /* 第 31 行 = 守卫行（deblock 滤带界） */
/* 带外行成本 ≈ 0（skip_run）；随后 H264E_encode(...) */
```

### fork 专属旋钮

| 符号 | 含义 |
|---|---|
| `h264e_sps_id` | 输出流的 SPS id（模仿流 vs 自有流） |
| `h264e_log2_max_frame_num_minus4` | frame_num 位宽 |
| `h264e_skip_y0/y1` | P-skip 强制行带（见上） |

## 集成（ESP-IDF 组件）

将本目录拷贝进工程 `components/minih264`，或以 submodule 方式加入。
`CMakeLists.txt` 自动注册汇编内核。

## 验证方法

每个汇编内核必须通过**逐位一致 A/B 门**：同一输入帧分别用 C 后端与
Xtensa 后端各编码一次，输出码流逐字节比较。宿主（macOS/Linux）构建以
`-DH264E_FORCE_PLAIN_C` 强制纯 C 后端，整条管线可在非设备环境复现。

## 与上游的差异

- 新增：ESP32-S3 EE/ASM 后端、P-skip 行带架构、上述 fork 专属旋钮
- 未动：API 面、SVC 代码路径、上游限制
  （baseline profile：无 Trellis、无 SATD 模式决策、无 4x4 运动补偿）

## 许可证

CC0-1.0 — 公有领域 dedication：随便用、随便改、可商用、无需署名。
CC0 不含专利授权（H.264 行业专利与编码器实现无关，另行看待）。
