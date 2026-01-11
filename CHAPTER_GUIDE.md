# GitBook 章节管理指南

本文档说明如何为 GitBook 添加和管理新章节。

## 📁 标准章节结构

每个大章节应该包含：

```
chapter-name/
├── README.md              # 章节大纲（必需）
├── section1/             # 子章节目录
│   ├── README.md         # 子章节概述
│   ├── topic1.md         # 具体主题
│   └── topic2.md
├── section2/
│   └── ...
└── cases/                # 实战案例（可选）
    └── ...
```

## 🎯 章节大纲模板

每个章节的 `README.md` 应包含以下部分：

### 1. 简介
- 章节概述
- 学习价值

### 2. 学习路线
```
基础 → 进阶 → 实战
```

### 3. 核心内容
按部分组织，每部分包含：
- 内容概述
- 子主题列表
- 学习时长
- 难度评级

### 4. 面试高频考点
- 必须掌握（5 星）
- 深入理解（4 星）
- 实战能力（5 星）

### 5. 推荐学习资源
- 书籍
- 博客/文章
- 开源项目

### 6. 学习建议
- 理论与实践结合
- 画图理解
- 阅读源码
- 动手实验
- 写总结

### 7. 学习检查清单
- [ ] 每个阶段的验收标准

### 8. 开始学习
- 不同基础的学习建议
- 预计学习时间
- 学习节奏建议

## 🚀 添加新章节的步骤

### 步骤 1: 使用模板创建大纲

```bash
# 复制模板
cp CHAPTER_TEMPLATE.md <chapter-name>/README.md

# 编辑大纲
vim <chapter-name>/README.md
```

### 步骤 2: 创建子目录结构

```bash
# 创建子章节目录
mkdir -p <chapter-name>/section1
mkdir -p <chapter-name>/section2
mkdir -p <chapter-name>/cases

# 创建占位符文件
touch <chapter-name>/section1/README.md
```

### 步骤 3: 更新 SUMMARY.md

在 `SUMMARY.md` 中添加章节链接：

```markdown
## 章节名称

* [知识体系大纲](chapter-name/README.md)
* [子章节 1](chapter-name/section1/README.md)
  * [具体主题 1](chapter-name/section1/topic1.md)
  * [具体主题 2](chapter-name/section1/topic2.md)
* [子章节 2](chapter-name/section2/README.md)
* [实战案例](chapter-name/cases/README.md)
```

### 步骤 4: 提交更改

```bash
git add .
git commit -m "新增: <章节名称>知识体系大纲"
git push
```

### 步骤 5: 等待 GitBook 同步

GitBook 会在 1-2 分钟内自动同步更新。

## 📝 编写内容的最佳实践

### 1. 标题层级

```markdown
# 章节标题（H1）- 仅用于页面主标题
## 大节（H2）- 主要段落
### 小节（H3）- 子段落
#### 细节（H4）- 详细说明
```

**注意**: GitBook 会根据 H2 和 H3 自动生成页面内目录。

### 2. 代码块

使用语言标识以启用语法高亮：

```markdown
​```java
public class Example {
    public static void main(String[] args) {
        System.out.println("Hello");
    }
}
​```
```

### 3. 强调重点

```markdown
- **加粗**：重要概念
- *斜体*：术语
- `代码`：类名、方法名
- > 引用：重要说明
```

### 4. 列表使用

```markdown
无序列表：
- 项目 1
- 项目 2

有序列表：
1. 步骤 1
2. 步骤 2

任务列表：
- [ ] 待完成
- [x] 已完成
```

### 5. 链接引用

```markdown
# 章内链接
[跳转到某章节](#章节标题)

# 跨文件链接
[参见 JMM](../foundation/jmm.md)

# 外部链接
[Java 文档](https://docs.oracle.com/javase/)
```

### 6. 图片

```markdown
![图片描述](./images/diagram.png)
```

建议：
- 创建 `images/` 目录存放图片
- 使用有意义的文件名
- 添加 alt 文本

### 7. 表格

```markdown
| 特性 | 方案 A | 方案 B |
|------|--------|--------|
| 性能 | 高 | 中 |
| 复杂度 | 高 | 低 |
```

