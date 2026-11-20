/*
 * minih264-flash demo — encode a deterministic synthetic clip on any host or
 * on the ESP32-S3 itself, and (with --ab) run the project's bit-exact A/B
 * gate between two backends in a single process.
 *
 * Three-phase story (normal mode):
 *   phase 1  full motion            -> normal P-frame sizes
 *   phase 2  static content + P-skip band -> frames collapse to ~dozens of bytes
 *   phase 3  full motion again      -> sizes recover
 *
 * Host build (see demo/Makefile):
 *   cc -O2 -I../include minih264_demo.c -o minih264_demo -lpthread
 *   cc -O2 -DH264E_FORCE_PLAIN_C    ... -> plain-C reference build
 *   cc -O2 -DH264E_ENABLE_PLAIN_C=1 ... -> dual-backend build (--ab works)
 *
 * ESP32-S3: compiled by examples/idf_demo (the __xtensa__ target pulls the
 * FreeRTOS worker pool and the real esp_timer; the A/B gate runs through
 * H264E_select_backend: Xtensa ASM vs plain C, on the chip itself).
 *
 * License: CC0-1.0 (same as the rest of the project).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>

#if defined(__xtensa__)
#define DEMO_ESP32 1
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#else
#include <pthread.h>
#endif

/* Apple clang lacks the GCC-ism vtbl2q_u8 used by the header's NEON path.
 * vqtbl2q_u8 has identical semantics (zero outside 0..31), so bridge it here
 * instead of patching the vendored header. */
#if defined(__aarch64__) && defined(__clang__) && !defined(DEMO_ESP32)
#include <arm_neon.h>
static inline uint8x8_t vtbl2q_u8(uint8x16x2_t lut, uint8x8_t idx)
{
    return vget_low_u8(vqtbl2q_u8(lut, vcombine_u8(idx, vdup_n_u8(0))));
}
#endif

/* The fork declares its P-skip band globals (h264e_skip_y0/y1) and profiling
 * counters inside the plain-C section of the header. On 64-bit hosts the
 * header auto-defines MINIH264_ONLY_SIMD and skips that section, so the use
 * sites elsewhere would reference undeclared identifiers — provide them here,
 * before the include. (Plain-C builds and the Xtensa target keep the header's
 * own definitions.) */
#if (defined(__x86_64__) || defined(__aarch64__) || defined(_M_X64) || \
     defined(_M_ARM64)) && \
    !defined(H264E_FORCE_PLAIN_C) && !defined(H264E_ENABLE_PLAIN_C)
volatile int h264e_skip_y0 = 0, h264e_skip_y1 = 0;
volatile int h264e_mbenc_n = 0, h264e_mbenc_dbg = 0;
static volatile int h264e_pb_dbg = 0;
#endif

#define MINIH264_IMPLEMENTATION
#include "minih264e.h"

#ifdef DEMO_ESP32
/* The Xtensa tsqd wrapper references this diagnostic knob, which the fork
 * normally gets from its firmware's video_enc.c (not part of this repo).
 * Default it off so the demo stands alone. */
int h264e_seg_dbg = 0;

/* unit-check the EE SAD asm against a plain C reimplementation: first probe
 * the actual EE zip/lane semantics (the asm's own docs mis-record them),
 * then sweep a single 255-valued pixel across all 256 positions. */
static int demo_ref_sad_mb(const uint8_t *a, int a_stride, const uint8_t *b, int sad[4])
{
    int s0 = 0, s1 = 0, s2 = 0, s3 = 0;
    for (int r = 0; r < 16; r++)
        for (int c = 0; c < 16; c++)
        {
            int d = abs((int)a[r * a_stride + c] - (int)b[r * 16 + c]);
            if (r < 8) { if (c < 8) s0 += d; else s1 += d; }
            else       { if (c < 8) s2 += d; else s3 += d; }
        }
    sad[0] = s0; sad[1] = s1; sad[2] = s2; sad[3] = s3;
    return s0 + s1 + s2 + s3;
}

