/* simd_probe6.S — qacc 乘累加读出布局专测(2026-11-16,M2-k2 tsqd 前置)
 * A 组:ramp {0..15} × ones16 → qacc 累加和(理论 120)
 * B 组:ramp ×10 图案 {0,10,..,150} × ones16 → 和 1200(测位宽)
 * 每组 dump qacc_l.l.128 / qacc_h.l.128 / qacc_l.h.32 / qacc_h.h.32
 */
    .text
    .align  4
    .global simd_probe6

# void simd_probe6(const uint8_t *ramp /*a2={0..15}*/,
#                  const uint8_t *rampx10 /*a3={0,10,..,150}*/,
#                  const uint8_t *ones /*a4={1,0}*/, uint8_t *out /*a5 64B*/)
simd_probe6:
    entry   a1, 32

    ee.vldbc.16     q2, a4          # q2 = 广播 int16(a4[0..1])=100

    # ---- A 组 ----
    ee.vld.128.ip   q0, a2, 16      # ramp={5,3,0,...} → lane0=5×100=500, lane1=3×100=300
    ee.zero.q       q7
    ee.vzip.8       q0, q7
    ee.zero.qacc
    ee.vmulas.s16.qacc  q0, q2
    ee.vmulas.s16.qacc  q7, q2
    mov.n   a14, a5                 # a14 从 out+0 递进,四 store 各占一段
    ee.st.qacc_l.l.128.ip a14, 16   # A[0] out+0..15
    ee.st.qacc_h.l.128.ip a14, 16   # A[1] out+16..31
    ee.st.qacc_l.h.32.ip  a14, 4    # A[2] out+32..35
    ee.st.qacc_h.h.32.ip  a14, 4    # A[3] out+36..39

    # ---- B 组 ----
    ee.vld.128.ip   q0, a3, 16      # rampx10
    ee.zero.q       q7
    ee.vzip.8       q0, q7
    ee.zero.qacc
    ee.vmulas.s16.qacc  q0, q2
    ee.vmulas.s16.qacc  q7, q2
    mov.n   a14, a5
    addi    a14, a14, 48
    ee.st.qacc_l.l.128.ip a14, 16   # B[0] out+48..63
    ee.st.qacc_h.l.128.ip a14, 16   # B[1] out+64..79
    ee.st.qacc_l.h.32.ip  a14, 4    # B[2] out+80..83
    ee.st.qacc_h.h.32.ip  a14, 4    # B[3] out+84..87

    retw.n
