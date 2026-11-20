# minih264-flash

minih264（上游 CC0 单头文件 H.264 编码器）的 **ESP32-S3 深度优化 fork**。
在原版纯 C 的基础上，把编码热路径下沉到 S3 的 EE 向量单元 + 手写 Xtensa
汇编，所有内核以**与 C 参考逐位一致（AB memcmp PASS）**为验收门。

## 优化内容

### Xtensa 汇编内核（asm/xtensa/，已接线生产）

| 内核 | 文件 | 说明 |
|---|---|---|
| SAD 8x8×4 象限 | `h264e_sad_mb_unlaign_8x8_xtensa.S` | 饱和减对+宽累加，返回值 callee-a2 |
| 前向变换·双块 | `h264e_fwd_xform2_xtensa.S` | 相邻双块一次变换（行向量+中途 4x4 双块转置 BFS 序列） |
| 量化 | `h264e_quant_block16_xtensa.S` | tsqd/quantize 双槽缓存 |
| 重建+clip | `h264e_recon_add_clip_xtensa.S` | vunzip.8 低字节 pack |
| 零块早退 | `h264e_is_zero8_xtensa.S` | quant 输出零判定早退门 |
| 参考拷贝 | `h264e_copy_rows16_xtensa.S` | 16 行搬运 |

`h264e_hadamar4_2d_xtensa.S` 为 B2 留档（hadamar4_2d ≡ 4x 恒等式发现案）。
`simd_probe*.S` 为语义神谕探针——S3 EE 向量指令集的实测记录
（127 条指令、vzip.8 绿色组合、vld.ip 增量必须 0 等"墙"的完整摸底），
新写内核前先读它，能省掉全部踩坑。

### 架构级改动（include/minih264e.h）

- **P_skip 强制 skip 架构**：`h264e_skip_y0/y1` MB 行带掩码，带外 MB 走
  最小路径四跳（跳输入缓存/dec 更新/deblock/refcopy），y1 行=守卫行
  （deblock 滤带界，跳了则编/解码重建分歧→带外漂移）
- **EE 向量单元接入**：检测宏 + vft 多后端分发表，宿主 PLAIN_C 与真机
  Xtensa 可切（A/B 位一致门的基础）
- **运行时参数**：`h264e_sps_id`、`h264e_log2_max_frame_num_minus4`、
  分段计时开关

## 集成（ESP-IDF 组件）

```bash
# 方式一：submodule 进工程 components/
git submodule add <repo-url> components/minih264
# 方式二：直接拷贝本目录为组件
```

宿主（macOS/Linux）验证：同一份 `include/minih264e.h` 以
`-DH264E_FORCE_PLAIN_C` 编译即纯 C 后端，与真机 Xtensa 后端
逐位比对（AB memcmp 门）。

## 性能

720p 单帧全 I：**400ms 级 → 263ms（9.14x）**（S3 240MHz，六内核全量
替换后）；P 帧链（P_skip 架构）静止帧 34ms/30B。

## License

上游原版与全部改动均为 **CC0-1.0**（公有领域 dedication）：
随便用、随便改、无需署名、可用于商业产品。H.264 编码本身的行业
专利面与本项目无关（CC0 不含专利授权，同任何开源实现）。
