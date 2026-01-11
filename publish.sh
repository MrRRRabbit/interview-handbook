#!/bin/bash

# GitBook 快速发布脚本
# 使用方法: ./publish.sh "提交信息"

set -e

echo "=== GitBook 发布助手 ==="

# 检查是否提供了提交信息
if [ -z "$1" ]; then
    echo "❌ 错误: 请提供提交信息"
    echo "用法: ./publish.sh \"更新了某某内容\""
    exit 1
fi

COMMIT_MSG="$1"

# 检查是否在 Git 仓库中
if [ ! -d ".git" ]; then
    echo "❌ 错误: 当前目录不是 Git 仓库"
    echo "请先运行: git init"
    exit 1
fi

# 检查是否有未提交的更改
if [ -z "$(git status --porcelain)" ]; then
    echo "ℹ️  没有需要提交的更改"
    exit 0
fi

echo "📝 准备提交更改..."

# 显示将要提交的文件
echo ""
echo "将要提交的文件:"
git status --short
echo ""

# 添加所有更改
echo "📦 添加文件到暂存区..."
git add .

# 提交
echo "💾 提交更改..."
git commit -m "$COMMIT_MSG"

# 推送
echo "🚀 推送到 GitHub..."
git push

echo ""
echo "✅ 完成! 你的更改已推送到 GitHub"
echo "📖 GitBook 将在 1-2 分钟内自动同步"
echo ""
echo "在线文档: https://mrrrrabbit.gitbook.io/interview-handbook"