### 8. 注意事项

```markdown
> ⚠️ **注意**: 这里有个重要提醒

> 💡 **提示**: 这是一个小技巧

> ✅ **最佳实践**: 推荐这样做

> ❌ **避免**: 不要这样做
```

## 🎨 章节命名规范

### 目录命名
- 使用小写字母
- 单词间用连字符分隔
- 英文命名（便于 URL）

```
✅ 好的命名:
concurrent/
lock-free/
distributed-system/

❌ 不好的命名:
并发编程/
LockFree/
distributed_system/
```

### 文件命名
- 使用小写字母
- 具有描述性
- .md 扩展名

```
✅ 好的命名:
jmm.md
cas-aba.md
best-practices.md

❌ 不好的命名:
1.md
文档.md
BestPractices.md
```

## 🔄 更新现有章节

### 添加新主题

1. 创建新的 .md 文件
2. 在相应的 README.md 中添加待办项
3. 更新 SUMMARY.md
4. 提交推送

### 重构章节结构

1. 备份原文件
2. 调整目录结构
3. 更新所有内部链接
4. 更新 SUMMARY.md
5. 测试所有链接是否正常

## 📊 进度跟踪

在每个章节的 README.md 中使用任务列表跟踪进度：

```markdown
## 待添加的主题

### 基础理论
- [x] 并发编程基础 ✅ 2024-01-15
- [ ] Java 内存模型 🚧 进行中
- [ ] CPU 缓存架构 📅 计划中

### 核心技术
- [ ] CAS 与原子操作
- [ ] 无锁数据结构
```

图例：
- ✅ 已完成
- 🚧 进行中
- 📅 计划中
- ⏸️ 暂停

## 🎯 内容质量标准

每篇文档应该包含：

### 必须有
- [ ] 清晰的标题和简介
- [ ] 核心概念的解释
- [ ] 代码示例（如适用）
- [ ] 关键点总结

### 建议有
- [ ] 原理图解
- [ ] 对比分析
- [ ] 实际应用场景
- [ ] 常见陷阱
- [ ] 面试要点
- [ ] 参考资料

### 可选
- [ ] 历史背景
- [ ] 深入阅读链接
- [ ] 练习题

## 🔍 自检清单

发布前检查：

- [ ] 所有链接都能正常跳转
- [ ] 代码示例能够运行
- [ ] 没有错别字
- [ ] 标题层级正确
- [ ] 图片能够显示
- [ ] SUMMARY.md 已更新
- [ ] 在本地或 GitBook 预览过

## 📚 示例章节

参考 `concurrent/` 目录作为标准示例：

```
concurrent/
├── README.md              # 完整的章节大纲
├── disruptor.md           # 已完成的详细主题
├── foundation/
│   └── README.md          # 子章节占位符
├── lock-free/
│   └── README.md
├── advanced/
│   └── README.md
├── performance/
│   └── README.md
├── distributed/
│   └── README.md
└── cases/
    └── README.md
```

## 🎓 协作建议

### 多人协作
1. 认领主题：在 README.md 中标注负责人
2. 创建分支：`feature/add-jmm-chapter`
3. 提交 PR：完成后创建 Pull Request
4. 代码审查：至少一人审查后合并

### 版本管理
```bash
# 创建特性分支
git checkout -b feature/add-new-chapter

# 完成后合并到主分支
git checkout main
git merge feature/add-new-chapter
git push
```

## 🚀 快速开始

使用自动化脚本：

```bash
# 更新整体结构
./update-gitbook-structure.sh

# 查看结果
tree -L 2 concurrent/
```

手动创建新章节：

```bash
# 1. 创建目录
mkdir -p new-chapter/section1

# 2. 复制模板
cp CHAPTER_TEMPLATE.md new-chapter/README.md

# 3. 编辑大纲
vim new-chapter/README.md

# 4. 更新 SUMMARY.md
vim SUMMARY.md

# 5. 提交
git add .
git commit -m "新增: 新章节大纲"
git push
```

---

有问题？参考：
- [GitBook 官方文档](https://docs.gitbook.com)
- [Markdown 语法](https://www.markdownguide.org)
- 项目中的现有章节示例
