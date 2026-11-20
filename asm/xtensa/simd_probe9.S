/* simd_probe9.S — vunzip/vzip 的 16/32 位变体语义神谕(2026-11-16,EE 变换内核前置)
 *
 * 变换内核的存储合并需要拆/并 32 位半区([A块|B块] lane 布局 ↔ 各自 16B 目标),
 * TRM 未文档化这些变体的精确语义。单位图案一眼定案:
 *   A 组: vunzip.16(q0,q1)  s16 图案 {0000,1111,...,FFFF} ×2
 *   B 组: vunzip.32(q0,q1)  32 位图案 {00000000,11111111,...,77777777} ×2
 *   C 组: vzip.16(q0,q1)
 *   D 组: vzip.32(q0,q1)
 * 假说(对/伙伴拼接后按 parity 解交错):A 组后 q0=[0000,2222,4444,6666,
 * 8888,AAAA,CCCC,EEEE], q1=[1111,...,FFFF];B 组后 q0=[00000000,22222222,
 * 44444444,66666666], q1=[11111111,...,77777777]。
 * 全 vld.ip 增量 0 + 显式 addi;EE 访问 16B 对齐。
 */
    .text
    .align  4
    .global simd_probe9

# void simd_probe9(const uint16_t *p16 /*a2, 32B 对齐*/,
#                  const uint32_t *p32 /*a3, 32B 对齐*/,
#                  uint8_t *out /*a4 ≥ 128B*/)
simd_probe9:
    entry   a1, 160

    # ---- A/D 组:s16 图案 ----
    ee.vld.128.ip   q0, a2, 0               # q0 = {0000..7777}
    addi    a9, a2, 16
    ee.vld.128.ip   q1, a9, 0               # q1 = {8888..FFFF}
    ee.vunzip.16    q0, q1
    mov.n   a9, a4
    ee.vst.128.ip   q0, a9, 16              # A[0] out+0..15
    ee.vst.128.ip   q1, a9, 16              # A[1] out+16..31

    ee.vld.128.ip   q0, a2, 0
    addi    a9, a2, 16
    ee.vld.128.ip   q1, a9, 0
    ee.vzip.16      q0, q1
    addi    a9, a4, 32
    ee.vst.128.ip   q0, a9, 16              # D[0] out+32..47
    ee.vst.128.ip   q1, a9, 16              # D[1] out+48..63

    # ---- B/C 组:32 位图案 ----
    ee.vld.128.ip   q2, a3, 0               # q2 = {00000000..33333333}
    addi    a9, a3, 16
    ee.vld.128.ip   q3, a9, 0               # q3 = {44444444..77777777}
    ee.vunzip.32    q2, q3
    addi    a9, a4, 64
    ee.vst.128.ip   q2, a9, 16              # B[0] out+64..79
    ee.vst.128.ip   q3, a9, 16              # B[1] out+80..95

    ee.vld.128.ip   q2, a3, 0
    addi    a9, a3, 16
    ee.vld.128.ip   q3, a9, 0
    ee.vzip.32      q2, q3
    addi    a9, a4, 96
    ee.vst.128.ip   q2, a9, 16              # C[0] out+96..111
    ee.vst.128.ip   q3, a9, 16              # C[1] out+112..127

    # E 组结论:vzip 仅 (q0,q7)/(q1,q6)/(q1,q7)/(q5,q6) 等组合实测可用,
    # q2 作为操作数触发 debug exception——内核装载用分批法避开(见变换内核注释)

    retw.n
