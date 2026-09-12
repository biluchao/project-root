# ==============================================================================
# Makefile
# 项目：量化交易系统
# 用途：统一构建入口（封装 CMake + Conan/vcpkg）
# 版本：1.0.0
# ==============================================================================

# ------------------------------------------------------------------------------
# 变量定义（使用 := 立即展开，避免递归计算）
# ------------------------------------------------------------------------------
PROJECT_NAME        := TradingSystem
BUILD_DIR           := build
BUILD_TYPE          ?= Release
INSTALL_PREFIX      ?= /usr/local
JOBS                ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# 包管理器选择：conan | vcpkg | system
PKG_MANAGER         ?= conan

# Conan 配置
CONAN_PROFILE       ?= default
CONAN_LOCKFILE      := conan.lock

# vcpkg 配置
VCPKG_ROOT          ?= $(HOME)/vcpkg
VCPKG_TRIPLET       ?= x64-linux

# 编译器缓存与链接器（可选）
CCACHE              := $(shell command -v ccache 2>/dev/null)
MOLD                := $(shell command -v mold 2>/dev/null)
LLD                 := $(shell command -v ld.lld 2>/dev/null)

# CMake 额外参数
CMAKE_EXTRA_ARGS    ?=

# 颜色输出
ifeq ($(shell tput colors 2>/dev/null || echo 0),0)
    C_GREEN :=
    C_YELLOW :=
    C_RED :=
    C_RESET :=
