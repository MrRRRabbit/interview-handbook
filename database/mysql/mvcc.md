# MySQL MVCC 原理

> MVCC（Multi-Version Concurrency Control，多版本并发控制）是 MySQL 实现高并发的核心机制。

## MVCC 基本概念

### 什么是 MVCC？

MVCC（Multi-Version Concurrency Control）是一种并发控制机制，通过维护数据的**多个版本**来实现：
- **读不加锁**
- **写不阻塞读**
- **提高并发性能**

### 为什么需要 MVCC？

**传统方案（锁）的问题**：

```sql
-- 事务 A：读操作
BEGIN;
SELECT * FROM t WHERE id = 1;  -- 加读锁
-- 持有锁很长时间...

-- 事务 B：写操作
BEGIN;
UPDATE t SET a = 1 WHERE id = 1;  -- ⏳ 等待读锁释放
-- 读阻塞了写，并发性能差
```

**MVCC 方案（快照）**：

```sql
-- 事务 A：读操作
BEGIN;
SELECT * FROM t WHERE id = 1;  -- 读快照，不加锁
-- 即使执行很长时间...

-- 事务 B：写操作
BEGIN;
UPDATE t SET a = 1 WHERE id = 1;  -- ✅ 直接执行
-- 读写不冲突，并发性能好
```

### MVCC 的核心思想

```
不是让读操作等待写操作
而是让读操作读取旧版本（快照）
写操作创建新版本

读写互不阻塞！
```

**示意图**：

```
时间线：
事务 A ----[读取版本 1]----------[读取版本 1]----
                |                      |
                ↓                      ↓
版本链：   版本 1 --------→ 版本 2 --------→ 版本 3
                            ↑                  ↑
                            |                  |
事务 B ----[创建版本 2]----    [创建版本 3]----

事务 A 始终读取版本 1（快照）
事务 B 不断创建新版本
互不干扰！
```

### MVCC 只在哪些隔离级别下工作？

MVCC 在 **READ COMMITTED** 和 **REPEATABLE READ** 隔离级别下工作。

- **READ UNCOMMITTED**：直接读最新数据，不需要 MVCC
- **SERIALIZABLE**：完全串行化，不使用 MVCC

---

## MVCC 的三大组件 ⭐⭐⭐⭐⭐

MVCC 由三个核心组件实现，这是**面试必考的内容**。

### 1. 隐藏列（Hidden Columns）

InnoDB 为每行数据添加了**三个隐藏列**：

| 列名 | 长度 | 作用 |
|------|------|------|
| **DB_TRX_ID** | 6 字节 | 最后修改该行的**事务 ID** |
| **DB_ROLL_PTR** | 7 字节 | **回滚指针**，指向 Undo Log 中的上一个版本 |
| **DB_ROW_ID** | 6 字节 | 隐藏的**主键**（如果表没有主键） |

**示例**：

```sql
CREATE TABLE t (
  id INT PRIMARY KEY,
  name VARCHAR(20)
);

INSERT INTO t VALUES (1, 'Alice');

-- 实际存储的数据（包含隐藏列）：
| id | name  | DB_TRX_ID | DB_ROLL_PTR | DB_ROW_ID |
|----|-------|-----------|-------------|-----------|
| 1  | Alice | 100       | NULL        | -         |
```

**关键点**：
- `DB_TRX_ID`：标识是哪个事务修改的
- `DB_ROLL_PTR`：指向上一个版本，形成版本链

### 2. Undo Log 版本链

每次修改数据时，旧版本会被保存到 **Undo Log** 中，通过 `DB_ROLL_PTR` 形成一个**版本链**。

**示例**：

```sql
-- 初始数据
INSERT INTO t VALUES (1, 'Alice');  -- 事务 ID = 100

-- 修改 1
UPDATE t SET name = 'Bob' WHERE id = 1;  -- 事务 ID = 200

-- 修改 2
UPDATE t SET name = 'Charlie' WHERE id = 1;  -- 事务 ID = 300
```

**版本链的形成**：

```
最新版本（当前数据）：
| id | name    | DB_TRX_ID | DB_ROLL_PTR |
|----|---------|-----------|-------------|
| 1  | Charlie | 300       | ptr → 版本 2 |
                              ↓
版本 2（Undo Log）：
| id | name | DB_TRX_ID | DB_ROLL_PTR |
|----|------|-----------|-------------|
| 1  | Bob  | 200       | ptr → 版本 1 |
                           ↓
版本 1（Undo Log）：
| id | name  | DB_TRX_ID | DB_ROLL_PTR |
|----|-------|-----------|-------------|
| 1  | Alice | 100       | NULL        |
```

