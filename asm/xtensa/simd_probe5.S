/* simd_probe5.S — EE.128 载入地址行为扫描(2026-11-16)
 * 已知:内部 DRAM heap 指针的 EE 载入出现 +4 偏移(sad 内核实录)。
 * 本轮:d0 = ptr+0 直接载入;d1 = ptr-4 载入(验证 +4 补偿);
 *      d2 = ptr+4 载入;d3 = 换寄存器 a10 载入(寄存器号影响?);
 *      d4 = 栈上缓冲载入;d5 = 静态 DRAM 数组载入(驱动提供)。
 */
    .text
    .align  4
    .global simd_probe5

# void simd_probe5(const uint8_t *p /*a2*/, uint8_t *out /*a3*/)
simd_probe5:
    entry   a1, 64

    # d0: ptr+0
    ee.vld.128.ip   q0, a2, 16
    addi            a2, a2, -16
    mov.n           a14, a3
    ee.vst.128.ip   q0, a14, 16

    # d1: ptr-4
    addi            a5, a2, -4
    ee.vld.128.ip   q1, a5, 16
    mov.n           a14, a3
    ee.vst.128.ip   q1, a14, 16

    # d2: ptr+4
    addi            a5, a2, 4
    ee.vld.128.ip   q2, a5, 16
    mov.n           a14, a3
    ee.vst.128.ip   q2, a14, 16

    # d3: 同地址走 a10
    mov.n           a10, a2
    ee.vld.128.ip   q3, a10, 16
    mov.n           a14, a3
    ee.vst.128.ip   q3, a14, 16

    # d4: 栈缓冲(a1+32,由调用方在栈附近放数据?此处读到的即栈内容)
    addi            a5, a1, 32
    ee.vld.128.ip   q4, a5, 16
    mov.n           a14, a3
    ee.vst.128.ip   q4, a14, 16

    # d5: 静态 DRAM 数组(调用方经 a2+16 传入第二缓冲)
    addi            a6, a2, 16
    ee.vld.128.ip   q5, a6, 16
    mov.n           a14, a3
    ee.vst.128.ip   q5, a14, 16

    retw.n