else
    C_GREEN := \033[0;32m
    C_YELLOW := \033[0;33m
    C_RED := \033[0;31m
    C_RESET := \033[0m
endif

# ------------------------------------------------------------------------------
# 默认目标
# ------------------------------------------------------------------------------
.DEFAULT_GOAL := all

# ------------------------------------------------------------------------------
# 伪目标声明（必须，否则同名目录会导致目标被跳过）
# ------------------------------------------------------------------------------
.PHONY: all help configure build test benchmark install package clean distclean \
        deps deps-conan deps-vcpkg deps-system run-core run-backend \
        format lint check-env

# ------------------------------------------------------------------------------
# 所有构建的入口
# ------------------------------------------------------------------------------
all: check-env deps configure build
	@echo "$(C_GREEN)>>> 构建完成: $(PROJECT_NAME) ($(BUILD_TYPE))$(C_RESET)"

# ==============================================================================
# 环境检查
# ==============================================================================
check-env:
	@echo "$(C_GREEN)>>> 检查构建环境...$(C_RESET)"
	@command -v cmake >/dev/null 2>&1 || \
		{ echo "$(C_RED)错误: 未找到 cmake，请安装 CMake 3.20+$(C_RESET)"; exit 1; }
	@command -v $(CXX) >/dev/null 2>&1 || \
		{ echo "$(C_RED)错误: 未找到 C++ 编译器$(C_RESET)"; exit 1; }
	@echo "  构建类型    : $(BUILD_TYPE)"
	@echo "  并行任务数  : $(JOBS)"
	@echo "  包管理器    : $(PKG_MANAGER)"
	@[ -n "$(CCACHE)" ] && echo "  ccache      : 已启用" || echo "  ccache      : 未安装（建议安装以加速重复编译）"
	@[ -n "$(MOLD)" ] && echo "  mold        : 已启用" || echo "  mold        : 未安装（可选）"

# ==============================================================================
# 依赖管理
# ==============================================================================
deps: deps-$(PKG_MANAGER)

deps-conan:
	@echo "$(C_GREEN)>>> 安装 Conan 依赖...$(C_RESET)"
	@command -v conan >/dev/null 2>&1 || \
		{ echo "$(C_RED)错误: 未找到 conan，请执行 pip install conan$(C_RESET)"; exit 1; }
	@if [ -f "$(CONAN_LOCKFILE)" ]; then \
		conan install . --lockfile=$(CONAN_LOCKFILE) --build=missing \
			-s build_type=$(BUILD_TYPE) -s:h build_type=$(BUILD_TYPE); \
	else \
		conan install . --build=missing \
			-s build_type=$(BUILD_TYPE) -s:h build_type=$(BUILD_TYPE); \
	fi

deps-vcpkg:
	@echo "$(C_GREEN)>>> 安装 vcpkg 依赖...$(C_RESET)"
	@[ -d "$(VCPKG_ROOT)" ] || \
		{ echo "$(C_RED)错误: VCPKG_ROOT 不存在: $(VCPKG_ROOT)$(C_RESET)"; exit 1; }
	@$(VCPKG_ROOT)/vcpkg install --triplet $(VCPKG_TRIPLET)

deps-system:
	@echo "$(C_YELLOW)>>> 使用系统包管理器，请确保已安装所有依赖$(C_RESET)"

# ==============================================================================
# CMake 配置
# ==============================================================================
configure:
	@echo "$(C_GREEN)>>> 配置 CMake...$(C_RESET)"
	@mkdir -p $(BUILD_DIR)
	@cmake -B $(BUILD_DIR) -S . \
		-DCMAKE_BUILD_TYPE=$(BUILD_TYPE) \
		-DCMAKE_INSTALL_PREFIX=$(INSTALL_PREFIX) \
		-DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
		$(if $(CCACHE),-DCMAKE_CXX_COMPILER_LAUNCHER=$(CCACHE)) \
		$(if $(MOLD),-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=mold \
			-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=mold) \
		$(if $(and $(filter vcpkg,$(PKG_MANAGER)),$(VCPKG_ROOT)), \
			-DCMAKE_TOOLCHAIN_FILE=$(VCPKG_ROOT)/scripts/buildsystems/vcpkg.cmake \
			-DVCPKG_TARGET_TRIPLET=$(VCPKG_TRIPLET)) \
		$(CMAKE_EXTRA_ARGS)
	@ln -sf $(BUILD_DIR)/compile_commands.json compile_commands.json 2>/dev/null || true

# ==============================================================================
# 构建
# ==============================================================================
build: configure
	@echo "$(C_GREEN)>>> 编译 $(PROJECT_NAME)...$(C_RESET)"
	@cmake --build $(BUILD_DIR) --parallel $(JOBS)
	@echo "$(C_GREEN)>>> 编译完成: $(BUILD_DIR)/bin/$(C_RESET)"

# ==============================================================================
# 测试
# ==============================================================================
test: build
	@echo "$(C_GREEN)>>> 运行测试...$(C_RESET)"
	@cd $(BUILD_DIR) && ctest --output-on-failure --parallel $(JOBS)

benchmark: build
	@echo "$(C_GREEN)>>> 运行性能基准测试...$(C_RESET)"
	@cd $(BUILD_DIR) && ctest -L benchmark --output-on-failure

# ==============================================================================
# 代码质量
# ==============================================================================
format:
	@echo "$(C_GREEN)>>> 格式化代码...$(C_RESET)"
	@find src -name '*.hpp' -o -name '*.cpp' | xargs clang-format -i

lint:
	@echo "$(C_GREEN)>>> 静态分析...$(C_RESET)"
	@find src -name '*.hpp' -o -name '*.cpp' | xargs clang-tidy -p $(BUILD_DIR)

# ==============================================================================
# 安装
# ==============================================================================
install: build
	@echo "$(C_GREEN)>>> 安装到 $(INSTALL_PREFIX)...$(C_RESET)"
	@cmake --install $(BUILD_DIR)

# ==============================================================================
# 打包
# ==============================================================================
package: build
	@echo "$(C_GREEN)>>> 生成安装包...$(C_RESET)"
	@cd $(BUILD_DIR) && cpack -G TGZ
	@echo "$(C_GREEN)>>> 安装包已生成: $(BUILD_DIR)/*.tar.gz$(C_RESET)"

# ==============================================================================
# 运行
# ==============================================================================
run-core: build
	@echo "$(C_GREEN)>>> 启动核心交易进程...$(C_RESET)"
	@$(BUILD_DIR)/bin/trading_core

run-backend: build
	@echo "$(C_GREEN)>>> 启动后端服务...$(C_RESET)"
	@$(BUILD_DIR)/bin/backend_server

# ==============================================================================
# 清理
# ==============================================================================
clean:
	@echo "$(C_GREEN)>>> 清理构建产物...$(C_RESET)"
	@rm -rf $(BUILD_DIR)
	@rm -f compile_commands.json
	@echo "$(C_GREEN)>>> 清理完成$(C_RESET)"

distclean: clean
	@echo "$(C_GREEN)>>> 完全清理（含依赖）...$(C_RESET)"
	@rm -rf CMakeUserPresets.json
	@echo "$(C_GREEN)>>> 完全清理完成$(C_RESET)"

# ==============================================================================
# 帮助
# ==============================================================================
help:
	@echo "========== $(PROJECT_NAME) 构建系统 =========="
	@echo ""
	@echo "  构建:"
	@echo "    make                     默认构建（Release）"
	@echo "    make BUILD_TYPE=Debug    调试构建"
	@echo "    make JOBS=8              指定并行数"
	@echo "    make PKG_MANAGER=vcpkg   使用 vcpkg"
	@echo ""
	@echo "  测试:"
	@echo "    make test                运行单元测试"
	@echo "    make benchmark           运行性能基准测试"
	@echo ""
	@echo "  部署:"
	@echo "    make install             安装到 INSTALL_PREFIX"
	@echo "    make package             生成 tar.gz 安装包"
	@echo ""
	@echo "  运行:"
	@echo "    make run-core            启动核心交易进程"
	@echo "    make run-backend         启动后端服务"
	@echo ""
	@echo "  维护:"
	@echo "    make format              格式化代码"
	@echo "    make lint                静态分析"
	@echo "    make clean               清理构建产物"
	@echo "    make distclean           完全清理"
	@echo ""
	@echo "  变量:"
	@echo "    BUILD_TYPE   构建类型（Release/Debug/RelWithDebInfo）"
	@echo "    JOBS         并行任务数（默认自动检测）"
	@echo "    PKG_MANAGER  包管理器（conan/vcpkg/system）"
	@echo "    VCPKG_ROOT   vcpkg 安装路径"
	@echo "    CCACHE       编译器缓存（自动检测）"
	@echo "    MOLD         快速链接器（自动检测）"
	@echo "=============================================="
