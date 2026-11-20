/* h264e_is_zero16_xtensa.S — EE 零块预判内核(B1 v2,2026-11-17)
 *
 * int h264e_is_zero16_xtensa(const int16_t *dat(a2,16B对齐),
 *                            const int16_t *thrA(a3,16B对齐),
 *                            const int16_t *thrB(a4,16B对齐))
 *   返回 1 = 16 个系数全部 |dat[i]| ≤ thr[i&7]
 *   thrA = 系数 0..7 的阈值向量(i0=1 时 lane0 已置 32767)
 *   thrB = 系数 8..15 的阈值向量(图案与 A 相同,恒为 v)
 *
 * v2 修正(v1 负 4ms 实测):C 版有超标早退优势 → v1 每块两次调用
 * (开销 2×15cyc)+全量运算不占优。v2 合并 16 系数单次调用摊薄开销。
 * 语义推导同 v1:thr ∈ [0,~4745],|dq| ≤ ~3060,无 s16 回绕;
 * t = max(|d|-thr, 0),t==0 ⟺ 全零;正 s16 非零 ⟺ dump 字非零。
 * 雷册:vst 增量 16;vld.ip-0 安全;返回 callee-a2。
 */
    .text
    .align  4
    .global h264e_is_zero16_xtensa

h264e_is_zero16_xtensa:
    entry   a1, 32

    # ---- 第一半(dat[0..7], thrA) ----
    mov.n   a14, a2
    ee.vld.128.ip   q0, a14, 0
    mov.n   a14, a3
    ee.vld.128.ip   q1, a14, 0
    ee.zero.q       q2
    ee.vsubs.s16    q3, q2, q0       # -d
    ee.vmax.s16     q0, q0, q3       # |d|
    ee.vsubs.s16    q1, q1, q0       # thrA-|d|
    ee.vsubs.s16    q3, q0, q1       # |d|-thr
    ee.vmax.s16     q3, q3, q2       # t = max(|d|-thr,0)
    mov.n   a14, a1
    ee.vst.128.ip   q3, a14, 16      # dump[0..15]

    # ---- 第二半(dat[8..15], thrB) ----
    addi    a14, a2, 16
    ee.vld.128.ip   q0, a14, 0
    mov.n   a14, a4
    ee.vld.128.ip   q1, a14, 0
    ee.zero.q       q2
    ee.vsubs.s16    q3, q2, q0
    ee.vmax.s16     q0, q0, q3
    ee.vsubs.s16    q1, q1, q0
    ee.vsubs.s16    q3, q0, q1
    ee.vmax.s16     q3, q3, q2
    mov.n   a14, a1
    ee.vst.128.ip   q3, a14, 16      # dump[16..31] 覆盖前半(已消费)

    l32i    a6, a1, 0
    l32i    a7, a1, 4
    or      a6, a6, a7
    l32i    a7, a1, 8
    or      a6, a6, a7
    l32i    a7, a1, 12
    or      a6, a6, a7
    movi    a2, 1
    beqz    a6, 1f
    movi    a2, 0
1:  retw.n
