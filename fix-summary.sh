#!/bin/bash

# 修复 GitBook 目录结构
# 使用方法: ./fix-summary.sh

echo "🔧 修复 GitBook SUMMARY.md"
echo ""

# 检查文件是否存在
if [ ! -f "SUMMARY.md" ]; then
    echo "❌ 错误: 找不到 SUMMARY.md 文件"
    echo "请确保在项目根目录运行此脚本"
    exit 1
fi

# 备份原文件
echo "📦 备份原文件..."
cp SUMMARY.md SUMMARY.md.backup
echo "✅ 备份完成: SUMMARY.md.backup"
echo ""

# 创建新的 SUMMARY.md（移除锚点链接）
echo "📝 创建修正后的 SUMMARY.md..."
cat > SUMMARY.md << 'EOF'
# Summary

## 简介

* [前言](INTRO.md)

## 并发编程

* [LMAX Disruptor](concurrent/disruptor.md)

## 分布式系统

* [待添加]()

## 消息队列

* [待添加]()

## 数据库

* [待添加]()

## 系统设计

* [待添加]()
EOF

echo "✅ SUMMARY.md 已更新"
echo ""

# 显示变更
echo "📋 变更内容:"
echo "   移除了 LMAX Disruptor 下的子章节锚点链接"
echo "   GitBook 会自动从文档内容生成页面内目录"
echo ""

# 询问是否提交
read -p "是否提交到 Git? (y/N): " DO_COMMIT
if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
    echo ""
    echo "💾 提交更改..."
    git add SUMMARY.md
    git commit -m "修复: 移除 SUMMARY.md 中不支持的锚点链接"
    
    read -p "是否推送到 GitHub? (y/N): " DO_PUSH
    if [[ "$DO_PUSH" =~ ^[Yy]$ ]]; then
        git push
        echo "✅ 已推送到 GitHub"
        echo ""
        echo "⏰ GitBook 将在 1-2 分钟内自动同步"
        echo "📖 稍后访问你的 GitBook 查看效果"
    fi
else
    echo ""
    echo "ℹ️  未提交更改"
    echo "如需恢复原文件，运行: mv SUMMARY.md.backup SUMMARY.md"
fi

echo ""
echo "============================================"
echo "✅ 修复完成！"
echo "============================================"
echo ""
echo "说明:"
echo "- GitBook 不支持在目录中使用锚点链接"
echo "- 打开 Disruptor 页面后，GitBook 会自动显示页面内目录"
echo "- 用户可以通过页面内的标题进行导航"
echo ""
