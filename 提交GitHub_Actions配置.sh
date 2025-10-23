#!/bin/bash

# 提交 GitHub Actions 配置到 Git
# 此脚本会将所有新增的 GitHub Actions 相关文件提交到 git

echo "=========================================="
echo "提交 GitHub Actions 配置到 Git"
echo "=========================================="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 检查是否是 git 仓库
if [ ! -d ".git" ]; then
    echo "❌ 错误：当前目录不是 Git 仓库"
    exit 1
fi

echo "📋 将要提交的文件："
echo ""
echo "GitHub Actions 工作流："
echo "  .github/workflows/1_validate_secrets.yml"
echo "  .github/workflows/2_add_identifiers.yml"
echo "  .github/workflows/3_create_certificates.yml"
echo "  .github/workflows/4_build_loop.yml"
echo ""
echo "文档文件："
echo "  GitHub_Actions_配置指南.md"
echo "  快速参考_GitHub_Actions.md"
echo "  GitHub_Actions_README.md"
echo "  初始化说明.md"
echo ""
echo "脚本文件："
echo "  setup_github_actions.sh"
echo "  init_project.sh"
echo "  setup_env.sh"
echo "  提交GitHub_Actions配置.sh"
echo "  查看配置指南.bat"
echo ""

read -p "是否继续提交这些文件？(y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消提交"
    exit 0
fi

echo ""
echo "正在添加文件到 Git..."

# 添加文件
git add .github/workflows/
git add *配置指南.md
git add GitHub_Actions_README.md
git add 快速参考_GitHub_Actions.md
git add 初始化说明.md
git add setup_github_actions.sh
git add init_project.sh
git add setup_env.sh
git add 提交GitHub_Actions配置.sh
git add 查看配置指南.bat

echo "✅ 文件已添加到暂存区"
echo ""

# 显示状态
echo "Git 状态："
git status --short
echo ""

# 提交
echo "正在提交..."
git commit -m "Add GitHub Actions workflows for automatic IPA build

- Add 4 GitHub Actions workflows:
  * 1_validate_secrets.yml - Validate configuration secrets
  * 2_add_identifiers.yml - Add app identifiers
  * 3_create_certificates.yml - Create and manage certificates
  * 4_build_loop.yml - Build and upload to TestFlight with scheduled builds

- Add comprehensive documentation:
  * GitHub_Actions_配置指南.md - Complete configuration guide (Chinese)
  * 快速参考_GitHub_Actions.md - Quick reference guide
  * GitHub_Actions_README.md - Overview and summary
  * 初始化说明.md - Project initialization guide

- Add helper scripts:
  * setup_github_actions.sh - GitHub Actions setup assistant
  * init_project.sh - Project initialization script
  * setup_env.sh - Environment setup script
  * 查看配置指南.bat - Windows documentation viewer

Features:
- Automatic weekly build checks (Wednesdays 08:00 UTC)
- Automatic monthly builds (1st of month 06:00 UTC)
- Automatic certificate renewal
- Keep-alive mechanism to prevent Actions from being disabled
- Complete Chinese documentation and guides"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 提交成功！"
    echo ""
    echo "=========================================="
    echo "下一步操作"
    echo "=========================================="
    echo ""
    echo "1. 推送到 GitHub："
    echo "   git push"
    echo ""
    echo "2. 或者推送到特定远程分支："
    echo "   git push origin main"
    echo ""
    echo "3. 推送后，访问你的 GitHub 仓库："
    echo "   - 进入 Settings → Secrets and variables → Actions"
    echo "   - 添加 6 个必需的 secrets"
    echo "   - 进入 Actions 标签运行工作流"
    echo ""
    echo "详细配置步骤请查看：GitHub_Actions_配置指南.md"
    echo ""
else
    echo ""
    echo "❌ 提交失败，请检查错误信息"
    exit 1
fi

