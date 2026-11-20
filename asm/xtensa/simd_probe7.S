/* simd_probe7.S — 量化内核语义专测(2026-11-16,M2-k2 AB 失败定位)
 * A 组:负数乘法布局——ramp(5,3,0..) × 广播(-100) → 期望 qacc lane0=-500
 *      (40-bit LE = 0C FE FF FF FF),验证负值 40-bit 落位与段序
 * B 组:s16 直载 lane 映射——16B = {1,-2,3,-4,...} int16 ×2 → vld → vst
 *      原样,验证无 zip 时 lane k = mem word k(1:1)
 * C 组:negind 链——dq = s16seq 复用前 8 个 {-100,100,-1,0,3060,-3060,0,0}
 *      → 期望 negind = {1,0,1,0,1,1,0,0}(s16 lane 直读)
 * 全部 vld.ip 增量 0 + 显式 addi(probe 实证惯用法)。
 */
    .text
    .align  4
    .global simd_probe7

# void simd_probe7(const uint8_t *ramp /*a2 = {5,3,0..}*/,
#                  const int16_t *s16seq /*a3(16 个 int16,前 8 做 dq)*/,
#                  const int16_t *neg100 /*a4*/, const int16_t *ones16 /*a5*/,
#                  uint8_t *out /*a6 ≥ 96B*/)
simd_probe7:
    entry   a1, 32

    /* A 组:负数广播乘(ramp zip 零扩展 × -100) */
    ee.vld.128.ip   q0, a2, 0
    ee.zero.q       q7
    ee.vzip.8       q0, q7
    ee.vldbc.16     q2, a4                  # 广播 -100
    ee.zero.qacc
    ee.vmulas.s16.qacc  q0, q2
    ee.vmulas.s16.qacc  q7, q2
    mov.n   a9, a6
    ee.st.qacc_l.l.128.ip a9, 16           # A[0] out+0..15
    ee.st.qacc_h.l.128.ip a9, 16           # A[1] out+16..31
    ee.st.qacc_l.h.32.ip  a9, 4            # A[2] out+32..35
    ee.st.qacc_h.h.32.ip  a9, 4            # A[3] out+36..39

    /* B 组:s16 直载 1:1 */
    ee.vld.128.ip   q1, a3, 0
    addi    a3, a3, 16
    ee.vld.128.ip   q3, a3, 0
    mov.n   a9, a6
    addi    a9, a9, 48
    ee.vst.128.ip   q1, a9, 16             # B[0] out+48..63
    ee.vst.128.ip   q3, a9, 16             # B[1] out+64..79

    /* C 组:negind 链(dq = s16seq 前 8 个) */
    addi    a3, a3, -32
    ee.vld.128.ip   q0, a3, 0
    ee.zero.q       q2
    ee.vsubs.s16    q5, q2, q0              # -dq
    ee.vmax.s16     q5, q5, q2              # b
    ee.vldbc.16     q4, a5                  # ones=1
    ee.vsubs.s16    q5, q4, q5              # 1-b
    ee.vmin.s16     q5, q5, q2              # ⚠️假说检验:vmax 助记符实为 min?
    ee.vsubs.s16    q5, q4, q5              # negind
    mov.n   a9, a6
    addi    a9, a9, 80
    ee.vst.128.ip   q5, a9, 16             # C[0] out+80..95

    retw.n
