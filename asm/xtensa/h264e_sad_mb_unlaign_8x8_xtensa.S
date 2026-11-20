/* h264e_sad_mb_unlaign_8x8_xtensa.S — S3 向量 SAD 内核 v6(压榨项目 M2-k1,2026-11-16)
 *
 * int h264e_sad_mb_unlaign_8x8_xtensa(const pix_t *a, int a_stride,
 *                                     const pix_t *b, int sad[4])
 * 与 C 版逐值一致:4 个 8x8 象限 SAD,返回总和。b 平铺 16x16(行距 16)。
 *
 * v6 定案修复(2026-11-16,三雷齐爆的完整复盘):
 *  ① 返回值必须在 callee-a2(C 版反汇编铁证:add.n a2,a2,a6; retw)。
 *    v5 把总和放 a10 = 调用方不可见 = 返回垃圾(a2 残留的首参指针值)。
 *    此前的"验证通过"全是假阴性:saber/双跑钩子里的"C 参考"经 MAP_NAME
 *    宏改写为 vft 间接调用,X 后端下 = asm 自己——asm-vs-asm 恒等。
 *  ② EE vst 禁止写调用方的 sad 数组(栈上 int[4] 无 16B 对齐保证;
 *    probe5 实证 4 对齐 EE 访问崩溃 = 单线程冻结根因)。横和暂存改用
 *    自身栈帧 [a1, a1+16)(Xtensa ABI:sp 16B 对齐;entry 32 保证在帧内),
 *    sad[0..3] 最终值用普通 s32i 写出(4 对齐即可)。
 *  ③ entry 16→32(约定余量;EE/横和暂存就在这 32B 帧内)。
 * 历史修复:.Lbot 补 b+16 行推进、a 行进量 a_stride-16→a_stride、
 * 删开发期 DEBUG 早退(它令真归约尾声从未跑过)。
 *
 * 语义依据(真机探针 simd_probe2/3/4/5 实测):vld/vst.128.ip 字节序 1:1;
 * zip.8(q,0) 零扩展顺序落位(byte i→lane 2i);vsubs/vmax/vadds.s16 顺序
 * 三操作数;⚠️vld.ip 增量必须 0(非 0 随内存区域漂移),指针推进用显式
 * addi/add;vst.ip = 后递增(先写 [ptr] 再 +=16);EE 访问 16B 对齐硬要求。
 * 算法:zip 零扩展 → 16 位精确相减 → vmax 取 abs → vadds 累加(≤8 行×255
 * =2040 无溢出)。四象限和全程驻留 a8-a11,函数尾统一写出。
 */
    .text
    .align  4
    .global h264e_sad_mb_unlaign_8x8_xtensa

h264e_sad_mb_unlaign_8x8_xtensa:
    entry   a1, 32

    mov     a9, a3              # a9 = a_stride(行推进)
    mov     a10, a2             # a 游标
    mov     a11, a4             # b 游标
    mov     a12, a5             # sad 输出(普通 s32i,仅 4 对齐要求)
    movi    a13, 8              # 行计数

    ee.zero.q   q5              # accL
    ee.zero.q   q3              # accR

