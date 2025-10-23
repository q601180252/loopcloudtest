#!/bin/bash

# 推送 Swift 6 兼容性修复到 GitHub

echo "=========================================="
echo "推送 Swift 6 兼容性修复"
echo "=========================================="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "📝 待推送的提交："
echo ""
git log origin/main..HEAD --oneline
echo ""

read -p "确认推送？(y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消推送"
    exit 0
fi

echo ""
echo "正在推送到 GitHub..."
git push

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ 推送成功！"
    echo "=========================================="
    echo ""
    echo "修复内容："
    echo "  ✓ 自动创建 NotificationHelperOverride.swift"
    echo "  ✓ 尝试使用 Xcode 16 支持 Swift 6"
    echo "  ✓ 添加了 fallback 逻辑"
    echo ""
    echo "=========================================="
    echo "🚀 下一步：重新运行构建"
    echo "=========================================="
    echo ""
    echo "1. 访问 GitHub Actions:"
    echo "   https://github.com/q601180252/loopcloudtest/actions"
    echo ""
    echo "2. 选择 '4. Build Loop' 工作流"
    echo ""
    echo "3. 点击 'Run workflow' → 'Run workflow'"
    echo ""
    echo "4. 观察构建日志，查看是否使用了 Xcode 16"
    echo ""
    echo "=========================================="
    echo "📊 如何检查 Xcode 版本"
    echo "=========================================="
    echo ""
    echo "在构建日志中查找："
    echo "  • 'Using Xcode 16.0' - 表示使用了 Xcode 16 ✅"
    echo "  • 'Using Xcode 15.4' - 表示 fallback 到 15.4 ⚠️"
    echo ""
    echo "如果使用了 Xcode 15.4，可能还会遇到 @retroactive 错误"
    echo ""
    echo "=========================================="
    echo "🔧 如果仍然失败"
    echo "=========================================="
    echo ""
    echo "查看备选方案："
    echo "  cat 备选_移除retroactive.patch"
    echo ""
    echo "查看详细说明："
    echo "  cat Swift6兼容性问题说明.md"
    echo ""
else
    echo ""
    echo "=========================================="
    echo "❌ 推送失败"
    echo "=========================================="
    echo ""
    echo "请手动推送："
    echo "  git push"
    echo ""
fi

