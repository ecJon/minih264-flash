/* h264e_quant_block16_xtensa.S — EE 量化内核(M2-k2,2026-11-16)
 *
 * void h264e_quant_block16_xtensa(int16_t *dq, int16_t *qv,
 *                                 const uint8_t *tbl, uint8_t *dump,
 *                                 int i0, int *nzp)
 *   a2=dq(16B 对齐,in:残差,out:反量化), a3=qv(out), a4=tbl(16B 对齐,96B),
 *   a5=dump(≥48B,16B 对齐,两半共用), a6=i0(1=lane0 不计 nz), a7=nzp(out)
 *
 * minih264e.h quantize() 单 4x4 块逐值等价(位一致目标):
 *   v  = (dq*qdat_mul + round + (dq<0 ? 0xFFFF-2*round : 0)) >> 16
 *   qv[i] = (int16)v;  dq[i] = (int16)(v*qdat_deq);  块 nz = 任一 v≠0
 * round = qdat[6] ≤ 30550(s16 正域);⚠️delta=0xFFFF-2*round 低 qp 达 58697
 * 超 s16 → seed 拆三项累加:round + negind*32767 + negind*(32768-2*round)
 * (bvec=32768-2r ∈ [-28332,25930] 全 qp s16 安全,已验算)。
 * negind ∈ {0,1} 全用已证原语:vsubs/vmax.s16(qp 域 dq∈[-4080,4080],1-b 无溢出)。
 * 值域已验:quant≤26214,deq≤3328,|v|≤1633 → 乘积+种子 ≤2^28,qacc 40-bit 充裕。
 *
 * 提取关键简化:v ∈ [-1633,1633] ⇒ v≠0 ⟺ v 低 16 位≠0;且 qv 存储(截 16 位)、
 * MULL(mod 2^16 等价)、nz(低16 判零)三个消费者全都只看低 16 位 →
 * 每个 lane 只需精确取出 v_low16(一条 extui/srli),不拼接 24 位:
 *   lane k v_low16 = acc bytes(5k+2,5k+3) 所在字场的合法 EXTUI/SRLI:
 *   L0 srli(w0,16)  L1 extui(w2,0,16)  L2 extui(w3,0,16)  L3 extui(w4,8,16)
 *   L4 srli(w5,16)  L5 extui(w7,0,16)  L6 extui(w8,0,16)  L7 extui(w9,8,16)
 * nz 补充位:L1 byte7=srli(w1,24),L5 byte27=srli(w6,24)。
 * EXTUI 位宽 ≤16(ISA 上限);无 l32ui 助记符(= l32i)。
 *
 * tbl 布局(C 侧缓存,按 qdat[0..7] 快照失效重建,基址 16B 对齐):
 *   +0  mulvec  {m0,m2,m0,m2,m2,m4,m2,m4}   两半图案相同(行 2,3 = 行 0,1)
 *   +16 roundvec 广播 qdat[6]
 *   +32 bvec    广播 (u16)(int16)(32768-2*qdat[6])
 *   +48 k32767  广播 32767
 *   +64 ones    广播 1
 *   +80 deqvec  {d1,d3,d1,d3,d3,d5,d3,d5}   l16ui 偏移 80..94
 *
 * qacc 读出(2026-11-16 标记向量实证,推翻 probe6 的连续流假设):
 * 四段各自 lane 对齐——l.l.128 = lane0,1,2+lane3.b0;h.l.128 = lane4,5,6+
 * lane7.b0;l.h.32 = lane3.b1-4;h.h.32 = lane7.b1-4。
 * 语义依据(simd_probe2..6 真机实证):vld.ip 增量必须 0;vsubs/vmax.s16 顺序
 * 三操作数;vmulas.s16.qacc 可多次累加;st.qacc 四段 40B;EE 访问 16B 对齐。
 */
    .text
    .align  4
    .global h264e_quant_block16_xtensa

