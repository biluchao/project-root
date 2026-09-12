# ==============================================================================
# cmake/FindONNXRuntime.cmake
# 查找 ONNX Runtime C/C++ 库
# 适用：Windows / Linux / macOS，静态库 / 动态库
# 版本：3.0.0（生产加固版）
# ==============================================================================

# ------------------------------------------------------------------------------
# 版本要求（ONNX Runtime 不保证 ABI 跨版本兼容）
# 1.23.x 为 ABI 断裂版本，生产环境建议 1.22.x 或更早稳定版本[reference:0]
# ------------------------------------------------------------------------------
set(ONNXRuntime_FIND_VERSION_MIN "1.16.0")
set(ONNXRuntime_FIND_VERSION_MAX "1.24.0")
set(ONNXRuntime_ABI_BREAK_VERSION "1.23.0")

# ------------------------------------------------------------------------------
# 用户可配置变量
# ------------------------------------------------------------------------------
set(ONNXRuntime_ROOT_DIR "" CACHE PATH "ONNX Runtime 安装根目录")
set(ONNXRuntime_USE_STATIC FALSE CACHE BOOL "使用静态库（默认动态库）")
set(ONNXRuntime_SKIP_DLL_COPY FALSE CACHE BOOL "跳过 DLL 自动复制（手动管理时启用）")

# ------------------------------------------------------------------------------
# 平台相关路径后缀
# ------------------------------------------------------------------------------
if(WIN32)
    set(_ORT_LIB_SUFFIXES lib lib/x64 lib/x86)
    # Windows 发布包中 DLL 位于 lib/ 或 bin/，需同时搜索
    set(_ORT_DLL_SUFFIXES lib bin lib/x64 bin/x64 lib/x86 bin/x86)
    set(_ORT_LIB_NAME onnxruntime)
    set(_ORT_DLL_NAME onnxruntime.dll)
    set(_ORT_PROVIDER_DLLS
        onnxruntime_providers_shared.dll
        onnxruntime_providers_cuda.dll
    )
elseif(APPLE)
    set(_ORT_LIB_SUFFIXES lib lib64)
    set(_ORT_DLL_SUFFIXES lib lib64)
    set(_ORT_LIB_NAME onnxruntime)
    set(_ORT_DLL_NAME libonnxruntime.dylib)
    set(_ORT_PROVIDER_DLLS
        libonnxruntime_providers_shared.dylib
        libonnxruntime_providers_cuda.dylib
    )
else()
    set(_ORT_LIB_SUFFIXES lib lib64)
    set(_ORT_DLL_SUFFIXES lib lib64)
    set(_ORT_LIB_NAME onnxruntime)
    set(_ORT_DLL_NAME libonnxruntime.so)
    set(_ORT_PROVIDER_DLLS
        libonnxruntime_providers_shared.so
        libonnxruntime_providers_cuda.so
    )
endif()

# ------------------------------------------------------------------------------
# 查找头文件
# ONNX Runtime 头文件实际路径为 include/onnxruntime/core/session/[reference:2]
# 部分发行版（conda-forge、Debian）将头文件放在 include/onnxruntime/[reference:3]
# 部分版本错误地将路径设置为 include/onnxruntime，需回退到 include/
# ------------------------------------------------------------------------------
find_path(ONNXRuntime_INCLUDE_DIR
    NAMES onnxruntime_cxx_api.h
    HINTS
        ${ONNXRuntime_ROOT_DIR}
        ENV ONNXRUNTIME_ROOT
        ENV ONNXRUNTIME_HOME
    PATH_SUFFIXES
        include
        include/onnxruntime
        include/onnxruntime/core/session
    NO_DEFAULT_PATH
)

if(NOT ONNXRuntime_INCLUDE_DIR)
    find_path(ONNXRuntime_INCLUDE_DIR
        NAMES onnxruntime_cxx_api.h
        PATH_SUFFIXES
            include
            include/onnxruntime
            include/onnxruntime/core/session
    )
endif()

# ------------------------------------------------------------------------------
# 查找库文件
# ------------------------------------------------------------------------------
find_library(ONNXRuntime_LIBRARY
    NAMES ${_ORT_LIB_NAME}
    HINTS
        ${ONNXRuntime_ROOT_DIR}
        ENV ONNXRUNTIME_ROOT
        ENV ONNXRUNTIME_HOME
    PATH_SUFFIXES ${_ORT_LIB_SUFFIXES}
    NO_DEFAULT_PATH
)

