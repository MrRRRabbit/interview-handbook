# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Chinese-language backend technology interview handbook (后端技术面试复习手册) built with GitBook. It covers distributed systems, concurrent programming, message queues, databases, and system design topics.

## Common Commands

```bash
# Local preview (requires gitbook-cli: npm install -g gitbook-cli)
gitbook serve

# Build static site to _book/
gitbook build

# Quick publish changes to GitHub (GitBook auto-syncs)
./publish.sh "commit message"
```

### 提交工作流
1. 完成修改后，先向用户确认修改内容
2. 用户确认后，使用 `./publish.sh "message"` 一步完成推送

## Architecture

### Content Structure

- `SUMMARY.md` - Table of contents defining navigation structure (GitBook requirement)
- `INTRO.md` - GitBook homepage (mapped via book.json)
- `book.json` - GitBook configuration (plugins, metadata, structure mapping)

### Topic Directories

Each major topic follows this pattern:
```
topic-name/
├── README.md           # Topic outline with learning path, key points, resources
└── subtopic/
    ├── README.md       # Subtopic overview
    └── specific.md     # Detailed content
```

Current topics:
- `concurrent/` - Concurrent programming (foundation, sync, lock-free, advanced, performance, distributed, cases)
- `database/` - Database systems (mysql/, redis/, sharding/)
- `distributed/` - Distributed systems
- `mq/` - Message queues
- `system-design/` - System design

### Content Templates

- `CHAPTER_TEMPLATE.md` - Standard template for new topic outlines
- `CHAPTER_GUIDE.md` - Guidelines for creating/managing chapters

## Content Conventions

### File Naming
- Directories: lowercase with hyphens (e.g., `lock-free/`, `system-design/`)
- Files: lowercase with hyphens, `.md` extension

### Document Structure
Each detailed topic document should include:
- Core concepts explanation
- Code examples (Java-focused)
- Interview key points (面试要点)
- Common pitfalls
- References

**注意**: 不要在文档中手动添加目录（如 `## 📚 目录`），GitBook 会自动生成导航。

### Adding New Content

1. Create markdown file in appropriate directory
2. Add entry to `SUMMARY.md` to include in navigation
3. Commit and push - GitBook syncs automatically

## gstack

Use the `/browse` skill from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

Available skills:
- `/office-hours` - Brainstorm new ideas
- `/plan-ceo-review` - Review a plan (strategy)
- `/plan-eng-review` - Review a plan (architecture)
- `/plan-design-review` - Review a plan (design)
- `/design-consultation` - Create a design system
- `/review` - Code review before merge
- `/ship` - Ready to deploy / create PR
- `/land-and-deploy` - Land and deploy changes
- `/canary` - Canary deployment
- `/benchmark` - Run benchmarks
- `/browse` - Web browsing (always use this)
- `/qa` - Test the app
- `/qa-only` - QA testing only
- `/design-review` - Visual design audit
- `/setup-browser-cookies` - Set up browser cookies
- `/setup-deploy` - Set up deployment
- `/retro` - Weekly retrospective
- `/investigate` - Debug errors
- `/document-release` - Post-ship doc updates
- `/codex` - Second opinion / adversarial code review
- `/cso` - Chief Security Officer review
- `/autoplan` - Auto-review a plan (all reviews at once)
- `/careful` - Working with production or live systems
- `/freeze` - Scope edits to one module/directory
- `/guard` - Maximum safety mode
- `/unfreeze` - Remove edit restrictions
- `/gstack-upgrade` - Upgrade gstack to latest version
