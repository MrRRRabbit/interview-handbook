#!/bin/bash

# 快速修复脚本 - 适用于已经运行过 init-gitbook.sh 但出错的情况
# 使用方法: ./quick-fix.sh

echo "=== GitBook 快速修复 ==="
echo ""

# 获取用户信息
read -p "GitHub 用户名 (例如: MrRRRabbit): " GITHUB_USERNAME
if [ -z "$GITHUB_USERNAME" ]; then
    echo "❌ 用户名不能为空"
    exit 1
fi

read -p "GitHub 仓库名 (默认: interview-handbook): " REPO_NAME
REPO_NAME=${REPO_NAME:-interview-handbook}

echo ""
echo "🔧 开始修复..."

# 1. 检查并创建 GITHUB_README.md（如果不存在）
if [ ! -f "GITHUB_README.md" ]; then
    echo "📝 创建 GITHUB_README.md..."
    cat > GITHUB_README.md << 'EOFREADME'
# 后端技术面试复习手册

[![GitBook](https://img.shields.io/badge/GitBook-在线阅读-blue)](https://GITHUB_USERNAME.gitbook.io/REPO_NAME)
[![GitHub](https://img.shields.io/github/stars/GITHUB_USERNAME/REPO_NAME?style=social)](https://github.com/GITHUB_USERNAME/REPO_NAME)

这是一份系统化的后端技术面试复习资料，涵盖分布式系统、并发编程、消息队列、数据库等核心技术领域的深度知识点。

## 📖 在线阅读

**[点击这里阅读完整文档](https://GITHUB_USERNAME.gitbook.io/REPO_NAME)**

## 📚 已完成内容

### 并发编程
- [x] LMAX Disruptor - 高性能无锁队列原理

## 🚀 快速开始

```bash
git clone https://github.com/GITHUB_USERNAME/REPO_NAME.git
cd REPO_NAME
```

## 🤝 贡献

欢迎提交 Pull Request！

---

**维护者**: [@GITHUB_USERNAME](https://github.com/GITHUB_USERNAME)
EOFREADME
fi

# 2. 替换占位符
echo "🔄 更新用户信息..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/GITHUB_USERNAME/$GITHUB_USERNAME/g" GITHUB_README.md
    sed -i '' "s/REPO_NAME/$REPO_NAME/g" GITHUB_README.md
    
    if [ -f "publish.sh" ]; then
        sed -i '' "s/你的用户名/$GITHUB_USERNAME/g" publish.sh
        sed -i '' "s/interview-handbook/$REPO_NAME/g" publish.sh
    fi
else
    # Linux
    sed -i "s/GITHUB_USERNAME/$GITHUB_USERNAME/g" GITHUB_README.md
    sed -i "s/REPO_NAME/$REPO_NAME/g" GITHUB_README.md
    
    if [ -f "publish.sh" ]; then
        sed -i "s/你的用户名/$GITHUB_USERNAME/g" publish.sh
        sed -i "s/interview-handbook/$REPO_NAME/g" publish.sh
    fi
fi

# 3. 重组文件结构
echo "📁 重组文件结构..."

# 如果 README.md 存在且不是 GitHub 版本，改名为 INTRO.md
if [ -f "README.md" ] && ! grep -q "GitBook.*在线阅读" README.md; then
    echo "   - README.md → INTRO.md"
    mv README.md INTRO.md
fi

# 将 GITHUB_README.md 改为 README.md
if [ -f "GITHUB_README.md" ]; then
    echo "   - GITHUB_README.md → README.md"
    mv GITHUB_README.md README.md
fi

# 4. 更新 SUMMARY.md
if [ -f "SUMMARY.md" ]; then
    echo "🔄 更新目录文件..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's|^\* \[前言\](README.md)|* [前言](INTRO.md)|g' SUMMARY.md
    else
        sed -i 's|^\* \[前言\](README.md)|* [前言](INTRO.md)|g' SUMMARY.md
    fi
fi

# 5. 更新 book.json
if [ -f "book.json" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's|"readme": "README.md"|"readme": "INTRO.md"|g' book.json
    else
        sed -i 's|"readme": "README.md"|"readme": "INTRO.md"|g' book.json
    fi
fi

echo ""
echo "✅ 修复完成！"
echo ""
echo "📁 当前文件:"
ls -lh *.md 2>/dev/null | awk '{print "   " $9}'
echo ""

# 6. 询问是否提交
if [ -d ".git" ]; then
    read -p "是否提交到 Git? (y/N): " DO_COMMIT
    if [[ "$DO_COMMIT" =~ ^[Yy]$ ]]; then
        git add .
        git commit -m "Initial commit: 后端技术面试复习手册" || git commit -m "Fix: 修复项目配置"
        echo "✅ Git 提交完成"
    fi
else
    echo "⚠️  当前目录不是 Git 仓库，跳过提交"
    read -p "是否初始化 Git 仓库? (y/N): " INIT_GIT
    if [[ "$INIT_GIT" =~ ^[Yy]$ ]]; then
        git init
        git add .
        git commit -m "Initial commit: 后端技术面试复习手册"
        echo "✅ Git 初始化完成"
    fi
fi

echo ""
echo "============================================"
echo "🎉 修复完成！后续步骤："
echo "============================================"
echo ""
echo "1️⃣  在 GitHub 创建仓库 (如果还没创建):"
echo "   https://github.com/new"
echo "   仓库名: $REPO_NAME"
echo ""
echo "2️⃣  关联并推送:"
echo "   git remote add origin https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "3️⃣  在 GitBook 导入:"
echo "   https://app.gitbook.com"
echo ""
echo "4️⃣  后续更新:"
echo "   ./publish.sh \"更新内容\""
echo ""