if(NOT ONNXRuntime_LIBRARY)
    find_library(ONNXRuntime_LIBRARY
        NAMES ${_ORT_LIB_NAME}
        PATH_SUFFIXES ${_ORT_LIB_SUFFIXES}
    )
endif()

# ------------------------------------------------------------------------------
# 查找运行时 DLL / SO
# 修复：colmap PR #4350 指出 DLL 位于 lib/ 而非 bin/ 是常见错误
# 修复：同时搜索 bin/ 和 lib/，优先 bin/
# ------------------------------------------------------------------------------
find_file(ONNXRuntime_DLL
    NAMES ${_ORT_DLL_NAME}
    HINTS
        ${ONNXRuntime_ROOT_DIR}
        ENV ONNXRUNTIME_ROOT
        ENV ONNXRUNTIME_HOME
    PATH_SUFFIXES ${_ORT_DLL_SUFFIXES}
    NO_DEFAULT_PATH
)

if(NOT ONNXRuntime_DLL)
    find_file(ONNXRuntime_DLL
        NAMES ${_ORT_DLL_NAME}
        PATH_SUFFIXES ${_ORT_DLL_SUFFIXES}
    )
endif()

# ------------------------------------------------------------------------------
# 查找 Provider 共享库（GPU 推理需要）
# 修复：未复制 Provider DLL 导致 CUDA 推理静默失败[reference:6]
# ------------------------------------------------------------------------------
set(ONNXRuntime_PROVIDER_LIBS "")
foreach(_provider ${_ORT_PROVIDER_DLLS})
    find_file(_ONNXRuntime_PROVIDER_${_provider}
        NAMES ${_provider}
        HINTS
            ${ONNXRuntime_ROOT_DIR}
            ENV ONNXRUNTIME_ROOT
            ENV ONNXRUNTIME_HOME
        PATH_SUFFIXES ${_ORT_DLL_SUFFIXES}
        NO_DEFAULT_PATH
    )
    if(_ONNXRuntime_PROVIDER_${_provider})
        list(APPEND ONNXRuntime_PROVIDER_LIBS ${_ONNXRuntime_PROVIDER_${_provider}})
    endif()
endforeach()

# ------------------------------------------------------------------------------
# 版本提取（从 onnxruntime_c_api.h 中的 ORT_API_VERSION 宏）
# ------------------------------------------------------------------------------
set(ONNXRuntime_VERSION "")
if(ONNXRuntime_INCLUDE_DIR)
    set(_ORT_VERSION_HEADER "${ONNXRuntime_INCLUDE_DIR}/onnxruntime_c_api.h")
    if(EXISTS "${_ORT_VERSION_HEADER}")
        file(STRINGS "${_ORT_VERSION_HEADER}" _ORT_VERSION_LINE
             REGEX "#define ORT_API_VERSION")
        if(_ORT_VERSION_LINE MATCHES "#define ORT_API_VERSION[ \t]+([0-9]+)")
            set(_ORT_RAW_VERSION "${CMAKE_MATCH_1}")
            if(_ORT_RAW_VERSION LESS 100)
                set(ONNXRuntime_VERSION "1.${_ORT_RAW_VERSION}")
            else()
                math(EXPR _major "${_ORT_RAW_VERSION} / 100")
                math(EXPR _minor "${_ORT_RAW_VERSION} % 100")
                set(ONNXRuntime_VERSION "${_major}.${_minor}")
            endif()
        endif()
    endif()
endif()

# ------------------------------------------------------------------------------
# 标准参数处理
# ------------------------------------------------------------------------------
include(FindPackageHandleStandardArgs)

find_package_handle_standard_args(ONNXRuntime
    REQUIRED_VARS
        ONNXRuntime_LIBRARY
        ONNXRuntime_INCLUDE_DIR
    VERSION_VAR ONNXRuntime_VERSION
    REASON_FAILURE_MESSAGE
        "ONNX Runtime 未找到。请设置 ONNXRuntime_ROOT_DIR 或环境变量 ONNXRUNTIME_ROOT。"
)

