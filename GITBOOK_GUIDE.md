# GitBook 发布和维护指南

## 方式一：使用 GitBook 官网（推荐）

### 1. 创建 GitBook 账号

访问 [https://www.gitbook.com](https://www.gitbook.com) 并注册账号。

### 2. 与 GitHub 集成（推荐方式）

#### 步骤 1: 创建 GitHub 仓库

```bash
# 在本地初始化 Git 仓库
cd /path/to/your/gitbook
git init

# 添加所有文件
git add .
git commit -m "Initial commit: 后端技术面试复习手册"

# 在 GitHub 创建仓库后，关联远程仓库
git remote add origin https://github.com/你的用户名/interview-handbook.git
git branch -M main
git push -u origin main
```

#### 步骤 2: 在 GitBook 中导入 GitHub 仓库

1. 登录 GitBook
2. 点击 "New Space" 或 "Create a new space"
3. 选择 "Import from GitHub"
4. 授权 GitBook 访问你的 GitHub
5. 选择刚创建的仓库
6. 选择分支（通常是 main）
7. 点击 "Import"

#### 步骤 3: 配置同步

GitBook 会自动监听 GitHub 仓库的变化：
- 推送到 GitHub → 自动更新 GitBook
- 在 GitBook 编辑 → 自动提交到 GitHub

### 3. 直接在 GitBook 编辑（不推荐）

你也可以直接在 GitBook 网页编辑器中创建和编辑内容，但这样会失去 Git 版本控制的优势。

## 方式二：使用 GitBook CLI（传统方式，已不再推荐）

> ⚠️ 注意：GitBook CLI 已经不再维护，官方推荐使用 GitBook.com 平台

如果仍想本地构建：

```bash
# 安装 GitBook CLI
npm install -g gitbook-cli

# 初始化（如果还没有 book.json）
gitbook init

# 安装插件
gitbook install

# 本地预览（访问 http://localhost:4000）
gitbook serve

# 构建静态网站到 _book 目录
gitbook build

# 部署到 GitHub Pages
# 1. 创建 gh-pages 分支
git checkout --orphan gh-pages
git rm -rf .
cp -r _book/* .
git add .
git commit -m "Publish book"
git push origin gh-pages

# 2. 在 GitHub 仓库设置中启用 GitHub Pages
```

## 推荐的工作流程

### 方案 A: GitHub + GitBook.com（最推荐）

```
本地编辑 → Git 提交 → GitHub → GitBook 自动同步 → 在线文档
```

**优势:**
- 版本控制完善
- 自动化发布
- 支持协作
- 免费托管
- 专业的阅读体验

**步骤:**

```bash
# 1. 本地修改文档
vim concurrent/disruptor.md

# 2. 提交到 Git
git add .
git commit -m "更新 Disruptor 文档"
git push origin main

# 3. GitBook 自动更新（无需操作）
```

### 方案 B: 纯 GitHub Pages

```
本地编辑 → GitBook CLI 构建 → GitHub Pages
```

**适用场景:** 想要完全自主控制，不依赖 GitBook 平台

```bash
# 构建脚本
#!/bin/bash

# 构建
gitbook build

# 发布到 GitHub Pages
git checkout gh-pages
cp -r _book/* .
git add .
git commit -m "Update documentation"
git push origin gh-pages
git checkout main
```

## 详细操作步骤

### Step 1: 准备 GitHub 仓库

```bash
# 创建 .gitignore 文件
cat > .gitignore << 'EOF'
# GitBook 构建输出
_book/
node_modules/

# 操作系统
.DS_Store
Thumbs.db

# 编辑器
.vscode/
.idea/
*.swp
EOF

# 创建 README for GitHub
cat > GITHUB_README.md << 'EOF'
# 后端技术面试复习手册

这是一份系统化的后端技术面试复习资料。

## 在线阅读

📖 [点击这里阅读完整文档](https://你的用户名.gitbook.io/interview-handbook)

## 本地运行

```bash
# 安装 GitBook CLI
npm install -g gitbook-cli

# 安装依赖
gitbook install

# 本地预览
gitbook serve
```

## 贡献

欢迎提交 Issue 和 Pull Request！
EOF

# 初始化仓库
git init
git add .
git commit -m "Initial commit"
```

### Step 2: 推送到 GitHub

```bash
# 在 GitHub 上创建新仓库（名称如 interview-handbook）

# 关联并推送
git remote add origin https://github.com/你的用户名/interview-handbook.git
git branch -M main
git push -u origin main
```

### Step 3: 连接 GitBook

1. 访问 [https://app.gitbook.com](https://app.gitbook.com)
2. 点击头像 → "Create new space"
3. 选择 "Import from GitHub"
4. 选择仓库 `interview-handbook`
5. 配置：
   - Space name: 后端技术面试复习手册
   - Description: 系统化的后端技术面试复习资料
   - Visibility: Public 或 Private
6. 点击 "Import"

### Step 4: 配置自定义域名（可选）

如果你有自己的域名：

1. 在 GitBook Space 设置中找到 "Custom domain"
2. 添加你的域名（如 `docs.yourdomain.com`）
3. 在 DNS 提供商处添加 CNAME 记录：
   ```
   CNAME docs yourdomain.gitbook.io
   ```

## 日常维护流程

### 添加新的知识点

```bash
# 1. 创建新文档
mkdir -p database
cat > database/redis.md << 'EOF'
# Redis 核心原理

## 数据结构
...
EOF

# 2. 更新目录
vim SUMMARY.md
# 添加：* [Redis](database/redis.md)

# 3. 提交
git add .
git commit -m "添加 Redis 知识点"
git push

# 4. 等待 GitBook 自动同步（约 1-2 分钟）
```

### 修改现有文档

```bash
# 1. 编辑文档
vim concurrent/disruptor.md

# 2. 本地预览（可选）
gitbook serve

# 3. 提交
git add concurrent/disruptor.md
git commit -m "更新 Disruptor 面试要点"
git push
```

### 目录结构建议

```
interview-handbook/
├── README.md              # GitBook 首页
├── SUMMARY.md            # 目录结构
├── book.json             # 配置文件
├── .gitignore
├── concurrent/           # 并发编程
│   ├── disruptor.md
│   ├── jmm.md
│   └── cas.md
├── distributed/          # 分布式系统
│   ├── cap.md
│   ├── consensus.md
│   └── distributed-lock.md
├── mq/                   # 消息队列
│   ├── kafka.md
│   ├── rabbitmq.md
│   └── rocketmq.md
├── database/             # 数据库
│   ├── mysql.md
│   ├── redis.md
│   └── mongodb.md
└── system-design/        # 系统设计
    ├── high-availability.md
    ├── scalability.md
    └── monitoring.md
```

## 高级配置

### book.json 优化

```json
{
  "title": "后端技术面试复习手册",
  "author": "Steve",
  "description": "涵盖分布式系统、并发编程、中间件等核心技术知识点",
  "language": "zh-hans",
  "gitbook": "3.2.3",
  
  "plugins": [
    "theme-comscore",
    "expandable-chapters",
    "code",
    "splitter",
    "search-pro",
    "-lunr",
    "-search",
    "github",
    "edit-link",
    "anchors",
    "copy-code-button",
    "prism",
    "-highlight"
  ],
  
  "pluginsConfig": {
    "github": {
      "url": "https://github.com/你的用户名/interview-handbook"
    },
    "edit-link": {
      "base": "https://github.com/你的用户名/interview-handbook/edit/main",
      "label": "编辑本页"
    },
    "prism": {
      "css": [
        "prismjs/themes/prism-tomorrow.css"
      ]
    }
  }
}
```

### 添加 GitHub Actions 自动构建（可选）

创建 `.github/workflows/gitbook.yml`:

```yaml
name: Build GitBook

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Node.js
      uses: actions/setup-node@v2
      with:
        node-version: '14'
    
    - name: Install GitBook CLI
      run: npm install -g gitbook-cli
    
    - name: Install plugins
      run: gitbook install
    
    - name: Build
      run: gitbook build
    
    - name: Deploy to GitHub Pages
      uses: peaceiris/actions-gh-pages@v3
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        publish_dir: ./_book
```

## 常见问题

### Q1: GitBook 没有自动同步？

**解决方案:**
1. 检查 GitBook 中的 GitHub Integration 是否正确配置
2. 在 Space Settings → Integrations 中重新同步
3. 确认 GitHub Webhook 是否正常（Settings → Webhooks）

### Q2: 本地预览和线上显示不一致？

**原因:** GitBook.com 使用自己的渲染引擎，与 GitBook CLI 略有不同

**建议:** 以 GitBook.com 的显示为准

### Q3: 如何设置访问权限？

在 GitBook Space 设置中：
- **Public**: 任何人可访问
- **Unlisted**: 有链接的人可访问
- **Private**: 仅团队成员可访问（付费功能）

### Q4: 如何备份文档？

```bash
# 方式 1: GitHub 就是备份
git clone https://github.com/你的用户名/interview-handbook.git

# 方式 2: GitBook 也支持导出
# 在 Space Settings → Advanced → Export
```

## 最佳实践

1. **使用 Git 分支管理**: 重大更新在 develop 分支，稳定后合并到 main
2. **编写有意义的 Commit 信息**: 方便追踪变更历史
3. **定期备份**: 虽然 GitHub 已经很可靠，但定期导出一份也不错
4. **使用 Issue 跟踪**: 记录待添加的知识点
5. **添加 Contributors**: 在 README 中感谢贡献者

## 推荐工具

- **Markdown 编辑器**: 
  - VS Code + Markdown Preview Enhanced
  - Typora
  - Mark Text

- **Git GUI**: 
  - GitHub Desktop
  - SourceTree
  - GitKraken

- **协作工具**:
  - GitHub Issues（问题跟踪）
  - GitHub Projects（进度管理）
  - GitHub Discussions（讨论区）

## 总结

**推荐流程**: GitHub + GitBook.com

这样你可以：
- ✅ 用熟悉的编辑器编写
- ✅ 用 Git 管理版本
- ✅ 自动发布到专业的阅读平台
- ✅ 完全免费

需要我帮你设置具体的某个步骤吗？
