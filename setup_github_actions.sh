#!/bin/bash

# GitHub Actions 设置辅助脚本
# 用于创建 alive 分支和显示配置状态

echo "=========================================="
echo "GitHub Actions 设置助手"
echo "=========================================="
echo ""

# 获取当前目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 检查是否是 git 仓库
if [ ! -d ".git" ]; then
    echo "❌ 错误：当前目录不是 Git 仓库"
    echo "请确保在 LoopWorkspace 项目根目录下运行此脚本"
    exit 1
fi

echo "✅ Git 仓库检测成功"
echo ""

# 检查 .github/workflows 目录
if [ ! -d ".github/workflows" ]; then
    echo "❌ 错误：未找到 .github/workflows 目录"
    echo "请先运行项目初始化"
    exit 1
fi

echo "✅ GitHub Actions 工作流文件存在"
echo ""

# 列出工作流文件
echo "📋 已配置的工作流："
ls -1 .github/workflows/ | while read file; do
    echo "   - $file"
done
echo ""

# 检查是否有 alive 分支
if git show-ref --verify --quiet refs/heads/alive; then
    echo "✅ alive 分支已存在"
else
    echo "⚠️  alive 分支不存在"
    echo ""
    read -p "是否创建 alive 分支？(y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 创建 alive 分支
        git checkout -b alive 2>/dev/null || git checkout alive
        echo "Keep alive branch for GitHub Actions" > keep_alive.txt
        git add keep_alive.txt
        git commit -m "Initialize alive branch for GitHub Actions keep-alive"
        echo "✅ alive 分支创建成功"
        echo ""
        echo "⚠️  请推送 alive 分支到远程："
        echo "   git push -u origin alive"
        git checkout main 2>/dev/null || git checkout master
    fi
fi
echo ""

echo "=========================================="
echo "配置检查清单"
echo "=========================================="
echo ""

echo "📝 GitHub Secrets（需要在 GitHub 网页配置）："
echo "   [ ] TEAMID"
echo "   [ ] FASTLANE_ISSUER_ID"
echo "   [ ] FASTLANE_KEY_ID"
echo "   [ ] FASTLANE_KEY"
echo "   [ ] GH_PAT"
echo "   [ ] MATCH_PASSWORD"
echo ""

echo "📝 GitHub Variables（需要在 GitHub 网页配置）："
echo "   [ ] ENABLE_NUKE_CERTS = true"
echo ""

echo "📝 Apple Developer Portal 配置："
echo "   [ ] 创建 App Group"
echo "   [ ] 配置 Bundle Identifiers"
echo "   [ ] 添加 Time Sensitive Notifications"
echo ""

echo "📝 App Store Connect 配置："
echo "   [ ] 创建 Loop app"
echo "   [ ] 添加测试用户"
echo ""

echo "=========================================="
echo "下一步操作"
echo "=========================================="
echo ""

echo "1. 将代码推送到 GitHub:"
echo "   git add ."
echo "   git commit -m 'Add GitHub Actions workflows'"
echo "   git push"
echo ""

echo "2. 在 GitHub 配置 Secrets:"
echo "   访问: https://github.com/你的用户名/LoopWorkspace/settings/secrets/actions"
echo ""

echo "3. 查看详细配置指南:"
echo "   cat GitHub_Actions_配置指南.md"
echo ""

echo "4. 查看快速参考:"
echo "   cat 快速参考_GitHub_Actions.md"
echo ""

echo "✅ 设置助手运行完成！"

