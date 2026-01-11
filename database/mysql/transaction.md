# MySQL 事务

> 事务是数据库的核心概念，理解事务的 ACID 特性和隔离级别是掌握 MySQL 的关键。

## 📚 目录

- [事务的基本概念](#事务的基本概念)
- [ACID 特性详解](#acid-特性详解)
- [事务隔离级别](#事务隔离级别)
- [并发问题详解](#并发问题详解)
- [当前读与快照读](#当前读与快照读)
- [日志系统](#日志系统)
- [事务的最佳实践](#事务的最佳实践)
- [面试高频问题](#面试高频问题)

---

## 事务的基本概念

### 什么是事务？

事务（Transaction）是数据库操作的最小工作单元，是一组不可分割的数据库操作序列。

**特点**：
- 要么全部成功
- 要么全部失败
- 保证数据的一致性

### 事务的使用

```sql
-- 开启事务
BEGIN;  -- 或 START TRANSACTION;

-- 执行 SQL 操作
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;

-- 提交事务
COMMIT;

-- 或者回滚事务
ROLLBACK;
```

### 为什么需要事务？

**场景：银行转账**

```sql
-- 没有事务的情况
UPDATE account SET balance = balance - 100 WHERE id = 1;  -- 转出成功
-- 💥 系统崩溃！
UPDATE account SET balance = balance + 100 WHERE id = 2;  -- 转入失败

-- 结果：100 元凭空消失了！
```

**使用事务**：

```sql
BEGIN;
UPDATE account SET balance = balance - 100 WHERE id = 1;
-- 💥 系统崩溃！
-- 事务未提交，数据库会自动回滚

-- 结果：数据保持一致 ✅
```

---

## ACID 特性详解 ⭐⭐⭐⭐⭐

ACID 是事务的四大特性，这是**面试必考的核心知识点**。

### A - Atomicity（原子性）

#### 定义

事务是不可分割的最小单位，要么全部成功，要么全部失败。

#### 实现原理：Undo Log

**机制**：
1. 事务开始时，记录数据的**原始值**到 Undo Log
2. 事务执行过程中，数据被修改
3. 如果需要回滚，使用 Undo Log 恢复数据

**示例**：

```sql
BEGIN;

-- 原始数据：balance = 1000
UPDATE account SET balance = 900 WHERE id = 1;

-- Undo Log 记录：
-- | 操作类型 | 表 | 主键 | 列 | 旧值 |
-- | UPDATE | account | id=1 | balance | 1000 |

ROLLBACK;
-- 使用 Undo Log 恢复：balance = 1000
```

**Undo Log 的作用**：
1. **保证原子性**：回滚时恢复数据
2. **实现 MVCC**：提供历史版本（下一章详解）

### C - Consistency（一致性）

#### 定义

事务执行前后，数据库从一个一致性状态转换到另一个一致性状态。

#### 什么是"一致性状态"？

**数据库层面**：
- 满足所有约束（主键、外键、唯一性、检查约束）
- 满足触发器规则

**业务层面**：
- 满足业务规则
- 例如：转账前后总金额不变

#### 实现原理

一致性**不是由单一机制保证的**，而是由其他三个特性共同实现：

```
Atomicity（原子性）
    +
Isolation（隔离性）
    +
Durability（持久性）
    ↓
Consistency（一致性）
```

**示例**：

```sql
-- 转账事务
BEGIN;
UPDATE account SET balance = balance - 100 WHERE id = 1;
UPDATE account SET balance = balance + 100 WHERE id = 2;
COMMIT;

-- 一致性保证：
-- 1. 原子性：两个 UPDATE 要么都成功，要么都失败
-- 2. 隔离性：其他事务看不到中间状态
-- 3. 持久性：提交后数据永久保存
-- 结果：总金额保持不变 ✅
```

### I - Isolation（隔离性）⭐⭐⭐⭐⭐

#### 定义

并发执行的事务之间互不干扰，每个事务都感觉像是独占数据库。

#### 实现原理：锁 + MVCC

**锁机制**：
- 解决**写-写冲突**
- 使用行锁、表锁等
- 详见 [锁机制文档](lock.md)

**MVCC（多版本并发控制）**：
- 解决**读-写冲突**
- 使用 Undo Log 版本链
- 详见 [MVCC 文档](mvcc.md)

```
写-写冲突：锁机制
    +
读-写冲突：MVCC
    ↓
Isolation（隔离性）
```

### D - Durability（持久性）⭐⭐⭐⭐⭐

#### 定义

事务一旦提交，对数据库的修改就是永久性的，即使系统崩溃也不会丢失。

#### 实现原理：Redo Log + WAL

**WAL（Write-Ahead Logging）机制**：

```
写数据的步骤：
1. 先写 Redo Log（顺序写，快）
2. 标记事务为 commit
3. 后台异步刷新脏页到磁盘（随机写，慢）
```

**为什么这样设计？**

| 操作 | 直接写磁盘 | 先写 Redo Log |
|------|-----------|---------------|
| IO 类型 | 随机写 | 顺序写 |
| 性能 | 慢 | 快 |
| 可靠性 | 高 | 高（持久化到磁盘） |

**示例流程**：

```sql
BEGIN;
UPDATE account SET balance = 900 WHERE id = 1;
COMMIT;  -- 提交点

-- 提交时发生的事情：
-- 1. 写 Redo Log：记录 "将 id=1 的 balance 改为 900"
-- 2. Redo Log 刷盘（fsync）
-- 3. 返回提交成功
-- 4. 后台线程异步将脏页刷盘

-- 💥 假设这时系统崩溃
-- 重启后：
-- 1. 读取 Redo Log
-- 2. 重放日志：将 id=1 的 balance 改为 900
-- 3. 数据恢复 ✅
```

**Redo Log 的刷盘策略**：

参数：`innodb_flush_log_at_trx_commit`

| 值 | 含义 | 性能 | 安全性 |
|----|------|------|--------|
| 0 | 每秒刷一次盘 | 最快 | 可能丢失 1 秒数据 |
| 1 | 每次提交都刷盘 | 最慢 | 最安全（默认） |
| 2 | 每次提交写到 OS 缓存 | 中等 | 可能丢失数据（OS 崩溃） |

**推荐配置**：
```sql
-- 生产环境（安全第一）
innodb_flush_log_at_trx_commit = 1

-- 对数据安全要求不高的场景（性能第一）
innodb_flush_log_at_trx_commit = 2
```

### ACID 特性总结

| 特性 | 定义 | 实现机制 | 重要性 |
|------|------|---------|--------|
| Atomicity | 全部成功或全部失败 | Undo Log | ⭐⭐⭐⭐⭐ |
| Consistency | 数据保持一致 | A + I + D | ⭐⭐⭐⭐ |
| Isolation | 事务间互不干扰 | 锁 + MVCC | ⭐⭐⭐⭐⭐ |
| Durability | 提交后永久保存 | Redo Log + WAL | ⭐⭐⭐⭐⭐ |

---

## 事务隔离级别 ⭐⭐⭐⭐⭐

隔离级别是**面试的绝对高频考点**，必须熟练掌握。

### 四种隔离级别

| 隔离级别 | 脏读 | 不可重复读 | 幻读 |
|---------|------|-----------|------|
| **READ UNCOMMITTED**<br>（读未提交） | ✓ | ✓ | ✓ |
| **READ COMMITTED**<br>（读已提交） | ✗ | ✓ | ✓ |
| **REPEATABLE READ**<br>（可重复读，MySQL 默认） | ✗ | ✗ | ✗* |
| **SERIALIZABLE**<br>（串行化） | ✗ | ✗ | ✗ |

**注意**：
- ✓ = 会出现该问题
- ✗ = 不会出现该问题
- ✗* = MySQL 的 RR 通过 Next-Key Lock 解决了幻读

### 设置隔离级别

```sql
-- 查看全局隔离级别
SELECT @@global.transaction_isolation;

-- 查看当前会话隔离级别
SELECT @@transaction_isolation;

-- 设置会话隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

---

## 并发问题详解 ⭐⭐⭐⭐⭐

这是**面试必问**的内容，必须能用 SQL 演示出来。

### 1. 脏读（Dirty Read）

#### 定义

一个事务读到了另一个**未提交**事务修改的数据。

#### 问题

如果那个事务回滚了，读到的就是无效数据。

#### 演示

**隔离级别**：READ UNCOMMITTED

```sql
-- 初始数据：id=1, balance=1000

-- 事务 A                          事务 B
SET SESSION TRANSACTION 
ISOLATION LEVEL READ UNCOMMITTED;
BEGIN;
                                   SET SESSION TRANSACTION 
                                   ISOLATION LEVEL READ UNCOMMITTED;
                                   BEGIN;
                                   
                                   UPDATE account 
                                   SET balance = 500 
                                   WHERE id = 1;
                                   -- 事务 B 修改但未提交
                                   
SELECT balance FROM account 
WHERE id = 1;
-- 读到 500（脏读！）
                                   
                                   ROLLBACK;
                                   -- 事务 B 回滚了
                                   
SELECT balance FROM account 
WHERE id = 1;
-- 又变成 1000 了
-- 之前读到的 500 是无效数据！
```

**影响**：
- 事务 A 基于 500 做决策
- 但 500 是无效数据
- 导致业务逻辑错误

#### 解决方案

使用 **READ COMMITTED** 或更高的隔离级别。

### 2. 不可重复读（Non-Repeatable Read）⭐⭐⭐⭐⭐

#### 定义

同一个事务内，多次读取同一数据，结果不一致。

#### 原因

其他事务**修改并提交**了数据。

#### 演示

**隔离级别**：READ COMMITTED

```sql
-- 初始数据：id=1, balance=1000

-- 事务 A                          事务 B
SET SESSION TRANSACTION 
ISOLATION LEVEL READ COMMITTED;
BEGIN;
                                   BEGIN;
                                   
SELECT balance FROM account 
WHERE id = 1;
-- 第一次读：balance = 1000
                                   
                                   UPDATE account 
                                   SET balance = 500 
                                   WHERE id = 1;
                                   
                                   COMMIT;
                                   -- 事务 B 提交了
                                   
SELECT balance FROM account 
WHERE id = 1;
-- 第二次读：balance = 500
-- 两次读取结果不一样！（不可重复读）

COMMIT;
```

**影响**：
- 同一个事务内，读取不一致
- 无法保证数据稳定性
- 影响业务逻辑

**使用场景**：
- 大多数场景可以接受不可重复读
- 例如：查询账户余额（实时性更重要）

#### 解决方案

使用 **REPEATABLE READ** 或更高的隔离级别。

### 3. 幻读（Phantom Read）⭐⭐⭐⭐⭐

#### 定义

同一个事务内，多次查询，返回的**结果集**不一致。

#### 原因

其他事务**插入或删除**了数据。

#### 与不可重复读的区别

| 问题 | 关注点 | 原因 |
|------|--------|------|
| 不可重复读 | **单条记录的值**变化 | 其他事务 **UPDATE** |
| 幻读 | **结果集的行数**变化 | 其他事务 **INSERT/DELETE** |

#### 演示

**隔离级别**：READ COMMITTED（没有间隙锁）

```sql
-- 初始数据：id=1, id=5, id=10

-- 事务 A                              事务 B
SET SESSION TRANSACTION 
ISOLATION LEVEL READ COMMITTED;
BEGIN;
                                       BEGIN;
                                       
SELECT * FROM t WHERE id > 5;
-- 第一次查询：返回 id=10（1 条记录）
                                       
                                       INSERT INTO t 
                                       VALUES (7, ...);
                                       
                                       COMMIT;
                                       -- 事务 B 插入并提交
                                       
SELECT * FROM t WHERE id > 5;
-- 第二次查询：返回 id=7, id=10（2 条记录）
-- 多了一条记录！（幻读）

COMMIT;
```

**更严重的幻读场景**：

```sql
-- 事务 A：想要锁定 id > 5 的所有记录
BEGIN;
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 锁定了 id=10

-- 此时只锁定了已存在的记录
-- 无法阻止新记录的插入（READ COMMITTED 没有间隙锁）

-- 事务 B：插入新记录
BEGIN;
INSERT INTO t VALUES (7, ...);  -- ✅ 成功插入
COMMIT;

-- 事务 A：再次查询
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 发现多了 id=7，但之前没有锁住它！
-- 这就是幻读的危害
```

#### MySQL 的解决方案 ⭐⭐⭐⭐⭐

**REPEATABLE READ + Next-Key Lock**

MySQL 的 RR 隔离级别通过 **Next-Key Lock**（临键锁）解决了幻读：

```sql
-- 隔离级别：REPEATABLE READ（MySQL 默认）

-- 事务 A
BEGIN;
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 加锁：(5, +∞) 的临键锁
-- 锁住了所有 id > 5 的间隙

-- 事务 B：尝试插入
BEGIN;
INSERT INTO t VALUES (7, ...);  -- ⏳ 阻塞！
-- 无法插入，因为被间隙锁阻止了

-- 事务 A：再次查询
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 结果集不变 ✅
COMMIT;

-- 事务 B：现在可以插入了
-- ✅ 成功
COMMIT;
```

**关键点**：
1. **当前读**（FOR UPDATE）使用 Next-Key Lock 防止幻读
2. **快照读**（普通 SELECT）使用 MVCC 防止幻读
3. 两种机制配合，彻底解决幻读

### 4. 丢失更新（Lost Update）

#### 定义

两个事务同时更新同一数据，后提交的事务覆盖了先提交的事务的修改。

#### 演示

```sql
-- 初始数据：balance = 1000

-- 事务 A                          事务 B
BEGIN;                             BEGIN;

SELECT balance FROM account 
WHERE id = 1;
-- 读到 1000
                                   SELECT balance FROM account 
                                   WHERE id = 1;
                                   -- 读到 1000
                                   
UPDATE account 
SET balance = 1000 + 100 
WHERE id = 1;
-- balance = 1100

COMMIT;
                                   
                                   UPDATE account 
                                   SET balance = 1000 + 50 
                                   WHERE id = 1;
                                   -- balance = 1050（覆盖了事务 A 的修改）
                                   
                                   COMMIT;

-- 最终：balance = 1050
-- 应该是：1000 + 100 + 50 = 1150
-- 事务 A 的 +100 丢失了！
```

#### 解决方案

**方案 1：使用锁**

```sql
-- 事务 A
BEGIN;
SELECT balance FROM account 
WHERE id = 1 FOR UPDATE;  -- 加排他锁
-- balance = 1000

UPDATE account 
SET balance = 1000 + 100 
WHERE id = 1;

COMMIT;

-- 事务 B
BEGIN;
SELECT balance FROM account 
WHERE id = 1 FOR UPDATE;  -- ⏳ 等待事务 A 释放锁
-- 等事务 A 提交后，读到 1100

UPDATE account 
SET balance = 1100 + 50 
WHERE id = 1;

COMMIT;

-- 最终：balance = 1150 ✅
```

**方案 2：使用原子操作**

```sql
-- 不要分两步（读 + 写）
-- 直接用一个原子操作
UPDATE account 
SET balance = balance + 100 
WHERE id = 1;
```

**方案 3：乐观锁**

```sql
-- 添加版本号字段
ALTER TABLE account ADD COLUMN version INT DEFAULT 0;

-- 事务 A
BEGIN;
SELECT balance, version FROM account WHERE id = 1;
-- balance = 1000, version = 1

UPDATE account 
SET balance = 1100, version = 2 
WHERE id = 1 AND version = 1;
-- ✅ 更新成功

COMMIT;

-- 事务 B
BEGIN;
SELECT balance, version FROM account WHERE id = 1;
-- balance = 1000, version = 1

UPDATE account 
SET balance = 1050, version = 2 
WHERE id = 1 AND version = 1;
-- ❌ 更新失败（version 已经是 2 了）

-- 重新读取最新数据
SELECT balance, version FROM account WHERE id = 1;
-- balance = 1100, version = 2

UPDATE account 
SET balance = 1150, version = 3 
WHERE id = 1 AND version = 2;
-- ✅ 更新成功

COMMIT;
```

### 并发问题总结表 ⭐⭐⭐⭐⭐

| 问题 | 定义 | 原因 | 隔离级别 | 解决方案 |
|------|------|------|---------|---------|
| 脏读 | 读到未提交的数据 | 其他事务未提交 | RU | RC 及以上 |
| 不可重复读 | 同一数据多次读取不一致 | 其他事务 UPDATE 并提交 | RC | RR 及以上 |
| 幻读 | 结果集行数变化 | 其他事务 INSERT/DELETE | RC | RR（Next-Key Lock） |
| 丢失更新 | 后提交的覆盖先提交的 | 并发更新 | 所有级别 | 加锁或乐观锁 |

---

## 当前读与快照读 ⭐⭐⭐⭐⭐

这是理解 MySQL 并发控制的**关键概念**。

### 快照读（Snapshot Read）

#### 定义

读取的是数据的**历史版本**（快照），不是最新版本。

#### 特点

- 不加锁
- 使用 MVCC 实现
- 读取的是事务开始时的快照

#### SQL 语句

```sql
-- 普通的 SELECT 语句都是快照读
SELECT * FROM t WHERE id = 1;
SELECT * FROM t WHERE id > 10;
SELECT COUNT(*) FROM t;
```

#### 示例

```sql
-- 初始数据：id=1, value=100

-- 事务 A（RR 隔离级别）        事务 B
BEGIN;
SELECT value FROM t 
WHERE id = 1;
-- 快照读：value = 100
                                   BEGIN;
                                   UPDATE t SET value = 200 
                                   WHERE id = 1;
                                   COMMIT;
                                   -- 事务 B 修改并提交
                                   
SELECT value FROM t 
WHERE id = 1;
-- 快照读：仍然是 value = 100
-- 读取的是事务开始时的快照

COMMIT;
```

### 当前读（Current Read）

#### 定义

读取的是数据的**最新版本**（当前值）。

#### 特点

- 会加锁
- 读取的是最新数据
- 使用锁机制防止并发修改

#### SQL 语句

```sql
-- 加共享锁的 SELECT
SELECT * FROM t WHERE id = 1 LOCK IN SHARE MODE;
SELECT * FROM t WHERE id = 1 FOR SHARE;  -- MySQL 8.0+

-- 加排他锁的 SELECT
SELECT * FROM t WHERE id = 1 FOR UPDATE;

-- DML 语句（隐式加排他锁）
INSERT INTO t VALUES (...);
UPDATE t SET ... WHERE ...;
DELETE FROM t WHERE ...;
```

#### 示例

```sql
-- 初始数据：id=1, value=100

-- 事务 A（RR 隔离级别）        事务 B
BEGIN;
SELECT value FROM t 
WHERE id = 1 FOR UPDATE;
-- 当前读：value = 100
-- 加排他锁
                                   BEGIN;
                                   UPDATE t SET value = 200 
                                   WHERE id = 1;
                                   -- ⏳ 等待事务 A 释放锁
                                   
SELECT value FROM t 
WHERE id = 1 FOR UPDATE;
-- 当前读：value = 100
-- 还是 100，因为事务 B 被阻塞了

COMMIT;
-- 释放锁
                                   -- ✅ 事务 B 的 UPDATE 执行
                                   COMMIT;
```

### 快照读 vs 当前读

| 特性 | 快照读 | 当前读 |
|------|--------|--------|
| 读取版本 | 历史版本（快照） | 最新版本 |
| 是否加锁 | 不加锁 | 加锁 |
| 实现机制 | MVCC | 锁 |
| 并发性能 | 高 | 低 |
| SQL 示例 | `SELECT ...` | `SELECT ... FOR UPDATE` |

### 幻读的完整解决方案 ⭐⭐⭐⭐⭐

MySQL 的 RR 隔离级别通过**两种机制**解决幻读：

#### 1. 快照读：MVCC

```sql
-- 事务 A（RR 隔离级别）
BEGIN;
SELECT * FROM t WHERE id > 5;
-- 快照读：返回事务开始时的数据
-- 假设返回 id=10（1 条）

-- 事务 B：插入新数据
BEGIN;
INSERT INTO t VALUES (7, ...);
COMMIT;

-- 事务 A：再次查询
SELECT * FROM t WHERE id > 5;
-- 快照读：仍然返回 id=10（1 条）
-- MVCC 保证读取的是同一个快照 ✅

COMMIT;
```

#### 2. 当前读：Next-Key Lock

```sql
-- 事务 A（RR 隔离级别）
BEGIN;
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 当前读：返回最新数据 id=10
-- 加锁：(5, +∞) 的临键锁

-- 事务 B：尝试插入
BEGIN;
INSERT INTO t VALUES (7, ...);
-- ⏳ 阻塞！被间隙锁阻止

-- 事务 A：再次查询
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 当前读：仍然返回 id=10（1 条）
-- Next-Key Lock 防止了新数据插入 ✅

COMMIT;

-- 事务 B：现在可以插入了
-- ✅ 成功
COMMIT;
```

### 总结

```
幻读的解决方案：
├── 快照读（普通 SELECT）
│   └── MVCC（读取历史快照）
└── 当前读（FOR UPDATE）
    └── Next-Key Lock（锁住间隙）
```

---

## 日志系统 ⭐⭐⭐⭐⭐

MySQL 有三种重要的日志，它们是实现事务 ACID 特性的基础。

### 1. Redo Log（重做日志）⭐⭐⭐⭐⭐

#### 作用

保证事务的**持久性**（Durability）。

#### 工作原理

**WAL（Write-Ahead Logging）机制**：

```
写数据流程：
1. 修改 Buffer Pool 中的数据页（内存操作，快）
2. 写 Redo Log Buffer
3. 事务提交时，Redo Log Buffer 刷到磁盘
4. 返回提交成功
5. 后台线程异步将脏页刷到磁盘
```

#### 为什么不直接写数据页？

| 操作 | 写 Redo Log | 写数据页 |
|------|------------|---------|
| IO 类型 | **顺序写** | **随机写** |
| 大小 | 小（只记录修改） | 大（整页 16KB） |
| 性能 | **快** | 慢 |

**示例**：

```sql
UPDATE t SET a = 1 WHERE id = 10;

-- Redo Log 只记录：
"将 t 表空间的第 N 页偏移 M 处的值改为 1"
-- 大小：几十字节

-- 数据页需要写入：
整个 16KB 的页
```

#### Redo Log 的格式

```
Redo Log = Header + Data

Header:
- Type（操作类型）
- Space ID（表空间 ID）
- Page Number（页号）

Data:
- Offset（偏移量）
- Length（长度）
- Value（新值）
```

#### 崩溃恢复

```sql
-- 系统崩溃前
BEGIN;
UPDATE t SET a = 1 WHERE id = 10;
COMMIT;  -- Redo Log 已刷盘
-- 💥 崩溃！数据页还在内存，未刷盘

-- 重启后
读取 Redo Log → 重放日志 → 将 a 改为 1 → 数据恢复 ✅
```

#### 两阶段提交（2PC）⭐⭐⭐⭐⭐

**为什么需要两阶段提交？**

保证 **Redo Log** 和 **Binlog** 的一致性。

**流程**：

```
事务提交流程：
1. Prepare 阶段：
   - 写 Redo Log
   - 状态标记为 prepare

2. 写 Binlog：
   - 写 Binlog 到磁盘

3. Commit 阶段：
   - 写 Redo Log
   - 状态标记为 commit
   - 事务提交完成
```

**异常场景分析**：

```
场景 1：Prepare 后，写 Binlog 前崩溃
- Redo Log 状态：prepare
- Binlog：未写入
- 恢复策略：回滚事务 ✅

场景 2：写 Binlog 后，Commit 前崩溃
- Redo Log 状态：prepare
- Binlog：已写入
- 恢复策略：提交事务 ✅（Binlog 有记录）

场景 3：Commit 后崩溃
- Redo Log 状态：commit
- Binlog：已写入
- 恢复策略：提交事务 ✅
```

**为什么这样设计？**

```
目的：保证主从一致
- 主库：使用 Redo Log 恢复
- 从库：使用 Binlog 同步
- 必须保证两者一致
```

#### 参数配置

```sql
-- Redo Log 刷盘策略
innodb_flush_log_at_trx_commit:
  0: 每秒刷一次（可能丢 1 秒数据）
  1: 每次提交都刷盘（最安全，默认）
  2: 每次提交写到 OS 缓存（折中）
```

### 2. Undo Log（回滚日志）⭐⭐⭐⭐⭐

#### 作用

1. 保证事务的**原子性**（Atomicity）
2. 实现 **MVCC**（多版本并发控制）

#### 工作原理

**记录数据的旧值**：

```sql
-- 原始数据：a = 10
UPDATE t SET a = 20 WHERE id = 1;

-- Undo Log 记录：
INSERT INTO undo_log VALUES (
  trx_id,           -- 事务 ID
  'UPDATE',         -- 操作类型
  't',              -- 表名
  'id=1',           -- 主键
  'a',              -- 列名
  10                -- 旧值
);
```

#### 回滚操作

```sql
BEGIN;
UPDATE t SET a = 20 WHERE id = 1;  -- a: 10 → 20
UPDATE t SET b = 30 WHERE id = 1;  -- b: 20 → 30
ROLLBACK;

-- 回滚过程：
1. 读取 Undo Log
2. b: 30 → 20（恢复）
3. a: 20 → 10（恢复）
4. 数据恢复到事务开始前的状态 ✅
```

#### Undo Log 版本链

**形成历史版本链**：

```
最新版本 → 版本 3 → 版本 2 → 版本 1
 (a=30)    (a=20)    (a=10)    (a=0)
 
每个版本记录：
- DB_TRX_ID：事务 ID
- DB_ROLL_PTR：指向上一个版本的指针
```

**这是 MVCC 的基础**，详见 [MVCC 文档](mvcc.md)。

#### Undo Log 的类型

1. **Insert Undo Log**：
   - INSERT 操作产生
   - 只在事务回滚时需要
   - 事务提交后立即删除

2. **Update Undo Log**：
   - UPDATE 和 DELETE 操作产生
   - 事务提交后不能立即删除
   - MVCC 可能需要读取历史版本
   - 由 Purge 线程清理

#### Purge 操作

**清理不再需要的 Undo Log**：

```
判断标准：
1. 事务已提交
2. 没有其他事务需要读取这个版本
3. 版本太旧（所有事务的 Read View 都不需要）

清理时机：
- 后台 Purge 线程定期执行
- innodb_purge_threads 参数控制线程数
```

#### 长事务的危害 ⭐⭐⭐⭐⭐

```sql
-- 事务 A：长事务
BEGIN;
SELECT * FROM t WHERE id = 1;
-- ... 执行了很长时间，一直不提交

-- 问题：
1. Undo Log 无法清理（事务 A 可能需要读取历史版本）
2. 占用大量存储空间
3. 影响性能
4. 可能导致主从延迟
```

**如何避免长事务？**

1. 尽快提交或回滚
2. 拆分大事务
3. 监控事务运行时间：
   ```sql
   SELECT * FROM information_schema.INNODB_TRX 
   WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;
   ```

### 3. Binlog（归档日志）

#### 作用

1. **主从复制**：从库通过 Binlog 同步数据
2. **数据恢复**：通过 Binlog 恢复到指定时间点

#### Binlog vs Redo Log

| 特性 | Redo Log | Binlog |
|------|----------|--------|
| 层级 | InnoDB 引擎层 | MySQL Server 层 |
| 内容 | 物理日志（页的修改） | 逻辑日志（SQL 语句） |
| 大小 | 固定大小，循环写 | 追加写，不覆盖 |
| 作用 | 崩溃恢复 | 主从复制、数据恢复 |

#### Binlog 格式

1. **STATEMENT**：
   - 记录 SQL 语句
   - 日志量小
   - 可能导致主从不一致（如 NOW()）

2. **ROW**：
   - 记录每行数据的变化
   - 日志量大
   - 保证主从一致（推荐）

3. **MIXED**：
   - 混合模式
   - 一般用 STATEMENT，特殊情况用 ROW

#### 参数配置

```sql
-- Binlog 刷盘策略
sync_binlog:
  0: 依赖 OS 刷盘
  1: 每次提交都刷盘（最安全）
  N: 每 N 次事务刷盘
```

### 日志系统总结

```
事务提交流程：
1. 修改 Buffer Pool（内存）
2. 写 Undo Log（保存旧值）
3. 写 Redo Log（prepare）
4. 写 Binlog
5. 写 Redo Log（commit）
6. 事务提交成功
7. 后台异步刷脏页
```

---

## 事务的最佳实践

### 1. 保持事务简短

```sql
-- ❌ 错误：长事务
BEGIN;
UPDATE t1 SET ...;
-- 执行复杂业务逻辑
-- 调用外部 API
-- 等待用户输入
UPDATE t2 SET ...;
COMMIT;

-- ✅ 正确：短事务
BEGIN;
UPDATE t1 SET ...;
UPDATE t2 SET ...;
COMMIT;
-- 业务逻辑在事务外处理
```

### 2. 避免长事务

**长事务的危害**：
- Undo Log 无法清理
- 锁持有时间长
- 影响并发性能
- 可能导致主从延迟

**如何避免**：
```sql
-- 设置事务超时
SET innodb_lock_wait_timeout = 10;

-- 监控长事务
SELECT * FROM information_schema.INNODB_TRX 
WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;
```

### 3. 合理选择隔离级别

```sql
-- 大多数场景：RC 够用
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 需要可重复读：RR
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 避免使用：SERIALIZABLE（性能差）
```

### 4. 显式开启事务

```sql
-- ✅ 推荐
BEGIN;
-- SQL 操作
IF error THEN
    ROLLBACK;
ELSE
    COMMIT;
END IF;

-- ❌ 不推荐：依赖自动提交
UPDATE t SET ...;
```

### 5. 使用合适的锁粒度

```sql
-- ❌ 不必要的锁
SELECT * FROM t FOR UPDATE;  -- 锁全表

-- ✅ 精确的锁
SELECT * FROM t WHERE id = 1 FOR UPDATE;  -- 只锁一行
```

### 6. 批量操作分批处理

```sql
-- ❌ 一次性处理
BEGIN;
UPDATE t SET ... WHERE id IN (1, 2, 3, ..., 100000);
COMMIT;

-- ✅ 分批处理
for i in range(0, 100000, 1000):
    BEGIN;
    UPDATE t SET ... WHERE id IN (i, i+1, ..., i+999);
    COMMIT;
```

---

## 面试高频问题 ⭐⭐⭐⭐⭐

### Q1: 事务的 ACID 特性是如何实现的？

**回答**：

1. **Atomicity（原子性）**：
   - 实现：Undo Log
   - 事务回滚时，使用 Undo Log 恢复数据

2. **Consistency（一致性）**：
   - 实现：由 A + I + D 共同保证
   - 数据库约束 + 业务规则

3. **Isolation（隔离性）**：
   - 实现：锁 + MVCC
   - 锁机制：解决写-写冲突
   - MVCC：解决读-写冲突

4. **Durability（持久性）**：
   - 实现：Redo Log + WAL
   - 先写日志，再写磁盘
   - 崩溃后通过 Redo Log 恢复

### Q2: MySQL 有哪几种隔离级别？

**回答**：

四种隔离级别，从低到高：

1. **READ UNCOMMITTED**（读未提交）
   - 会出现：脏读、不可重复读、幻读
   - 几乎不使用

2. **READ COMMITTED**（读已提交）
   - 会出现：不可重复读、幻读
   - Oracle、SQL Server 默认
   - 适合大多数场景

3. **REPEATABLE READ**（可重复读）
   - MySQL 默认
   - 通过 Next-Key Lock 解决了幻读
   - 适合需要可重复读的场景

4. **SERIALIZABLE**（串行化）
   - 完全串行执行
   - 性能最差
   - 很少使用

### Q3: 什么是脏读、不可重复读、幻读？

**脏读**：
- 读到其他事务**未提交**的数据
- 如果那个事务回滚，读到的是无效数据

**不可重复读**：
- 同一事务内，多次读取**同一数据**，结果不一致
- 原因：其他事务 UPDATE 并提交

**幻读**：
- 同一事务内，多次查询，**结果集**不一致
- 原因：其他事务 INSERT/DELETE 并提交

**区别**：
- 不可重复读关注**单条记录的值**
- 幻读关注**结果集的行数**

### Q4: MySQL 如何解决幻读？

**回答**：

MySQL 的 RR 隔离级别通过**两种机制**解决幻读：

1. **快照读（普通 SELECT）**：
   - 使用 MVCC
   - 读取的是事务开始时的快照
   - 看不到其他事务的插入

2. **当前读（FOR UPDATE）**：
   - 使用 Next-Key Lock（临键锁）
   - 锁住索引记录 + 间隙
   - 阻止其他事务插入

**示例**：
```sql
-- 快照读
SELECT * FROM t WHERE id > 5;
-- MVCC 保证读取同一快照

-- 当前读
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- Next-Key Lock 锁住 (5, +∞)，阻止插入
```

### Q5: 快照读和当前读的区别？

**快照读**：
- 普通的 SELECT
- 读取历史版本（快照）
- 不加锁
- 使用 MVCC
- 并发性能高

**当前读**：
- SELECT ... FOR UPDATE
- INSERT、UPDATE、DELETE
- 读取最新版本
- 加锁
- 使用锁机制
- 并发性能低

### Q6: Redo Log 和 Undo Log 的区别？

| 特性 | Redo Log | Undo Log |
|------|----------|----------|
| 作用 | 保证持久性 | 保证原子性 + MVCC |
| 内容 | 数据页的**新值** | 数据的**旧值** |
| 时机 | 事务提交时写入 | 修改数据时写入 |
| 用途 | 崩溃恢复（重做） | 事务回滚（撤销） |

### Q7: 什么是两阶段提交？为什么需要？

**什么是**：

事务提交分两个阶段：
1. **Prepare 阶段**：写 Redo Log（状态 prepare）
2. **Commit 阶段**：写 Binlog，然后写 Redo Log（状态 commit）

**为什么需要**：

保证 **Redo Log** 和 **Binlog** 的一致性。

- Redo Log 用于崩溃恢复（主库）
- Binlog 用于主从复制（从库）
- 必须保证两者一致，否则主从数据不一致

**示例**：
```
如果不用两阶段提交：
1. 先写 Redo Log
2. 💥 崩溃（Binlog 未写）
3. 主库恢复：有数据
4. 从库同步：无数据
5. 主从不一致！
```

### Q8: 如何避免长事务？

**长事务的危害**：
- Undo Log 无法清理
- 锁持有时间长
- 影响并发
- 主从延迟

**避免方法**：

1. **拆分大事务**：
   ```sql
   -- 分批处理
   for i in range(0, 100000, 1000):
       BEGIN;
       UPDATE t SET ... WHERE id IN (...);
       COMMIT;
   ```

2. **设置超时**：
   ```sql
   SET innodb_lock_wait_timeout = 10;
   ```

3. **监控长事务**：
   ```sql
   SELECT * FROM information_schema.INNODB_TRX 
   WHERE TIME_TO_SEC(TIMEDIFF(NOW(), trx_started)) > 60;
   ```

4. **及时提交或回滚**

5. **不要在事务中执行耗时操作**（网络请求、文件 IO）

---

## 总结

### 核心要点 ⭐⭐⭐⭐⭐

1. **ACID 特性**：
   - Atomicity：Undo Log
   - Isolation：锁 + MVCC
   - Durability：Redo Log + WAL
   - Consistency：A + I + D

2. **隔离级别**：
   - RU：脏读 + 不可重复读 + 幻读
   - RC：不可重复读 + 幻读
   - RR：解决了幻读（MySQL 默认）
   - SERIALIZABLE：完全隔离

3. **并发问题**：
   - 脏读：读未提交
   - 不可重复读：UPDATE 并提交
   - 幻读：INSERT/DELETE 并提交

4. **幻读的解决**：
   - 快照读：MVCC
   - 当前读：Next-Key Lock

5. **日志系统**：
   - Redo Log：持久性
   - Undo Log：原子性 + MVCC
   - Binlog：主从复制

### 记住这些关键点

- ✅ **ACID 的实现机制**
- ✅ **四种隔离级别及其问题**
- ✅ **脏读、不可重复读、幻读的区别**
- ✅ **快照读 vs 当前读**
- ✅ **Redo Log vs Undo Log**
- ✅ **两阶段提交**
- ✅ **避免长事务**

---

**下一步**：学习 [MVCC 原理](mvcc.md)，深入理解多版本并发控制。