**图示**：

```
当前版本      版本 2      版本 1
 Charlie  →    Bob    →   Alice
(TRX 300)   (TRX 200)   (TRX 100)
```

**关键点**：
- 版本链是通过 `DB_ROLL_PTR` 连接的
- 版本链保存在 Undo Log 中
- 最新版本在表中，历史版本在 Undo Log 中

### 3. Read View（读视图）⭐⭐⭐⭐⭐

Read View 是一个**数据结构**，用于判断哪些版本对当前事务可见。

**Read View 包含的信息**：

| 字段 | 含义 |
|------|------|
| **m_ids** | 当前活跃的事务 ID 列表 |
| **min_trx_id** | m_ids 中的最小值 |
| **max_trx_id** | 系统应该分配给下一个事务的 ID（当前最大事务 ID + 1） |
| **creator_trx_id** | 创建该 Read View 的事务 ID |

**示例**：

```sql
-- 假设当前有以下事务：
事务 100：已提交
事务 200：活跃中
事务 300：活跃中
事务 400：已提交

-- 事务 500 开始，创建 Read View：
{
  m_ids: [200, 300],        // 活跃的事务
  min_trx_id: 200,          // 最小活跃事务 ID
  max_trx_id: 500,          // 下一个事务 ID
  creator_trx_id: 500       // 当前事务 ID
}
```

**关键点**：
- Read View 记录了**创建快照时**的活跃事务
- 用于判断版本的可见性
- RC 和 RR 级别创建 Read View 的时机不同（重要！）

---

## Read View 详解

### Read View 的创建时机

这是 **RC** 和 **RR** 隔离级别的**核心区别**！

#### READ COMMITTED（RC）

**每次读取数据前都创建一个新的 Read View**

```sql
BEGIN;
SELECT * FROM t WHERE id = 1;  -- 创建 Read View 1
-- 其他事务提交了修改
SELECT * FROM t WHERE id = 1;  -- 创建 Read View 2（新的）
COMMIT;
```

**结果**：
- 每次都能读到最新已提交的数据
- 导致不可重复读

#### REPEATABLE READ（RR）

**只在第一次读取数据时创建 Read View，之后复用**

```sql
BEGIN;
SELECT * FROM t WHERE id = 1;  -- 创建 Read View
-- 其他事务提交了修改
SELECT * FROM t WHERE id = 1;  -- 复用之前的 Read View
COMMIT;
```

**结果**：
- 始终读取同一个快照
- 保证可重复读

### Read View 的作用

用于判断版本链上的哪个版本对当前事务**可见**。

**判断流程**：

```
沿着版本链从新到旧遍历：
  ↓
对每个版本，判断是否可见
  ↓
找到第一个可见的版本
  ↓
返回该版本的数据
```

---

## 可见性判断算法 ⭐⭐⭐⭐⭐

这是 MVCC 的**核心算法**，面试经常要求**手写**或**详细描述**。

### 判断规则

对于版本链上的某个版本，其 `DB_TRX_ID` 记为 `version_trx_id`。

根据以下规则判断该版本是否可见：

#### 规则 1：当前事务自己修改的，可见

```
if (version_trx_id == creator_trx_id) {
    return 可见;  // 自己修改的，肯定可见
}
```

#### 规则 2：版本在 Read View 创建前就已提交，可见

```
if (version_trx_id < min_trx_id) {
    return 可见;  // 已经提交的旧版本
}
```

#### 规则 3：版本是在 Read View 创建后才开始的，不可见

```
if (version_trx_id >= max_trx_id) {
    return 不可见;  // 未来的事务
}
```

#### 规则 4：版本的事务在 Read View 创建时是否活跃

```
if (min_trx_id <= version_trx_id < max_trx_id) {
    if (version_trx_id in m_ids) {
        return 不可见;  // 当时还活跃，未提交
    } else {
        return 可见;    // 当时已经提交
    }
}
```

### 完整算法（伪代码）

