# ==============================================================================
# cmake/CompilerOptions.cmake
# 生产级编译选项统一配置
# 适用：GCC / Clang / MSVC
# 特性：稳定性优先、数值安全、安全加固、性能可控
# 版本：2.0.0（生产加固版）
# ==============================================================================

# ------------------------------------------------------------------------------
# 选项开关
# ------------------------------------------------------------------------------
option(ENABLE_NATIVE_ARCH   "启用 -march=native（仅同机构建部署时开启）" OFF)
option(ENABLE_LTO           "启用链接时优化"                             OFF)
option(ENABLE_ASAN          "启用 AddressSanitizer（仅测试环境）"        OFF)
option(ENABLE_TSAN          "启用 ThreadSanitizer（仅测试环境）"         OFF)
option(ENABLE_UBSAN         "启用 UndefinedBehaviorSanitizer（仅测试）"  OFF)
option(ENABLE_COVERAGE      "启用代码覆盖率（仅测试）"                   OFF)
option(ENABLE_WERROR        "警告视为错误（仅 CI）"                      OFF)
option(ENABLE_PGO_GENERATE  "PGO 生成阶段"                               OFF)
option(ENABLE_PGO_USE       "PGO 使用阶段"                               OFF)
option(ENABLE_HARDENING     "安全加固（栈保护、FORTIFY、RELRO）"         ON)
option(ENABLE_SMALL_STACK   "缩减默认栈为 1MB（超多线程场景）"           OFF)
option(ENABLE_TRACE_LOG     "Release 下保留 TRACE 日志"                  OFF)
option(ENABLE_SIMD_HINTS    "启用 SIMD 提示（不指定具体指令集）"         OFF)

set(PGO_PROFILE_DIR "${CMAKE_BINARY_DIR}/pgo" CACHE PATH "PGO profile 目录")

# ------------------------------------------------------------------------------
# 编译器识别
# ------------------------------------------------------------------------------
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
    set(COMPILER_GCC TRUE)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    set(COMPILER_CLANG TRUE)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    set(COMPILER_MSVC TRUE)
else()
    message(FATAL_ERROR "不支持的编译器: ${CMAKE_CXX_COMPILER_ID}")
endif()

include(CheckCXXCompilerFlag)
include(CheckIPOSupported)

# ------------------------------------------------------------------------------
# 默认构建类型
# ------------------------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "构建类型" FORCE)
endif()

# ------------------------------------------------------------------------------
# 互斥检查（早期失败，避免浪费时间）
# ------------------------------------------------------------------------------
if(ENABLE_ASAN AND ENABLE_TSAN)
    message(FATAL_ERROR "[CompilerOptions] ASan 与 TSan 不能同时启用")
endif()
if((ENABLE_ASAN OR ENABLE_TSAN OR ENABLE_UBSAN) AND (ENABLE_PGO_GENERATE OR ENABLE_PGO_USE))
    message(FATAL_ERROR "[CompilerOptions] Sanitizer 与 PGO 不能同时启用")
endif()
if(ENABLE_LTO AND (ENABLE_ASAN OR ENABLE_TSAN))
    message(FATAL_ERROR "[CompilerOptions] LTO 与 Sanitizer 不能同时启用")
endif()

