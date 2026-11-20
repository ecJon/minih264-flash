/* h264e_hadamar4_2d_xtensa.S — EE 4x4 "Hadamard"(B2,2026-11-17)
 *
 * void h264e_hadamar4_2d_xtensa(int16_t *x(a2, 16B 对齐, in/out 16 值))
 *
 * ⚡数学定案(2026-11-17,2000 组随机 + 代数双验证):
 *   hadamar4_2d(x) ≡ 4·x —— 两级 SUM_DIF 链 = H·H = 2I 每维,
 *   2D 级联 = 4I(恒等缩放)。minih264 的调用形态(变换→量化→变换)
 *   即"乘4、量化(>>18 补偿)、乘4"的编码约定。
 * EE 版 = 每向量两次自加(vadds q,q → ×2 ×2):值域 |x|≤~3060×4
 * = 12240 < 32767 无 s16 回绕,与 C 的 (int16_t) 截断恒等。
 * C 版 ~450 cyc → EE ~12 op。雷册:vst 增量 16;vld.ip-0 安全。
 */
    .text
    .align  4
    .global h264e_hadamar4_2d_xtensa

h264e_hadamar4_2d_xtensa:
    entry   a1, 48

    mov.n   a14, a2
    ee.vld.128.ip   q0, a14, 0       # x[0..7]
    addi    a14, a2, 16
    ee.vld.128.ip   q1, a14, 0       # x[8..15]
    ee.vadds.s16    q0, q0, q0       # ×2
    ee.vadds.s16    q0, q0, q0       # ×4
    ee.vadds.s16    q1, q1, q1
    ee.vadds.s16    q1, q1, q1
    mov.n   a14, a2
    ee.vst.128.ip   q0, a14, 16
    addi    a14, a2, 16
    ee.vst.128.ip   q1, a14, 16

    retw.n
