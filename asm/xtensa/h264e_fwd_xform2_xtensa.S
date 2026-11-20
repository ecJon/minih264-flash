/* h264e_fwd_xform2_xtensa.S — EE 前向 4x4x2 变换内核(M2-k3,2026-11-16)
 *
 * void h264e_fwd_xform2_xtensa(const uint8_t *inp, const uint8_t *pred,
 *                              int stride, int16_t *outA, int16_t *outB)
 *   a2=inp, a3=pred, a4=stride, a5=outA, a6=outB(各 int16[16],16B 对齐)
 *   相邻双块(B = A+4)的 FwdTransformResidual4x42 位一致复刻
 *   (TRANSPOSE_BLOCK=1 形态,行主序 out[c+4j])。
 *
 * 数学(v2,行向量+中途转置;v1 二级配 k 维是错的——C 的二级配列维):
 *   行向量 R_k=[A块行k|B块行k](lanes=列); t0=R0+R3 t1=R0-R3
 *   t2=R1+R2 t3=R1-R2; k0=t0+t2 k1=2t1+t3 k2=t0-t2 k3=t1-2t3
 *   [4x4 双块转置 6 步] → V_c(lanes=k)
 *   E0=V0+V3 E1=V0-V3 E2=V1+V2 E3=V1-V2
 *   W0=E0+E2 W1=2E1+E3 W2=E0-E2 W3=E1-2E3 (W_j = 输出行 j)
 * 宿主验证:固定图案 + 200 组随机全 MATCH(与 C 逐值一致)
 * 与 C 逐值一致:中间 |v| ≤ ~9180 ≪ 32767 无 s16 溢出,回绕语义 =
 * C int 算术 + (int16_t) 截断(无溢出时恒等)。
 *
 * ⚠️装载分批法(2026-11-16 真机定案):vzip.8 仅 (q0,q7)/(q1,q6) 等
 * 特定组合实测可用,q2 作为 zip 操作数触发 debug exception(probe9 E
 * 组二分实录)——4 次 zip 不可行。改为:inp 两次 zip(绿色组合)→
 * vst 暂存 obuf → pred 两次 zip → inp 行向量以 s16 直载(vld,量化
 * 内核已验证)从 obuf 读回。全程只用已验证原语。
 * ⚠️vst.128.ip 增量 0 = 雷(Cache error,probe9 实录)——store 一律
 * 增量 16;vld.ip 增量 0 安全(esp-nn 惯用法)。
 *
 * 帧布局(sp 16 对齐):ibuf[32@0] pbuf[32@32] obuf[64@64] nbuf[64@128]
 * 语义依据(simd_probe2..9 真机实证);inp/pred 4 对齐,outA/B 16 对齐。
 */
    .text
    .align  4
    .global h264e_fwd_xform2_xtensa

