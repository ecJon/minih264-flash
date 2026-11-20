/* simd_probe3.S — 向量指令语义探针·第三轮:qacc 读出专测(2026-11-16)
 * 已确认(probe2):vld→vst 恒等;zip.8(q,zero) 零扩展顺序落位(byte i→lane 2i);
 * vsubs.s8 = 8 位回绕减;xor-0x80 偏置 + vmax.s8 = 无符号序 max;
 * vsubs.s16 顺序落位。
 * 本轮只测 qacc 乘累加 + st.qacc 四变体读出。三组已知和互不相同:
 *   A 组 p1={1,0..}   dot ones → 期望 1
 *   B 组 pa+1 载入(跳过首字节)→ 期望和 = 806(0x326)
 *   C 组 pa 全 16 字节 → 期望和 = 1056(0x420)
 * pa = {250,10,128,127,0,255,200,50,1,2,3,4,5,6,7,8}
 */
    .text
    .align  4
    .global simd_probe3

# void simd_probe3(const uint8_t *p1 /*a2*/, const uint8_t *pa /*a3*/,
#                  uint8_t *out /*a4*/)  + D组:zip 全图案(p3 由 pa 首行 16 字节
#                  递增图案充当——驱动侧 pa2 传入)
simd_probe3:
    entry   a1, 32

    ee.vldbc.16     q2, a2          # ones16 = int16 LE(p1[0..1]) = 1

    # ---- A 组:one-hot dot ones ----
    addi            a5, a2, 0
    ee.vld.128.ip   q5, a5, 16      # p1
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.zero.qacc
    ee.vmulas.s16.qacc  q5, q2
    ee.st.qacc_l.l.128.ip a4, 16    # A[0]
    ee.st.qacc_h.l.128.ip a4, 16    # A[1]
    ee.st.qacc_l.h.32.ip  a4, 4     # A[2]
    ee.st.qacc_h.h.32.ip  a4, 4     # A[3]

    # ---- B 组:pa+1 dot(和 = 806) ----
    addi            a5, a3, 1
    ee.vld.128.ip   q5, a5, 16      # pa[1..16](第 16 字节越界读 1 字节,探针可接受)
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.zero.qacc
    ee.vmulas.s16.qacc  q5, q2
    ee.st.qacc_l.l.128.ip a4, 16    # B[0]
    ee.st.qacc_h.l.128.ip a4, 16    # B[1]
    ee.st.qacc_l.h.32.ip  a4, 4     # B[2]
    ee.st.qacc_h.h.32.ip  a4, 4     # B[3]

    # ---- C 组:pa 全 16 字节 dot(和 = 1056) ----
    addi            a5, a3, 0
    ee.vld.128.ip   q5, a5, 16      # pa
    ee.zero.q       q6
    ee.vzip.8       q5, q6
    ee.zero.qacc
    ee.vmulas.s16.qacc  q5, q2
    ee.st.qacc_l.l.128.ip a4, 16    # C[0]
    ee.st.qacc_h.l.128.ip a4, 16    # C[1]
    ee.st.qacc_l.h.32.ip  a4, 4     # C[2]
    ee.st.qacc_h.h.32.ip  a4, 4     # C[3]

    retw.n
