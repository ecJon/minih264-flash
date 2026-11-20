<div align="center">

# minih264-flash

**小而極快 ⚡ 的 H.264/SVC 編碼器單標頭檔程式庫——ESP32-S3 上快 ~10 倍**

*Xtensa EE 向量單元 + 手寫組合語言 · 與 C 參考實作逐位元一致*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-支援平台)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | **繁體中文** | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 真機示範（ESP32-S3，160x120）

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 影格 @ 160x120 —— 運動 / 靜態+P-skip / 運動*

</div>

---
## 📖 簡介

**minih264-flash** fork 自 [lieff/minih264](https://github.com/lieff/minih264)——一個優秀的極簡單標頭檔 H.264/SVC 編碼器 C 程式庫（含可選的 SSE/NEON SIMD 路徑），以公有領域（CC0）發布。編碼器的架構與設計全部歸功於上游作者，本 fork 只是站在巨人的肩膀上。

在這份堅實的地基之上，本 fork 將編碼熱路徑移植到 ESP32-S3 的 **EE 向量單元**（手寫 Xtensa 組合語言）——720p 完整影格編碼從 ~2400 ms 降到 **263 ms，快約 10 倍**。每個核心都通過**與 C 參考實作逐位元一致的 A/B 閘門**驗收——SIMD 路徑只改變*速度*，不改變*輸出*。

> ⚠️ 與上游一樣，程式碼高度實驗性：以編碼器的精巧度換取體積與速度（見[侷限性](#-侷限性)）。

## ✨ 特性

- 📄 **單標頭檔、零相依**——只需 `#include "minih264e.h"`
- ⚡ **ESP32-S3 EE 向量單元**——最熱的 5 個核心（前向轉換、量化、重建、SAD、列拷貝）移植至 128 位元向量組合語言；~94% 的程式碼仍是 C
- 🔁 **C 永遠是回退後端**——每個組合語言核心都有對應的純 C 實作；`-DH264E_FORCE_PLAIN_C` 可在編譯期關閉組合語言（C 後端同時也是 A/B 閘門的逐位元參考）
- 🎯 **P-skip 架構**——強制跳過可設定的 MB 列帶，實作髒區編碼：靜態 UI 影格僅 **~34 ms / 30 位元組**，無需完整 I 影格
- 🧵 **雙執行緒編碼**（2-band 多執行緒），附序列回退池
- 🔧 **執行期掛鉤**——`h264e_sps_id`、`h264e_log2_max_frame_num_minus4`、分段計時開關
- 🆓 **CC0 授權**——隨便用、隨便改、可商用、無需署名

## 📊 效能

ESP32-S3 @ 240 MHz · 1280×720 · 完整 I 影格：

| | 基準 C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| 編碼耗時 | ~2400 ms | **263 ms（快 9.1 倍）** |
| 體積 | — | 單標頭檔 + 手寫 Xtensa 組合語言 |

P 影格鏈（髒區模式，類 UI 靜態內容）：靜態影格 **~34 ms / 30 位元組**；完整影格編碼 ~263 ms。

> x86 平台上與 x264 的對比（速度、體積、PSNR）請見[上游 README](https://github.com/lieff/minih264#comparison-with-x264)。

## 📦 快速開始

### ESP-IDF 元件

將本倉庫複製進專案作為 `components/minih264`，或以 submodule 方式加入——內建的 `CMakeLists.txt` 會自動註冊 Xtensa 組合語言核心：

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### 主機建置（參考實作 / A/B 測試）

在 macOS/Linux 上使用 `-DH264E_FORCE_PLAIN_C` 強制純 C 後端——整條管線可在非裝置環境重現。

### 執行 demo

```bash
cd demo
make test        # 權威 A/B 閘門：SIMD 執行檔 vs 純 C 執行檔，
                 # 碼流以 cmp(1) 逐位元組比較
./minih264_demo  # 三階段測試片（運動 / 靜態+P-skip / 運動）
                 # -> out.h264（Annex-B）；播放：ffplay out.h264
```

ESP32-S3 範例位於 `examples/idf_demo`（ESP-IDF v5.x）：

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

它**在晶片上**編碼同一段測試片（160x120，無 PSRAM 的板子也能跑），隨後在真機上執行 A/B 閘門：Xtensa EE 組合語言 vs 純 C，透過 `H264E_select_backend` 於執行期切換。

## 🚀 使用方法

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P 影格鏈 */
par.max_threads = 2;    /* 2-band 多執行緒 */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* 極限速度 */
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
/* `coded` 有效期限至下一次 H264E_encode 呼叫 */
```

### 髒區編碼（P-skip）

```c
/* MB 列 [y0, y1) 強制 skip：無損自參考影格拷貝（成本≈0，skip_run）。
 * 第 y1 列是去塊濾波守衛列。 */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB 列帶，全域變數 */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... 照常呼叫 H264E_encode(...) */
```

### fork 專屬旋鈕

| 符號 | 意義 |
|---|---|
| `h264e_sps_id` | 輸出碼流中的 SPS id（模仿流 vs 自有流） |
| `h264e_log2_max_frame_num_minus4` | frame_num 位元寬度 |
| `h264e_skip_y0 / h264e_skip_y1` | P-skip 強制列帶 `[y0, y1)`（見上） |

## ✅ 驗證方法

每個組合語言核心必須通過**逐位元一致 A/B 閘門**：同一輸入影格分別以 C 後端與 Xtensa 後端各編碼一次，輸出碼流逐位元組比較。主機建置使用 `-DH264E_FORCE_PLAIN_C`，參考側可在任意環境執行。你可以在任意主機上用 `cd demo && make test` 重現該閘門；ESP32-S3 範例則透過 `H264E_select_backend` 在晶片上執行同樣的閘門。

## 🌍 支援平台

| 後端 | 狀態 |
|---|---|
| ESP32-S3 Xtensa + EE 向量組合語言 | 生產 |
| 純 C（任意 32 位元+ MCU / 主機） | 參考實作 + A/B 閘門 |
| 上游 x86 SSE / ARM NEON | 繼承自上游（本 fork 未測） |

## ⚠️ 侷限性

繼承自上游——相對 x264 *baseline* 檔，minih264 未實作：

- Trellis 量化
- 基於 SATD 的預測模式決策
- 4×4 運動補償

此外，上游的 x86 SSE / ARM NEON 後端原樣保留，但**在本 fork 中未經測試**。

## 🙏 致謝

- [lieff/minih264](https://github.com/lieff/minih264)——上游單標頭檔編碼器。沒有它就沒有本 fork。

## 🔗 相關連結

- [x264](https://www.videolan.org/developers/x264.html)——開源 H.264 編碼器標竿
- [openh264](https://github.com/cisco/openh264)——Cisco 開源 H.264 編解碼器
- [kvazaar](https://github.com/ultravideo/kvazaar)——學術派 HEVC 編碼器
- [JM](http://iphome.hhi.de/suehring/tml/)——H.264/AVC 官方參考軟體（Fraunhofer HHI）
- [h264bsd](https://github.com/mikeracca/h264bsd)——精簡型 H.264 解碼器
- [jcodec](https://github.com/jcodec/jcodec)——純 Java H.264 編解碼器

## 🤝 參與貢獻

歡迎 PR！唯一規則：**每個組合語言核心必須通過逐位元一致 A/B 閘門**——同一輸入分別以 C 後端與 Xtensa 後端編碼，碼流逐位元組比較一致。

## 📄 授權條款

CC0-1.0——公有領域 dedication：隨便用、隨便改、可商用、無需署名。

> 注意：CC0 不含專利授權。H.264 產業專利與編碼器實作無關，需另行看待。