h264e_fwd_xform2_xtensa:
    entry   a1, 208

    # ============ staging:4 行 × (inp A/B + pred A/B) ============
    mov     a8, a2                   # inp 行游标
    mov     a9, a3                   # pred 行游标(行距恒 16)
    mov     a10, a4                  # inp 行距(运行时)

    l32i    a13, a8, 0               # 行 0
    s32i    a13, a1, 0
    l32i    a13, a8, 4
    s32i    a13, a1, 4
    l32i    a13, a9, 0
    s32i    a13, a1, 32
    l32i    a13, a9, 4
    s32i    a13, a1, 36
    add     a8, a8, a10
    addi    a9, a9, 16

    l32i    a13, a8, 0               # 行 1
    s32i    a13, a1, 8
    l32i    a13, a8, 4
    s32i    a13, a1, 12
    l32i    a13, a9, 0
    s32i    a13, a1, 40
    l32i    a13, a9, 4
    s32i    a13, a1, 44
    add     a8, a8, a10
    addi    a9, a9, 16

    l32i    a13, a8, 0               # 行 2
    s32i    a13, a1, 16
    l32i    a13, a8, 4
    s32i    a13, a1, 20
    l32i    a13, a9, 0
    s32i    a13, a1, 48
    l32i    a13, a9, 4
    s32i    a13, a1, 52
    add     a8, a8, a10
    addi    a9, a9, 16

    l32i    a13, a8, 0               # 行 3
    s32i    a13, a1, 24
    l32i    a13, a8, 4
    s32i    a13, a1, 28
    l32i    a13, a9, 0
    s32i    a13, a1, 56
    l32i    a13, a9, 4
    s32i    a13, a1, 60

    # ============ 批 1:inp 行向量(zip 绿色组合 ×2 → obuf) ============
    mov.n   a14, a1
    ee.vld.128.ip   q0, a14, 0       # ibuf 行 0,1
    ee.zero.q       q7
    ee.vzip.8       q0, q7           # q0=r0, q7=r1
    addi    a14, a1, 16
    ee.vld.128.ip   q1, a14, 0       # ibuf 行 2,3
    ee.zero.q       q6
    ee.vzip.8       q1, q6           # q1=r2, q6=r3
    addi    a14, a1, 64
    ee.vst.128.ip   q0, a14, 16      # obuf+0  = r0
    addi    a14, a1, 80
    ee.vst.128.ip   q7, a14, 16      # obuf+16 = r1
    addi    a14, a1, 96
    ee.vst.128.ip   q1, a14, 16      # obuf+32 = r2
    addi    a14, a1, 112
    ee.vst.128.ip   q6, a14, 16      # obuf+48 = r3

    # ============ 批 2:pred 行向量(zip 绿色组合 ×2) ============
    addi    a14, a1, 32
    ee.vld.128.ip   q0, a14, 0       # pbuf 行 0,1
    ee.zero.q       q7
    ee.vzip.8       q0, q7           # q0=p0, q7=p1
    addi    a14, a1, 48
    ee.vld.128.ip   q1, a14, 0       # pbuf 行 2,3
    ee.zero.q       q6
    ee.vzip.8       q1, q6           # q1=p2, q6=p3

    # ============ inp 行向量 s16 直载回(q2..q5) ============
    addi    a14, a1, 64
    ee.vld.128.ip   q2, a14, 0       # q2=r0
    addi    a14, a1, 80
    ee.vld.128.ip   q3, a14, 0       # q3=r1
    addi    a14, a1, 96
    ee.vld.128.ip   q4, a14, 0       # q4=r2
    addi    a14, a1, 112
    ee.vld.128.ip   q5, a14, 0       # q5=r3

    # ============ 残差 + 列蝶形(t) ============
    ee.vsubs.s16    q2, q2, q0       # R0
    ee.vsubs.s16    q3, q3, q7       # R1
    ee.vsubs.s16    q4, q4, q1       # R2
    ee.vsubs.s16    q5, q5, q6       # R3
    ee.vadds.s16    q0, q2, q5       # t0
    ee.vsubs.s16    q1, q2, q5       # t1
    ee.vadds.s16    q6, q3, q4       # t2
    ee.vsubs.s16    q7, q3, q4       # t3

    # ============ C 矩阵(k) ============
    ee.vadds.s16    q2, q0, q6       # k0 = t0+t2
    ee.vsubs.s16    q3, q0, q6       # k2 = t0-t2
    ee.vadds.s16    q4, q1, q1       # 2t1
    ee.vadds.s16    q4, q4, q7       # k1 = 2t1+t3
    ee.vsubs.s16    q5, q1, q7       # t1-t3
    ee.vsubs.s16    q5, q5, q7       # k3 = t1-2t3

    # ============ 4x4 双块转置(BFS 6 步;宿主 200 组随机位一致验证) ============
    # (K0,K1,K2,K3)=(q2,q4,q3,q5) → (V0,V1,V2,V3)=(q2,q4,q3,q5)
    ee.vunzip.16    q2, q4
    ee.vunzip.16    q3, q5
    ee.vunzip.32    q2, q3
    ee.vunzip.16    q2, q3
    ee.vunzip.32    q4, q5
    ee.vunzip.16    q4, q5

    # ============ 第二级(列方向配对,向量组合) → out 行向量 ============
    ee.vadds.s16    q0, q2, q5       # E0 = V0+V3
    ee.vsubs.s16    q1, q2, q5       # E1
    ee.vadds.s16    q6, q4, q3       # E2 = V1+V2
    ee.vsubs.s16    q7, q4, q3       # E3
    ee.vadds.s16    q2, q0, q6       # W0 = E0+E2 → [A行0|B行0]
    ee.vsubs.s16    q3, q0, q6       # W2 = E0-E2 → [A行2|B行2]
    ee.vadds.s16    q4, q1, q1       # 2E1
    ee.vadds.s16    q4, q4, q7       # W1        → [A行1|B行1]
    ee.vsubs.s16    q5, q1, q7       # E1-E3
    ee.vsubs.s16    q5, q5, q7       # W3        → [A行3|B行3]

    # ============ 存储:nbuf vst + AR 拆拷 ============
    addi    a14, a1, 128
    ee.vst.128.ip   q2, a14, 16      # nbuf+0  = out0
    addi    a14, a1, 144
    ee.vst.128.ip   q4, a14, 16      # nbuf+16 = out1
    addi    a14, a1, 160
    ee.vst.128.ip   q3, a14, 16      # nbuf+32 = out2
    addi    a14, a1, 176
    ee.vst.128.ip   q5, a14, 16      # nbuf+48 = out3(帧 208 容纳 176+16)
    nop                              # EE store → CPU load 同步(时序冒险修复)

    # A 块:行 j 8B 在 nbuf+16j → outA+8j
    l32i    a13, a1, 128
    s32i    a13, a5, 0
    l32i    a13, a1, 132
    s32i    a13, a5, 4
    l32i    a13, a1, 144
    s32i    a13, a5, 8
    l32i    a13, a1, 148
    s32i    a13, a5, 12
    l32i    a13, a1, 160
    s32i    a13, a5, 16
    l32i    a13, a1, 164
    s32i    a13, a5, 20
    l32i    a13, a1, 176
    s32i    a13, a5, 24
    l32i    a13, a1, 180
    s32i    a13, a5, 28

    # B 块:行 j 8B 在 nbuf+16j+8 → outB+8j
    l32i    a13, a1, 136
    s32i    a13, a6, 0
    l32i    a13, a1, 140
    s32i    a13, a6, 4
    l32i    a13, a1, 152
    s32i    a13, a6, 8
    l32i    a13, a1, 156
    s32i    a13, a6, 12
    l32i    a13, a1, 168
    s32i    a13, a6, 16
    l32i    a13, a1, 172
    s32i    a13, a6, 20
    l32i    a13, a1, 184
    s32i    a13, a6, 24
    l32i    a13, a1, 188
    s32i    a13, a6, 28

    retw.n
