# Wrapper component exposing the repository as "minih264" for the example
# project. The repo root CMakeLists.txt registers the same sources as an IDF
# component, but its component name would follow the checkout directory name
# (e.g. "minih264-flash" - dashes are unsafe as component names), so the
# example references the sources through this stable-named wrapper instead.
# Relative base: examples/idf_demo/components/minih264 -> repo root = x4 "../".
idf_component_register(
    SRCS
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/simd_probe6.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/simd_probe7.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/simd_probe8.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/simd_probe9.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/h264e_fwd_xform2_xtensa.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/h264e_recon_add_clip_xtensa.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/h264e_copy_rows16_xtensa.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/h264e_sad_mb_unlaign_8x8_xtensa.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../asm/xtensa/h264e_quant_block16_xtensa.S"
        "${CMAKE_CURRENT_LIST_DIR}/../../../../demo/ee_lane_probe.S"
    INCLUDE_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../../../include"
)
