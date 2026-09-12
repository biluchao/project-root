# 贡献指南

感谢您对本量化交易系统的关注。本项目涉及真实资金交易，代码正确性直接影响资金安全。请在贡献前仔细阅读本指南。

---

## 一、行为准则

参与本项目即表示您同意遵守 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。我们致力于营造开放、包容、专业的协作环境。

---

## 二、开发环境搭建

### 2.1 前置要求

| 工具 | 最低版本 | 说明 |
|------|----------|------|
| CMake | 3.20 | 构建系统 |
| C++ 编译器 | GCC 13 / Clang 17 / MSVC 19.30 | 需支持 C++20 |
| Ninja | 1.11 | 构建后端（推荐） |
| Conan 或 vcpkg | 2.x / 最新 | 依赖管理（二选一） |
| Git | 2.40+ | 版本控制 |
| Python | 3.10+ | 辅助脚本与 AI 训练 |
| clang-format | 17+ | 代码格式化 |
| clang-tidy | 17+ | 静态分析 |
| pre-commit | 3.x | 提交前钩子 |

### 2.2 克隆与构建

```bash
# 克隆仓库
git clone https://github.com/your-org/trading-system.git
cd trading-system

# 安装 pre-commit 钩子（必须）
pre-commit install

# 使用 vcpkg 安装依赖
vcpkg install

# 或使用 Conan
conan install . --build=missing -s build_type=Release

# 构建
cmake -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
cmake --build build -j$(nproc)

# 运行测试
ctest --test-dir build --output-on-failure
