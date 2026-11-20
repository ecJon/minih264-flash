/* simd_probe4.S — zip.8 完整落位图(2026-11-16,M2-k1 SAD 修复前置)
 * seq={0,1,...,15} 与零 zip → dump 两半,一次得到 16 字节→lane 完整映射。
 * 附加:偏置域(seq^0x80)的 zip 落位(SAD 管线实际形态)。
 * 注意:全部用正向 .ip 加载 + addi 记账(probe1 的负增量加载会扰动落位)。
 */
    .text
    .align  4
    .global simd_probe4

# void simd_probe4(const uint8_t *seq /*a2={0..15}*/,
#                  const uint8_t *x80 /*a3*/, uint8_t *out /*a4*/)
simd_probe4:
    entry   a1, 32

    ee.vld.128.ip   q0, a2, 16      # q0 = {0..15}
    ee.zero.q       q7
    ee.vzip.8       q0, q7
    ee.vst.128.ip   q0, a4, 16      # r0 = zip.lo
    ee.vst.128.ip   q7, a4, 16      # r1 = zip.hi

    # 偏置域落位:addi 回退指针再正向加载
    addi            a2, a2, -16
    ee.vld.128.ip   q1, a2, 16      # q1 = seq(干净重载)
    ee.vld.128.ip   q2, a3, 16      # q2 = 0x80 广播
    ee.xorq         q1, q1, q2      # seq ^ 0x80
    ee.zero.q       q7
    ee.vzip.8       q1, q7
    ee.vst.128.ip   q1, a4, 16      # r2 = 偏置 zip.lo
    ee.vst.128.ip   q7, a4, 16      # r3 = 偏置 zip.hi

    # 16 位链路可解码差:zip(seq 偏置) - zip(seq 原始) = 每 lane -128?+128?
    # (seq-0x80 - seq = -128)——同时验证 vsubs.s16 与 lane 对齐
    addi            a2, a2, -16
    ee.vld.128.ip   q5, a2, 16      # q5 = seq 原始
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.vsubs.s16    q3, q1, q5      # d_lo = 偏置 - 原始(逐 lane -128 → 0xff80)
    ee.vst.128.ip   q3, a4, 16      # r4
    ee.vsubs.s16    q3, q7, q6      # d_hi
    ee.vst.128.ip   q3, a4, 16      # r5

    # ---- r6-r8: vadds/vmax/vsubs.s16 链语义(单位向量)----
    # p1={1,0..} q0 重载;构造 acc={1,0..} 后连加两次 q1={2,0..}
    addi            a2, a2, -16
    ee.vld.128.ip   q5, a2, 16      # q5 = p1 = {1,0..}
    ee.zero.q       q6
    ee.vzip.8       q5, q6          # q5 = {1} s16 零扩展
    addi            a2, a2, -16
    ee.vld.128.ip   q1, a2, 16      # q1 = seq(正向干净重载)
    ee.zero.q       q6
    ee.vzip.8       q1, q6          # q1 = {1}
    ee.vadds.s16    q5, q5, q1      # 1+1=2
    ee.vadds.s16    q5, q5, q1      # 2+1=3
    ee.vst.128.ip   q5, a4, 16      # r6: lane0=3 → 三操作数加;若 6/12 → 叠乘语义

    ee.vmax.s16     q3, q5, q1      # max(3,1)=3
    ee.vst.128.ip   q3, a4, 16      # r7

    ee.vsubs.s16    q3, q1, q5      # 1-3 = -2 → 0xfffe
    ee.vst.128.ip   q3, a4, 16      # r8

    retw.n
