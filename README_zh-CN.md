<div align="center">

# minih264-flash

**小而极快 ⚡ 的 H.264/SVC 编码器单头文件库——ESP32-S3 上快 ~10 倍**

*Xtensa EE 向量单元 + 手写汇编 · 与 C 参考逐位一致*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-支持平台)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | **简体中文** | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 真机演示（ESP32-S3，160x120）

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 帧 @ 160x120 —— 运动 / 静止+P-skip / 运动*

</div>

---
## 📖 简介

**minih264-flash** fork 自 [lieff/minih264](https://github.com/lieff/minih264)——一个优秀的极简单头文件 H.264/SVC 编码器 C 库（含可选的 SSE/NEON SIMD 路径），以公有领域（CC0）发布。编码器的架构与设计全部归功于上游作者，本 fork 只是站在巨人的肩膀上。

在这份坚实的地基之上，本 fork 将编码热路径移植到 ESP32-S3 的 **EE 向量单元**（手写 Xtensa 汇编）——720p 全帧编码从 ~2400 ms 降到 **263 ms，快约 10 倍**。每个内核都通过**与 C 参考逐位一致的 A/B 门**验收——SIMD 路径只改变*速度*，不改变*输出*。

> ⚠️ 与上游一样，代码高度实验性：以编码器的精巧度换取体积与速度（见[局限性](#-局限性)）。

## ✨ 特性

- 📄 **单头文件、零依赖**——只需 `#include "minih264e.h"`
- ⚡ **ESP32-S3 EE 向量单元**——最热的 5 个内核（前向变换、量化、重建、SAD、行拷贝）迁移至 128 位向量汇编；~94% 的代码仍是 C
- 🔁 **C 永远是回退后端**——每个汇编内核都有对应的纯 C 实现；`-DH264E_FORCE_PLAIN_C` 可在编译期关闭汇编（C 后端同时也是 A/B 门的逐位参考）
- 🎯 **P-skip 架构**——强制跳过可配置的 MB 行带，实现脏区编码：静止 UI 帧仅 **~34 ms / 30 字节**，无需全量 I 帧
- 🧵 **双线程编码**（2-band 多线程），附串行回退池
- 🔧 **运行时钩子**——`h264e_sps_id`、`h264e_log2_max_frame_num_minus4`、分段计时开关
- 🆓 **CC0 协议**——随便用、随便改、可商用、无需署名

## 📊 性能

ESP32-S3 @ 240 MHz · 1280×720 · 全 I 帧：

| | 基线 C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| 编码耗时 | ~2400 ms | **263 ms（快 9.1 倍）** |
| 体积 | — | 单头文件 + 手写 Xtensa 汇编 |

P 帧链（脏区模式，类 UI 静止内容）：静止帧 **~34 ms / 30 字节**；全帧编码 ~263 ms。

> x86 平台上与 x264 的对比（速度、体积、PSNR）请见[上游 README](https://github.com/lieff/minih264#comparison-with-x264)。

## 📦 快速开始

### ESP-IDF 组件

将本仓库拷贝进工程作为 `components/minih264`，或以 submodule 方式加入——自带的 `CMakeLists.txt` 会自动注册 Xtensa 汇编内核：

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### 宿主构建（参考实现 / A/B 测试）

在 macOS/Linux 上使用 `-DH264E_FORCE_PLAIN_C` 强制纯 C 后端——整条管线可在非设备环境复现。

### 运行 demo

```bash
cd demo
make test        # 权威 A/B 门：SIMD 二进制 vs 纯 C 二进制，
                 # 码流用 cmp(1) 逐字节比较
./minih264_demo  # 三阶段测试片（运动 / 静止+P-skip / 运动）
                 # -> out.h264（Annex-B）；播放：ffplay out.h264
```

ESP32-S3 示例位于 `examples/idf_demo`（ESP-IDF v5.x）：

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

它**在芯片上**编码同一段测试片（160x120，无 PSRAM 的板子也能跑），随后在真机上运行 A/B 门：Xtensa EE 汇编 vs 纯 C，通过 `H264E_select_backend` 运行时切换。

## 🚀 使用方法

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P 帧链 */
par.max_threads = 2;    /* 2-band 多线程 */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* 极限速度 */
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
/* `coded` 有效期至下一次 H264E_encode 调用 */
```

### 脏区编码（P-skip）

```c
/* MB 行 [y0, y1) 强制 skip：无损从参考帧拷贝（成本≈0，skip_run）。
 * 第 y1 行是去块滤波守卫行。 */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB 行带，全局变量 */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... 照常调用 H264E_encode(...) */
```

### fork 专属旋钮

| 符号 | 含义 |
|---|---|
| `h264e_sps_id` | 输出码流中的 SPS id（模仿流 vs 自有流） |
| `h264e_log2_max_frame_num_minus4` | frame_num 位宽 |
| `h264e_skip_y0 / h264e_skip_y1` | P-skip 强制行带 `[y0, y1)`（见上） |

## ✅ 验证方法

每个汇编内核必须通过**逐位一致 A/B 门**：同一输入帧分别用 C 后端与 Xtensa 后端各编码一次，输出码流逐字节比较。宿主构建使用 `-DH264E_FORCE_PLAIN_C`，参考侧可在任意环境运行。你可以在任意宿主上用 `cd demo && make test` 复现该门；ESP32-S3 示例则通过 `H264E_select_backend` 在芯片上运行同样的门。

## 🌍 支持平台

| 后端 | 状态 |
|---|---|
| ESP32-S3 Xtensa + EE 向量汇编 | 生产 |
| 纯 C（任意 32 位+ MCU / 宿主） | 参考实现 + A/B 门 |
| 上游 x86 SSE / ARM NEON | 继承自上游（本 fork 未测） |

## ⚠️ 局限性

继承自上游——相对 x264 *baseline* 档，minih264 未实现：

- Trellis 量化
- 基于 SATD 的预测模式决策
- 4×4 运动补偿

此外，上游的 x86 SSE / ARM NEON 后端原样保留，但**在本 fork 中未经测试**。

## 🙏 致谢

- [lieff/minih264](https://github.com/lieff/minih264)——上游单头文件编码器。没有它就没有本 fork。

## 🔗 相关链接

- [x264](https://www.videolan.org/developers/x264.html)——开源 H.264 编码器标杆
- [openh264](https://github.com/cisco/openh264)——Cisco 开源 H.264 编解码器
- [kvazaar](https://github.com/ultravideo/kvazaar)——学术派 HEVC 编码器
- [JM](http://iphome.hhi.de/suehring/tml/)——H.264/AVC 官方参考软件（Fraunhofer HHI）
- [h264bsd](https://github.com/mikeracca/h264bsd)——紧凑型 H.264 解码器
- [jcodec](https://github.com/jcodec/jcodec)——纯 Java H.264 编解码器

## 🤝 参与贡献

欢迎 PR！唯一规则：**每个汇编内核必须通过逐位一致 A/B 门**——同一输入分别用 C 后端与 Xtensa 后端编码，码流逐字节比较一致。

## 📄 许可证

CC0-1.0——公有领域 dedication：随便用、随便改、可商用、无需署名。

> 注意：CC0 不含专利授权。H.264 行业专利与编码器实现无关，需另行看待。
