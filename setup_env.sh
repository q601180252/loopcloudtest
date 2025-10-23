#!/bin/bash
# 设置项目所需的环境变量
# 将此文件 source 到你的 shell 配置文件中

export PATH="/usr/local/opt/ruby/bin:$PATH"
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:$PATH"

echo "✓ LoopWorkspace 环境变量已设置"
echo "  Ruby: $(ruby --version | cut -d' ' -f1-2)"
echo "  Bundler: $(bundle --version)"

