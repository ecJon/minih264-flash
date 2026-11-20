/* simd_probe2.S — 向量指令语义探针·第二轮:单位向量法(2026-11-16)
 * 第一轮结论:vzip.8/vst 有硬件车道置换,手工解码易错;one-hot 让一切可读。
 * 图案(全部零填充 16B):
 *   p1={1,0..}  p2={2,0..}  p3={10,250,0..}  p4={250,10,0..}  x80={128×16}
 * 行定义:
 *   r0  vld→vst 恒等基线
 *   r1/r2 one-hot zip 低/高半落位
 *   r3  vsubs.s8 操作数顺序({1}-{2} → 0xff = dst=第一源-第二源)
 *   r4  vsubs.s8 饱和({10}-{250} 真差 -240 → 0x80=饱和 / 0x10=回绕)
 *   r5  xorq 语义({1}^0x80 → 0x81)
 *   r6  偏置后 vmax.s8 保序({122} vs {-118} → 0x7a)
 *   r7  vsubs.s16(zero, {2}) → 0xfffe 落位
 *   r8-r11 qacc one-hot 点积四变体读出
 *   r12-r15 qacc {250,10} 点积读出(250=0xfa,10=0xa 落位)
 */
    .text
    .align  4
    .global simd_probe2

# void simd_probe2(const uint8_t *p1 /*a2*/, const uint8_t *p2 /*a3*/,
#                  const uint8_t *p3 /*a4*/, const uint8_t *p4 /*a5*/,
#                  const uint8_t *x80 /*a6*/, uint8_t *out /*a7*/)
simd_probe2:
    entry   a1, 32

    # r0: vld→vst 恒等
    ee.vld.128.ip   q0, a2, 16      # q0 = p1
    ee.vst.128.ip   q0, a7, 16      # r0

    # r1/r2: one-hot zip
    ee.zero.q       q7
    ee.vzip.8       q0, q7          # q0 被破坏,后续用内存重载
    ee.vst.128.ip   q0, a7, 16      # r1
    ee.vst.128.ip   q7, a7, 16      # r2

    # r3: vsubs.s8 顺序(p1 - p2)
    ee.vld.128.ip   q0, a2, 16      # 重载 p1
    ee.vld.128.ip   q1, a3, 16      # q1 = p2
    ee.vsubs.s8     q3, q0, q1
    ee.vst.128.ip   q3, a7, 16      # r3

    # r4: vsubs.s8 饱和(p3 - p4 = {10}-{250})
    ee.vld.128.ip   q5, a4, 16      # q5 = p3
    ee.vld.128.ip   q6, a5, 16      # q6 = p4
    ee.vsubs.s8     q3, q5, q6
    ee.vst.128.ip   q3, a7, 16      # r4

    # r5: xorq
    ee.vld.128.ip   q2, a6, 16      # q2 = x80
    ee.xorq         q3, q0, q2
    ee.vst.128.ip   q3, a7, 16      # r5

    # r6: 偏置后 vmax.s8 保序
    ee.xorq         q5, q5, q2      # {10}^80 = {-118}
    ee.xorq         q6, q6, q2      # {250}^80 = {122}
    ee.vmax.s8      q3, q5, q6
    ee.vst.128.ip   q3, a7, 16      # r6 (字节0 应 0x7a)

    # r7: vsubs.s16(zero, {2}) 负向量
    ee.vld.128.ip   q5, a3, 16      # p2 = {2}
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.zero.q       q4
    ee.vsubs.s16    q3, q4, q5
    ee.vst.128.ip   q3, a7, 16      # r7

    # r8-r11: qacc one-hot 点积(qacc += dot(zip(p1), ones16))
    ee.vld.128.ip   q5, a2, 16      # p1
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.vldbc.16     q2, a2          # ones16 = p1 前 2 字节 = int16(1)
    ee.zero.qacc
    ee.vmulas.s16.qacc  q5, q2
    ee.st.qacc_l.l.128.ip a7, 16    # r8
    ee.st.qacc_h.l.128.ip a7, 16    # r9
    ee.st.qacc_l.h.32.ip  a7, 4     # r10
    ee.st.qacc_h.h.32.ip  a7, 4     # r11

    # r12-r15: qacc {250,10} 点积
    ee.zero.qacc
    ee.vld.128.ip   q5, a5, 16      # p4 = {250,10}
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.vmulas.s16.qacc  q5, q2
    ee.st.qacc_l.l.128.ip a7, 16    # r12
    ee.st.qacc_h.l.128.ip a7, 16    # r13
    ee.st.qacc_l.h.32.ip  a7, 4     # r14
    ee.st.qacc_h.h.32.ip  a7, 4     # r15

    retw.n
