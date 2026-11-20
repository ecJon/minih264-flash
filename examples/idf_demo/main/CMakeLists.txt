idf_component_register(
    SRCS "${CMAKE_CURRENT_LIST_DIR}/../../../demo/minih264_demo.c"
    INCLUDE_DIRS "${CMAKE_CURRENT_LIST_DIR}"
    REQUIRES esp_timer
    PRIV_REQUIRES minih264 freertos heap
)

# bisect switch (temporary): H264E_BISECT_C_QUANT / H264E_BISECT_C_SAD
# force the C fallbacks inside the Xtensa tsqd wrapper / SAD table entry
