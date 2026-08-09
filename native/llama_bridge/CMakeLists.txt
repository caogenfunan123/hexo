cmake_minimum_required(VERSION 3.16)
project(llama_bridge C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# 指向 llama.cpp 源码目录（通过 -DLLAMA_CPP_DIR=path 传入）
set(LLAMA_CPP_DIR "" CACHE PATH "Path to llama.cpp source directory")

if(NOT LLAMA_CPP_DIR)
    message(FATAL_ERROR "Please pass -DLLAMA_CPP_DIR=<path-to-llama.cpp>")
endif()

# llama.cpp 的公共头文件目录
add_library(llama_bridge SHARED llama_bridge.c)
target_include_directories(llama_bridge PRIVATE
    ${LLAMA_CPP_DIR}
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/ggml/include
)

# 依赖 llama.cpp 预编译静态库
# 构建 llama.cpp 静态库:
#   cmake -B build -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TESTS=OFF -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF
#   cmake --build build --target llama -j
# 产物: build/src/libllama.a 与 build/ggml/src/libggml.a 等
set(LLAMA_BUILD_DIR "" CACHE PATH "Path to llama.cpp build directory")
if(NOT LLAMA_BUILD_DIR)
    message(FATAL_ERROR "Please pass -DLLAMA_BUILD_DIR=<path-to-llama.cpp-build>")
endif()

target_link_libraries(llama_bridge PRIVATE
    ${LLAMA_BUILD_DIR}/src/libllama.a
    ${LLAMA_BUILD_DIR}/ggml/src/libggml.a
    ${LLAMA_BUILD_DIR}/ggml/src/ggml-cpu/libggml-cpu.a
    ${LLAMA_BUILD_DIR}/common/libcommon.a
    dl pthread m
)

set_target_properties(llama_bridge PROPERTIES
    OUTPUT_NAME llama_bridge
    VERSION 1.0.0
    SOVERSION 1
)
