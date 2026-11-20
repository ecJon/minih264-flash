<div align="center">

# minih264-flash

**작지만 번개처럼 빠른 ⚡ H.264/SVC 인코더 단일 헤더 라이브러리 — ESP32-S3에서 약 10배 빠름**

*Xtensa EE 벡터 유닛 + 핸드어셈블리 · C 레퍼런스와 비트 단위 일치*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-지원-플랫폼)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | **한국어** | [Deutsch](README_de.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 실기기 데모 (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 프레임 @ 160x120 — 모션 / 정지+P-skip / 모션*

</div>

---
## 📖 소개

**minih264-flash**는 [lieff/minih264](https://github.com/lieff/minih264)의 포크입니다. 원본은 이식성 있는 순수 C로 작성된 훌륭한 미니멀 단일 헤더 H.264/SVC 인코더 라이브러리(선택적 SSE/NEON SIMD 경로 포함)로, 퍼블릭 도메인(CC0)으로 공개되어 있습니다. 인코더의 아키텍처와 설계는 모두 원본 저자의 공입니다 — 이 프로젝트는 거인의 어깨 위에 서 있습니다.

그 탄탄한 기반 위에서 이 포크는 인코더 핫패스를 ESP32-S3의 **EE 벡터 유닛**으로 핸드어셈블리로 이식했습니다 — 720p 풀 프레임 인코딩이 약 2400 ms에서 **263 ms(약 10배)**로. 모든 커널은 C 레퍼런스와의 **비트 단위 일치 A/B 게이트**로 검증됩니다 — SIMD 경로는 *속도*만 바꿀 뿐, *출력*은 바꾸지 않습니다.

> ⚠️ 원본과 마찬가지로 코드는 실험적입니다: 인코더의 정교함을 크기와 속도로 교환합니다([제한 사항](#-제한-사항) 참조).

## ✨ 특징

- 📄 **단일 헤더, 의존성 없음** — `#include "minih264e.h"` 한 줄이면 끝
- ⚡ **ESP32-S3 EE 벡터 유닛** — 가장 뜨거운 5개 커널(순방향 변환, 양자화, 재구성, SAD, 행 복사)을 128비트 벡터 어셈블리로 이식. 코드의 약 94%는 여전히 C
- 🔁 **C는 언제나 폴백** — 모든 어셈블리 커널에는 순수 C 구현이 대응합니다. `-DH264E_FORCE_PLAIN_C`로 컴파일 시점에 어셈블리를 끌 수 있습니다(C 백엔드는 A/B 게이트의 비트 일치 레퍼런스이기도 합니다)
- 🎯 **P-skip 아키텍처** — 설정 가능한 MB 행 밴드를 강제 스킵하는 더티 리전(dirty-region) 인코딩: 정적 UI 프레임은 풀 I 프레임 대신 **약 34 ms / 30 바이트**
- 🧵 **듀얼 스레드 인코딩**(2-band MT), 직렬 폴백 풀 포함
- 🔧 **런타임 훅** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, 구간별 프로파일링 스위치
- 🆓 **CC0 라이선스** — 사용·수정·판매 자유, 출처 표기 불필요

## 📊 벤치마크

ESP32-S3 @ 240 MHz · 1280×720 · 풀 I 프레임:

| | baseline C @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| 인코딩 시간 | ~2400 ms | **263 ms (9.1배 향상)** |
| 크기 | — | 단일 헤더 + 핸드어셈블리 |

P 프레임 체인(더티 리전 모드, UI 형태의 정적 콘텐츠): 정적 프레임 **약 34 ms / 30 바이트**, 풀 프레임 인코딩 약 263 ms.

> x86에서의 x264 비교(속도·크기·PSNR)는 [원본 README](https://github.com/lieff/minih264#comparison-with-x264)를 참고하세요.

## 📦 시작하기

### ESP-IDF 컴포넌트

이 저장소를 프로젝트에 `components/minih264`로 복사하거나 서브모듈로 추가하세요. 포함된 `CMakeLists.txt`가 Xtensa 어셈블리 커널을 자동 등록합니다:

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### 호스트 빌드(레퍼런스 / A/B 테스트)

macOS/Linux에서는 `-DH264E_FORCE_PLAIN_C` 옵션으로 순수 C 백엔드를 강제할 수 있으며 — 전체 파이프라인을 디바이스 없이 재현할 수 있습니다.

### 데모 실행

```bash
cd demo
make test        # 공식 A/B 게이트: SIMD 바이너리 vs 순수 C 바이너리,
                 # 비트스트림을 cmp(1)로 바이트 단위 비교
./minih264_demo  # 3단계 테스트 클립(모션 / 정지+P-skip / 모션)
                 # -> out.h264 (Annex-B); 재생: ffplay out.h264
```

ESP32-S3 예제는 `examples/idf_demo` (ESP-IDF v5.x)에 있습니다:

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

동일한 클립을 **칩 위에서** 인코딩하고(160x120, PSRAM 없는 보드에서도 동작), 이어서 실기기에서 A/B 게이트를 실행합니다: Xtensa EE 어셈블리 vs 순수 C, `H264E_select_backend`로 런타임에 전환.

## 🚀 사용법

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* P 프레임 체인 */
par.max_threads = 2;    /* 2-band 멀티스레딩 */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* 최고 속도 */
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
/* `coded`는 다음 H264E_encode 호출까지 유효 */
```

### 더티 리전 인코딩(P-skip)

```c
/* MB 행 [y0, y1)을 강제 스킵: 참조 프레임에서 무손실 복사
 * (비용≈0, skip_run). y1 행은 디블로킹 가드 행. */
extern int h264e_skip_y0, h264e_skip_y1;   /* MB 행 밴드, 전역 */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... 평소처럼 H264E_encode(...) 호출 */
```

### 포크 전용 설정

| 심볼 | 의미 |
|---|---|
| `h264e_sps_id` | 출력 스트림에 기록할 SPS id (스트림 모방 vs 자체 스트림) |
| `h264e_log2_max_frame_num_minus4` | frame_num 비트 폭 |
| `h264e_skip_y0 / h264e_skip_y1` | P-skip 강제 밴드 `[y0, y1)` (위 참조) |

## ✅ 검증 방법론

모든 어셈블리 커널은 **비트 단위 일치 A/B 게이트**를 통과해야 합니다: 동일한 입력 프레임을 C 백엔드와 Xtensa 백엔드로 각각 인코딩한 뒤, 출력 비트스트림을 바이트 단위로 비교합니다. 호스트 빌드는 `-DH264E_FORCE_PLAIN_C`를 사용해 레퍼런스 측을 어디서든 실행할 수 있습니다. 이 게이트는 임의의 호스트에서 `cd demo && make test`로 재현할 수 있으며, ESP32-S3 예제는 `H264E_select_backend`을 통해 칩 위에서 동일한 게이트를 실행합니다.

## 🌍 지원 플랫폼

| 백엔드 | 상태 |
|---|---|
| ESP32-S3 Xtensa + EE 벡터 ASM | 프로덕션 |
| 순수 C (32비트 이상 MCU / 호스트) | 레퍼런스 & A/B 게이트 |
| 원본 x86 SSE / ARM NEON | 원본에서 상속 (이 포크에서 미검증) |

## ⚠️ 제한 사항

원본에서 상속 — x264 *baseline* 빌드와 비교하여 minih264에는 다음 기능이 없습니다:

- Trellis 양자화
- SATD 기반 예측 모드 결정
- 4×4 동작 보상

또한 원본의 x86 SSE / ARM NEON 백엔드는 그대로 유지되지만 **이 포크에서는 검증되지 않았습니다**.

## 🙏 크레딧 및 감사의 말

- [lieff/minih264](https://github.com/lieff/minih264) — 원본 단일 헤더 인코더. 이 포크는 그것 없이는 존재할 수 없습니다.

## 🔗 관련 링크

- [x264](https://www.videolan.org/developers/x264.html) — 오픈소스 H.264 인코더의 표준
- [openh264](https://github.com/cisco/openh264) — Cisco의 오픈소스 H.264 코덱
- [kvazaar](https://github.com/ultravideo/kvazaar) — 학계 계열 HEVC 인코더
- [JM](http://iphome.hhi.de/suehring/tml/) — H.264/AVC 공식 레퍼런스 소프트웨어 (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — 경량 H.264 디코더
- [jcodec](https://github.com/jcodec/jcodec) — 순수 Java H.264 코덱

## 🤝 기여하기

PR을 환영합니다! 규칙은 하나: **모든 어셈블리 커널은 비트 단위 일치 A/B 게이트를 통과해야 합니다** — 동일한 입력을 C 백엔드와 Xtensa 백엔드로 인코딩하고, 비트스트림을 바이트 단위로 일치시키세요.

## 📄 라이선스

CC0-1.0 — 퍼블릭 도메인. 사용·수정·판매 자유, 출처 표기 불필요.

> 참고: CC0는 특허권을 부여하지 않습니다. H.264 업계 특허는 인코더 구현과 별개의 문제입니다.
