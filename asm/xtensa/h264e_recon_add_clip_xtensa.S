/* h264e_recon_add_clip_xtensa.S — EE 重建加+clip 内核(M2-k4,2026-11-17)
 *
 * void h264e_recon_add_clip_xtensa(const int16_t *dq, const uint8_t *pred,
 *                                   uint8_t *out, int out_stride)
 *   a2=dq(16B 对齐,int16[16] 行主序), a3=pred(4 对齐,4x4 行距 16),
 *   a4=out(4 对齐), a5=out_stride
 *   C 位一致复刻:out[j*stride+i] = clip_byte(dq[j*4+i] + pred[j*16+i])
 *
 * 流:staging pred(4×4B 行距16 → 帧 16B 连排)→ zip(q0,q7) 零扩展 →
 *   dq s16 直载(q2/q3)→ vadds → vmax(0)/vmin(255) clip →
 *   vunzip.8(q0,q1) 低字节 pack(拼接 32B 偶字节 = 16 像素行主序)→
 *   帧 scratch vst → AR 拆拷 4 行。
 * 值域:|dq|≤~3000(逆变换输出)+pred≤255 → s16 安全;clip 后 ∈[0,255],
 *   低字节 = 值。宿主仿真 300 组随机+边界全 MATCH。
 *
 * ⚠️雷册遵守:vzip.8 只用 (q0,q7) 绿色组合;vst 一律增量 16;
 *   vld.ip 增量 0 安全;EE 访问 16B 对齐(帧内 sp 16 对齐)。
 * vunzip.8(q0,q1) 首次启用(语义=拼接 32B 偶字节;vunzip 系列无雷记录,
 *   xprobe 单测验证)。
 */
    .text
    .align  4
    .global h264e_recon_add_clip_xtensa

h264e_recon_add_clip_xtensa:
    entry   a1, 64                   # predstg[16@0] k255[16@16] out[16@32]

    # ---- staging:pred 4 行(行距 16)----
    mov     a8, a3
    l32i    a13, a8, 0
    s32i    a13, a1, 0
    l32i    a13, a8, 16
    s32i    a13, a1, 4
    l32i    a13, a8, 32
    s32i    a13, a1, 8
    l32i    a13, a8, 48
    s32i    a13, a1, 12

    # ---- k255 向量(0x00FF00FF ×4 word)----
    movi    a13, 255
    slli    a14, a13, 16
    or      a13, a13, a14            # 0x00FF00FF
    s32i    a13, a1, 16
    s32i    a13, a1, 20
    s32i    a13, a1, 24
    s32i    a13, a1, 28

    # ---- 装载 ----
    mov.n   a14, a2
    ee.vld.128.ip   q2, a14, 0       # dq[0..7]
    addi    a14, a2, 16
    ee.vld.128.ip   q3, a14, 0       # dq[8..15]
    mov.n   a14, a1
    ee.vld.128.ip   q0, a14, 0       # predstg
    ee.zero.q       q7
    ee.vzip.8       q0, q7           # q0=[p01], q7=[p23](s16 零扩展)
    addi    a14, a1, 16
    ee.vld.128.ip   q6, a14, 0       # k255
    ee.zero.q       q5               # 0

    # ---- 加 + clip ----
    ee.vadds.s16    q0, q2, q0        # sum01
    ee.vadds.s16    q1, q3, q7        # sum23
    ee.vmax.s16     q0, q0, q5
    ee.vmin.s16     q0, q0, q6
    ee.vmax.s16     q1, q1, q5
    ee.vmin.s16     q1, q1, q6

    # ---- 低字节 pack(vunzip.8 偶字节)----
    ee.vunzip.8     q0, q1            # q0 = 16 像素行主序(q1 = 全 0 丢弃)
    addi    a14, a1, 32
    ee.vst.128.ip   q0, a14, 16

    # ---- AR 拆拷 4 行 ×4B ----
    l32i    a13, a1, 32
    s32i    a13, a4, 0
    l32i    a13, a1, 36
    add     a8, a4, a5
    s32i    a13, a8, 0
    l32i    a13, a1, 40
    add     a9, a8, a5
    s32i    a13, a9, 0
    l32i    a13, a1, 44
    add     a10, a9, a5
    s32i    a13, a10, 0

    retw.n