```python
def is_visible(version_trx_id, read_view):
    # 规则 1：自己修改的
    if version_trx_id == read_view.creator_trx_id:
        return True
    
    # 规则 2：已提交的旧版本
    if version_trx_id < read_view.min_trx_id:
        return True
    
    # 规则 3：未来的事务
    if version_trx_id >= read_view.max_trx_id:
        return False
    
    # 规则 4：判断是否在活跃列表中
    if version_trx_id in read_view.m_ids:
        return False  # 当时活跃，不可见
    else:
        return True   # 当时已提交，可见

def get_visible_version(row, read_view):
    """沿着版本链找到第一个可见的版本"""
    current = row  # 从最新版本开始
    
    while current is not None:
        if is_visible(current.DB_TRX_ID, read_view):
            return current  # 找到可见版本
        
        # 沿着版本链往前找
        current = get_undo_log(current.DB_ROLL_PTR)
    
    return None  # 没有可见版本
```

### 可见性判断示例

**场景**：

```sql
-- 版本链：
Charlie (TRX 300) → Bob (TRX 200) → Alice (TRX 100)

-- Read View：
{
  m_ids: [200, 300],
  min_trx_id: 200,
  max_trx_id: 400,
  creator_trx_id: 500
}

-- 判断每个版本是否可见：
```

**判断 Charlie（TRX 300）**：

```
version_trx_id = 300
creator_trx_id = 500

1. 300 == 500？ ✗
2. 300 < 200？  ✗
3. 300 >= 400？ ✗
4. 300 in [200, 300]？ ✓ → 不可见

结论：不可见（事务 300 在创建 Read View 时还活跃）
```

**判断 Bob（TRX 200）**：

```
version_trx_id = 200

1. 200 == 500？ ✗
2. 200 < 200？  ✗
3. 200 >= 400？ ✗
4. 200 in [200, 300]？ ✓ → 不可见

结论：不可见（事务 200 在创建 Read View 时还活跃）
```

**判断 Alice（TRX 100）**：

```
version_trx_id = 100

1. 100 == 500？ ✗
2. 100 < 200？  ✓ → 可见

结论：可见（事务 100 在创建 Read View 前就已提交）
```

**最终结果**：读到 **Alice**

---

## RC 和 RR 的 MVCC 区别 ⭐⭐⭐⭐⭐

这是**面试的高频考点**，必须理解两者的区别。

### 核心区别

| 隔离级别 | Read View 创建时机 | 结果 |
|---------|-------------------|------|
| **READ COMMITTED** | 每次读取前都创建 | 能读到其他事务的最新提交 |
| **REPEATABLE READ** | 第一次读取时创建，之后复用 | 读取的是事务开始时的快照 |

### 详细示例

#### 场景设置

```sql
-- 初始数据
id = 1, name = 'Alice', DB_TRX_ID = 100（已提交）

-- 时间线：
T1: 事务 A 开始（TRX 200）
T2: 事务 B 开始（TRX 300）
T3: 事务 A 第一次读取
T4: 事务 B 修改并提交
T5: 事务 A 第二次读取
```

#### READ COMMITTED 场景

```sql
-- T1: 事务 A 开始
BEGIN;  -- TRX 200

-- T2: 事务 B 开始
BEGIN;  -- TRX 300

-- T3: 事务 A 第一次读取
SELECT name FROM t WHERE id = 1;

-- 创建 Read View 1：
{
  m_ids: [200, 300],
  min_trx_id: 200,
  max_trx_id: 400,
  creator_trx_id: 200
}

-- 版本链：Alice (TRX 100)
-- 判断：100 < 200 → 可见
-- 读取：Alice ✅

-- T4: 事务 B 修改并提交
UPDATE t SET name = 'Bob' WHERE id = 1;
COMMIT;

-- 版本链：Bob (TRX 300) → Alice (TRX 100)

-- T5: 事务 A 第二次读取
SELECT name FROM t WHERE id = 1;

-- ⚠️ RC 级别：创建新的 Read View 2
{
  m_ids: [200],        // 事务 B 已提交，不在活跃列表中
  min_trx_id: 200,
  max_trx_id: 400,
  creator_trx_id: 200
}

-- 判断 Bob (TRX 300)：
-- 300 in [200]？ ✗ → 可见（事务 300 已提交）
-- 读取：Bob ✅

-- 结果：第二次读取到了新数据（不可重复读）
```

#### REPEATABLE READ 场景