/* 宏:当前 qacc → dump 40B → 8 lane 提取 + qv/dq 存储 + nz 累加
 * 入:a4=tbl a5=dump a13=nz累加器(跨宏保持) a6=i0(仅影响 lane0)
 * 出:a13 累加;a9-a15 全破坏
 *
 * ⚠️真机实证段结构(2026-11-16 标记向量实验,两轮 dump 交叉验证):
 * 四个 store 段各自对齐 lane 边界,不是连续 320-bit 流!
 *   seg1 qacc_l.l.128 @ b0-15  = lane0,1,2 完整 + lane3.byte0
 *   seg2 qacc_h.l.128 @ b16-31 = lane4,5,6 完整 + lane7.byte0
 *   seg3 qacc_l.h.32  @ b32-35 = lane3.byte1-4
 *   seg4 qacc_h.h.32  @ b36-39 = lane7.byte1-4
 * 各 v 低 16 位地址:v0=b2,3 | v1=b7,8 | v2=b12,13 | v3=b33,34 |
 *                 v4=b18,19 | v5=b23,24 | v6=b28,29 | v7=b37,38
 * (EXTUI 位宽 ≤16;无 l32ui 助记符;vld.ip 增量必须 0)
 */
.macro QDUMP8
    mov.n   a9, a5                          # dump 基址副本(四段推进)
    ee.st.qacc_l.l.128.ip a9, 16            # b0-15
    ee.st.qacc_h.l.128.ip a9, 16            # b16-31
    ee.st.qacc_l.h.32.ip  a9, 4             # b32-35
    ee.st.qacc_h.h.32.ip  a9, 4             # b36-39
    # ---- L0: v_lo = srli(w0,16)(b2,3);w0 @ 0 ----
    l32i    a10, a5, 0
    srli    a9, a10, 16
    bnez    a6, 1f                          # i0=1 → lane0 不计 nz
    or      a13, a13, a9
1:  s16i    a9, a3, 0
    l16ui   a10, a4, 80
    mull    a9, a9, a10
    s16i    a9, a2, 0
    # ---- L1: v_lo = b7|b8<<8;w4 @ 4, w8 @ 8 ----
    l32i    a11, a5, 4
    l32i    a12, a5, 8
    srli    a9, a11, 24
    extui   a14, a12, 0, 8
    slli    a14, a14, 8
    or      a9, a9, a14
    or      a13, a13, a9
    s16i    a9, a3, 2
    l16ui   a10, a4, 82
    mull    a9, a9, a10
    s16i    a9, a2, 2
    # ---- L2: v_lo = extui(w12,0,16)(b12,13) ----
    l32i    a11, a5, 12
    extui   a9, a11, 0, 16
    or      a13, a13, a9
    s16i    a9, a3, 4
    l16ui   a10, a4, 84
    mull    a9, a9, a10
    s16i    a9, a2, 4
    # ---- L3: v_lo = extui(w32,8,16)(b33,34);lane3 高段在 seg3! ----
    l32i    a12, a5, 32
    extui   a9, a12, 8, 16
    or      a13, a13, a9
    s16i    a9, a3, 6
    l16ui   a10, a4, 86
    mull    a9, a9, a10
    s16i    a9, a2, 6
    # ---- L4: v_lo = srli(w16,16)(b18,19);seg2 起点 ----
    l32i    a11, a5, 16
    srli    a9, a11, 16
    or      a13, a13, a9
    s16i    a9, a3, 8
    l16ui   a10, a4, 88
    mull    a9, a9, a10
    s16i    a9, a2, 8
    # ---- L5: v_lo = b23|b24<<8;w20 @ 20, w24 @ 24 ----
    l32i    a12, a5, 20
    l32i    a15, a5, 24
    srli    a9, a12, 24
    extui   a14, a15, 0, 8
    slli    a14, a14, 8
    or      a9, a9, a14
    or      a13, a13, a9
    s16i    a9, a3, 10
    l16ui   a10, a4, 90
    mull    a9, a9, a10
    s16i    a9, a2, 10
    # ---- L6: v_lo = extui(w28,0,16)(b28,29) ----
    l32i    a11, a5, 28
    extui   a9, a11, 0, 16
    or      a13, a13, a9
    s16i    a9, a3, 12
    l16ui   a10, a4, 92
    mull    a9, a9, a10
    s16i    a9, a2, 12
    # ---- L7: v_lo = extui(w36,8,16)(b37,38);lane7 高段在 seg4! ----
    l32i    a12, a5, 36
    extui   a9, a12, 8, 16
    or      a13, a13, a9
    s16i    a9, a3, 14
    l16ui   a10, a4, 94
    mull    a9, a9, a10
    s16i    a9, a2, 14
