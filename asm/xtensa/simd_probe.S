/* simd_probe.S — S3 向量指令语义探针(压榨项目 M2 前置,2026-11-16)
 * 真芯片上钉死 TRM 悬案:
 *   c1  ee.vsubs.s8 对无符号字节的饱和行为(signed 饱和破坏范围)
 *   c2/c3 ee.vzip.8 零扩展的精确落位(低/高半各落哪个 q)
 *   c4/c5 ee.vsubs.s16 16 位域相减
 *   c6/c7 ee.vmax/vmin.s8 对未偏置字节的 signed 行为
 *   c8-c11 qacc 乘累加 + st.qacc 四变体读出
 * 语法均抄自 esp-nn 实编译代码。C 侧(video_enc.c VENC_BENCH)hexdump 对照。
 */
    .text
    .align  4
    .global simd_probe

# void simd_probe(const uint8_t *pa /*a2*/, const uint8_t *pb /*a3*/,
#                 const uint8_t *ones /*a4*/, uint8_t *out /*a5*/)
simd_probe:
    entry   a1, 32

    ee.vld.128.ip   q0, a2, 16      # q0 = pa
    ee.vld.128.ip   q1, a3, 16      # q1 = pb
    ee.vldbc.16     q2, a4          # q2 = 广播 int16(=1)
    ee.zero.q       q6

    # ---- c1: vsubs.s8(pa - pb) 饱和语义 ----
    ee.vsubs.s8     q3, q0, q1
    ee.vst.128.ip   q3, a5, 16      # out[0]

    # ---- c2/c3: vzip.8(pa, 0) 零扩展布局 ----
    addi            a2, a2, -16     # 回退重载 pa
    ee.vld.128.ip   q4, a2, 16
    ee.zero.q       q7
    ee.vzip.8       q4, q7          # 成对变换:低半/高半落位待观察
    ee.vst.128.ip   q4, a5, 16      # out[1] zip 后 q4
    ee.vst.128.ip   q7, a5, 16      # out[2] zip 后 q7

    # ---- c4/c5: 16 位域相减(pa 扩展 - pb 扩展) ----
    addi            a3, a3, -16     # 重载 pb
    ee.vld.128.ip   q5, a3, 16
    ee.zero.q       q6
    ee.vzip.8       q5, q6          # wb = (q5 低, q6 高)
    ee.vsubs.s16    q3, q4, q5
    ee.vst.128.ip   q3, a5, 16      # out[3] 低 8 通道
    ee.vsubs.s16    q3, q7, q6
    ee.vst.128.ip   q3, a5, 16      # out[4] 高 8 通道

    # ---- c6/c7: vmax/vmin.s8(q0/q1 仍为原始 pa/pb) ----
    ee.vmax.s8      q3, q0, q1
    ee.vst.128.ip   q3, a5, 16      # out[5]
    ee.vmin.s8      q3, q0, q1
    ee.vst.128.ip   q3, a5, 16      # out[6]

    # ---- c8-c11: qacc 乘累加 sum(pa_i * 1) 与四种读出 ----
    ee.zero.qacc
    ee.vmulas.s16.qacc  q4, q2      # 低 8 通道
    ee.vmulas.s16.qacc  q7, q2      # 高 8 通道
    ee.st.qacc_l.l.128.ip a5, 16    # out[7]
    ee.st.qacc_h.l.128.ip a5, 16    # out[8]
    ee.st.qacc_l.h.32.ip  a5, 4     # out[9]  (4B)
    ee.st.qacc_h.h.32.ip  a5, 4     # out[10] (4B)

    retw.n
