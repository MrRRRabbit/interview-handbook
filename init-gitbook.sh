#!/bin/bash

# GitBook 项目初始化脚本（macOS 兼容版本）
# 使用方法: ./init-gitbook.sh

set -e

echo "=== GitBook 项目初始化 ==="
echo ""

# 检查是否已经是 Git 仓库
if [ -d ".git" ]; then
    echo "⚠️  警告: 已经是 Git 仓库，跳过初始化"
else
    echo "📦 初始化 Git 仓库..."
    git init
    echo "✅ Git 仓库初始化完成"
fi

echo ""
echo "📝 请提供以下信息:"
echo ""

# 获取 GitHub 用户名
read -p "GitHub 用户名: " GITHUB_USERNAME
if [ -z "$GITHUB_USERNAME" ]; then
    echo "❌ 用户名不能为空"
    exit 1
fi

# 获取仓库名
read -p "GitHub 仓库名 (默认: interview-handbook): " REPO_NAME
REPO_NAME=${REPO_NAME:-interview-handbook}

# 更新 GITHUB_README.md 中的占位符
echo ""
echo "📄 更新 README 文件..."

# macOS 使用 sed -i '' 语法
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/你的用户名/$GITHUB_USERNAME/g" GITHUB_README.md
    sed -i '' "s/interview-handbook/$REPO_NAME/g" GITHUB_README.md
else
    # Linux
    sed -i "s/你的用户名/$GITHUB_USERNAME/g" GITHUB_README.md
    sed -i "s/interview-handbook/$REPO_NAME/g" GITHUB_README.md
fi

# 将 GITHUB_README.md 重命名为 README.md（用于 GitHub 显示）
# 保留原 README.md 为 INTRO.md（用于 GitBook 首页）
if [ -f "README.md" ]; then
    mv README.md INTRO.md
fi
mv GITHUB_README.md README.md

# 更新 SUMMARY.md
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|README.md|INTRO.md|g" SUMMARY.md
    sed -i '' "s|README.md|INTRO.md|g" book.json
    sed -i '' "s/你的用户名/$GITHUB_USERNAME/g" publish.sh
    sed -i '' "s/interview-handbook/$REPO_NAME/g" publish.sh
else
    sed -i "s|README.md|INTRO.md|g" SUMMARY.md
    sed -i "s|README.md|INTRO.md|g" book.json
    sed -i "s/你的用户名/$GITHUB_USERNAME/g" publish.sh
    sed -i "s/interview-handbook/$REPO_NAME/g" publish.sh
fi

echo "✅ 文件更新完成"

# 首次提交
echo ""
echo "💾 创建首次提交..."
git add .
git commit -m "Initial commit: 后端技术面试复习手册"
echo "✅ 首次提交完成"

# 提示后续步骤
echo ""
echo "============================================"
echo "✅ 初始化完成！"
echo "============================================"
echo ""
echo "接下来的步骤:"
echo ""
echo "1️⃣  在 GitHub 创建仓库:"
echo "   访问: https://github.com/new"
echo "   仓库名: $REPO_NAME"
echo "   不要初始化 README、.gitignore 或 License"
echo ""
echo "2️⃣  关联并推送到 GitHub:"
echo "   git remote add origin https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "3️⃣  连接到 GitBook:"
echo "   访问: https://app.gitbook.com"
echo "   选择 'Create new space' → 'Import from GitHub'"
echo "   选择仓库: $REPO_NAME"
echo ""
echo "4️⃣  后续更新只需运行:"
echo "   ./publish.sh \"更新说明\""
echo ""
echo "📖 在线文档将在: https://$GITHUB_USERNAME.gitbook.io/$REPO_NAME"
echo "============================================"