static void demo_sad_selftest(void)
{
    static uint8_t A_unaligned[16 * 32 + 64], B_unaligned[16 * 16 + 64];
    /* EE vector loads demand 16-byte alignment; mirror the real call sites */
    uint8_t *A = (uint8_t *)(((uintptr_t)A_unaligned + 63) & ~(uintptr_t)63);
    uint8_t *B = (uint8_t *)(((uintptr_t)B_unaligned + 63) & ~(uintptr_t)63);
    int bad = 0;

    /* -- probe 1: vld/vst byte identity -- */
    extern void ee_probe_roundtrip(const uint8_t *in, uint8_t *out);
    for (int i = 0; i < 16; i++) A[i] = (uint8_t)i;
    memset(B, 0xAA, 16);
    ee_probe_roundtrip(A, B);
    printf("[sadtest] roundtrip ok=%d (B=%d..%d)\n",
           memcmp(A, B, 16) == 0, B[0], B[15]);

    /* -- probe 2: where does ee.vzip.8 put q0-in and q1-in bytes? -- */
    extern void ee_probe_zip16(const uint8_t *ina, const uint8_t *inb,
                               uint8_t *lo, uint8_t *hi);
    memset(B, 0xAA, 64);
    for (int i = 0; i < 16; i++) B[i] = (uint8_t)(16 + i); /* q1-in = 16..31 */
    ee_probe_zip16(A, B, B + 16, B + 32);
    printf("[sadtest] zip q0 lo: %d %d %d %d %d %d %d %d\n",
           B[16], B[17], B[18], B[19], B[20], B[21], B[22], B[23]);
    printf("[sadtest] zip q0 hi: %d %d %d %d %d %d %d %d\n",
           B[24], B[25], B[26], B[27], B[28], B[29], B[30], B[31]);
    printf("[sadtest] zip q1 lo: %d %d %d %d %d %d %d %d\n",
           B[32], B[33], B[34], B[35], B[36], B[37], B[38], B[39]);
    printf("[sadtest] zip q1 hi: %d %d %d %d %d %d %d %d\n",
           B[40], B[41], B[42], B[43], B[44], B[45], B[46], B[47]);
    for (int i = 0; i < 16; i++) B[i] = 0;

    /* per-pixel probe: single 255-valued pixel at (r,c) -> print the quadrant
     * map the asm actually produces (T/B x L/R), one char per pixel */
    char map[16][17];
    memset(map, 0, sizeof map);
    for (int r = 0; r < 16; r++)
    {
        for (int c = 0; c < 16; c++)
        {
        memset(A, 0, 16 * 32);
        memset(B, 0, 16 * 16);
        A[r * 16 + c] = 255;
            int sa[4];
            h264e_sad_mb_unlaign_8x8_xtensa(A, 16, B, sa);
            /* decode: which quadrant got the 255? (0=TL,1=TR,2=BL,3=BR) */
            int q = -1;
            for (int k = 0; k < 4; k++)
                if (sa[k] == 255) q = k;
            if (q < 0) { map[r][c] = '?'; bad++; }
            else map[r][c] = "TLBR"[q]; /* order: T-L, T-R, B-L, B-R */
            if (q >= 0 && sa[0] + sa[1] + sa[2] + sa[3] != 255) { map[r][c] = 'X'; bad++; }
        }
    }
    printf("[sadtest] quadrant map (expect rows0-7: L then R; rows8-15: L then R):\n");
    for (int r = 0; r < 16; r++)
    {
        printf("[sadtest] row %2d |%s|\n", r, map[r]);
        esp_rom_delay_us(30000); /* let the UART drain; garbled lines otherwise */
    }

    uint32_t seed = 0x12345678;
    for (int t = 0; t < 4096 && bad < 8; t++)
    {
        for (int i = 0; i < 256; i++) { seed = seed * 1664525u + 1013904223u; A[i] = (uint8_t)(seed >> 24); }
        for (int i = 0; i < 256; i++) { seed = seed * 1664525u + 1013904223u; B[i] = (uint8_t)(seed >> 24); }
        int sa[4], sr[4];
        int suma = h264e_sad_mb_unlaign_8x8_xtensa(A, 16, B, sa);
        int sumr = demo_ref_sad_mb(A, 16, B, sr);
        if (memcmp(sa, sr, sizeof sa) || suma != sumr)
        {
            printf("[sadtest] random t=%d: asm={%d,%d,%d,%d}/%d ref={%d,%d,%d,%d}/%d\n",
                   t, sa[0], sa[1], sa[2], sa[3], suma,
                   sr[0], sr[1], sr[2], sr[3], sumr);
            bad++;
        }
    }
    printf("[sadtest] %s (%d mismatches)\n", bad ? "FAIL" : "PASS", bad);
}
#endif /* DEMO_ESP32 */

/* ------------------------------------------------------------------ */
/* platform: clock + aligned memory                                    */
/* ------------------------------------------------------------------ */

#ifndef DEMO_ESP32
/* The header calls esp_timer_get_time() for its internal profiler; provide a
 * clock_gettime-backed definition so the demo links on any POSIX host. */