```sql
-- T1: 事务 A 开始
BEGIN;  -- TRX 200

-- T2: 事务 B 开始
BEGIN;  -- TRX 300

-- T3: 事务 A 第一次读取
SELECT name FROM t WHERE id = 1;

-- 创建 Read View：
{
  m_ids: [200, 300],
  min_trx_id: 200,
  max_trx_id: 400,
  creator_trx_id: 200
}

-- 版本链：Alice (TRX 100)
-- 判断：100 < 200 → 可见
-- 读取：Alice ✅

-- T4: 事务 B 修改并提交
UPDATE t SET name = 'Bob' WHERE id = 1;
COMMIT;

-- 版本链：Bob (TRX 300) → Alice (TRX 100)

-- T5: 事务 A 第二次读取
SELECT name FROM t WHERE id = 1;

-- ⚠️ RR 级别：复用之前的 Read View
{
  m_ids: [200, 300],   // 还是之前的活跃列表
  min_trx_id: 200,
  max_trx_id: 400,
  creator_trx_id: 200
}

-- 判断 Bob (TRX 300)：
-- 300 in [200, 300]？ ✓ → 不可见（在创建 Read View 时，事务 300 还活跃）

-- 继续沿版本链查找
-- 判断 Alice (TRX 100)：
-- 100 < 200 → 可见
-- 读取：Alice ✅

-- 结果：第二次还是读取到旧数据（可重复读）
```

### 对比总结

```
READ COMMITTED：
事务 A 第一次读 → 创建 Read View 1 → 读到 Alice
事务 B 修改提交
事务 A 第二次读 → 创建 Read View 2 → 读到 Bob
结果：不可重复读

REPEATABLE READ：
事务 A 第一次读 → 创建 Read View → 读到 Alice
事务 B 修改提交
事务 A 第二次读 → 复用 Read View → 读到 Alice
结果：可重复读
```

---

## MVCC 完整示例

### 示例 1：单事务修改，多事务读取

**时间线**：

```
T1: 事务 A 开始（TRX 100）
T2: 事务 A 修改 name = 'Bob'
T3: 事务 B 开始（TRX 200）
T4: 事务 B 读取
T5: 事务 A 提交
T6: 事务 B 再次读取
```

**执行过程**：

```sql
-- T1: 事务 A 开始
BEGIN;  -- TRX 100

-- T2: 事务 A 修改
UPDATE t SET name = 'Bob' WHERE id = 1;

-- 版本链：Bob (TRX 100) → Alice (TRX 50，已提交)

-- T3: 事务 B 开始（RR 隔离级别）
BEGIN;  -- TRX 200

-- T4: 事务 B 读取
SELECT name FROM t WHERE id = 1;

-- 创建 Read View：
{
  m_ids: [100, 200],
  min_trx_id: 100,
  max_trx_id: 300,
  creator_trx_id: 200
}

-- 判断 Bob (TRX 100)：
-- 100 in [100, 200]？ ✓ → 不可见

-- 判断 Alice (TRX 50)：
-- 50 < 100 → 可见

-- 读取：Alice ✅

-- T5: 事务 A 提交
COMMIT;

-- T6: 事务 B 再次读取
SELECT name FROM t WHERE id = 1;

-- 复用 Read View：
{
  m_ids: [100, 200],  // 还是之前的
  ...
}

-- 判断 Bob (TRX 100)：
-- 100 in [100, 200]？ ✓ → 不可见
-- （虽然事务 A 已提交，但在创建 Read View 时还活跃）

-- 判断 Alice (TRX 50)：
-- 50 < 100 → 可见

-- 读取：Alice ✅

COMMIT;
```

### 示例 2：多个版本的查找

**版本链**：

```
David (TRX 400) → Charlie (TRX 300) → Bob (TRX 200) → Alice (TRX 100)
```

**Read View**：

```
{
  m_ids: [200, 300],
  min_trx_id: 200,
  max_trx_id: 500,
  creator_trx_id: 500
}
```

**查找过程**：

```
1. 判断 David (TRX 400)：
   400 >= 500？ ✗
   400 in [200, 300]？ ✗ → 可见 ✅
   
   找到可见版本：David
```

如果 David 不可见：

```
2. 判断 Charlie (TRX 300)：
   300 in [200, 300]？ ✓ → 不可见
   
3. 判断 Bob (TRX 200)：
   200 in [200, 300]？ ✓ → 不可见
   
4. 判断 Alice (TRX 100)：
   100 < 200 → 可见 ✅
   
   找到可见版本：Alice
```

