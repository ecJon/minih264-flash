# minih264-flash on-device demo (ESP32-S3)
cmake_minimum_required(VERSION 3.16)

# pull the encoder in under a stable component name regardless of how this
# repository directory is named on disk
set(EXTRA_COMPONENT_DIRS "${CMAKE_CURRENT_LIST_DIR}/components")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(idf_demo)
