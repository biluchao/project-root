# ==============================================================================
# 顶层 CMakeLists.txt
# 项目：量化交易系统
# 构建系统：CMake 3.20+
# 语言：C++20
# 版本：1.0.0
# ==============================================================================

cmake_minimum_required(VERSION 3.20)

# ------------------------------------------------------------------------------
# 项目定义
# ------------------------------------------------------------------------------
project(TradingSystem
    VERSION 1.0.0
    DESCRIPTION "Production-grade quantitative trading system"
    LANGUAGES CXX
)

# ------------------------------------------------------------------------------
# C++ 标准（全局，不可覆盖）
# ------------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ------------------------------------------------------------------------------
# 默认构建类型（单配置生成器必须）
# 修复：未设置 CMAKE_BUILD_TYPE 时静默产生未优化二进制
# ------------------------------------------------------------------------------
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "构建类型" FORCE)
    message(STATUS "[CMake] 未指定构建类型，默认为 Release")
endif()

# ------------------------------------------------------------------------------
# 路径设置
# ------------------------------------------------------------------------------
list(APPEND CMAKE_MODULE_PATH
    "${CMAKE_SOURCE_DIR}/cmake"
)

# ------------------------------------------------------------------------------
# 编译选项（在 target 之前加载，影响全局编译行为）
# ------------------------------------------------------------------------------
include(CompilerOptions)

# ------------------------------------------------------------------------------
# 输出目录统一（避免 DLL/EXE/LIB 散落各处）
# 修复：DLL 与 EXE 不在同一目录导致运行时找不到
# ------------------------------------------------------------------------------
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# 多配置生成器（MSVC）下按配置分目录
foreach(_config IN ITEMS DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    string(TOUPPER "${_config}" _config_upper)
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${_config_upper}
        "${CMAKE_BINARY_DIR}/lib/${_config}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${_config_upper}
        "${CMAKE_BINARY_DIR}/lib/${_config}")
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${_config_upper}
        "${CMAKE_BINARY_DIR}/bin/${_config}")
endforeach()

# ------------------------------------------------------------------------------
# 依赖管理
# ------------------------------------------------------------------------------

# ---- 必需依赖 ----
find_package(Threads REQUIRED)

# ---- ONNX Runtime（自定义 Find 模块） ----
# 修复：官方不提供 onnxruntimeConfig.cmake，必须使用自定义模块
find_package(ONNXRuntime 1.16 REQUIRED)

# ---- Boost（Asio/Beast 用于网络） ----
set(BOOST_MIN_VERSION 1.82)
find_package(Boost ${BOOST_MIN_VERSION} REQUIRED
    COMPONENTS system
)

# ---- 其他依赖（可选，失败时降级） ----
find_package(spdlog QUIET)
find_package(nlohmann_json QUIET)
find_package(Eigen3 QUIET)
find_package(PostgreSQL QUIET)
find_package(hiredis QUIET)
find_package(OpenSSL REQUIRED)

# 缺失可选依赖时使用内置版本
if(NOT spdlog_FOUND)
    message(STATUS "[CMake] spdlog 未找到，使用内置头文件")
    add_subdirectory(third_party/spdlog)
endif()

if(NOT nlohmann_json_FOUND)
    message(STATUS "[CMake] nlohmann_json 未找到，使用内置头文件")
    add_subdirectory(third_party/nlohmann_json)
endif()

# ------------------------------------------------------------------------------
# 第三方依赖统一标记为 SYSTEM（屏蔽其头文件警告）
# 修复：-Werror 下第三方头文件告警导致构建失败
# ------------------------------------------------------------------------------
if(TARGET Boost::system)
    get_target_property(_boost_inc Boost::system INTERFACE_INCLUDE_DIRECTORIES)
    if(_boost_inc)
        set_target_properties(Boost::system PROPERTIES
            INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${_boost_inc}")
    endif()
endif()

# ------------------------------------------------------------------------------
# 项目子目录（按组装顺序）
# ------------------------------------------------------------------------------
add_subdirectory(src/common)
add_subdirectory(src/event)
add_subdirectory(src/data)
add_subdirectory(src/indicator)
add_subdirectory(src/strategy)
add_subdirectory(src/ai)
add_subdirectory(src/oms)
add_subdirectory(src/virtual_broker)
add_subdirectory(src/experience)
add_subdirectory(src/portfolio)
add_subdirectory(src/backtest)
add_subdirectory(src/compliance)
add_subdirectory(src/core_main)
add_subdirectory(src/backend)

# ------------------------------------------------------------------------------
# 组装器工具
# ------------------------------------------------------------------------------
add_subdirectory(deploy)

# ------------------------------------------------------------------------------
# 测试（仅当 BUILD_TESTING 开启）
# ------------------------------------------------------------------------------
include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
    add_subdirectory(benchmarks)
endif()

# ------------------------------------------------------------------------------
# 安装规则
# ------------------------------------------------------------------------------
install(TARGETS
    trading_core
    backend_server
    deploy_tool
    RUNTIME DESTINATION bin
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY config/
    DESTINATION config
    FILES_MATCHING PATTERN "*.json" PATTERN "*.yaml"
)

install(DIRECTORY models/
    DESTINATION models
    FILES_MATCHING PATTERN "*.onnx"
)

# ------------------------------------------------------------------------------
# 打包（CPack）
# ------------------------------------------------------------------------------
set(CPACK_PROJECT_NAME "TradingSystem")
set(CPACK_PROJECT_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VENDOR "TradingSystem")
include(CPack)

# ------------------------------------------------------------------------------
# 配置摘要
# ------------------------------------------------------------------------------
message(STATUS "==================================================")
message(STATUS " TradingSystem ${PROJECT_VERSION}")
message(STATUS "   构建类型    : ${CMAKE_BUILD_TYPE}")
message(STATUS "   C++ 标准    : ${CMAKE_CXX_STANDARD}")
message(STATUS "   输出目录    : ${CMAKE_BINARY_DIR}")
message(STATUS "   Boost       : ${Boost_VERSION}")
message(STATUS "   ONNX Runtime: ${ONNXRuntime_VERSION}")
message(STATUS "   PostgreSQL  : ${PostgreSQL_VERSION_STRING}")
message(STATUS "   测试        : ${BUILD_TESTING}")
message(STATUS "==================================================")