.Ltop:
    ee.vld.128.ip   q0, a10, 0    # 载入增量 0,指针显式推进
    ee.vld.128.ip   q1, a11, 0
    ee.zero.q   q7
    ee.vzip.8   q0, q7          # wa_lo=q0, wa_hi=q7
    ee.zero.q   q6
    ee.vzip.8   q1, q6          # wb_lo=q1, wb_hi=q6
    ee.vsubs.s16 q0, q0, q1     # d_lo
    ee.vsubs.s16 q7, q7, q6     # d_hi
    ee.zero.q   q6
    ee.vsubs.s16 q6, q6, q0     # -d_lo
    ee.vmax.s16 q0, q0, q6      # |d_lo|
    ee.vadds.s16 q5, q5, q0
    ee.zero.q   q6
    ee.vsubs.s16 q6, q6, q7     # -d_hi
    ee.vmax.s16 q7, q7, q6      # |d_hi|
    ee.vadds.s16 q3, q3, q7
    add     a10, a10, a9
    addi    a11, a11, 16
    addi    a13, a13, -1
    bnez    a13, .Ltop

    # TL:accL → [a1] 横和暂存(自身帧,16B 对齐)→ a8
    mov.n   a14, a1             # ⚠️vst.ip 会后递增基址——必须用副本,不能直接 a1
    nop
    ee.vst.128.ip q5, a14, 16
    l16si   a8,  a1, 0
    l16si   a9,  a1, 2
    add     a8, a8, a9
    l16si   a9,  a1, 4
    add     a8, a8, a9
    l16si   a9,  a1, 6
    add     a8, a8, a9
    l16si   a9,  a1, 8
    add     a8, a8, a9
    l16si   a9,  a1, 10
    add     a8, a8, a9
    l16si   a9,  a1, 12
    add     a8, a8, a9
    l16si   a9,  a1, 14
    add     a8, a8, a9          # a8 = TL

    # TR:accR → [a1] → a9
    mov.n   a14, a1
    nop
    ee.vst.128.ip q3, a14, 16
    l16si   a9,  a1, 0
    l16si   a10, a1, 2
    add     a9, a9, a10
    l16si   a10, a1, 4
    add     a9, a9, a10
    l16si   a10, a1, 6
    add     a9, a9, a10
    l16si   a10, a1, 8
    add     a9, a9, a10
    l16si   a10, a1, 10
    add     a9, a9, a10
    l16si   a10, a1, 12
    add     a9, a9, a10
    l16si   a10, a1, 14
    add     a9, a9, a10         # a9 = TR(a10 此后可复用)

    # ============ 行 8-15:BL=accL, BR=accR ============
    mov     a14, a3             # 行推进 = a_stride
    slli    a15, a3, 3
    add     a10, a2, a15        # a + 8*a_stride
    addi    a11, a4, 128        # b + 8*16
    movi    a13, 8
    ee.zero.q   q5
    ee.zero.q   q3
.Lbot:
    ee.vld.128.ip   q0, a10, 0
    ee.vld.128.ip   q1, a11, 0
    ee.zero.q   q7
    ee.vzip.8   q0, q7
    ee.zero.q   q6
    ee.vzip.8   q1, q6
    ee.vsubs.s16 q0, q0, q1
    ee.vsubs.s16 q7, q7, q6
    ee.zero.q   q6
    ee.vsubs.s16 q6, q6, q0
    ee.vmax.s16 q0, q0, q6
    ee.vadds.s16 q5, q5, q0
    ee.zero.q   q6
    ee.vsubs.s16 q6, q6, q7
    ee.vmax.s16 q7, q7, q6
    ee.vadds.s16 q3, q3, q7
    add     a10, a10, a14       # a 行 +a_stride
    addi    a11, a11, 16        # b 行 +16
    addi    a13, a13, -1
    bnez    a13, .Lbot

    # BL:accL → [a1] → a10(a13/a15/a14 轮转,不碰 a8/a9)
    mov.n   a14, a1
    nop
    ee.vst.128.ip q5, a14, 16
    l16si   a10, a1, 0
    l16si   a13, a1, 2
    add     a10, a10, a13
    l16si   a15, a1, 4
    add     a10, a10, a15
    l16si   a13, a1, 6
    add     a10, a10, a13
    l16si   a15, a1, 8
    add     a10, a10, a15
    l16si   a13, a1, 10
    add     a10, a10, a13
    l16si   a15, a1, 12
    add     a10, a10, a15
    l16si   a13, a1, 14
    add     a10, a10, a13       # a10 = BL

    # BR:accR → [a1] → a11
    mov.n   a14, a1
    nop
    ee.vst.128.ip q3, a14, 16
    l16si   a11, a1, 0
    l16si   a13, a1, 2
    add     a11, a11, a13
    l16si   a15, a1, 4
    add     a11, a11, a15
    l16si   a13, a1, 6
    add     a11, a11, a13
    l16si   a15, a1, 8
    add     a11, a11, a15
    l16si   a13, a1, 10
    add     a11, a11, a13
    l16si   a15, a1, 12
    add     a11, a11, a15
    l16si   a13, a1, 14
    add     a11, a11, a13       # a11 = BR

    # 四象限写出(普通 s32i,sad 仅 4 对齐)+ 总和 → a2(⚠️返回寄存器)
    s32i    a8,  a12, 0
    s32i    a9,  a12, 4
    s32i    a10, a12, 8
    s32i    a11, a12, 12
    add     a2, a8, a9
    add     a2, a2, a10
    add     a2, a2, a11         # a2 = 总和(callee 视图返回值)

    retw.n
