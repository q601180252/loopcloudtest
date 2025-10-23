#!/bin/bash

# LoopWorkspace 项目初始化脚本
# 此脚本用于 macOS 系统（iOS 开发环境）
# 注意：iOS 项目只能在 macOS 上开发，不支持 Windows

echo "开始初始化 LoopWorkspace 项目..."

# 设置颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${BLUE}步骤 1/4: 检查并初始化 Git 子模块...${NC}"
if git submodule update --init --recursive; then
    echo -e "${GREEN}✓ Git 子模块初始化成功${NC}"
else
    echo -e "${RED}✗ Git 子模块初始化失败${NC}"
    exit 1
fi

echo -e "\n${BLUE}步骤 2/4: 检查 Ruby 版本...${NC}"
# 设置 Homebrew Ruby 路径
export PATH="/usr/local/opt/ruby/bin:$PATH"
RUBY_VERSION=$(ruby --version)
echo "当前 Ruby 版本: $RUBY_VERSION"

if ruby -e 'exit(Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1.0"))'; then
    echo -e "${RED}✗ Ruby 版本过低，需要 >= 3.1.0${NC}"
    echo "请运行以下命令安装最新版本的 Ruby:"
    echo "  brew install ruby"
    echo "  echo 'export PATH=\"/usr/local/opt/ruby/bin:\$PATH\"' >> ~/.zshrc"
    exit 1
else
    echo -e "${GREEN}✓ Ruby 版本符合要求${NC}"
fi

echo -e "\n${BLUE}步骤 3/4: 检查并安装 Bundler...${NC}"
if ! command -v bundle &> /dev/null; then
    echo "Bundler 未安装，正在安装..."
    gem install bundler:2.6.2
fi
echo -e "${GREEN}✓ Bundler 已就绪${NC}"

echo -e "\n${BLUE}步骤 4/4: 安装 Ruby 依赖 (fastlane 等)...${NC}"
if bundle install; then
    echo -e "${GREEN}✓ Ruby 依赖安装成功${NC}"
else
    echo -e "${RED}✗ Ruby 依赖安装失败${NC}"
    exit 1
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}项目初始化完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "接下来的步骤："
echo "1. 在 Xcode 中打开项目："
echo "   xed ."
echo ""
echo "2. 如需在真机上构建，请编辑 LoopConfigOverride.xcconfig 文件"
echo "   取消注释 LOOP_DEVELOPMENT_TEAM 并填入你的开发团队 ID"
echo ""
echo "3. 选择 'LoopWorkspace' scheme 进行构建"
echo ""