.endm

h264e_quant_block16_xtensa:
    entry   a1, 32

    # ============ 前半:系数 0-7 ============
    ee.vld.128.ip   q0, a2, 0               # dq[0..7](s16 lane 直载)
    ee.zero.q       q2
    ee.vsubs.s16    q3, q2, q0              # -dq
    ee.vmax.s16     q3, q3, q2              # b = |dq|(负)/0(正或零)
    addi    a9, a4, 64
    ee.vld.128.ip   q5, a9, 0               # ones
    ee.vsubs.s16    q3, q5, q3              # 1-b
    ee.vmax.s16     q3, q3, q2
    ee.vsubs.s16    q3, q5, q3              # negind ∈ {0,1}
    addi    a9, a4, 16
    ee.vld.128.ip   q6, a9, 0               # roundvec
    addi    a9, a4, 48
    ee.vld.128.ip   q7, a9, 0               # k32767
    ee.vld.128.ip   q4, a4, 0               # mulvec
    ee.zero.qacc
    ee.vmulas.s16.qacc q0, q4               # dq*mul
    ee.vmulas.s16.qacc q6, q5               # +round×ones(q5 仍=ones)
    ee.vmulas.s16.qacc q3, q7               # +negind×32767
    addi    a9, a4, 32
    ee.vld.128.ip   q5, a9, 0               # bvec(q5 释放 ones 后再载)
    ee.vmulas.s16.qacc q3, q5               # +negind×bvec
    movi    a13, 0                          # nz 累加器清零
    QDUMP8                                  # 前半提取/存储(a6=i0 生效于 lane0)

    # ============ 后半:系数 8-15 ============
    movi    a6, 0                           # 后半全 lane 计 nz
    addi    a8, a2, 16
    ee.vld.128.ip   q0, a8, 0               # dq[8..15](a2 推进前读)
    addi    a2, a2, 16                      # dq 写游标
    addi    a3, a3, 16                      # qv 写游标
    ee.zero.q       q2
    ee.vsubs.s16    q3, q2, q0
    ee.vmax.s16     q3, q3, q2
    addi    a9, a4, 64
    ee.vld.128.ip   q5, a9, 0               # ones(q5 已被 bvec 占用)
    ee.vsubs.s16    q3, q5, q3
    ee.vmax.s16     q3, q3, q2
    ee.vsubs.s16    q3, q5, q3              # negind
    ee.zero.qacc
    ee.vmulas.s16.qacc q0, q4               # q4=mulvec 跨半保持
    ee.vmulas.s16.qacc q6, q5               # +round×ones(q6=roundvec 保持)
    ee.vmulas.s16.qacc q3, q7               # +negind×32767(q7 保持)
    addi    a9, a4, 32
    ee.vld.128.ip   q5, a9, 0               # bvec
    ee.vmulas.s16.qacc q3, q5
    QDUMP8

    # ---- nzp 写出 ----
    movi    a9, 0
    bnez    a13, 2f
    s32i    a9, a7, 0
    j       3f
2:  movi    a9, 1
    s32i    a9, a7, 0
3:  retw.n
