<div align="center">

# minih264-flash

**Petit, mais fulgurant ⚡ encodeur H.264/SVC en bibliothèque à en-tête unique — ~10× plus rapide sur ESP32-S3**

*Unité vectorielle EE Xtensa + assemblage écrit à la main · identique au bit près à la référence C*

[![License: CC0-1.0](https://img.shields.io/badge/License-CC0--1.0-2ea44f.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-ESP32--S3-E7352C.svg)](#-plateformes-prises-en-charge)
[![Language](https://img.shields.io/badge/lang-C%20%7C%20Xtensa%20ASM-blue.svg)](#)
[![Upstream](https://img.shields.io/badge/upstream-lieff%2Fminih264-8da9c4.svg)](https://github.com/lieff/minih264)
[![GitHub stars](https://img.shields.io/github/stars/ecJon/minih264-flash.svg?style=social)](https://github.com/ecJon/minih264-flash/stargazers)

[English](README.md) | [简体中文](README_zh-CN.md) | [繁體中文](README_zh-TW.md) | [日本語](README_ja.md) | [한국어](README_ko.md) | [Deutsch](README_de.md) | **Français** | [Español](README_es.md) | [Italiano](README_it.md) | [Português (Brasil)](README_pt-BR.md) | [Русский](README_ru.md)

</div>

---

<div align="center">

## 📺 Démo sur l'appareil (ESP32-S3, 160x120)

![ESP32-S3 on-device demo](demo/assets/esp32_demo_160x120.mp4)

![demo frames](demo/assets/esp32_demo_frames.png)

*60 images @ 160x120 — mouvement / statique+P-skip / mouvement*

</div>

---
## 📖 Présentation

**minih264-flash** est un fork de [lieff/minih264](https://github.com/lieff/minih264) — un excellent encodeur H.264/SVC minimaliste, bibliothèque C à en-tête unique en C portable (avec chemins SIMD SSE/NEON optionnels), placée dans le domaine public (CC0). Toute l'architecture et la conception de l'encodeur sont l'œuvre de l'auteur amont — ce projet se tient simplement sur ses épaules.

Sur ces fondations solides, ce fork porte les chemins chauds de l'encodeur dans l'**unité vectorielle EE** de l'ESP32-S3, en assemblage Xtensa écrit à la main — l'encodage d'une image 720p complète passe de ~2400 ms à **263 ms, soit ~10× plus vite**. Chaque noyau est validé par un **verrou A/B identique au bit près** face à la référence C — le chemin SIMD change la *vitesse*, jamais la *sortie*.

> ⚠️ Comme en amont, le code est hautement expérimental : la sophistication de l'encodeur est échangée contre la taille et la vitesse (voir [Limitations](#-limitations)).

## ✨ Fonctionnalités

- 📄 **En-tête unique, zéro dépendance** — juste `#include "minih264e.h"`
- ⚡ **Unité vectorielle EE de l'ESP32-S3** — les 5 noyaux les plus chauds (transformation directe, quantification, reconstruction, SAD, copie de lignes) portés en ASM vectoriel 128 bits ; ~94 % du code reste du C
- 🔁 **Le C reste toujours le repli** — chaque noyau ASM a un équivalent en C pur ; `-DH264E_FORCE_PLAIN_C` désactive l'ASM à la compilation (le backend C est aussi la référence bit à bit du verrou A/B)
- 🎯 **Architecture P-skip** — bande de lignes de MB configurable forcée en skip pour l'encodage par région sale : une image UI statique coûte **~34 ms / 30 octets** au lieu d'un I-frame complet
- 🧵 **Encodage bi-thread** (MT 2 bandes) avec pool de repli série
- 🔧 **Crochets d'exécution** — `h264e_sps_id`, `h264e_log2_max_frame_num_minus4`, commutateur de profilage par segment
- 🆓 **Licence CC0** — utiliser, modifier, vendre ; aucune attribution requise

## 📊 Benchmark

ESP32-S3 @ 240 MHz · 1280×720 · I-frame complet :

| | C de référence @ 160 MHz | **minih264-flash @ 240 MHz** |
|---|---|---|
| temps d'encodage | ~2400 ms | **263 ms (9,1× plus rapide)** |
| encombrement | — | en-tête unique + assemblage manuel |

Chaîne de P-frames (mode région sale, contenu UI statique) : **~34 ms / 30 octets** par image statique ; encodage d'une image complète ~263 ms.

> Pour la comparaison x86 face à x264 (vitesse, taille, PSNR), voir le [README amont](https://github.com/lieff/minih264#comparison-with-x264).

## 📦 Pour commencer

### Composant ESP-IDF

Copiez ce dépôt dans votre projet sous `components/minih264`, ou ajoutez-le en submodule — le `CMakeLists.txt` fourni enregistre automatiquement les noyaux ASM Xtensa :

```bash
git submodule add https://github.com/ecJon/minih264-flash.git components/minih264
```

### Build hôte (référence / tests A/B)

Sur macOS/Linux, compilez avec `-DH264E_FORCE_PLAIN_C` pour forcer le backend C pur — tout le pipeline reste reproductible hors de la cible.

### Lancer la démo

```bash
cd demo
make test        # verrou A/B faisant foi : binaire SIMD vs binaire C pur,
                 # flux binaires comparés octet par octet avec cmp(1)
./minih264_demo  # clip en trois phases (mouvement / statique+P-skip / mouvement)
                 # -> out.h264 (Annex-B) ; lecture : ffplay out.h264
```

Un exemple ESP32-S3 se trouve dans `examples/idf_demo` (ESP-IDF v5.x) :

```bash
idf.py set-target esp32s3
idf.py -p PORT build flash monitor
```

Il encode le même clip **sur la puce** (160x120, fonctionne sans PSRAM) puis exécute le verrou A/B sur l'appareil : assemblage Xtensa EE vs C pur, basculé à l'exécution via `H264E_select_backend`.

## 🚀 Utilisation

```c
#include "minih264e.h"

H264E_create_param_t par = { 0 };
par.width  = 1280;
par.height = 720;
par.gop         = 30;   /* chaîne de P-frames */
par.max_threads = 2;    /* multithread 2 bandes */

int szp, szs;
H264E_sizeof(&par, &szp, &szs);
H264E_persist_t *persist = malloc(szp);
H264E_scratch_t *scratch = malloc(szs);
H264E_init(persist, &par);

H264E_run_param_t rp = {
    .encode_speed = 9,          /* le plus rapide */
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
/* `coded` reste valable jusqu'au prochain appel H264E_encode */
```

### Encodage par région sale (P-skip)

```c
/* Les lignes de MB [y0, y1) sont forcées en skip : copie sans perte
 * depuis l'image de référence (coût≈0, skip_run).
 * La ligne y1 est une ligne de garde pour le deblocking. */
extern int h264e_skip_y0, h264e_skip_y1;   /* bande de lignes MB, globale */

h264e_skip_y0 = 20;
h264e_skip_y1 = 31;

/* ... encoder normalement avec H264E_encode(...) */
```

### Réglages propres au fork

| symbole | signification |
|---|---|
| `h264e_sps_id` | id SPS inscrit dans le flux émis (flux imité vs flux propre) |
| `h264e_log2_max_frame_num_minus4` | largeur en bits de frame_num |
| `h264e_skip_y0 / h264e_skip_y1` | bande forcée P-skip `[y0, y1)` (voir ci-dessus) |

## ✅ Méthodologie de vérification

Chaque noyau ASM doit passer un **verrou A/B identique au bit près** : la même image d'entrée est encodée une fois avec le backend C et une fois avec le backend Xtensa, puis les deux flux binaires sont comparés octet par octet. Les builds hôtes utilisent `-DH264E_FORCE_PLAIN_C` pour que le côté référence du verrou s'exécute partout. Vous pouvez reproduire le verrou sur n'importe quel hôte avec `cd demo && make test` ; l'exemple ESP32-S3 exécute le même verrou sur la puce via `H264E_select_backend`.

## 🌍 Plateformes prises en charge

| backend | état |
|---|---|
| ESP32-S3 Xtensa + ASM vectoriel EE | production |
| C pur (tout MCU 32 bits+ / hôte) | référence & verrou A/B |
| x86 SSE / ARM NEON de l'amont | hérité (non testé dans ce fork) |

## ⚠️ Limitations

Héritées de l'amont — face à un build x264 *baseline*, minih264 n'implémente pas :

- la quantification Trellis
- la sélection de mode de prédiction basée sur le SATD
- la compensation de mouvement 4×4

Par ailleurs, les backends x86 SSE / ARM NEON de l'amont sont emportés tels quels mais **non testés dans ce fork**.

## 🙏 Remerciements

- [lieff/minih264](https://github.com/lieff/minih264) — l'encodeur amont à en-tête unique. Ce fork n'existerait pas sans lui.

## 🔗 Liens intéressants

- [x264](https://www.videolan.org/developers/x264.html) — l'encodeur H.264 open source de référence
- [openh264](https://github.com/cisco/openh264) — codec H.264 open source de Cisco
- [kvazaar](https://github.com/ultravideo/kvazaar) — encodeur HEVC académique
- [JM](http://iphome.hhi.de/suehring/tml/) — logiciel de référence H.264/AVC (Fraunhofer HHI)
- [h264bsd](https://github.com/mikeracca/h264bsd) — décodeur H.264 compact
- [jcodec](https://github.com/jcodec/jcodec) — codec H.264 en Java pur

## 🤝 Contribuer

Les PR sont les bienvenues ! Une seule règle : **chaque noyau ASM doit passer le verrou A/B identique au bit près** — encodez la même entrée avec le backend C et le backend Xtensa, puis comparez les flux binaires octet par octet.

## 📄 Licence

CC0-1.0 — dedication au domaine public. Utiliser, modifier, vendre ; aucune attribution requise.

> Remarque : CC0 n'accorde aucun droit de brevet. Les brevets industriels liés au H.264 constituent un dossier séparé, indépendant de l'implémentation de l'encodeur.