# ------------------------------------------------------------------------------
# 版本范围检查与 ABI 断裂警告
# ------------------------------------------------------------------------------
if(ONNXRuntime_FOUND AND ONNXRuntime_VERSION)
    if(ONNXRuntime_VERSION VERSION_LESS ONNXRuntime_FIND_VERSION_MIN)
        message(FATAL_ERROR
            "[FindONNXRuntime] 版本过低: ${ONNXRuntime_VERSION}，"
            "最低要求 ${ONNXRuntime_FIND_VERSION_MIN}。")
    endif()
    if(ONNXRuntime_VERSION VERSION_GREATER_EQUAL ONNXRuntime_ABI_BREAK_VERSION)
        message(WARNING
            "[FindONNXRuntime] 检测到版本 ${ONNXRuntime_VERSION}，"
            "该版本存在已知 ABI 断裂（1.23.x 升级了 VS2022 工具链）。"
            "生产环境建议使用 1.22.x 或更早的稳定版本。")
    endif()
    if(ONNXRuntime_VERSION VERSION_GREATER ONNXRuntime_FIND_VERSION_MAX)
        message(WARNING
            "[FindONNXRuntime] 版本过高: ${ONNXRuntime_VERSION}，"
            "已验证最高版本为 ${ONNXRuntime_FIND_VERSION_MAX}。")
    endif()
endif()

# ------------------------------------------------------------------------------
# 创建导入目标（现代 CMake 方式）
# ------------------------------------------------------------------------------
if(ONNXRuntime_FOUND AND NOT TARGET ONNXRuntime::ONNXRuntime)

    add_library(ONNXRuntime::ONNXRuntime UNKNOWN IMPORTED)
    set_target_properties(ONNXRuntime::ONNXRuntime PROPERTIES
        IMPORTED_LOCATION "${ONNXRuntime_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${ONNXRuntime_INCLUDE_DIR}"
    )

    # Windows 下同时设置 IMPLIB
    if(WIN32 AND ONNXRuntime_DLL)
        set_target_properties(ONNXRuntime::ONNXRuntime PROPERTIES
            IMPORTED_IMPLIB "${ONNXRuntime_LIBRARY}"
        )
    endif()

    # 查找依赖项
    find_package(Threads REQUIRED)
    target_link_libraries(ONNXRuntime::ONNXRuntime
        INTERFACE
            Threads::Threads
            ${CMAKE_DL_LIBS}
    )

    # 静态链接时的额外系统依赖
    if(ONNXRuntime_USE_STATIC)
        if(WIN32)
            target_link_libraries(ONNXRuntime::ONNXRuntime
                INTERFACE
                    ws2_32
                    advapi32
            )
        endif()
    endif()

    mark_as_advanced(
        ONNXRuntime_INCLUDE_DIR
        ONNXRuntime_LIBRARY
        ONNXRuntime_DLL
        ONNXRuntime_PROVIDER_LIBS
    )
endif()

# ------------------------------------------------------------------------------
# DLL 自动复制辅助函数（Windows 生产部署必须）
# 修复：colmap PR #4350 — DLL 位于 lib/ 而非 bin/
# 修复：copy_if_different 避免每次构建都复制
# 修复：Provider DLL 一并复制（GPU 推理必需）[reference:8]
# ------------------------------------------------------------------------------
function(onnxruntime_copy_dlls TARGET_NAME)
    if(NOT WIN32 OR ONNXRuntime_SKIP_DLL_COPY)
        return()
    endif()

    if(NOT ONNXRuntime_DLL)
        message(WARNING
            "[FindONNXRuntime] 未找到 ONNX Runtime DLL，"
            "目标 ${TARGET_NAME} 运行时可能失败。")
        return()
    endif()

    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${ONNXRuntime_DLL}"
            "$<TARGET_FILE_DIR:${TARGET_NAME}>"
        COMMENT "复制 ONNX Runtime DLL 到 ${TARGET_NAME} 输出目录"
    )

    foreach(_provider ${ONNXRuntime_PROVIDER_LIBS})
        add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${_provider}"
                "$<TARGET_FILE_DIR:${TARGET_NAME}>"
            COMMENT "复制 Provider DLL 到 ${TARGET_NAME} 输出目录"
        )
    endforeach()
endfunction()

# ------------------------------------------------------------------------------
# 配置摘要
# ------------------------------------------------------------------------------
if(ONNXRuntime_FOUND)
    message(STATUS "==================================================")
    message(STATUS " ONNX Runtime 配置")
    message(STATUS "   版本      : ${ONNXRuntime_VERSION}")
    message(STATUS "   头文件    : ${ONNXRuntime_INCLUDE_DIR}")
    message(STATUS "   库文件    : ${ONNXRuntime_LIBRARY}")
    message(STATUS "   运行时    : ${ONNXRuntime_DLL}")
    message(STATUS "   Providers : ${ONNXRuntime_PROVIDER_LIBS}")
    if(ONNXRuntime_VERSION VERSION_GREATER_EQUAL ONNXRuntime_ABI_BREAK_VERSION)
        message(STATUS "   ⚠️ 警告    : 检测到 1.23.x ABI 断裂版本，生产环境建议降级")
    endif()
    message(STATUS "==================================================")
endif()
