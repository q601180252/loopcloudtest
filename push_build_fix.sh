#!/bin/bash

# 推送构建修复到 GitHub

echo "=========================================="
echo "推送构建修复"
echo "=========================================="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "📝 提交信息："
git log -1 --pretty=format:"%s%n%n%b"
echo ""
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
    echo "  ✓ 在构建前自动创建 NotificationHelperOverride.swift"
    echo "  ✓ 解决了 LibreTransmitter 编译错误"
    echo ""
    echo "下一步："
    echo "  1. 访问 GitHub Actions:"
    echo "     https://github.com/q601180252/loopcloudtest/actions"
    echo ""
    echo "  2. 重新运行 '4. Build Loop' 工作流"
    echo ""
    echo "  3. 这次应该能成功编译了！"
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

