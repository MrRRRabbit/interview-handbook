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

### Adding New Content

1. Create markdown file in appropriate directory
2. Add entry to `SUMMARY.md` to include in navigation
3. Commit and push - GitBook syncs automatically
