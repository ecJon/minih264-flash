<div align="center">

# minih264-flash

**Pequeno, porém absurdo de rápido ⚡ encoder H.264/SVC de cabeçalho único — ~10× mais rápido no ESP32-S3**

*Unidade vetorial EE Xtensa + assembly escrito à mão · bit-exato em relação à referência em C*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-plataformas-suportadas)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | **Português (Brasil)** | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 Demonstração no dispositivo (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 frames @ 160x120 — movimento / estático+P-skip / movimento*

</div>

---
## 📖 Introdução

**minih264-flash** é um fork de [lieff/minih264](https://github.com/lieff/minih264) — um excelente encoder H.264/SVC minimalista, biblioteca C de cabeçalho único escrita em C portável (com caminhos SIMD SSE/NEON opcionais), lançada em domínio público (CC0). Toda a arquitetura e o design do encoder são mérito do autor original — este projeto apenas se apoia em seus ombros.

Sobre essa base sólida, este fork porta os caminhos críticos do encoder para a **unidade vetorial EE** do ESP32-S3, como assembly Xtensa escrito à mão — a codificação de um frame completo em 720p cai de ~2400 ms para **263 ms, ~10× mais rápido**. Cada kernel é aceito por um **gate A/B bit-exato** contra a referência em C — o caminho SIMD muda a *velocidade*, nunca a *saída*.

> ⚠️ Como no upstream, o código é altamente experimental: a sofisticação do encoder é trocada por tamanho e velocidade (veja [Limitações](#-limitações)).

## ✨ Funcionalidades

- 📄 **Cabeçalho único, zero dependências** — basta `#include "minih264e.h"`
- ⚡ **Unidade vetorial EE do ESP32-S3** — os 5 kernels mais quentes (transformada direta, quantização, reconstrução, SAD, cópia de linhas) portados para ASM vetorial de 128 bits; ~94% do código continua em C
- 🔁 **C é sempre o fallback** — cada kernel ASM tem um gêmeo em C puro; `-DH264E_FORCE_PLAIN_C` desativa o ASM em tempo de compilação (o backend C também é a referência bit-exata do gate A/B)
- 🎯 **Arquitetura P-skip** — uma faixa configurável de linhas de MB é forçada a skip para codificação de região suja: um frame de UI estático custa **~34 ms / 30 bytes** em vez de um I-frame completo
- 🧵 **Codificação com dois threads** (MT de 2 faixas) com pool de fallback serial
- 🔧 **Ganchos de runtime** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, interruptor de profiling por segmento
- 🆓 **Licença CC0** — usar, modificar, vender; sem necessidade de atribuição

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · I-frame completo:

| | C de referência @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| tempo de codificação | ~2400 ms | **263 ms (9,1× mais rápido)** |
| tamanho | — | cabeçalho único + assembly à mão |

Cadeia de P-frames (modo região suja, conteúdo de UI estático): **~34 ms / 30 bytes** por frame estático; codificação de frame completo ~263 ms.

> Para a comparação com o x264 em x86 (velocidade, tamanho, PSNR), veja o [README do upstream](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Primeiros passos

### Componente ESP-IDF

Copie este repositório para o seu projeto como `components/minih264`, ou adicione-o como submodule — o `CMakeLists.txt` incluído registra automaticamente os kernels ASM Xtensa:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Build no host (referência / testes A/B)

No macOS/Linux, compile com `-DH264E_FORCE_PLAIN_C` para forçar o backend em C puro — todo o pipeline continua reproduzível fora do dispositivo.

### Executar a demo

```bash
cd demo
make test        # gate A/B autoritativo: binário SIMD vs binário C puro,
                 # bitstreams comparados byte a byte com cmp(1)
./minih264_demo  # clipe em três fases (movimento / estático+P-skip / movimento)
                 # -> out.h264 (Annex-B); reprodução: ffplay out.h264
```

Um exemplo para ESP32-S3 vive em `examples/idf_demo` (ESP-IDF v5.x):

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

Ele codifica o mesmo clipe **no chip** (160x120, funciona sem PSRAM) e depois roda o gate A/B no dispositivo: assembly Xtensa EE vs C puro, alternado em tempo de execução via `H264E_select_backend`.

## 🚀 Uso

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* cadeia de P-frames */
par.max_threads = 2;    /* multithread de 2 faixas */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* o mais rápido */
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
/* `coded` é válido até a próxima chamada de H264E_encode */
```

### Codificação de região suja (P-skip)

```c
/* As linhas de MB [y0, y1) são forçadas a skip: cópia sem perda
 * do frame de referência (custo≈0, skip_run).
 * A linha y1 é uma linha de guarda para o deblocking. */
extern int h264e_skip_y0, h264e_skip_y1;   /* faixa de linhas MB, global */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... codificar normalmente com H264E_encode(...) */
```

### Controles específicos do fork

| símbolo | significado |
|---|---|
| `h264e_sps_id` | id SPS escrito no fluxo emitido (fluxo imitado vs. fluxo próprio) |
| `h264e_log2_max_frame_num_minus4` | largura em bits de frame_num |
| `h264e_skip_y0 / h264e_skip_y1` | faixa forçada P-skip `[y0, y1)` (ver acima) |

## ✅ Metodologia de verificação

Cada kernel ASM deve passar por um **gate A/B bit-exato**: o mesmo frame de entrada é codificado uma vez com o backend C e outra com o backend Xtensa, e os dois bitstreams de saída são comparados byte a byte. Builds no host usam `-DH264E_FORCE_PLAIN_C`, de modo que o lado de referência roda em qualquer ambiente. Você pode reproduzir o gate em qualquer host com `cd demo && make test`; o exemplo ESP32-S3 executa o mesmo gate no chip via `H264E_select_backend`.

## 🌍 Plataformas suportadas

| backend | status |
|---|---|
| ESP32-S3 Xtensa + ASM vetorial EE | produção |
| C puro (qualquer MCU 32 bits+ / host) | referência & gate A/B |
| x86 SSE / ARM NEON do upstream | herdado (não testado neste fork) |

## ⚠️ Limitações

Herdadas do upstream — em relação a um build *baseline* do x264, o minih264 não implementa:

- quantização Trellis
- seleção de modo de predição baseada em SATD
- compensação de movimento 4×4

Além disso, os backends x86 SSE / ARM NEON do upstream são mantidos como estão, mas **não foram testados neste fork**.

## 🙏 Créditos e agradecimentos

- [lieff/minih264](https://github.com/lieff/minih264) — o encoder upstream de cabeçalho único. Este fork não existiria sem ele.

## 🔗 Links interessantes

- [x264](https://www.videolan.org/developers/x264.html) — o encoder H.264 open source de referência
- [openh264](https://github.com/cisco/openh264) — codec H.264 open source da Cisco
- [kvazaar](https://github.com/ultravideo/kvazaar) — encoder HEVC acadêmico
- [JM](http://iphome.hhi.de/suehring/tml/) — software de referência H.264/AVC (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — decoder H.264 compacto
- [jcodec](https://github.com/jcodec/jcodec) — codec H.264 em Java puro

## 🤝 Contribuir

PRs são bem-vindos! Uma única regra: **todo kernel ASM deve passar pelo gate A/B bit-exato** — codifique a mesma entrada com o backend C e com o backend Xtensa e compare os bitstreams byte a byte.

## 📄 Licença

CC0-1.0 — dedicação ao domínio público. Usar, modificar, vender; sem necessidade de atribuição.

> Nota: CC0 não concede nenhum direito de patente. As patentes industriais do H.264 são um assunto separado, independente da implementação do encoder.
