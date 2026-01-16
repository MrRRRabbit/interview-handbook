# MySQL 日志系统

> 日志系统是 MySQL 数据安全和高可用的基石。本章深入讲解 Redo Log、Undo Log 和 Binlog 的实现细节。
>
> 基础概念请参考 [事务 - 日志系统](transaction.md#日志系统)，本章将深入原理层面。

## 日志系统概述

### 三种核心日志

MySQL 的日志系统由三种核心日志组成，它们分别位于不同的层级：

```
                      MySQL Server 层
                    ┌──────────────────┐
                    │      Binlog      │ ─→ 主从复制、数据恢复
                    │   (二进制日志)    │
                    └────────┬─────────┘
                             │
        ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┼─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
                             │
                      InnoDB 存储引擎层
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐        ┌─────▼─────┐       ┌────▼────┐
    │Redo Log │        │ Undo Log  │       │ Buffer  │
    │ (重做)   │        │  (回滚)   │       │  Pool   │
    │ 持久性   │        │  原子性   │       │         │
    └─────────┘        └───────────┘       └─────────┘
```

### 日志与 ACID 的对应关系

| 日志 | 层级 | 保证的特性 | 核心作用 |
|------|------|-----------|---------|
| **Redo Log** | InnoDB 引擎层 | Durability（持久性） | 崩溃恢复 |
| **Undo Log** | InnoDB 引擎层 | Atomicity（原子性） | 回滚 + MVCC |
| **Binlog** | MySQL Server 层 | - | 主从复制、数据恢复 |

### 日志的协作关系

```
事务执行流程：

    BEGIN
      │
      ▼
┌─────────────┐
│ 修改数据     │ ─→ Buffer Pool（内存）
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 记录 Undo   │ ─→ 保存旧值（用于回滚）
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 记录 Redo   │ ─→ 保存新值（用于恢复）
└──────┬──────┘
       │
    COMMIT
       │
       ▼
┌─────────────┐
│ 两阶段提交   │ ─→ Redo(prepare) → Binlog → Redo(commit)
└─────────────┘
```

---

## Redo Log 深入 ⭐⭐⭐⭐⭐

Redo Log 是 InnoDB 实现持久性的核心机制，理解其工作原理对于优化 MySQL 性能至关重要。

### Redo Log 的本质

**物理日志**：记录的是对数据页的物理修改。

```
Redo Log 记录示例：
"将表空间 ID=5 的页号 100，偏移量 200 处的值改为 0x1234"

特点：
- 记录页级别的变化
- 内容紧凑，写入快
- 支持幂等性（可重复执行）
```

### 循环写机制 ⭐⭐⭐⭐⭐

Redo Log 采用**循环写**（circular write）的方式，使用固定大小的文件组。

```
Redo Log 文件组结构：
┌─────────────────────────────────────────────────┐
│              ib_logfile0 (1GB)                  │
├─────────────────────────────────────────────────┤
│              ib_logfile1 (1GB)                  │
└─────────────────────────────────────────────────┘

循环写示意图：

┌────┬────┬────┬────┬────┬────┬────┬────┐
│ 0  │ 1  │ 2  │ 3  │ 4  │ 5  │ 6  │ 7  │
└────┴────┴────┴────┴────┴────┴────┴────┘
          ↑                   ↑
     checkpoint           write pos

├─────────┤                   ├─────────┤
  可覆盖区                     待写入区
 (已刷脏页)                  (新的日志)

write pos：当前写入位置，一直往前推进
checkpoint：当前可以擦除的位置（对应的脏页已刷盘）

可用空间 = write pos 到 checkpoint 之间的区域
```

**关键理解**：
- `write pos` 追上 `checkpoint` 时，必须等待脏页刷盘
- 这也是为什么 Redo Log 不能设置太小的原因

### Log Sequence Number (LSN) ⭐⭐⭐⭐

LSN 是 Redo Log 的逻辑序列号，是一个单调递增的数字。

**LSN 的作用**：
1. **标识日志位置**：每条 Redo Log 记录都有唯一的 LSN
2. **跟踪脏页**：每个脏页记录最后修改它的 LSN
3. **判断恢复起点**：checkpoint 记录已刷盘的 LSN 位置

```sql
-- 查看当前 LSN 状态
SHOW ENGINE INNODB STATUS\G

-- 关键信息：
-- Log sequence number: 当前 LSN（最新写入）
-- Log flushed up to: 已刷盘的 LSN
-- Pages flushed up to: 脏页已刷盘到的 LSN
-- Last checkpoint at: 最后一次 checkpoint 的 LSN
```

**示例输出解读**：

```
LOG
---
Log sequence number          2638452079
Log buffer assigned up to    2638452079
Log buffer completed up to   2638452079
Log written up to            2638452079
Log flushed up to            2638452079
Added dirty pages up to      2638452079
Pages flushed up to          2638452079
Last checkpoint at           2638452079

-- 如果 Log sequence number >> Last checkpoint at
-- 说明有大量脏页未刷盘，可能需要触发 checkpoint
```

### Mini-Transaction (mtr)

Mini-Transaction 是 Redo Log 的最小写入单位，保证一组相关操作的原子性。

```
mtr 的概念：

单个 SQL 操作可能涉及多个页的修改：
UPDATE t SET a = 1 WHERE id = 10;

可能修改：
├─ 数据页（修改记录）
├─ 索引页（更新索引）
└─ Undo 页（记录旧值）

这些修改必须作为一个 mtr 原子提交到 Redo Log
```

**mtr 的特点**：
- 一个事务包含多个 mtr
- 每个 mtr 要么全部写入，要么全部不写入
- mtr 结束时会写入一个特殊的 MLOG_MULTI_REC_END 标记

### Redo Log Buffer 刷盘时机 ⭐⭐⭐⭐

Redo Log Buffer 中的内容会在以下时机刷到磁盘：

| 触发条件 | 说明 |
|---------|------|
| **事务提交** | 由 `innodb_flush_log_at_trx_commit` 控制 |
| **Buffer 空间不足** | Log Buffer 使用超过一半时触发 |
| **后台线程** | 每秒定时刷盘 |
| **Checkpoint** | 推进 checkpoint 时需要刷盘 |
| **关闭数据库** | 正常关闭时刷盘 |

### innodb_flush_log_at_trx_commit 深入 ⭐⭐⭐⭐⭐

这是控制 Redo Log 刷盘策略的核心参数：

```
┌─────────────────────────────────────────────────────┐
│               Redo Log Buffer                       │
│                   (内存)                            │
└────────────────────┬────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
      值 = 0      值 = 1      值 = 2
         │           │           │
    每秒刷盘    每次提交     每次提交
         │      fsync        write
         │           │      (不fsync)
         ▼           ▼           ▼
┌─────────────────────────────────────────────────────┐
│                 OS Page Cache                       │
└────────────────────┬────────────────────────────────┘
                     │ fsync
                     ▼
┌─────────────────────────────────────────────────────┐
│                    磁盘                              │
└─────────────────────────────────────────────────────┘
```

**详细对比**：

| 值 | 行为 | 崩溃影响 | 性能 | 适用场景 |
|----|------|---------|------|---------|
| **0** | 每秒 write + fsync | MySQL 崩溃：丢 1 秒<br>OS 崩溃：丢 1 秒 | 最高 | 非关键数据 |
| **1** | 每次提交 write + fsync | 不丢数据 | 最低 | **生产环境默认** |
| **2** | 每次提交 write，每秒 fsync | MySQL 崩溃：不丢<br>OS 崩溃：丢 1 秒 | 中等 | 允许少量丢失 |

**示例场景**：

```sql
-- 场景 1：值 = 0
BEGIN;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;  -- 只写到 Log Buffer
-- 0.5 秒后 MySQL 崩溃
-- 结果：数据丢失 ❌

-- 场景 2：值 = 1（默认）
BEGIN;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;  -- 立即 write + fsync 到磁盘
-- 0.5 秒后 MySQL 崩溃
-- 结果：数据不丢失 ✅

-- 场景 3：值 = 2
BEGIN;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;  -- 只 write 到 OS Cache
-- 0.5 秒后 OS 崩溃
-- 结果：数据可能丢失 ⚠️
```

### Checkpoint 机制详解 ⭐⭐⭐⭐

Checkpoint 是协调 Redo Log 和 Buffer Pool 的关键机制。

**为什么需要 Checkpoint**：
1. Redo Log 空间有限，需要循环使用
2. 缩短数据库恢复时间
3. 将脏页按一定频率刷到磁盘

**两种 Checkpoint 类型**：

| 类型 | 触发条件 | 特点 |
|------|---------|------|
| **Sharp Checkpoint** | 数据库关闭时 | 刷新所有脏页，停止服务 |
| **Fuzzy Checkpoint** | 运行时 | 部分刷新，不影响服务 |

**Fuzzy Checkpoint 的触发条件**：

```
1. Master Thread Checkpoint
   - 后台线程每秒/每10秒定期触发

2. FLUSH_LRU_LIST Checkpoint
   - Buffer Pool 空闲页不足时触发
   - 由参数 innodb_lru_scan_depth 控制

3. Async/Sync Flush Checkpoint
   - Redo Log 空间不足时触发
   - 根据剩余空间比例决定：
     ├─ > 75%：异步刷新
     └─ < 75%：同步刷新（阻塞）

4. Dirty Page Too Much Checkpoint
   - 脏页比例超过 innodb_max_dirty_pages_pct 时触发
```

**关键参数**：

```sql
-- 查看相关参数
SHOW VARIABLES LIKE 'innodb_max_dirty_pages_pct%';

-- innodb_max_dirty_pages_pct = 90（默认）
-- 脏页超过 90% 时强制 checkpoint

-- innodb_max_dirty_pages_pct_lwm = 10（默认）
-- 脏页超过 10% 时开始预刷新
```

### 查看 Redo Log 状态

```sql
-- 查看 Redo Log 配置
SHOW VARIABLES LIKE 'innodb_log%';

-- 常见输出：
-- innodb_log_buffer_size = 16777216 (16MB)
-- innodb_log_file_size = 50331648 (48MB)
-- innodb_log_files_in_group = 2
-- innodb_log_write_ahead_size = 8192

-- 查看 Redo Log 文件
-- 默认位置：数据目录下的 ib_logfile0, ib_logfile1
```

---

## Undo Log 深入 ⭐⭐⭐⭐⭐

Undo Log 承担两个重要职责：保证事务原子性（回滚）和支持 MVCC。

### Undo Log 的本质

**逻辑日志**：记录的是如何撤销操作的逻辑信息。

```
Undo Log 记录示例：

-- 对于 INSERT 操作：
记录主键值，回滚时执行 DELETE

-- 对于 DELETE 操作：
记录整行数据，回滚时执行 INSERT

-- 对于 UPDATE 操作：
记录旧值，回滚时执行反向 UPDATE
```

### Undo Log 的两种类型 ⭐⭐⭐⭐

| 类型 | 对应操作 | 提交后 | 用途 |
|------|---------|--------|------|
| **Insert Undo Log** | INSERT | 可立即删除 | 仅回滚 |
| **Update Undo Log** | UPDATE/DELETE | 需保留 | 回滚 + MVCC |

**为什么 Insert Undo Log 可以立即删除**：
- INSERT 的数据对其他事务不可见（不存在历史版本）
- 提交后不再需要为 MVCC 保留

**为什么 Update Undo Log 需要保留**：
- 其他事务可能需要读取旧版本（MVCC）
- 必须等到没有事务需要这个版本才能删除

### Undo Log 的存储结构 ⭐⭐⭐⭐

```
Undo Log 存储层次：

┌─────────────────────────────────────────────────────┐
│                 Undo Tablespace                     │
│              (undo001, undo002, ...)                │
├─────────────────────────────────────────────────────┤
│   ┌───────────────────────────────────────────┐     │
│   │           Rollback Segment (128个)         │     │
│   │  ┌─────────────────────────────────────┐  │     │
│   │  │          Undo Slot (1024个)          │  │     │
│   │  │  ┌─────────────────────────────┐    │  │     │
│   │  │  │        Undo Log            │    │  │     │
│   │  │  │   (事务的所有 Undo 记录)     │    │  │     │
│   │  │  └─────────────────────────────┘    │  │     │
│   │  └─────────────────────────────────────┘  │     │
│   └───────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────┘

结构关系：
- 1 个 Undo Tablespace 包含多个 Rollback Segment
- 1 个 Rollback Segment 包含 1024 个 Undo Slot
- 1 个 Undo Slot 对应 1 个事务的 Undo Log 链
```

### 版本链的形成 ⭐⭐⭐⭐⭐

每次 UPDATE 操作都会在 Undo Log 中形成一个版本节点，通过 `ROLL_PTR` 指针串联成版本链。

```
版本链示意图：

假设对 id=1 的记录进行了 3 次修改：

当前数据（表中）：
┌──────────────────────────────────────────┐
│ id=1, name='Charlie', TRX_ID=300         │
│ ROLL_PTR ────────────────────────────┐   │
└──────────────────────────────────────────┘
                                       │
                                       ▼
Undo Log 版本 1（TRX 300 的 Undo）：
┌──────────────────────────────────────────┐
│ id=1, name='Bob', TRX_ID=200             │
│ ROLL_PTR ────────────────────────────┐   │
└──────────────────────────────────────────┘
                                       │
                                       ▼
Undo Log 版本 2（TRX 200 的 Undo）：
┌──────────────────────────────────────────┐
│ id=1, name='Alice', TRX_ID=100           │
│ ROLL_PTR = NULL                          │
└──────────────────────────────────────────┘

MVCC 读取时：
- TRX 250 发起读取
- 当前版本 TRX_ID=300 > 250，不可见
- 沿 ROLL_PTR 找到 TRX_ID=200，仍 > 250，不可见
- 继续找到 TRX_ID=100 < 250，可见 ✅
- 返回 name='Alice'
```

> 详细的 MVCC 可见性判断请参考 [MVCC 原理](mvcc.md)

### Purge 机制详解 ⭐⭐⭐⭐

Purge 是清理不再需要的 Undo Log 的后台操作。

**Purge 的触发条件**：
- Undo Log 对应的事务已提交
- 没有任何活跃事务需要读取这个版本

**History List**：
```
History List 是已提交但未 Purge 的 Undo Log 链表

┌─────────────────────────────────────────────────────┐
│                    History List                     │
├─────────────────────────────────────────────────────┤
│  TRX 100 ─→ TRX 101 ─→ TRX 102 ─→ ... ─→ TRX 200   │
│  (最老)                                     (最新)   │
└─────────────────────────────────────────────────────┘

Purge 从最老的事务开始清理，需要满足：
- 该事务已提交
- 所有活跃事务的 Read View 都不需要该版本
```

**查看 History List 长度**：

```sql
-- 查看 History List 长度
SHOW ENGINE INNODB STATUS\G

-- 关注这行：
-- History list length 156

-- 如果这个数字持续增长，说明 Purge 跟不上
-- 可能原因：存在长事务阻止 Purge
```

### 长事务的危害 ⭐⭐⭐⭐⭐

长事务是 Undo Log 膨胀的主要原因。

**危害分析**：

```
场景：存在一个运行 2 小时的长事务

┌────────────────────────────────────────────────────┐
│           Time = 0                                 │
│   TRX 100 开始（长事务）                            │
│   创建 Read View，记录当前活跃事务                   │
└───────────────────────┬────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────┐
│           Time = 0 ~ 2h                            │
│   TRX 101, 102, 103, ... TRX 50000 执行并提交       │
│   所有这些事务的 Undo Log 都不能 Purge              │
│   因为 TRX 100 的 Read View 可能需要读取它们        │
└───────────────────────┬────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────┐
│           结果                                     │
│   - History List 持续增长                          │
│   - Undo Tablespace 膨胀                           │
│   - 查询性能下降（版本链过长）                       │
│   - 磁盘空间不足风险                                │
└────────────────────────────────────────────────────┘
```

**监控长事务**：

```sql
-- 查找运行时间超过 60 秒的事务
SELECT
    trx_id,
    trx_state,
    trx_started,
    trx_mysql_thread_id,
    trx_query,
    TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) AS running_seconds
FROM information_schema.INNODB_TRX
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60
ORDER BY running_seconds DESC;

-- 查看事务持有的锁
SELECT * FROM performance_schema.data_locks
WHERE ENGINE_TRANSACTION_ID = <trx_id>;
```

**预防措施**：

```sql
-- 设置事务超时时间
SET innodb_lock_wait_timeout = 10;  -- 等待锁超时
SET max_execution_time = 30000;     -- 查询超时（毫秒）

-- 监控告警
-- 配置监控系统对 History List > 10000 时告警
```

### 查看 Undo Log 状态

```sql
-- 查看 Undo Tablespace
SELECT
    TABLESPACE_NAME,
    FILE_NAME,
    ENGINE
FROM information_schema.FILES
WHERE FILE_TYPE = 'UNDO LOG';

-- 查看回滚段使用情况
SELECT
    NAME,
    SUBSYSTEM,
    COUNT,
    MAX_COUNT,
    AVG_COUNT
FROM information_schema.INNODB_METRICS
WHERE NAME LIKE '%undo%';

-- MySQL 8.0+ 查看 Undo 空间
SELECT
    TABLESPACE_NAME,
    FILE_NAME,
    TOTAL_EXTENTS,
    EXTENT_SIZE
FROM information_schema.INNODB_TABLESPACES
WHERE SPACE_TYPE = 'Undo';
```

---

## Binlog 深入 ⭐⭐⭐⭐

Binlog 是 MySQL Server 层的日志，是主从复制和数据恢复的基础。

### Binlog 的本质

**逻辑日志**：记录的是对数据的逻辑修改（SQL 语句或行变化）。

```
Binlog 与 Redo Log 的本质区别：

Redo Log（物理日志）：
"将 page 100, offset 200 的值改为 0x1234"

Binlog（逻辑日志）：
"UPDATE t SET name='Alice' WHERE id=1"
或
"id=1: name 'Bob' → 'Alice'"
```

### Binlog vs Redo Log ⭐⭐⭐⭐⭐

| 特性 | Redo Log | Binlog |
|------|----------|--------|
| **层级** | InnoDB 存储引擎层 | MySQL Server 层 |
| **类型** | 物理日志（页修改） | 逻辑日志（SQL/行变化） |
| **写入方式** | 循环写，固定大小 | 追加写，无限增长 |
| **作用** | 崩溃恢复 | 主从复制、数据恢复 |
| **存储引擎** | 仅 InnoDB | 所有存储引擎 |
| **是否必需** | InnoDB 必需 | 可选（但生产必开） |

**为什么需要两种日志**：

```
历史原因：
├─ MySQL 最初没有 InnoDB，只有 Binlog
├─ InnoDB 作为插件引入，带来了 Redo Log
└─ 两者各有用途，无法互相替代

功能差异：
├─ Redo Log：保证单机数据持久性
├─ Binlog：支持主从复制、按时间点恢复
└─ 两者配合：保证数据安全和高可用
```

### Binlog 格式详解 ⭐⭐⭐⭐⭐

Binlog 有三种格式，由 `binlog_format` 参数控制：

#### STATEMENT 格式

```sql
-- 记录 SQL 语句本身
SET binlog_format = 'STATEMENT';

UPDATE account SET balance = balance - 100 WHERE id = 1;

-- Binlog 内容：
-- UPDATE account SET balance = balance - 100 WHERE id = 1

-- 优点：
-- ✅ 日志量小
-- ✅ 易于理解和审计

-- 缺点：
-- ❌ 某些函数导致主从不一致
```

**STATEMENT 格式的问题**：

```sql
-- 问题示例 1：时间函数
UPDATE t SET create_time = NOW() WHERE id = 1;
-- 主库执行：2026-01-15 10:00:00
-- 从库执行：2026-01-15 10:00:01（复制有延迟）
-- 结果：主从数据不一致 ❌

-- 问题示例 2：随机函数
UPDATE t SET value = RAND() WHERE id = 1;
-- 主库和从库生成不同的随机数
-- 结果：主从数据不一致 ❌

-- 问题示例 3：UUID 函数
INSERT INTO t VALUES (UUID(), 'test');
-- 主库和从库生成不同的 UUID
-- 结果：主从数据不一致 ❌

-- 问题示例 4：不确定性 SQL
DELETE FROM t WHERE id > 10 LIMIT 1;
-- 如果没有 ORDER BY，删除哪一行是不确定的
-- 结果：主从可能删除不同的行 ❌
```

#### ROW 格式

```sql
-- 记录行的变化
SET binlog_format = 'ROW';

UPDATE account SET balance = balance - 100 WHERE id = 1;

-- Binlog 内容（逻辑表示）：
-- ### UPDATE account
-- ### WHERE
-- ###   id=1
-- ###   balance=1000
-- ### SET
-- ###   id=1
-- ###   balance=900

-- 优点：
-- ✅ 精确记录每行的变化
-- ✅ 保证主从一致

-- 缺点：
-- ❌ 批量操作时日志量大
-- ❌ 可读性差（需要工具解析）
```

**ROW 格式的日志量问题**：

```sql
-- 批量更新 100 万行
UPDATE t SET status = 1;

-- STATEMENT 格式：记录 1 条 SQL
-- ROW 格式：记录 100 万行的变化（Before/After 各一次）

-- 可能导致：
-- - Binlog 文件暴增
-- - 主从复制延迟
-- - 磁盘空间不足
```

#### MIXED 格式

```sql
-- 混合模式
SET binlog_format = 'MIXED';

-- 规则：
-- 1. 默认使用 STATEMENT 格式
-- 2. 当检测到不确定性 SQL 时，自动切换为 ROW 格式

-- 会触发切换为 ROW 的情况：
-- - 使用 UUID(), NOW(), RAND() 等函数
-- - 使用用户自定义函数（UDF）
-- - 使用临时表
-- - 使用 INSERT ... SELECT
```

#### 格式选择建议

| 场景 | 推荐格式 | 原因 |
|------|---------|------|
| **生产环境** | ROW | 保证主从一致性 |
| **日志量敏感** | MIXED | 折中方案 |
| **开发测试** | STATEMENT | 可读性好，方便调试 |
| **大批量更新频繁** | 谨慎使用 ROW | 考虑分批执行 |

### sync_binlog 参数 ⭐⭐⭐⭐

控制 Binlog 刷盘策略：

```
┌─────────────────────────────────────────────────────┐
│               Binlog Buffer                         │
│                  (内存)                             │
└────────────────────┬────────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
      值 = 0      值 = 1      值 = N
         │           │           │
    OS 自己     每次提交     每 N 次
     决定       fsync       提交 fsync
```

| 值 | 行为 | 性能 | 安全性 |
|----|------|------|--------|
| **0** | 由 OS 决定何时刷盘 | 最高 | 最低 |
| **1** | 每次提交都 fsync | 最低 | **最高** |
| **N** | 每 N 次提交 fsync | 中等 | 中等 |

**生产建议**：

```sql
-- 金融等高安全要求场景
sync_binlog = 1

-- 普通业务（允许少量丢失）
sync_binlog = 100

-- 批量导入数据时临时调整
sync_binlog = 0  -- 导入完成后改回
```

### Binlog 实用命令

```sql
-- 查看 Binlog 是否开启
SHOW VARIABLES LIKE 'log_bin';

-- 查看 Binlog 格式
SHOW VARIABLES LIKE 'binlog_format';

-- 查看当前使用的 Binlog 文件
SHOW MASTER STATUS;

-- 查看所有 Binlog 文件列表
SHOW BINARY LOGS;

-- 查看 Binlog 事件
SHOW BINLOG EVENTS IN 'mysql-bin.000001' LIMIT 10;

-- 手动切换 Binlog 文件
FLUSH BINARY LOGS;

-- 清理 Binlog
PURGE BINARY LOGS TO 'mysql-bin.000005';
PURGE BINARY LOGS BEFORE '2026-01-01 00:00:00';
```

**使用 mysqlbinlog 工具**：

```bash
# 查看 Binlog 内容
mysqlbinlog mysql-bin.000001

# ROW 格式解析为可读形式
mysqlbinlog --base64-output=decode-rows -v mysql-bin.000001

# 指定时间范围
mysqlbinlog --start-datetime="2026-01-15 10:00:00" \
            --stop-datetime="2026-01-15 11:00:00" \
            mysql-bin.000001

# 恢复数据到某个时间点
mysqlbinlog --stop-datetime="2026-01-15 10:30:00" \
            mysql-bin.000001 | mysql -u root -p
```

---

## 两阶段提交 ⭐⭐⭐⭐⭐

两阶段提交（2PC）是保证 Redo Log 和 Binlog 一致性的关键机制。

### 为什么需要两阶段提交

**问题场景**：如果 Redo Log 和 Binlog 分别独立写入

```
场景 1：先写 Redo Log，后写 Binlog

时间线：
├─ T1: 写 Redo Log（成功）
├─ T2: 💥 MySQL 崩溃
└─ T3: Binlog 未写入

恢复后：
├─ 主库：根据 Redo Log 恢复 → 数据存在
├─ 从库：没有收到 Binlog → 数据不存在
└─ 结果：主从不一致 ❌
```

```
场景 2：先写 Binlog，后写 Redo Log

时间线：
├─ T1: 写 Binlog（成功）
├─ T2: 💥 MySQL 崩溃
└─ T3: Redo Log 未写入

恢复后：
├─ 主库：没有 Redo Log → 数据不存在
├─ 从库：收到 Binlog 并执行 → 数据存在
└─ 结果：主从不一致 ❌
```

### 两阶段提交流程 ⭐⭐⭐⭐⭐

```
两阶段提交详细流程：

┌─────────────────────────────────────────────────────┐
│                   事务执行阶段                       │
│  1. 修改 Buffer Pool                                │
│  2. 记录 Undo Log                                   │
│  3. 记录 Redo Log（在 Redo Log Buffer）             │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼ COMMIT
┌─────────────────────────────────────────────────────┐
│              阶段 1：Prepare 阶段                    │
│                                                     │
│  将 Redo Log 写入磁盘，标记状态为 "prepare"          │
│  此时事务处于 "准备提交" 状态                        │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              写入 Binlog                            │
│                                                     │
│  将 Binlog 写入磁盘（根据 sync_binlog 参数刷盘）     │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              阶段 2：Commit 阶段                     │
│                                                     │
│  将 Redo Log 状态改为 "commit"                      │
│  事务提交完成                                       │
└─────────────────────────────────────────────────────┘
```

**简化记忆**：

```
Prepare → Binlog → Commit

Redo Log (prepare) ─→ Binlog ─→ Redo Log (commit)
        │                              │
        └──────────────────────────────┘
                   XID 关联
```

### 崩溃恢复场景分析 ⭐⭐⭐⭐⭐

根据崩溃发生的时间点，恢复策略不同：

| 崩溃时间点 | Redo Log 状态 | Binlog 状态 | 恢复策略 |
|-----------|--------------|-------------|---------|
| Prepare 之前 | 无 | 无 | 事务自然回滚 |
| Prepare 之后，Binlog 之前 | prepare | 无 | **回滚** |
| Binlog 之后，Commit 之前 | prepare | **完整** | **提交** |
| Commit 之后 | commit | 完整 | 已提交，无需处理 |

**恢复决策逻辑**：

```
崩溃恢复时的判断流程：

┌─────────────────────────────────────────────────────┐
│           扫描 Redo Log，找到所有事务                │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│         Redo Log 状态是 commit？                    │
│                                                     │
│    YES ─────────────→ 事务已提交，执行 Redo          │
│     │                                               │
│    NO（状态是 prepare）                              │
│     │                                               │
│     ▼                                               │
│  检查对应的 Binlog 是否存在且完整                    │
│                                                     │
│    完整 ─────────────→ 提交事务（执行 Redo）         │
│     │                                               │
│    不完整/不存在 ────→ 回滚事务（执行 Undo）          │
└─────────────────────────────────────────────────────┘
```

**示例场景**：

```sql
-- 场景：写完 Binlog 后崩溃

BEGIN;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;

时间线：
├─ T1: Redo Log (prepare) ✅
├─ T2: Binlog 写入 ✅
├─ T3: 💥 崩溃（Redo commit 未完成）

恢复时：
├─ 发现 Redo Log 状态为 prepare
├─ 检查 Binlog，发现该事务的 Binlog 完整
├─ 决策：提交事务
├─ 将 Redo Log 标记为 commit
└─ 结果：数据一致 ✅
```

### XID 的作用 ⭐⭐⭐⭐

XID（Transaction ID）是关联 Redo Log 和 Binlog 的纽带。

```
XID 的工作原理：

事务提交时：
├─ Redo Log 中记录：XID = 12345, status = prepare
└─ Binlog 中记录：XID = 12345

恢复时：
├─ 扫描 Redo Log，找到 prepare 状态的事务：XID = 12345
├─ 在 Binlog 中查找 XID = 12345
├─ 如果找到且完整 → 提交
└─ 如果未找到或不完整 → 回滚
```

---

## 崩溃恢复机制

### InnoDB 崩溃恢复流程 ⭐⭐⭐⭐

```
MySQL 启动时的崩溃恢复流程：

┌─────────────────────────────────────────────────────┐
│               MySQL 启动                            │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│           1. 读取 Redo Log                          │
│           从 checkpoint 位置开始扫描                 │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│           2. Redo 阶段（前滚）                       │
│                                                     │
│  重放所有已提交事务的修改：                          │
│  - Redo Log 状态为 commit 的事务                    │
│  - Redo Log 状态为 prepare 且 Binlog 完整的事务     │
│                                                     │
│  保证：已提交的数据不丢失                            │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│           3. Undo 阶段（回滚）                       │
│                                                     │
│  回滚所有未提交的事务：                              │
│  - Redo Log 状态为 prepare 且 Binlog 不完整的事务   │
│  - 没有 Redo Log 记录的活跃事务                     │
│                                                     │
│  保证：未提交的数据不会存在                          │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│           4. 恢复完成                               │
│           数据库可以接受连接                         │
└─────────────────────────────────────────────────────┘
```

### Double Write Buffer ⭐⭐⭐⭐

Double Write 是防止部分页写入（Partial Page Write）的机制。

**问题背景**：

```
InnoDB 页大小：16KB
OS 页大小：4KB

写入一个 InnoDB 页需要 4 次 OS IO

如果在写入过程中崩溃：
├─ T1: 写入第 1 个 4KB ✅
├─ T2: 写入第 2 个 4KB ✅
├─ T3: 💥 崩溃
└─ T4: 第 3、4 个 4KB 未写入

结果：
├─ 磁盘上的页数据不完整
├─ Redo Log 也无法修复（Redo Log 假设页是完整的）
└─ 数据损坏 ❌
```

**Double Write 的解决方案**：

```
Double Write 流程：

1. 脏页先写到 Double Write Buffer（内存）
2. 将 Double Write Buffer 写到共享表空间（磁盘，顺序写）
3. 写入完成后，再写入各自的数据文件（随机写）

恢复时：
├─ 如果数据文件的页不完整
├─ 从 Double Write 区域复制完整的页
└─ 然后再应用 Redo Log
```

**相关参数**：

```sql
-- 查看 Double Write 状态
SHOW VARIABLES LIKE 'innodb_doublewrite';

-- 查看 Double Write 统计
SHOW STATUS LIKE 'Innodb_dblwr%';

-- Innodb_dblwr_pages_written：写入的页数
-- Innodb_dblwr_writes：写入次数
```

### 恢复时间影响因素

| 因素 | 影响 | 优化建议 |
|------|------|---------|
| **Redo Log 大小** | 越大，恢复时间越长 | 不要设置过大（推荐 1-4GB） |
| **Checkpoint 频率** | 频率越低，恢复时间越长 | 适当调整 checkpoint 参数 |
| **脏页数量** | 越多，恢复时间越长 | 控制 innodb_max_dirty_pages_pct |
| **磁盘性能** | IO 性能影响恢复速度 | 使用 SSD |

---

## 日志参数调优

### Redo Log 参数

```sql
-- Redo Log 文件大小
-- 影响：循环写的空间，checkpoint 频率
-- 建议：1GB - 4GB（根据写入量调整）
innodb_log_file_size = 1G

-- Redo Log 文件数量
-- 默认 2 个，组成 Redo Log Group
innodb_log_files_in_group = 2

-- Redo Log Buffer 大小
-- 影响：事务提交前的缓冲能力
-- 建议：16MB - 64MB
innodb_log_buffer_size = 64M

-- 刷盘策略（最重要的参数）
-- 1 = 最安全，0 = 最快，2 = 折中
innodb_flush_log_at_trx_commit = 1

-- 查看当前配置
SHOW VARIABLES LIKE 'innodb_log%';
```

### Binlog 参数

```sql
-- Binlog 格式
-- ROW = 最安全，STATEMENT = 最小，MIXED = 折中
binlog_format = ROW

-- 刷盘策略
-- 1 = 最安全
sync_binlog = 1

-- 单个 Binlog 文件大小
-- 超过后自动切换新文件
max_binlog_size = 1G

-- Binlog 过期时间
-- MySQL 5.7
expire_logs_days = 7

-- MySQL 8.0+（单位：秒）
binlog_expire_logs_seconds = 604800

-- 查看当前配置
SHOW VARIABLES LIKE '%binlog%';
```

### "双一" 配置详解 ⭐⭐⭐⭐⭐

"双一" 是指两个关键参数都设置为 1，是**最安全的配置组合**：

```sql
-- "双一" 配置
innodb_flush_log_at_trx_commit = 1
sync_binlog = 1

-- 含义：
-- 每次事务提交时：
-- 1. Redo Log 立即 fsync 到磁盘
-- 2. Binlog 立即 fsync 到磁盘

-- 优点：
-- ✅ 数据不丢失（任何崩溃场景）
-- ✅ 主从一致

-- 缺点：
-- ❌ 每次提交都有两次 fsync
-- ❌ IO 压力大，性能最低
```

**性能与安全的权衡**：

| 配置组合 | 安全性 | 性能 | 适用场景 |
|---------|--------|------|---------|
| `flush=1, sync=1` | 最高 | 最低 | 金融、交易系统 |
| `flush=1, sync=0` | 高 | 中等 | 重要业务数据 |
| `flush=2, sync=100` | 中等 | 较高 | 普通业务 |
| `flush=0, sync=0` | 最低 | 最高 | 批量导入、测试环境 |

**批量导入时的临时调整**：

```sql
-- 批量导入前（提高性能）
SET GLOBAL innodb_flush_log_at_trx_commit = 0;
SET GLOBAL sync_binlog = 0;

-- 执行导入...

-- 导入完成后（恢复安全配置）
SET GLOBAL innodb_flush_log_at_trx_commit = 1;
SET GLOBAL sync_binlog = 1;
```

---

## 面试高频问题 ⭐⭐⭐⭐⭐

### Q1: Redo Log 和 Binlog 的区别？

**答案要点**：

| 维度 | Redo Log | Binlog |
|------|----------|--------|
| 层级 | InnoDB 引擎层 | MySQL Server 层 |
| 类型 | 物理日志（页修改） | 逻辑日志（SQL/行变化） |
| 写入 | 循环写，固定大小 | 追加写，无限增长 |
| 作用 | 崩溃恢复 | 主从复制、数据恢复 |
| 时机 | 事务执行过程中 | 事务提交时 |

---

### Q2: 为什么需要两阶段提交？

**答案要点**：

1. **核心目的**：保证 Redo Log 和 Binlog 的一致性
2. **问题场景**：
   - 先写 Redo 后崩溃：主库有数据，从库没有
   - 先写 Binlog 后崩溃：主库没数据，从库有
3. **解决方案**：
   - Prepare 阶段：Redo Log 写入，状态为 prepare
   - Commit 阶段：Binlog 写入后，Redo Log 状态改为 commit
4. **恢复逻辑**：
   - Prepare + Binlog 完整 → 提交
   - Prepare + Binlog 不完整 → 回滚

---

### Q3: innodb_flush_log_at_trx_commit 各值的含义？

**答案要点**：

| 值 | 行为 | 数据丢失风险 |
|----|------|-------------|
| 0 | 每秒 write + fsync | MySQL/OS 崩溃：丢 1 秒 |
| 1 | 每次提交 write + fsync | 不丢失 |
| 2 | 每次提交 write，每秒 fsync | OS 崩溃：丢 1 秒 |

**生产建议**：值 = 1（安全第一）

---

### Q4: Binlog 为什么推荐 ROW 格式？

**答案要点**：

1. **STATEMENT 的问题**：
   - NOW()、RAND()、UUID() 等函数主从结果不同
   - 不确定性 SQL（无 ORDER BY 的 LIMIT）
2. **ROW 的优势**：
   - 精确记录每行的变化
   - 保证主从数据一致
3. **ROW 的代价**：
   - 批量操作时日志量大
   - 可通过分批执行缓解

---

### Q5: Undo Log 的两个作用？

**答案要点**：

1. **保证原子性（回滚）**：
   - 记录数据的旧值
   - ROLLBACK 时使用 Undo Log 恢复
2. **支持 MVCC**：
   - 形成版本链
   - 其他事务可以读取历史版本
   - 实现非锁定读

---

### Q6: 长事务对 Undo Log 有什么影响？

**答案要点**：

1. **Undo Log 无法 Purge**：
   - 长事务的 Read View 可能需要旧版本
   - 即使其他事务提交，Undo Log 也不能清理
2. **危害**：
   - History List 增长
   - Undo Tablespace 膨胀
   - 版本链过长，查询变慢
3. **预防**：
   - 监控长事务
   - 设置事务超时
   - 避免在事务中执行耗时操作

---

### Q7: MySQL 崩溃恢复是如何进行的？

**答案要点**：

1. **Redo 阶段（前滚）**：
   - 从 checkpoint 开始扫描 Redo Log
   - 重放已提交事务（commit 状态）
   - 重放 prepare + Binlog 完整的事务
2. **Undo 阶段（回滚）**：
   - 回滚未提交事务
   - 回滚 prepare + Binlog 不完整的事务
3. **关键判断**：
   - 以 Binlog 是否完整作为最终提交依据

---

### Q8: 如何保证 MySQL 数据不丢失？

**答案要点**：

1. **"双一" 配置**：
   ```sql
   innodb_flush_log_at_trx_commit = 1
   sync_binlog = 1
   ```
2. **主从复制**：
   - 半同步复制（Semi-Sync）
   - 组复制（Group Replication）
3. **备份策略**：
   - 定期全量备份
   - 结合 Binlog 增量恢复

---

### Q9: Redo Log 的 checkpoint 机制？

**答案要点**：

1. **作用**：
   - 释放 Redo Log 空间（循环写）
   - 缩短崩溃恢复时间
2. **触发条件**：
   - 后台线程定时触发
   - Redo Log 空间不足
   - 脏页比例过高
3. **过程**：
   - 将 checkpoint 之前的脏页刷盘
   - 推进 checkpoint 位置

---

### Q10: Redo Log 为什么能提高写入性能？

**答案要点**：

1. **WAL 机制**：
   - Write-Ahead Logging
   - 先写日志，后写数据
2. **性能优势**：
   - Redo Log：顺序写（追加）
   - 数据文件：随机写（分散在各处）
   - 顺序写比随机写快 100+ 倍
3. **代价转移**：
   - 脏页由后台线程异步刷盘
   - 用户无需等待数据页落盘

---

## 总结

### 核心要点 ⭐⭐⭐⭐⭐

**1. 三种日志的作用**：

| 日志 | 作用 | 实现的特性 |
|------|------|-----------|
| Redo Log | 崩溃恢复 | 持久性（D） |
| Undo Log | 回滚 + MVCC | 原子性（A） |
| Binlog | 主从复制、数据恢复 | - |

**2. 两阶段提交**：
```
Redo Log (prepare) → Binlog → Redo Log (commit)
```

**3. 关键参数**：
```sql
-- "双一" 配置 = 最安全
innodb_flush_log_at_trx_commit = 1
sync_binlog = 1
```

**4. 崩溃恢复**：
- Redo 阶段：重放已提交事务
- Undo 阶段：回滚未提交事务

### 记住这些关键点

- ✅ **Redo Log 是物理日志，Binlog 是逻辑日志**
- ✅ **两阶段提交保证主从一致**
- ✅ **Undo Log 形成版本链支持 MVCC**
- ✅ **"双一" 配置保证数据安全**
- ✅ **长事务影响 Undo Log 清理**
- ✅ **Binlog 推荐 ROW 格式**

---

**相关文档**：
- [MySQL 事务](transaction.md) - ACID 特性详解、隔离级别
- [MySQL MVCC](mvcc.md) - 版本链与可见性判断
- [MySQL 锁机制](lock.md) - 并发控制

**下一步**：学习 [MySQL 性能优化](optimization.md)，掌握索引优化、查询优化和参数调优。