---

## MVCC 的局限性

### 1. 只对快照读有效 ⭐⭐⭐⭐⭐

MVCC 只对**普通的 SELECT**（快照读）有效，对**当前读无效**。

```sql
-- 快照读：使用 MVCC
SELECT * FROM t WHERE id = 1;  -- 读历史版本，不加锁

-- 当前读：使用锁
SELECT * FROM t WHERE id = 1 FOR UPDATE;  -- 读最新版本，加锁
```

### 2. 无法解决当前读的幻读

**场景**：

```sql
-- RR 隔离级别

-- 事务 A
BEGIN;
SELECT * FROM t WHERE id > 5 FOR UPDATE;  -- 当前读
-- 返回 id=10（1 条）

-- 事务 B
BEGIN;
INSERT INTO t VALUES (7, ...);
COMMIT;

-- 事务 A
SELECT * FROM t WHERE id > 5 FOR UPDATE;  -- 当前读
-- 返回 id=7, id=10（2 条）
-- 幻读！
```

**解决方案**：**Next-Key Lock**（临键锁）

```sql
-- 事务 A
BEGIN;
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 加锁：(5, +∞) 的临键锁

-- 事务 B
BEGIN;
INSERT INTO t VALUES (7, ...);  -- ⏳ 被间隙锁阻塞
```

### 3. 写操作不使用 MVCC

```sql
-- UPDATE、DELETE、INSERT 都是当前读
UPDATE t SET name = 'Bob' WHERE id = 1;
-- 读取最新版本，加锁，不使用 MVCC
```

### 总结

```
MVCC 的适用范围：
├── 快照读（普通 SELECT）        ✅ 使用 MVCC
├── 当前读（FOR UPDATE）          ❌ 使用锁
├── INSERT、UPDATE、DELETE       ❌ 使用锁
└── 幻读的完整解决
    ├── 快照读的幻读               ✅ MVCC 解决
    └── 当前读的幻读               ✅ Next-Key Lock 解决
```

---

## 面试高频问题 ⭐⭐⭐⭐⭐

### Q1: 什么是 MVCC？

**回答**：

MVCC（Multi-Version Concurrency Control）是一种多版本并发控制机制，通过维护数据的多个版本来实现：

1. **读不加锁**：读取历史版本（快照），不需要加锁
2. **写不阻塞读**：写操作创建新版本，不影响读操作
3. **提高并发**：读写互不阻塞

**核心思想**：
- 不是让读等待写
- 而是让读读取旧版本
- 写创建新版本

### Q2: MVCC 的实现原理？

**回答**：

MVCC 由**三大组件**实现：

1. **隐藏列**：
   - `DB_TRX_ID`：事务 ID
   - `DB_ROLL_PTR`：回滚指针
   - `DB_ROW_ID`：隐藏主键

2. **Undo Log 版本链**：
   - 每次修改保存旧版本
   - 通过 `DB_ROLL_PTR` 形成链表
   - 示例：Charlie → Bob → Alice

3. **Read View**：
   - 记录活跃事务列表
   - 判断版本可见性
   - RC 和 RR 创建时机不同

**可见性判断**：
- 自己修改的：可见
- 已提交的旧版本：可见
- 未来的事务：不可见
- 活跃的事务：不可见

### Q3: RC 和 RR 的 MVCC 有什么区别？

**回答**：

核心区别在于 **Read View 的创建时机**：

**READ COMMITTED**：
- 每次读取前都创建新的 Read View
- 能读到其他事务的最新提交
- 导致不可重复读

**REPEATABLE READ**：
- 只在第一次读取时创建 Read View
- 之后的读取复用同一个 Read View
- 保证可重复读

**示例**：
```sql
-- RC 级别
BEGIN;
SELECT * FROM t;  -- 创建 Read View 1
-- 其他事务提交
SELECT * FROM t;  -- 创建 Read View 2（新的）
-- 读到不同的数据（不可重复读）

-- RR 级别
BEGIN;
SELECT * FROM t;  -- 创建 Read View
-- 其他事务提交
SELECT * FROM t;  -- 复用 Read View
-- 读到相同的数据（可重复读）
```

### Q4: MVCC 如何判断版本可见性？

**回答**：

有**四条规则**：

