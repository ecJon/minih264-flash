<div align="center">

# minih264-flash

**小さく、しかし爆速 ⚡ H.264/SVC エンコーダー シングルヘッダーライブラリ——ESP32-S3 で約 10 倍速**

*Xtensa EE ベクトルユニット + ハンドアセンブリ · C リファレンスとビット単位で一致*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-対応プラットフォーム)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | **日本語** | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 実機デモ（ESP32-S3、160x120）

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 フレーム @ 160x120 —— 動き / 静止+P-skip / 動き*

</div>

---
## 📖 概要

**minih264-flash** は [lieff/minih264](https://github.com/lieff/minih264) のフォークです。上流は、ポータブルな C で書かれた優れたミニマルなシングルヘッダー H.264/SVC エンコーダーライブラリ（オプションで SSE/NEON SIMD パスを搭載）で、パブリックドメイン（CC0）として公開されています。エンコーダーのアーキテクチャと設計はすべて上流の作者の功績です——このプロジェクトは巨人の肩の上に立っています。

その堅実な土台の上に、このフォークはエンコーダーのホットパスを ESP32-S3 の **EE ベクトルユニット**へハンドアセンブリとして移植しました——720p の完全フレームエンコードは約 2400 ms から **263 ms（約 10 倍速）** へ。すべてのカーネルは C リファレンスとの**ビット完全一致 A/B ゲート**で検証されています——SIMD パスが変えるのは*速度*であって、*出力*ではありません。

> ⚠️ 上流と同様にコードは実験的なものです：エンコーダーの精緻さをサイズと速度と引き換えにしています（[制限事項](#-制限事項)を参照）。

## ✨ 特徴

- 📄 **シングルヘッダー・依存ゼロ**——`#include "minih264e.h"` するだけ
- ⚡ **ESP32-S3 EE ベクトルユニット**——最もホットな 5 つのカーネル（順方向変換・量子化・再構成・SAD・行コピー）を 128 ビットベクトルアセンブリに移植。コードの約 94% は依然として C
- 🔁 **C は常にフォールバック**——すべてのアセンブリカーネルには純 C 実装が対応。`-DH264E_FORCE_PLAIN_C` でコンパイル時にアセンブリを無効化できます（C バックエンドは A/B ゲートのビット一致リファレンスでもあります）
- 🎯 **P-skip アーキテクチャ**——設定可能な MB 行バンドを強制スキップするダーティリージョンエンコーディング：静止 UI フレームは完全 I フレームの代わりに **約 34 ms / 30 バイト**
- 🧵 **デュアルスレッドエンコード**（2-band MT）、シリアルフォールバックプール付き
- 🔧 **ランタイムフック**——`h264e_sps_id`、`h264e_log2_max_frame_num_minus4`、区間計測スイッチ
- 🆓 **CC0 ライセンス**——利用・改変・販売自由、クレジット表記不要

## 📊 ベンチマーク

ESP32-S3 @ 240 MHz · 1280×720 · 完全 I フレーム：

| | baseline C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| エンコード時間 | ~2400 ms | **263 ms（9.1 倍速）** |
| フットプリント | — | シングルヘッダー + ハンドアセンブリ |

P フレームチェーン（ダーティリージョンモード、UI 系の静止コンテンツ）：静止フレーム **約 34 ms / 30 バイト**、フルフレームエンコードは約 263 ms。

> x86 上での x264 との比較（速度・サイズ・PSNR）は[上流の README](https://github.com/lieff/minih264#comparison-with-x264) を参照してください。

## 📦 はじめに

### ESP-IDF コンポーネント

このリポジトリを `components/minih264` としてプロジェクトにコピーするか、サブモジュールとして追加してください。同梱の `CMakeLists.txt` が Xtensa アセンブリカーネルを自動登録します：

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### ホストビルド（リファレンス / A/B テスト）

macOS/Linux では `-DH264E_FORCE_PLAIN_C` を付けてビルドするとピュア C バックエンドが強制され、パイプライン全体を実機なしで再現できます。

### デモの実行

```bash
cd demo
make test        # 権威ある A/B ゲート：SIMD バイナリ vs ピュア C バイナリ、
                 # ビットストリームを cmp(1) でバイト単位比較
./minih264_demo  # 3 フェーズのテストクリップ（動き / 静止+P-skip / 動き）
                 # -> out.h264（Annex-B）；再生：ffplay out.h264
```

ESP32-S3 向けサンプルは `examples/idf_demo`（ESP-IDF v5.x）：

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

同じクリップを**チップ上で**エンコードし（160x120、PSRAM なしのボードでも動作）、その後 A/B ゲートを実機上で実行します：Xtensa EE アセンブリ vs ピュア C、`H264E_select_backend` で実行時に切り替え。

## 🚀 使い方

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P フレームチェーン */
par.max_threads = 2;    /* 2-band マルチスレッド */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* 最速 */
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
/* `coded` は次の H264E_encode 呼び出しまで有効 */
```

### ダーティリージョンエンコーディング（P-skip）

```c
/* MB 行 [y0, y1) を強制スキップ：参照フレームから無欠喪コピー
 * （コスト≈0、skip_run）。y1 行はデブロック用ガード行。 */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB 行バンド、グローバル */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... 通常どおり H264E_encode(...) を呼ぶ */
```

### フォーク固有のノブ

| シンボル | 意味 |
|---|---|
| `h264e_sps_id` | 出力ストリームに書き込む SPS id（ストリーム模倣 vs 独自ストリーム） |
| `h264e_log2_max_frame_num_minus4` | frame_num のビット幅 |
| `h264e_skip_y0 / h264e_skip_y1` | P-skip 強制バンド `[y0, y1)`（上記参照） |

## ✅ 検証手法

すべてのアセンブリカーネルは**ビット完全一致 A/B ゲート**を通過しなければなりません：同じ入力フレームを C バックエンドと Xtensa バックエンドでそれぞれエンコードし、出力ビットストリームをバイト単位で比較します。ホストビルドでは `-DH264E_FORCE_PLAIN_C` を使用し、リファレンス側は任意の環境で実行できます。このゲートは任意のホストで `cd demo && make test` により再現でき、ESP32-S3 サンプルは `H264E_select_backend` によってチップ上で同じゲートを実行します。

## 🌍 対応プラットフォーム

| バックエンド | 状態 |
|---|---|
| ESP32-S3 Xtensa + EE ベクトル ASM | 本番 |
| ピュア C（32 ビット以上の任意 MCU / ホスト） | リファレンス & A/B ゲート |
| 上流の x86 SSE / ARM NEON | 上流から継承（本フォークでは未検証） |

## ⚠️ 制限事項

上流から継承——x264 *baseline* に対して、minih264 は以下を実装していません：

- Trellis 量子化
- SATD ベースの予測モード決定
- 4×4 動き補償

さらに、上流の x86 SSE / ARM NEON バックエンドはそのまま引き継がれていますが、**本フォークでは未検証**です。

## 🙏 クレジット・謝辞

- [lieff/minih264](https://github.com/lieff/minih264)——上流のシングルヘッダーエンコーダー。このフォークはそれなしには存在しません。

## 🔗 関連リンク

- [x264](https://www.videolan.org/developers/x264.html)——オープンソース H.264 エンコーダーの標準的存在
- [openh264](https://github.com/cisco/openh264)——Cisco 製オープンソース H.264 コーデック
- [kvazaar](https://github.com/ultravideo/kvazaar)——アカデミック系 HEVC エンコーダー
- [JM](http://iphome.hhi.de/suehring/tml/)——H.264/AVC 公式リファレンスソフトウェア（Fraunhofer HHI）
- [h264bsd](https://github.com/mikeracca/h264bsd)——コンパクトな H.264 デコーダー
- [jcodec](https://github.com/jcodec/jcodec)——ピュア Java の H.264 コーデック

## 🤝 コントリビュート

PR を歓迎します！ルールはひとつ：**すべてのアセンブリカーネルはビット完全一致 A/B ゲートを通過すること**——同じ入力を C バックエンドと Xtensa バックエンドでエンコードし、ビットストリームをバイト単位で一致させてください。

## 📄 ライセンス

CC0-1.0——パブリックドメイン。利用・改変・販売自由、クレジット表記不要。

> 注意：CC0 は特許権を付与するものではありません。H.264 の業界特許はエンコーダーの実装とは別の問題です。