int64_t esp_timer_get_time(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static void *demo_aligned_alloc(size_t align, size_t size)
{
    void *p = NULL;
    if (posix_memalign(&p, align, size) != 0)
        return NULL;
    return p;
}
static void demo_aligned_free(void *p) { free(p); }

#else /* DEMO_ESP32 */

static void *demo_aligned_alloc(size_t align, size_t size)
{
    return heap_caps_aligned_alloc(align, size, MALLOC_CAP_DEFAULT);
}
static void demo_aligned_free(void *p) { heap_caps_aligned_free(p); }

#endif

/* ------------------------------------------------------------------ */
/* platform: worker pool for the encoder's callback-based MT           */
/*                                                                     */
/* The encoder splits MB rows into bands and calls                     */
/* run_func_in_thread(token, job, job_data[], njobs); it expects the   */
/* call to return only after every job has completed.                  */
/* ------------------------------------------------------------------ */

#ifndef DEMO_ESP32

#define DEMO_MAX_SPAWN 7
struct demo_spawn_arg
{
    void (*job)(void *);
    void *data;
};
static void *demo_spawn_tramp(void *p)
{
    struct demo_spawn_arg *a = p;
    a->job(a->data);
    return NULL;
}

static void demo_pool_run(void *token, void (*job)(void *), void *job_data[], int njobs)
{
    (void)token;
    struct demo_spawn_arg sa[DEMO_MAX_SPAWN];
    pthread_t th[DEMO_MAX_SPAWN];
    int spawned = 0;
    for (int i = 1; i < njobs && spawned < DEMO_MAX_SPAWN; i++)
    {
        sa[spawned].job = job;
        sa[spawned].data = job_data[i];
        if (pthread_create(&th[spawned], NULL, demo_spawn_tramp, &sa[spawned]) == 0)
            spawned++;
    }
    job(job_data[0]); /* first job inline */
    for (int i = 0; i < spawned; i++)
        pthread_join(th[i], NULL);
}

#else /* DEMO_ESP32 */

#define DEMO_ESP_WORKERS 1 /* caller handles job 0 -> 2 threads total */
typedef struct
{
    void (*job)(void *);
    void **job_data;
    int njobs, worker_id, nworkers;
    TaskHandle_t main_task;
} demo_esp_slot_t;

static void demo_esp_worker(void *param)
{
    demo_esp_slot_t *s = param;
    for (int i = s->worker_id + 1; i < s->njobs; i += s->nworkers)
        s->job(s->job_data[i]);
    xTaskNotifyGive(s->main_task);
    vTaskDelete(NULL);
}

static void demo_pool_run(void *token, void (*job)(void *), void *job_data[], int njobs)
{
    (void)token;
    static demo_esp_slot_t slots[DEMO_ESP_WORKERS];
    TaskHandle_t th[DEMO_ESP_WORKERS];
    int want = njobs - 1 < DEMO_ESP_WORKERS ? njobs - 1 : DEMO_ESP_WORKERS;
    int spawned = 0;
    for (int i = 0; i < want; i++)
    {
        slots[i].job = job;
        slots[i].job_data = job_data;
        slots[i].njobs = njobs;
        slots[i].worker_id = i;
        slots[i].nworkers = want;
        slots[i].main_task = xTaskGetCurrentTaskHandle();
        if (xTaskCreate(demo_esp_worker, "h264e_w", 16384, &slots[i], 5, &th[i]) != pdPASS)
            break;
        spawned++;
    }
    job(job_data[0]); /* first job inline */
    for (int i = spawned + 1; i < njobs; i++)
        job(job_data[i]); /* shares of workers that failed to spawn */
    for (uint32_t total = 0; total < (uint32_t)spawned;)
        total += ulTaskNotifyTake(pdFALSE, portMAX_DELAY);
}

#endif

/* ------------------------------------------------------------------ */
/* demo configuration + deterministic synthetic clip                   */
/* ------------------------------------------------------------------ */

typedef struct
{
    int width, height;   /* pixels (must be even; ptr/stride need %8) */
    int frames;          /* number of frames to encode                */
    int gop;             /* IDR period                                */
    int threads;         /* encoder bands (1 = serial)                */
    int speed;           /* encode_speed 0..10                        */
    int qp_min, qp_max;
    int target_bytes;    /* desired_frame_bytes                       */
    const char *out_path;
    int ab_mode;         /* run the A/B gate instead of writing a file */
    int no_skip;         /* disable the P-skip phase-2 band            */
} demo_cfg_t;

static void demo_defaults(demo_cfg_t *c)
{
#ifdef DEMO_ESP32
    /* 160x120 keeps persist+scratch within the ~380 KiB internal heap of a
     * PSRAM-less ESP32-S3, and threads=1 (scratch scales with band count)
     * leaves room for the A/B gate's frame store. The 2-band MT showcase
     * lives in the host build (demo/Makefile). */
    c->width = 160;
    c->height = 120;
    c->frames = 60;
    c->threads = 1;
#else
    c->width = 1280;   /* 720p: the owner's upstream-comparison resolution */
    c->height = 720;
    c->frames = 90;
    c->threads = 2;
#endif
    c->gop = 30;
    c->speed = 9;
    c->qp_min = 12;
    c->qp_max = 24;
    c->target_bytes = 0; /* derived from resolution in demo_run() */
    c->out_path = "out.h264";
    c->ab_mode = 0;
    c->no_skip = 0;
}

/* Static gradient + a box travelling diagonally. Integer math only and a
 * pure function of (width, height, frame index) -> bit-identical frames on
 * every run, which is what the A/B gate relies on. During the "frozen"
 * phase the whole image is bit-identical to the previous frame, so the
 * P-skip band losslessly reuses the reference. */
static void demo_gen_yuv(const demo_cfg_t *c, int idx, int frozen,
                         uint8_t *yp, uint8_t *up, uint8_t *vp,
                         int stride_y, int stride_uv)
{
    enum { BOX_W = 48, BOX_H = 32, SPEED = 2 };
    int t = frozen ? c->frames / 3 - 1 : idx;
    int bx = 32 + (t * SPEED) % (c->width - 32 - BOX_W);
    int by = 24 + (t * SPEED / 2) % (c->height - 24 - BOX_H);
    int cbx = bx / 2, cby = by / 2, cbw = BOX_W / 2, cbh = BOX_H / 2;
    int cw = c->width / 2, ch = c->height / 2;

    for (int y = 0; y < c->height; y++)
    {
        uint8_t *row = yp + (size_t)y * stride_y;
        for (int x = 0; x < c->width; x++)
        {
            int in_box = x >= bx && x < bx + BOX_W && y >= by && y < by + BOX_H;
            row[x] = in_box ? (uint8_t)(210 - ((x - bx) >> 3))
                            : (uint8_t)(20 + ((x * 2 + y * 3) >> 4));
        }
    }
    uint8_t wob = (uint8_t)(128 + ((t / 4) % 3) * 6);
    for (int y = 0; y < ch; y++)
        for (int x = 0; x < cw; x++)
        {
            up[(size_t)y * stride_uv + x] = wob;
            vp[(size_t)y * stride_uv + x] = (uint8_t)(160 - (wob - 128));
        }
    for (int y = cby; y < cby + cbh && y < ch; y++)
        for (int x = cbx; x < cbx + cbw && x < cw; x++)
        {
            up[(size_t)y * stride_uv + x] = 180;
            vp[(size_t)y * stride_uv + x] = 90;
        }
}

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

static void demo_fatal(const char *what, int rc)
{
    printf("[error] %s returned %d\n", what, rc);
    exit(1);
}

/* verify Annex-B shape: starts with a 4-byte start code, IDR frames carry
 * SPS(7)/PPS(8), and every frame contains a slice NAL(1/5) */
static int demo_check_annexb(const unsigned char *p, int len, int expect_idr)
{
    static const unsigned char sc[4] = { 0, 0, 0, 1 };
    if (len < 8 || memcmp(p, sc, 4) != 0)
        return -1;
    int saw_sps = 0, saw_pps = 0, saw_slice = 0;
    for (int i = 0; i + 4 <= len; i++)
    {
        if (memcmp(p + i, sc, 4) != 0)
            continue;
        int type = p[i + 4] & 0x1F;
        if (type == 7) saw_sps = 1;
        if (type == 8) saw_pps = 1;
        if (type == 1 || type == 5) saw_slice = 1;
    }
    if (expect_idr && (!saw_sps || !saw_pps))
        return -2;
    if (!saw_slice)
        return -3;
    return 0;
}

static int demo_is_keyframe(const demo_cfg_t *c, int idx)
{
    return idx % c->gop == 0;
}

/* true while the demo is in the frozen/static phase */
static int demo_is_frozen(const demo_cfg_t *c, int idx)
{
    int a = c->frames / 3, b = c->frames * 2 / 3;
    return idx >= a && idx < b;
}

static void demo_apply_skip_band(const demo_cfg_t *c, int idx)
{
    if (!c->no_skip && demo_is_frozen(c, idx))
    {
        int mbrows = (c->height + 15) / 16;
        h264e_skip_y0 = mbrows / 3;
        h264e_skip_y1 = mbrows - mbrows / 3;
    }
    else
    {
        h264e_skip_y0 = 0;
        h264e_skip_y1 = 0;
    }
}

static void demo_print_phase(const demo_cfg_t *c, int idx)
{
    static int last_phase = -1;
    int a = c->frames / 3, b = c->frames * 2 / 3;
    int phase = idx < a ? 1 : (idx < b ? 2 : 3);
    if (phase == last_phase)
        return;
    last_phase = phase;
    if (phase == 1)
        printf("-- phase 1: full motion (frames 0..%d)\n", a - 1);
    else if (phase == 2)
    {
        if (c->no_skip)
            printf("-- phase 2: static content, P-skip DISABLED\n");
        else
        {
            int mbrows = (c->height + 15) / 16;
            printf("-- phase 2: static content + P-skip band [%d..%d) MB rows "
                   "(frames %d..%d)\n",
                   mbrows / 3, mbrows - mbrows / 3, a, b - 1);
        }
    }
    else
        printf("-- phase 3: full motion again (frames %d..%d)\n", b, c->frames - 1);
}

typedef struct
{
    H264E_persist_t *persist;
    H264E_scratch_t *scratch;
    H264E_create_param_t par;
    H264E_run_param_t run;
} demo_enc_t;

/* size + allocate the encoder buffers once; init separately per backend so
 * the A/B gate can reuse the same buffers for both passes (a second alloc
 * after pass 0's frame store fragments the heap) */
static int demo_enc_alloc(demo_enc_t *e, const demo_cfg_t *c)
{
    memset(e, 0, sizeof(*e));
    e->par.width = c->width;
    e->par.height = c->height;
    e->par.gop = c->gop;
    e->par.const_input_flag = 1; /* encoder must not touch our input */
    e->par.max_threads = c->threads;
    e->par.run_func_in_thread = demo_pool_run;
#if H264E_SVC_API
    e->par.num_layers = 1;
#endif

    int szp, szs;
    if (H264E_sizeof(&e->par, &szp, &szs) != H264E_STATUS_SUCCESS)
        demo_fatal("H264E_sizeof", -1);
    printf("[enc] persist %d bytes, scratch %d bytes\n", szp, szs);

    e->persist = demo_aligned_alloc(64, szp);
    e->scratch = demo_aligned_alloc(64, szs);
    if (!e->persist || !e->scratch)
    {
        printf("[error] out of memory (%d + %d bytes)\n", szp, szs);
        return -1;
    }
    return 0;
}

/* (Re-)initialise the encoder for a backend: 0 = SIMD/Xtensa, 1 = plain C.
 * H264E_init memsets and rebuilds the state, so this is safe to call again
 * on the same buffers. On dual-backend builds the backend is selected per
 * init: host via par.enableNEON; ESP32 via H264E_select_backend AFTER init,
 * because init_vft unconditionally resets g_vft to the Xtensa table. */
static void demo_enc_init(demo_enc_t *e, int backend, const demo_cfg_t *c)
{
#if H264E_CONFIGS_COUNT > 1 && !defined(DEMO_ESP32)
    e->par.enableNEON = !backend;
#endif
    if (H264E_init(e->persist, &e->par) != H264E_STATUS_SUCCESS)
        demo_fatal("H264E_init", -1);
#if H264E_CONFIGS_COUNT > 1 && defined(DEMO_ESP32)
    H264E_select_backend(backend); /* 0 = Xtensa ASM, non-0 = plain C */
#endif

    memset(&e->run, 0, sizeof(e->run));
    e->run.encode_speed = c->speed;
    e->run.qp_min = c->qp_min;
    e->run.qp_max = c->qp_max;
    e->run.desired_frame_bytes = c->target_bytes;
    e->run.frame_type = H264E_FRAME_TYPE_DEFAULT;
}

static void demo_enc_destroy(demo_enc_t *e)
{
    demo_aligned_free(e->persist);
    demo_aligned_free(e->scratch);
}

/* base64 line encoder for the ESP32 UART stream dump (off-device viewing) */
static void demo_b64_line(const unsigned char *p, int n, char *out)
{
    static const char t[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int o = 0;
    for (int i = 0; i < n; i += 3)
    {
        int b0 = p[i];
        int b1 = (i + 1 < n) ? p[i + 1] : 0;
        int b2 = (i + 2 < n) ? p[i + 2] : 0;
        out[o++] = t[b0 >> 2];
        out[o++] = t[((b0 & 3) << 4) | (b1 >> 4)];
        out[o++] = (i + 1 < n) ? t[((b1 & 15) << 2) | (b2 >> 6)] : '=';
        out[o++] = (i + 2 < n) ? t[b2 & 63] : '=';
    }
    out[o] = 0;
}

/* ------------------------------------------------------------------ */
/* mode 1: normal run — encode the clip, write Annex-B file            */
/* ------------------------------------------------------------------ */

static int demo_run_normal(const demo_cfg_t *c)
{
    int stride_y = (c->width + 15) & ~15;
    int stride_uv = stride_y / 2;
    size_t ys = (size_t)stride_y * c->height;
    size_t cs = (size_t)stride_uv * (c->height / 2);

    uint8_t *yp = demo_aligned_alloc(64, ys);
    uint8_t *up = demo_aligned_alloc(64, cs);
    uint8_t *vp = demo_aligned_alloc(64, cs);
    if (!yp || !up || !vp)
    {
        printf("[error] out of memory for frame planes\n");
        return 1;
    }

    demo_enc_t e;
    if (demo_enc_alloc(&e, c))
    {
        demo_aligned_free(yp);
        demo_aligned_free(up);
        demo_aligned_free(vp);
        return 1;
    }
    demo_enc_init(&e, 0, c);

#ifndef DEMO_ESP32
    FILE *f = fopen(c->out_path, "wb");
    if (!f)
    {
        printf("[error] cannot open %s for writing\n", c->out_path);
        demo_aligned_free(yp);
        demo_aligned_free(up);
        demo_aligned_free(vp);
        demo_enc_destroy(&e);
        return 1;
    }
#else
    /* no filesystem on device: per-frame stats go to the serial monitor */
    FILE *f = NULL;
#endif

    int64_t total_us = 0;
    size_t total_bytes = 0;
    int bad = 0;
    for (int i = 0; i < c->frames; i++)
    {
        demo_print_phase(c, i);
        demo_apply_skip_band(c, i);
        demo_gen_yuv(c, i, demo_is_frozen(c, i), yp, up, vp, stride_y, stride_uv);

        H264E_io_yuv_t in;
        memset(&in, 0, sizeof(in));
        in.yuv[0] = yp;
        in.yuv[1] = up;
        in.yuv[2] = vp;
        in.stride[0] = stride_y;
        in.stride[1] = in.stride[2] = stride_uv;

        unsigned char *coded;
        int coded_len;
        int64_t t0 = esp_timer_get_time();
        int rc = H264E_encode(e.persist, e.scratch, &e.run, &in, &coded, &coded_len);
        int64_t dt = esp_timer_get_time() - t0;
        total_us += dt;
        if (rc != H264E_STATUS_SUCCESS)
            demo_fatal("H264E_encode", rc);

        int abrc = demo_check_annexb(coded, coded_len, demo_is_keyframe(c, i));
        if (abrc != 0)
        {
            printf("[warn] frame %d: annex-b check failed (%d)\n", i, abrc);
            bad = 1;
        }
        total_bytes += (size_t)coded_len;
        if (f)
            fwrite(coded, 1, (size_t)coded_len, f);
#ifdef DEMO_ESP32
        /* off-device stream dump: base64 over UART — extract with
         * demo/uart_h264_extract.py into a playable Annex-B file */
        {
            static const unsigned char tbl[] =
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            char line[128];
            const unsigned char *pp = coded;
            int left = coded_len;
            printf("[B64 %d %d]\n", i, coded_len);
            while (left > 0)
            {
                int n = left > 72 ? 72 : left;
                int li = 0;
                for (int k = 0; k < n; k += 3)
                {
                    int b0 = pp[k];
                    int b1 = (k + 1 < n) ? pp[k + 1] : 0;
                    int b2 = (k + 2 < n) ? pp[k + 2] : 0;
                    line[li++] = tbl[b0 >> 2];
                    line[li++] = tbl[((b0 & 3) << 4) | (b1 >> 4)];
                    line[li++] = (k + 1 < n) ? tbl[((b1 & 15) << 2) | (b2 >> 6)] : '=';
                    line[li++] = (k + 2 < n) ? tbl[b2 & 63] : '=';
                }
                line[li] = 0;
                printf("%s\n", line);
                pp += n;
                left -= n;
            }
            printf("[/B64]\n");
        }
#endif
        printf("frame %3d (%s) %8d bytes %8.1f ms%s\n", i,
               demo_is_keyframe(c, i) ? "IDR" : "P  ", coded_len,
               (double)dt / 1000.0,
               (!c->no_skip && demo_is_frozen(c, i)) ? "  <- P-skip" : "");
    }

    double secs = (double)total_us / 1e6;
    printf("\n[done] %d frames, %zu bytes, %.2f s (%.1f fps avg)\n",
           c->frames, total_bytes, secs, (double)c->frames / secs);
    if (f)
    {
        fclose(f);
        printf("[done] wrote %s (Annex-B). hint: ffplay %s\n", c->out_path, c->out_path);
    }
    if (bad)
        printf("[warn] annex-b self-check reported problems\n");

    demo_aligned_free(yp);
    demo_aligned_free(up);
    demo_aligned_free(vp);
    demo_enc_destroy(&e);
    return bad;
}

/* ------------------------------------------------------------------ */
/* mode 2: A/B gate — the same frames encoded through both backends,   */
/* then compared byte-for-byte.                                        */
/*                                                                     */
/* g_vft is shared and read at every call, so the comparison runs as   */
/* two sequential passes: pass 0 (re-)inits with the SIMD/Xtensa       */
/* backend and stores every frame; pass 1 re-inits with plain C and    */
/* compares on the fly.                                                */
/*                                                                     */
/* NOTE (host, arm64 -O2): kernel dispatch through VFT function         */
/* pointers is not inlined, and the non-inlined codegen is known to    */
/* produce different (still valid) bitstreams than single-config       */
/* builds — see "Known issues" in demo/README.md. The authoritative   */
/* host gate is `make test` (two single-config binaries + cmp). On     */
/* the ESP32-S3 the VFT build *is* the production configuration, so    */
/* this on-chip gate is the real thing.                                */
/* ------------------------------------------------------------------ */

static const char *demo_simd_name(void)
{
#if H264E_ENABLE_NEON
    return "ARM NEON";
#elif H264E_ENABLE_SSE2
    return "x86 SSE2";
#elif H264E_ENABLE_XTENSA
    return "Xtensa EE ASM";
#else
    return "SIMD";
#endif
}

static int demo_run_ab(const demo_cfg_t *c)
{
#if H264E_CONFIGS_COUNT < 2
    (void)c;
    printf("[ab] this binary has only one backend compiled in.\n"
           "     rebuild with: make ab  (-DH264E_ENABLE_PLAIN_C=1)\n");
    return 1;
#else
    int stride_y = (c->width + 15) & ~15;
    int stride_uv = stride_y / 2;
    size_t cs = (size_t)stride_uv * (c->height / 2);
    uint8_t *yp = demo_aligned_alloc(64, (size_t)stride_y * c->height);
    uint8_t *up = demo_aligned_alloc(64, cs);
    uint8_t *vp = demo_aligned_alloc(64, cs);
    unsigned char **store = calloc((size_t)c->frames, sizeof(*store));
    int *store_len = calloc((size_t)c->frames, sizeof(*store_len));
    if (!yp || !up || !vp || !store || !store_len)
    {
        printf("[error] out of memory for A/B gate buffers\n");
        return 1;
    }

    demo_enc_t e;
    int mismatches = 0;
    int64_t total_us = 0;

    /* one allocation for both passes: re-allocating after pass 0's frame
     * store fragments the heap (fatal on PSRAM-less devices) */
    if (demo_enc_alloc(&e, c))
    {
        for (int i = 0; i < c->frames; i++)
            free(store[i]);
        free(store);
        free(store_len);
        demo_aligned_free(yp);
        demo_aligned_free(up);
        demo_aligned_free(vp);
        return 1;
    }

    printf("[ab] backend A: %s | backend B: plain C\n", demo_simd_name());
    for (int pass = 0; pass < 2; pass++)
    {
        /* buffers are allocated once and re-initialised per pass; destroying
         * inside the loop would leave pass 1 re-initialising freed memory
         * (heap corruption) */
        demo_enc_init(&e, pass, c); /* pass 0 = SIMD/Xtensa, pass 1 = plain C */
        printf("[ab] pass %d/2 (%s): encoding %d frames...\n",
               pass + 1, pass == 0 ? demo_simd_name() : "plain C", c->frames);

        for (int i = 0; i < c->frames; i++)
        {
            /* no P-skip band here: pure backend comparison */
            h264e_skip_y0 = h264e_skip_y1 = 0;
            demo_gen_yuv(c, i, demo_is_frozen(c, i), yp, up, vp, stride_y, stride_uv);

            H264E_io_yuv_t in;
            memset(&in, 0, sizeof(in));
            in.yuv[0] = yp;
            in.yuv[1] = up;
            in.yuv[2] = vp;
            in.stride[0] = stride_y;
            in.stride[1] = in.stride[2] = stride_uv;

            unsigned char *coded;
            int coded_len;
            int64_t t0 = esp_timer_get_time();
            int rc = H264E_encode(e.persist, e.scratch, &e.run, &in, &coded, &coded_len);
            total_us += esp_timer_get_time() - t0;
            if (rc != H264E_STATUS_SUCCESS)
                demo_fatal("H264E_encode", rc);

            if (pass == 0)
            {
                store[i] = malloc((size_t)coded_len);
                if (!store[i])
                {
                    printf("[error] out of memory storing pass-0 frames\n");
                    return 1;
                }
                memcpy(store[i], coded, (size_t)coded_len);
                store_len[i] = coded_len;
            }
            else
            {
                const char *verdict;
                if (coded_len != store_len[i])
                {
                    verdict = "FAIL(len)";
                    mismatches++;
                }
                else
                {
                    size_t off = 0;
                    while (off < (size_t)coded_len && store[i][off] == coded[off])
                        off++;
                    if (off == (size_t)coded_len)
                        verdict = "OK";
                    else
                    {
                        mismatches++;
                        static int first_reported = 0;
                        if (!first_reported)
                        {
                            printf("        first diff at byte %zu: A=0x%02x B=0x%02x\n",
                                   off, store[i][off], coded[off]);
                            first_reported = 1;
                        }
                        verdict = "FAIL";
                    }
                }
                printf("[ab] frame %3d: A=%7d B=%7d %s\n", i,
                       store_len[i], coded_len, verdict);
            }
        }
    }

    printf("\n[gate] %s (%d/%d frames byte-identical, %.2f s)\n",
           mismatches ? "FAIL" : "PASS", c->frames - mismatches, c->frames,
           (double)total_us / 1e6);
#ifndef DEMO_ESP32
    if (mismatches)
        printf("[ab] note: on host VFT builds the indirect-call codegen is\n"
               "     known to diverge from single-config builds (see\n"
               "     demo/README.md). The authoritative host gate is:\n"
               "     make test\n");
#endif

    for (int i = 0; i < c->frames; i++)
        free(store[i]);
    free(store);
    free(store_len);
    demo_enc_destroy(&e);
    demo_aligned_free(yp);
    demo_aligned_free(up);
    demo_aligned_free(vp);
    return mismatches != 0;
#endif
}

/* ------------------------------------------------------------------ */
/* entry points                                                        */
/* ------------------------------------------------------------------ */

#ifndef DEMO_ESP32

static void demo_usage(const char *argv0)
{
    printf("usage: %s [-w W] [-h H] [-n FRAMES] [-g GOP] [-t THREADS] "
           "[-o FILE] [--ab] [--no-skip]\n"
           "  defaults: 1280x720, 90 frames, gop 30, 2 threads, out.h264\n"
           "  --ab      bit-exact gate between the two compiled backends\n"
           "  --no-skip disable the P-skip static-phase band\n",
           argv0);
}

int main(int argc, char **argv)
{
    demo_cfg_t c;
    demo_defaults(&c);
    c.target_bytes = c.width * c.height / 10;

    for (int i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--ab"))
            c.ab_mode = 1;
        else if (!strcmp(argv[i], "--no-skip"))
            c.no_skip = 1;
        else if (!strcmp(argv[i], "-o") && i + 1 < argc)
            c.out_path = argv[++i];
        else if (!strcmp(argv[i], "-w") && i + 1 < argc)
            c.width = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-h") && i + 1 < argc)
            c.height = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-n") && i + 1 < argc)
            c.frames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-g") && i + 1 < argc)
            c.gop = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc)
            c.threads = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--help"))
        {
            demo_usage(argv[0]);
            return 0;
        }
        else
        {
            printf("unknown option: %s\n", argv[i]);
            demo_usage(argv[0]);
            return 1;
        }
    }
    printf("minih264-flash demo: %dx%d @ %d frames, gop %d, threads %d\n",
           c.width, c.height, c.frames, c.gop, c.threads);
    return c.ab_mode ? demo_run_ab(&c) : demo_run_normal(&c);
}

#else /* DEMO_ESP32 */

/* H264E_encode runs band 0 on the *calling* task's stack; the IDF main task
 * ships with a 3.5 KiB stack, far too small for the encoder. Run the demo in
 * a dedicated task with a real stack instead. */
static void demo_entry(void *arg)
{
    (void)arg;
    demo_cfg_t c;
    demo_defaults(&c);
    c.target_bytes = c.width * c.height / 10;

    printf("\n=== minih264-flash ESP32-S3 demo: %dx%d @ %d frames ===\n",
           c.width, c.height, c.frames);

    printf("\n--- normal clip (Annex-B stats go to the serial monitor) ---\n");
    demo_run_normal(&c);

    /* SAD unit check: must run AFTER an encoder init -- the call goes through
     * the vft (g_vft), which is only valid once H264E_init has run */
    demo_sad_selftest();

    printf("\n--- A/B gate: Xtensa EE ASM vs plain C, on-chip ---\n");
    int rc = demo_run_ab(&c);
    printf("\n=== demo %s ===\n", rc == 0 ? "PASSED" : "FAILED");
    vTaskDelete(NULL); /* never return: FreeRTOS aborts a returning task */
}

void app_main(void)
{
    /* EE (SIMD) register file is not saved across context switches:
     * the demo (and any task touching the EE kernels) must be pinned
     * to one core, or a core migration mid-kernel corrupts state. */
    xTaskCreatePinnedToCore(demo_entry, "demo", 16384, NULL, 5, NULL, 0);
}

#endif