# ==============================================================================
# GCC / Clang 配置
# ==============================================================================
if(COMPILER_GCC OR COMPILER_CLANG)

    # ---- 基础警告 ----
    add_compile_options(-Wall -Wextra -Wpedantic)
    if(ENABLE_WERROR)
        add_compile_options(-Werror)
    endif()

    # ---- 数值安全：显式禁用破坏 IEEE 语义的选项 ----
    # 即使有人通过 CMAKE_CXX_FLAGS 注入也会被覆盖
    add_compile_options(
        -fno-fast-math
        -fno-finite-math-only
        -fno-unsafe-math-optimizations
    )
    # 主动拒绝 -Ofast / -ffast-math（若用户误用则报错）
    if(CMAKE_CXX_FLAGS MATCHES "-Ofast" OR CMAKE_CXX_FLAGS_RELEASE MATCHES "-Ofast")
        message(FATAL_ERROR "[CompilerOptions] 检测到 -Ofast，会破坏金融数值计算，已拒绝")
    endif()
    if(CMAKE_CXX_FLAGS MATCHES "-ffast-math")
        message(FATAL_ERROR "[CompilerOptions] 检测到 -ffast-math，会破坏金融数值计算，已拒绝")
    endif()

    # ---- 符号可见性 ----
    # 可执行文件默认隐藏，减少符号冲突；共享库目标可单独覆盖
    add_compile_options(-fvisibility=hidden)

    # ---- PIC ----
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)

    # ---- 线程（关键：必须在此处 find，否则下游 target 忘记链接会运行时报错） ----
    set(THREADS_PREFER_PTHREAD_FLAG ON)
    find_package(Threads REQUIRED)

    # ---- 优化级别 ----
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3)
        add_compile_options(-fno-omit-frame-pointer)
    elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        add_compile_options(-O2 -g)
        add_compile_options(-fno-omit-frame-pointer)
    elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
        add_compile_options(-O0 -g3 -fno-omit-frame-pointer)
    endif()

    # ---- 架构优化 ----
    if(ENABLE_NATIVE_ARCH)
        # 风险：构建机与部署机 CPU 不同会导致 SIGILL 崩溃
        # 社区案例：CI 缓存了 AVX-512 构建产物，在不支持的 runner 上崩溃
        add_compile_options(-march=native -mtune=native)
        message(WARNING "[CompilerOptions] 启用 -march=native，部署机必须与构建机 CPU 完全一致，否则可能 SIGILL 崩溃")
    else()
        # 保守基线：不指定具体指令集，仅对 x86_64 使用 generic tune
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
            add_compile_options(-mtune=generic)
        endif()
        # 可选：仅启用 SIMD 提示，不指定具体指令集
        if(ENABLE_SIMD_HINTS)
            add_compile_options(-ftree-vectorize)
        endif()
    endif()

    # ---- 安全加固（探测式添加） ----
    if(ENABLE_HARDENING)
        check_cxx_compiler_flag("-fstack-protector-strong" HAS_STACK_PROTECTOR)
        if(HAS_STACK_PROTECTOR)
            add_compile_options(-fstack-protector-strong)
        endif()

        check_cxx_compiler_flag("-fstack-clash-protection" HAS_STACK_CLASH)
        if(HAS_STACK_CLASH)
            add_compile_options(-fstack-clash-protection)
        endif()

        # _FORTIFY_SOURCE 需 -O1 以上，Debug 下会触发警告
        if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
            add_compile_definitions(_FORTIFY_SOURCE=2)
        endif()

        # 链接器加固
        if(UNIX AND NOT APPLE)
            add_link_options(-Wl,-z,relro,-z,now)
        endif()
    endif()

    # ---- LTO ----
    if(ENABLE_LTO)
        check_ipo_supported(RESULT IPO_OK OUTPUT IPO_ERR)
        if(IPO_OK)
            set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)
            message(STATUS "[CompilerOptions] 启用 LTO")
        else()
            message(WARNING "[CompilerOptions] LTO 不被支持: ${IPO_ERR}，回退到普通优化")
        endif()
    endif()

    # ---- PGO ----
    if(ENABLE_PGO_GENERATE)
        add_compile_options(-fprofile-generate=${PGO_PROFILE_DIR})
        add_link_options(-fprofile-generate=${PGO_PROFILE_DIR})
        message(STATUS "[CompilerOptions] PGO 生成模式 → ${PGO_PROFILE_DIR}")
    elseif(ENABLE_PGO_USE)
        if(NOT EXISTS "${PGO_PROFILE_DIR}")
            message(WARNING "[CompilerOptions] PGO profile 目录不存在: ${PGO_PROFILE_DIR}，跳过 PGO")
        else()
            add_compile_options(-fprofile-use=${PGO_PROFILE_DIR})
            if(COMPILER_GCC)
                add_compile_options(-fprofile-correction)
            endif()
            add_link_options(-fprofile-use=${PGO_PROFILE_DIR})
            message(STATUS "[CompilerOptions] PGO 使用模式 ← ${PGO_PROFILE_DIR}")
        endif()
    endif()

    # ---- Sanitizers ----
    if(ENABLE_ASAN)
        add_compile_options(-fsanitize=address -fno-omit-frame-pointer)
        add_link_options(-fsanitize=address)
        message(STATUS "[CompilerOptions] 启用 ASan（仅测试环境）")
    endif()
    if(ENABLE_TSAN)
        add_compile_options(-fsanitize=thread -fno-omit-frame-pointer)
        add_link_options(-fsanitize=thread)
        message(STATUS "[CompilerOptions] 启用 TSan（仅测试环境）")
    endif()
    if(ENABLE_UBSAN)
        add_compile_options(-fsanitize=undefined -fno-sanitize-recover=all)
        add_link_options(-fsanitize=undefined)
        message(STATUS "[CompilerOptions] 启用 UBSan（仅测试环境）")
    endif()

    # ---- 覆盖率 ----
    if(ENABLE_COVERAGE)
        add_compile_options(--coverage -fprofile-arcs -ftest-coverage)
        add_link_options(--coverage)
    endif()

    # ---- GCC 专属 ----
    if(COMPILER_GCC)
        add_compile_options(-Wno-maybe-uninitialized)

        # -fno-plt：减少 PLT 开销，但需 glibc >= 2.26
        if(UNIX AND NOT APPLE)
            check_cxx_compiler_flag("-fno-plt" HAS_FNO_PLT)
            if(HAS_FNO_PLT)
                add_compile_options(-fno-plt)
            endif()
        endif()
    endif()

    # ---- Clang 专属 ----
    if(COMPILER_CLANG)
        add_compile_options(
            -Wno-gnu-zero-variadic-macro-arguments
        )
    endif()

