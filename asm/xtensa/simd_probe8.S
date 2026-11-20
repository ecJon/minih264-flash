/* simd_probe8.S — s16 算术指令神谕(2026-11-16,P7C negind 全 1 事故定位)
 *
 * P7C 链式探针自相矛盾(vmax 版全 1 / vmin 版全 100),说明对
 * vsubs/vmax/vmin 的语义假设有错且链式结构无法区分。本探针对每条指令
 * 独立隔离 dump(无链),输入带符号 + 边界:
 *   a = {5, -3, -32768, 7}
 *   b = {2, 9, 1, -1}
 * 预期(标准语义):
 *   R1 vsubs(a,b) = {3,-12,7,8}     (a-b;lane2 -32769 回绕→+32767)
 *   R2 vmax(a,b)  = {5,9,-32768,7}  (带符号逐 lane 最大)
 *   R3 vmin(a,b)  = {2,-3,-32768,-1}
 *   R4 vsubs(z,a) = {-5,3,-32768,-7}(取负;lane2 -(-32768) 回绕)
 *   R5 vadds(a,b) = {7,6,...}       (加;lane2 -32767)
 * 任何偏离 = 语义发现,直接改内核设计。
 */
    .text
    .align  4
    .global simd_probe8

# void simd_probe8(const int16_t *a /*a2 = {5,-3,-32768,7}*/,
#                  const int16_t *b /*a3 = {2,9,1,-1}*/,
#                  uint8_t *out /*a4 ≥ 80B*/)
simd_probe8:
    entry   a1, 32

    ee.vld.128.ip   q0, a2, 0               # a(4 个 s16,高 lane 无关紧要)
    ee.vld.128.ip   q1, a3, 0               # b
    ee.zero.q       q2                      # 零向量

    mov.n   a9, a4
    ee.vsubs.s16    q3, q0, q1              # R1: a-b
    ee.vst.128.ip   q3, a9, 16              # out+0..15

    ee.vmax.s16     q4, q0, q1              # R2: max(a,b)
    ee.vst.128.ip   q4, a9, 16              # out+16..31

    ee.vmin.s16     q5, q0, q1              # R3: min(a,b)
    ee.vst.128.ip   q5, a9, 16              # out+32..47

    ee.vsubs.s16    q6, q2, q0              # R4: 0-a
    ee.vst.128.ip   q6, a9, 16              # out+48..63

    ee.vadds.s16    q7, q0, q1              # R5: a+b
    ee.vst.128.ip   q7, a9, 16              # out+64..79

    retw.n
