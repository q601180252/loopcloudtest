#!/bin/bash

# 提交 Bundle ID 更新到 Git

echo "=========================================="
echo "提交 Bundle ID 更新（loopkit → loopkit3）"
echo "=========================================="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "📋 将要提交的文件："
echo ""
echo "修改的文件："
echo "  ✓ fastlane/Fastfile"
echo "  ✓ .github/workflows/2_add_identifiers.yml"
echo ""
echo "新增的文件："
echo "  ✓ 自定义Bundle_ID说明.md"
echo ""

read -p "是否继续提交？(y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消提交"
    exit 0
fi

echo ""
echo "正在添加文件到 Git..."

# 添加文件
git add fastlane/Fastfile
git add .github/workflows/2_add_identifiers.yml
git add 自定义Bundle_ID说明.md

echo "✅ 文件已添加到暂存区"
echo ""

# 提交
echo "正在提交..."
git commit -m "Update bundle IDs from loopkit to loopkit3

Changes:
- Update all bundle ID references in Fastfile
  * com.TEAMID.loopkit.* → com.TEAMID.loopkit3.*
- Update App Group identifier in workflow messages
  * group.com.TEAMID.loopkit.LoopGroup → group.com.TEAMID.loopkit3.LoopGroup
- Add documentation for custom bundle ID configuration

Bundle IDs updated:
- com.HHZN32E89C.loopkit3.Loop
- com.HHZN32E89C.loopkit3.Loop.statuswidget
- com.HHZN32E89C.loopkit3.Loop.LoopWatch
- com.HHZN32E89C.loopkit3.Loop.LoopWatch.watchkitextension
- com.HHZN32E89C.loopkit3.Loop.Loop-Intent-Extension
- com.HHZN32E89C.loopkit3.Loop.LoopWidgetExtension"

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
    echo "2. 在 App Store Connect 创建 App："
    echo "   https://appstoreconnect.apple.com/apps"
    echo "   Bundle ID: com.HHZN32E89C.loopkit3.Loop"
    echo ""
    echo "3. 重新运行构建工作流："
    echo "   GitHub Actions → 4. Build Loop → Run workflow"
    echo ""
    echo "详细说明请查看：自定义Bundle_ID说明.md"
    echo ""
else
    echo ""
    echo "❌ 提交失败，请检查错误信息"
    exit 1
fi