endif()

# ==============================================================================
# MSVC 配置
# ==============================================================================
if(COMPILER_MSVC)
    add_compile_options(
        /W4
        /permissive-
        /Zc:__cplusplus
        /Zc:preprocessor
        /utf-8
        /MP
        /EHsc
        /bigobj
    )

    # 数值安全
    add_compile_options(/fp:precise)

    # 拒绝 /fp:fast
    if(CMAKE_CXX_FLAGS MATCHES "/fp:fast")
        message(FATAL_ERROR "[CompilerOptions] 检测到 /fp:fast，会破坏金融数值计算，已拒绝")
    endif()

    # 安全加固
    if(ENABLE_HARDENING)
        add_compile_options(/GS /guard:cf /DYNAMICBASE /NXCOMPAT)
        add_link_options(/guard:cf)
    endif()

    # Release 优化
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(/O2 /Oi /Ot)
        if(ENABLE_LTO)
            add_compile_options(/GL)
            add_link_options(/LTCG)
        endif()
    endif()

    if(ENABLE_WERROR)
        add_compile_options(/WX)
    endif()

    if(ENABLE_ASAN)
        add_compile_options(/fsanitize=address)
        add_link_options(/fsanitize=address)
    endif()

    if(ENABLE_TSAN OR ENABLE_UBSAN)
        message(WARNING "[CompilerOptions] MSVC 不支持 TSan/UBSan，已忽略")
    endif()
endif()

# ==============================================================================
# C++ 标准（全局强制）
# ==============================================================================
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ==============================================================================
# 全局宏
# ==============================================================================
add_compile_definitions(
    $<$<CONFIG:Release>:NDEBUG>
    $<$<CONFIG:RelWithDebInfo>:NDEBUG>
)

if(ENABLE_TRACE_LOG)
    add_compile_definitions($<$<CONFIG:Release>:SPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_TRACE>)
else()
    add_compile_definitions($<$<CONFIG:Release>:SPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_INFO>)
endif()

# ==============================================================================
# 链接器选项
# ==============================================================================
if(UNIX AND NOT APPLE AND (COMPILER_GCC OR COMPILER_CLANG))

    find_program(MOLD_LINKER mold)
    find_program(LLD_LINKER ld.lld)
    if(MOLD_LINKER)
        add_link_options(-fuse-ld=mold)
        message(STATUS "[CompilerOptions] 使用 mold 链接器")
    elseif(LLD_LINKER)
        add_link_options(-fuse-ld=lld)
        message(STATUS "[CompilerOptions] 使用 lld 链接器")
    endif()

    if(ENABLE_SMALL_STACK)
        add_link_options(-Wl,-z,stack-size=1048576)
        message(STATUS "[CompilerOptions] 栈大小缩减为 1MB")
    else()
        add_link_options(-Wl,-z,stack-size=8388608)
    endif()

endif()

# ==============================================================================
# 配置摘要
# ==============================================================================
message(STATUS "==================================================")
message(STATUS " 编译配置摘要")
message(STATUS "   编译器      : ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "   构建类型    : ${CMAKE_BUILD_TYPE}")
message(STATUS "   C++ 标准    : ${CMAKE_CXX_STANDARD}")
message(STATUS "   native 架构 : ${ENABLE_NATIVE_ARCH}")
message(STATUS "   LTO         : ${ENABLE_LTO}")
message(STATUS "   加固        : ${ENABLE_HARDENING}")
message(STATUS "   ASan/TSan/UBSan : ${ENABLE_ASAN}/${ENABLE_TSAN}/${ENABLE_UBSAN}")
message(STATUS "   PGO         : gen=${ENABLE_PGO_GENERATE} use=${ENABLE_PGO_USE}")
message(STATUS "   小栈模式    : ${ENABLE_SMALL_STACK}")
message(STATUS "==================================================")
