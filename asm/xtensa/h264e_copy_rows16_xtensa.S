/* h264e_copy_rows16_xtensa.S — EE 行复制内核(B3,2026-11-17)
 *
 * void h264e_copy_rows16_xtensa(const void *src16(a2,16B对齐),
 *                               pix_t *dst(a3,16B对齐), int rows(a4))
 *   同一 16 字节行复制 rows 遍到 dst(行距 16 = 连续)。
 *   intra_predict 16x16/chroma 的垂直/DC 模式写循环:
 *   C = 4×l32i + rows×4 store;EE = 4×l32i(staging)+1 vld + rows vst。
 *   rows=16(luma):68→~25 op;rows=8(chroma):36→~17。
 *   源不对齐(top 指针仅 4 对齐)→ C 侧先读 t0-t3 落帧(它本来就读),
 *   asm 从帧 staging vld。
 * 雷册:vst 增量 16;vld.ip-0 安全。
 */
    .text
    .align  4
    .global h264e_copy_rows16_xtensa

h264e_copy_rows16_xtensa:
    entry   a1, 32

    mov.n   a14, a2
    ee.vld.128.ip   q0, a14, 0       # 16B 源
    mov.n   a14, a3
1:  ee.vst.128.ip   q0, a14, 16      # 写一行,推进 16
    addi    a4, a4, -1
    bnez    a4, 1b

    retw.n