```
假设版本的事务 ID 是 version_trx_id
Read View 包含：m_ids, min_trx_id, max_trx_id, creator_trx_id

规则 1：自己修改的
if (version_trx_id == creator_trx_id)
    → 可见

规则 2：已提交的旧版本
if (version_trx_id < min_trx_id)
    → 可见

规则 3：未来的事务
if (version_trx_id >= max_trx_id)
    → 不可见

规则 4：判断是否活跃
if (min_trx_id <= version_trx_id < max_trx_id)
    if (version_trx_id in m_ids)
        → 不可见（还活跃）
    else
        → 可见（已提交）
```

**查找流程**：
1. 从最新版本开始
2. 依次判断每个版本是否可见
3. 返回第一个可见的版本

### Q5: 快照读和当前读的区别？

**快照读**：
- 普通的 SELECT
- 读取历史版本
- 不加锁
- 使用 MVCC

**当前读**：
- SELECT ... FOR UPDATE
- INSERT、UPDATE、DELETE
- 读取最新版本
- 加锁
- 不使用 MVCC

### Q6: MVCC 能完全解决幻读吗？

**回答**：

**不能完全解决**，需要配合 Next-Key Lock。

**快照读的幻读**：✅ MVCC 解决
```sql
SELECT * FROM t WHERE id > 5;
-- 读取快照，MVCC 保证结果集不变
```

**当前读的幻读**：❌ MVCC 无法解决，需要 Next-Key Lock
```sql
SELECT * FROM t WHERE id > 5 FOR UPDATE;
-- 当前读，需要 Next-Key Lock 锁住间隙
```

**完整解决方案**：
```
RR 隔离级别下：
- 快照读：MVCC
- 当前读：Next-Key Lock
两者配合，彻底解决幻读
```

### Q7: 为什么 UPDATE 语句是当前读？

**回答**：

UPDATE 必须基于**最新数据**修改，不能基于快照。

**如果使用快照读（错误）**：
```sql
-- 事务 A
BEGIN;
SELECT balance FROM account WHERE id = 1;  -- 快照读：1000
UPDATE account SET balance = 1000 + 100 WHERE id = 1;

-- 事务 B（在事务 A 之前提交）
UPDATE account SET balance = 1000 - 200 WHERE id = 1;
-- balance = 800
COMMIT;

-- 事务 A 提交
COMMIT;
-- balance = 1100（错误！应该是 900）
```

**使用当前读（正确）**：
```sql
-- 事务 A
BEGIN;
UPDATE account SET balance = balance + 100 WHERE id = 1;
-- 当前读，读到 800
-- balance = 900 ✅
COMMIT;
```

### Q8: MVCC 的优缺点？

**优点**：
1. ✅ **读写不阻塞**：提高并发性能
2. ✅ **读不加锁**：避免锁开销
3. ✅ **实现快照隔离**：保证一致性读

**缺点**：
1. ❌ **额外存储开销**：需要维护多个版本
2. ❌ **只对快照读有效**：当前读仍需加锁
3. ❌ **需要清理旧版本**：Purge 操作有开销

---

## 总结

### 核心要点 ⭐⭐⭐⭐⭐

1. **MVCC 的三大组件**：
   - 隐藏列：DB_TRX_ID、DB_ROLL_PTR
   - Undo Log 版本链
   - Read View

2. **可见性判断**：
   - 自己修改的：可见
   - 已提交的旧版本：可见
   - 未来的事务：不可见
   - 活跃的事务：不可见

3. **RC vs RR**：
   - RC：每次创建新 Read View
   - RR：第一次创建，后续复用

4. **MVCC 的局限**：
   - 只对快照读有效
   - 当前读需要加锁
   - 需要配合 Next-Key Lock 解决幻读

### 记住这些关键点

- ✅ **三大组件**
- ✅ **四条可见性规则**
- ✅ **RC 和 RR 的 Read View 创建时机**
- ✅ **快照读 vs 当前读**
- ✅ **MVCC + Next-Key Lock 解决幻读**

### 学习建议

1. **画图理解**：
   - 画出版本链
   - 画出 Read View
   - 画出可见性判断过程

2. **动手实验**：
   - 搭建 MySQL 环境
   - 模拟不同隔离级别
   - 验证可见性规则

3. **结合锁机制**：
   - MVCC 解决读-写冲突
   - 锁解决写-写冲突
   - 两者配合实现隔离性

---

**相关文档**：
- [MySQL 锁机制](lock.md)
- [MySQL 事务](transaction.md)
