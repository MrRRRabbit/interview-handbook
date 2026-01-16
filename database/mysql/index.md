# MySQL 索引原理与优化

> 索引是数据库性能优化的关键，理解索引原理是写出高效 SQL 的基础。

## 📚 目录

- [索引的基本概念](#索引的基本概念)
- [索引数据结构](#索引数据结构)
- [索引类型](#索引类型)
- [聚簇索引与非聚簇索引](#聚簇索引与非聚簇索引)
- [索引优化](#索引优化)
- [执行计划分析](#执行计划分析)
- [面试高频问题](#面试高频问题)
- [总结](#总结)

---

## 索引的基本概念

### 什么是索引？

索引是帮助 MySQL 高效获取数据的**数据结构**。可以类比为书籍的目录：

```
没有索引：从第一页开始翻，直到找到目标内容（全表扫描）
有索引：先查目录，直接定位到目标页码（索引查找）
```

### 为什么需要索引？

**场景：在 1000 万条数据中查找一条记录**

```sql
-- 没有索引
SELECT * FROM users WHERE phone = '13800138000';
-- 全表扫描：扫描 1000 万行，耗时数秒甚至数分钟

-- 有索引
SELECT * FROM users WHERE phone = '13800138000';
-- 索引查找：定位到几行数据，耗时毫秒级
```

### 索引的代价

| 优点 | 代价 |
|------|------|
| 加快查询速度 | 占用额外存储空间 |
| 加快排序速度 | 降低写入性能（INSERT/UPDATE/DELETE） |
| 加快分组速度 | 需要维护索引结构 |

**结论**：索引不是越多越好，需要权衡利弊。

---

## 索引数据结构 ⭐⭐⭐⭐⭐

### B+ Tree 索引

InnoDB 使用 **B+ Tree** 作为默认索引结构，这是面试必考点。

#### B+ Tree 的结构

```
                    ┌─────────────────┐
                    │  [15] [30] [50] │  ← 根节点（只存键）
                    └────┬───┬───┬───┘
                         │   │   │
         ┌───────────────┘   │   └───────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
    ┌─────────┐        ┌─────────┐        ┌─────────┐
    │ [5][10] │        │[20][25] │        │[35][45] │  ← 中间节点
    └──┬──┬───┘        └──┬──┬───┘        └──┬──┬───┘
       │  │               │  │               │  │
       ▼  ▼               ▼  ▼               ▼  ▼
    ┌─────────────────────────────────────────────┐
    │ [1]↔[5]↔[10]↔[15]↔[20]↔[25]↔[30]↔[35]↔[45] │  ← 叶子节点（存数据）
    └─────────────────────────────────────────────┘
                    双向链表连接
```

#### B+ Tree 的特点

| 特点 | 说明 |
|------|------|
| **所有数据在叶子节点** | 非叶子节点只存索引键，不存数据 |
| **叶子节点形成双向链表** | 支持高效的范围查询 |
| **非叶子节点可存更多键** | 降低树高，减少 IO 次数 |
| **查询复杂度稳定** | 所有查询都要走到叶子节点，O(log n) |

#### 为什么选择 B+ Tree？⭐⭐⭐⭐⭐

**为什么不用 B Tree？**

```
B Tree vs B+ Tree：

B Tree：                              B+ Tree：
┌────────────────────┐               ┌────────────────────┐
│ [15,data] [30,data]│               │   [15]    [30]     │  ← 无数据
└────────────────────┘               └────────────────────┘

├─ 数据存在所有节点                    ├─ 数据只存叶子节点
├─ 每个节点能存的键更少                ├─ 每个节点能存的键更多
├─ 树更高                             ├─ 树更矮（IO 更少）
└─ 范围查询需要中序遍历                └─ 范围查询只需遍历叶子链表
```

**为什么不用红黑树（平衡二叉树）？**

```
红黑树 vs B+ Tree：

红黑树：每个节点只有 2 个子节点
├─ 1000 万数据，树高约 24 层
├─ 查一条数据需要 24 次 IO
└─ 太慢！

B+ Tree：每个节点可有上千个子节点（取决于页大小）
├─ 1000 万数据，树高约 3-4 层
├─ 查一条数据需要 3-4 次 IO
└─ 很快！
```

**为什么不用哈希表？**

```
哈希表：
├─ 等值查询 O(1)，很快 ✅
├─ 不支持范围查询 ❌（WHERE id > 10）
├─ 不支持排序 ❌（ORDER BY）
├─ 不支持最左前缀匹配 ❌
└─ 存在哈希冲突

B+ Tree：
├─ 等值查询 O(log n)，稍慢
├─ 支持范围查询 ✅
├─ 支持排序 ✅
├─ 支持最左前缀匹配 ✅
└─ 更通用
```

#### B+ Tree 索引的查找过程

```sql
-- 假设查询：SELECT * FROM t WHERE id = 25;

步骤：
1. 从根节点开始：[15, 30, 50]
   ├─ 25 > 15，继续往右
   └─ 25 < 30，进入 [15, 30) 区间的子节点

2. 到达中间节点：[20, 25]
   └─ 25 == 25，进入对应的叶子节点

3. 到达叶子节点：找到 id=25 的完整数据

总共：3 次 IO（根节点常驻内存，实际可能只有 2 次）
```

#### 一页能存多少数据？

```
InnoDB 页大小：16KB

假设：
├─ 主键为 BIGINT（8 字节）
├─ 指针大小 6 字节
└─ 每个索引项 = 8 + 6 = 14 字节

非叶子节点能存的索引项：16KB / 14B ≈ 1170 个

假设叶子节点每行数据 1KB：
└─ 每个叶子节点存 16 行数据

三层 B+ Tree 能存：
├─ 第一层：1 个节点
├─ 第二层：1170 个节点
├─ 第三层：1170 * 1170 = 136 万个节点
└─ 总数据：136 万 * 16 = 约 2100 万行

结论：3 层 B+ Tree 可存 2000 万+ 数据，只需 3 次 IO！
```

### Hash 索引

#### Hash 索引的特点

```
Hash 索引结构：

         哈希函数
            │
            ▼
┌─────────────────────────────────────┐
│ Bucket 0: → [data1] → [data2]      │
│ Bucket 1: → [data3]                │
│ Bucket 2: → (empty)                │
│ Bucket 3: → [data4] → [data5]      │
│ ...                                 │
└─────────────────────────────────────┘

特点：
├─ 通过哈希函数计算 bucket 位置
├─ 等值查询 O(1)
└─ 哈希冲突用链表解决
```

#### 使用场景

| 场景 | 是否适合 Hash 索引 |
|------|-------------------|
| 等值查询（WHERE id = 10） | ✅ 适合 |
| 范围查询（WHERE id > 10） | ❌ 不适合 |
| 排序（ORDER BY id） | ❌ 不适合 |
| 前缀匹配（WHERE name LIKE 'abc%'） | ❌ 不适合 |

#### InnoDB 中的 Hash

```sql
-- InnoDB 不支持显式创建 Hash 索引
-- 但有自适应哈希索引（Adaptive Hash Index）

-- 查看自适应哈希索引状态
SHOW VARIABLES LIKE 'innodb_adaptive_hash_index';

-- 特点：
-- 1. InnoDB 自动为热点页建立哈希索引
-- 2. 用户无法控制
-- 3. 加速等值查询
```

**Memory 引擎支持 Hash 索引**：

```sql
-- Memory 引擎可以显式创建 Hash 索引
CREATE TABLE mem_table (
    id INT,
    name VARCHAR(50),
    INDEX USING HASH (id)
) ENGINE = MEMORY;
```

---

## 索引类型

### 主键索引（Primary Key）⭐⭐⭐⭐⭐

主键索引是一种特殊的唯一索引，每个表只能有一个。

```sql
-- 创建主键索引
CREATE TABLE users (
    id BIGINT PRIMARY KEY,        -- 方式 1
    name VARCHAR(50)
);

CREATE TABLE users (
    id BIGINT,
    name VARCHAR(50),
    PRIMARY KEY (id)              -- 方式 2
);

-- 已有表添加主键
ALTER TABLE users ADD PRIMARY KEY (id);
```

**主键选择建议**：

| 方案 | 优点 | 缺点 |
|------|------|------|
| **自增主键** | 顺序插入，性能好 | 分布式环境有问题 |
| **UUID** | 全局唯一 | 无序，插入性能差 |
| **业务主键** | 业务含义明确 | 可能需要修改，有风险 |

**自增主键的优势**：

```
自增主键（顺序插入）：
┌─────────────────────────────────────────┐
│ [1][2][3][4][5][6][7][8]...            │
└─────────────────────────────────────────┘
├─ 新数据追加在末尾
├─ 不需要页分裂
└─ 插入效率高 ✅

UUID/随机主键：
┌─────────────────────────────────────────┐
│ [a][?][c][?][e][?][g]...               │  ← 随机位置插入
└─────────────────────────────────────────┘
├─ 新数据可能插入中间
├─ 频繁页分裂
└─ 插入效率低 ❌
```

### 唯一索引（Unique Index）

唯一索引确保列值不重复。

```sql
-- 创建唯一索引
CREATE UNIQUE INDEX idx_phone ON users(phone);

-- 或者
ALTER TABLE users ADD UNIQUE INDEX idx_phone (phone);

-- 创建表时指定
CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    phone VARCHAR(20),
    UNIQUE KEY idx_phone (phone)
);
```

**唯一索引 vs 普通索引**：

| 特性 | 唯一索引 | 普通索引 |
|------|---------|---------|
| 值可重复 | ❌ | ✅ |
| 插入检查 | 需要检查唯一性 | 不需要 |
| 插入性能 | 稍慢 | 稍快 |
| Change Buffer | 不能使用 | 可以使用 |

### 普通索引（Normal Index）

最基本的索引类型，没有任何限制。

```sql
-- 创建普通索引
CREATE INDEX idx_name ON users(name);

-- 或者
ALTER TABLE users ADD INDEX idx_name (name);
```

### 全文索引（Full-Text Index）

用于全文搜索，适合大文本字段。

```sql
-- 创建全文索引
CREATE FULLTEXT INDEX idx_content ON articles(content);

-- 使用全文索引
SELECT * FROM articles
WHERE MATCH(content) AGAINST('MySQL 优化');

-- 注意：
-- 1. InnoDB 从 MySQL 5.6 开始支持全文索引
-- 2. 默认只对英文分词，中文需要 ngram 解析器
-- 3. 生产环境建议使用 Elasticsearch
```

### 组合索引（Composite Index）⭐⭐⭐⭐⭐

组合索引是在多个列上创建的索引。

```sql
-- 创建组合索引
CREATE INDEX idx_name_age ON users(name, age);

-- 等价于创建了：
-- 1. (name) 的索引
-- 2. (name, age) 的索引
-- 注意：没有单独的 (age) 索引！
```

#### 最左前缀原则 ⭐⭐⭐⭐⭐

组合索引遵循**最左前缀原则**，这是面试高频考点。

```sql
-- 假设有组合索引 idx(a, b, c)

-- 能使用索引的查询：
WHERE a = 1                      -- ✅ 使用 a
WHERE a = 1 AND b = 2            -- ✅ 使用 a, b
WHERE a = 1 AND b = 2 AND c = 3  -- ✅ 使用 a, b, c
WHERE a = 1 AND c = 3            -- ⚠️ 只使用 a（跳过了 b）
WHERE a = 1 AND b > 2 AND c = 3  -- ⚠️ 使用 a, b（c 无法使用，因为 b 是范围）

-- 不能使用索引的查询：
WHERE b = 2                      -- ❌ 没有最左列 a
WHERE c = 3                      -- ❌ 没有最左列 a
WHERE b = 2 AND c = 3            -- ❌ 没有最左列 a
```

**最左前缀原则的原因**：

```
组合索引 (a, b, c) 的 B+ Tree 结构：

先按 a 排序，a 相同时按 b 排序，b 相同时按 c 排序

┌──────────────────────────────────────────────────────┐
│ (1,1,1)(1,1,2)(1,2,1)(1,2,2)(2,1,1)(2,1,2)(2,2,1)... │
└──────────────────────────────────────────────────────┘
      └───────────────┘└───────────────┘
          a=1 的数据      a=2 的数据

可以看到：
├─ 整体按 a 有序 → 可以用 a 查询
├─ 在 a=1 内，按 b 有序 → 可以用 (a, b) 查询
├─ 单独看 b 列，整体无序 → 不能单独用 b 查询
└─ 单独看 c 列，整体无序 → 不能单独用 c 查询
```

#### 索引下推（Index Condition Pushdown, ICP）

MySQL 5.6 引入的优化，减少回表次数。

```sql
-- 假设有索引 idx(name, age)，查询：
SELECT * FROM users WHERE name LIKE 'Zhang%' AND age = 25;

-- 无 ICP（MySQL 5.6 之前）：
-- 1. 索引找到所有 name LIKE 'Zhang%' 的记录
-- 2. 每条记录都回表
-- 3. 回表后再判断 age = 25

-- 有 ICP（MySQL 5.6+）：
-- 1. 索引找到所有 name LIKE 'Zhang%' 的记录
-- 2. 在索引层直接判断 age = 25
-- 3. 只有满足条件的才回表

-- 效果：减少回表次数，提高性能

-- EXPLAIN 中看到 "Using index condition" 表示使用了 ICP
```

---

## 聚簇索引与非聚簇索引 ⭐⭐⭐⭐⭐

这是 InnoDB 索引的核心概念，必须深入理解。

### 聚簇索引（Clustered Index）

**定义**：数据和索引存储在一起的索引。InnoDB 的主键索引就是聚簇索引。

```
聚簇索引结构：

           ┌────────────────────────┐
           │      [15] [30]         │  ← 非叶子节点：只存主键
           └──────────┬─────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
    ┌─────────┐               ┌─────────┐
    │[5] [10] │               │[20][25] │  ← 非叶子节点
    └────┬────┘               └────┬────┘
         │                         │
         ▼                         ▼
┌──────────────┐           ┌──────────────┐
│ id=5:  {...} │           │ id=20: {...} │
│ id=10: {...} │ ←──────→  │ id=25: {...} │  ← 叶子节点：存完整行数据
└──────────────┘           └──────────────┘
   双向链表连接
```

**聚簇索引的特点**：

| 特点 | 说明 |
|------|------|
| 一个表只能有一个 | 数据只能按一种方式排序存储 |
| 叶子节点存完整行数据 | 找到索引就找到了数据 |
| 主键查询效率高 | 不需要回表 |
| 顺序插入效率高 | 自增主键最佳 |

**InnoDB 聚簇索引的选择规则**：

```
1. 如果有主键 → 主键作为聚簇索引
2. 如果没有主键，但有唯一非空索引 → 第一个唯一非空索引作为聚簇索引
3. 都没有 → InnoDB 自动生成一个隐藏的 ROW_ID 作为聚簇索引
```

### 非聚簇索引（Secondary Index / 二级索引）

**定义**：叶子节点存储的是主键值，而不是完整行数据。

```
非聚簇索引结构（假设在 name 列上建索引）：

           ┌────────────────────────┐
           │   [Li] [Wang] [Zhang]  │  ← 非叶子节点：存 name 值
           └──────────┬─────────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
    ┌──────────┐              ┌──────────┐
    │[Chen][Li]│              │[Wang][Wu]│  ← 非叶子节点
    └────┬─────┘              └────┬─────┘
         │                         │
         ▼                         ▼
┌────────────────┐         ┌────────────────┐
│ Chen → id=15  │         │ Wang → id=8   │
│ Li   → id=3   │ ←────→  │ Wu   → id=22  │  ← 叶子节点：存主键值
└────────────────┘         └────────────────┘

注意：叶子节点只存 name 和对应的主键 id，不存完整行数据！
```

### 回表查询 ⭐⭐⭐⭐⭐

通过非聚簇索引查询时，如果需要的列不在索引中，就需要**回表**。

```sql
-- 假设有索引 idx_name(name)
SELECT * FROM users WHERE name = 'Zhang';

查询过程：
1. 在 name 索引中找到 name='Zhang'，得到主键 id=10
2. 用 id=10 去主键索引（聚簇索引）中查找完整行数据
3. 返回结果

这个过程称为"回表"

┌──────────────┐      ┌──────────────┐
│  name 索引    │ ──→  │  主键索引    │
│ Zhang → id=10│      │ id=10: {...} │
└──────────────┘      └──────────────┘
    第一次查找              第二次查找（回表）
```

**回表的代价**：
- 多一次 B+ Tree 查找
- 如果回表数据量大，性能下降明显

### 覆盖索引 ⭐⭐⭐⭐⭐

如果查询的列都在索引中，就不需要回表，称为**覆盖索引**。

```sql
-- 假设有索引 idx_name_age(name, age)

-- 需要回表：
SELECT * FROM users WHERE name = 'Zhang';
-- 索引中没有其他列，需要回表

-- 不需要回表（覆盖索引）：
SELECT name, age FROM users WHERE name = 'Zhang';
-- 所需的 name, age 都在索引中，不需要回表 ✅

-- EXPLAIN 中 Extra 显示 "Using index" 表示使用了覆盖索引
```

**覆盖索引优化示例**：

```sql
-- 原始查询（需要回表）
SELECT id, name, age FROM users WHERE name = 'Zhang';

-- 优化方案 1：创建覆盖索引
CREATE INDEX idx_name_age ON users(name, age);
-- 现在 id（主键自动包含）、name、age 都在索引中，无需回表

-- 优化方案 2：减少查询列
SELECT name FROM users WHERE name = 'Zhang';
-- 只查 name，原索引就是覆盖索引
```

### 索引结构对比总结

| 特性 | 聚簇索引 | 非聚簇索引 |
|------|---------|-----------|
| 叶子节点内容 | 完整行数据 | 主键值 |
| 数量限制 | 一个表只有一个 | 可以有多个 |
| 查询效率 | 高（不需要回表） | 可能需要回表 |
| 插入效率 | 取决于主键顺序 | 取决于索引列顺序 |
| 存储方式 | 数据即索引 | 索引和数据分离 |

---

## 索引优化 ⭐⭐⭐⭐⭐

### 索引失效场景

了解哪些情况会导致索引失效，是写出高效 SQL 的关键。

#### 1. 对索引列使用函数或表达式

```sql
-- 假设 create_time 有索引

-- ❌ 索引失效
SELECT * FROM orders WHERE YEAR(create_time) = 2024;
SELECT * FROM orders WHERE create_time + 1 = '2024-01-02';

-- ✅ 索引有效
SELECT * FROM orders
WHERE create_time >= '2024-01-01' AND create_time < '2025-01-01';
```

**原因**：对列使用函数后，需要对每行数据计算函数值，无法利用 B+ Tree 的有序性。

#### 2. 隐式类型转换

```sql
-- 假设 phone 是 VARCHAR 类型，有索引

-- ❌ 索引失效
SELECT * FROM users WHERE phone = 13800138000;
-- phone 是字符串，13800138000 是数字
-- MySQL 会把 phone 转为数字比较，相当于对 phone 用了函数

-- ✅ 索引有效
SELECT * FROM users WHERE phone = '13800138000';
```

**类型转换规则**：
```
字符串和数字比较 → 字符串转为数字
字符串和日期比较 → 字符串转为日期
```

#### 3. 前导模糊查询

```sql
-- 假设 name 有索引

-- ❌ 索引失效
SELECT * FROM users WHERE name LIKE '%Zhang';
SELECT * FROM users WHERE name LIKE '%Zhang%';

-- ✅ 索引有效
SELECT * FROM users WHERE name LIKE 'Zhang%';
```

**原因**：B+ Tree 索引是按字符顺序排序的，`%` 在前面无法定位起始位置。

#### 4. OR 条件（部分列无索引）

```sql
-- 假设 name 有索引，age 没有索引

-- ❌ 索引可能失效
SELECT * FROM users WHERE name = 'Zhang' OR age = 25;
-- MySQL 可能选择全表扫描

-- ✅ 优化方案
-- 方案 1：给 age 也加索引
-- 方案 2：改用 UNION
SELECT * FROM users WHERE name = 'Zhang'
UNION
SELECT * FROM users WHERE age = 25;
```

#### 5. 不等于条件

```sql
-- 假设 status 有索引

-- ⚠️ 可能索引失效（取决于数据分布）
SELECT * FROM users WHERE status != 1;
SELECT * FROM users WHERE status <> 1;
SELECT * FROM users WHERE status NOT IN (1, 2);

-- 如果 status != 1 的数据很多，MySQL 可能选择全表扫描
```

**原因**：不等于条件可能匹配大量数据，此时全表扫描可能比索引更快。

#### 6. IS NULL / IS NOT NULL

```sql
-- 假设 email 有索引

-- ⚠️ 可能索引失效（取决于数据分布）
SELECT * FROM users WHERE email IS NULL;
SELECT * FROM users WHERE email IS NOT NULL;
```

**建议**：尽量避免 NULL 值，使用默认值代替。

#### 7. 联合索引不满足最左前缀

```sql
-- 假设有索引 idx(a, b, c)

-- ❌ 索引失效
SELECT * FROM t WHERE b = 1;
SELECT * FROM t WHERE c = 1;
SELECT * FROM t WHERE b = 1 AND c = 2;
```

### 索引设计原则

#### 1. 选择性高的列建索引

**选择性** = 不重复值数量 / 总行数

```sql
-- 查看列的选择性
SELECT
    COUNT(DISTINCT column_name) / COUNT(*) AS selectivity
FROM table_name;

-- 选择性接近 1：适合建索引（如身份证号、手机号）
-- 选择性很低：不太适合单独建索引（如性别、状态）
```

#### 2. 考虑查询频率和方式

```sql
-- 根据实际查询建索引
-- 如果经常这样查询：
SELECT * FROM orders WHERE user_id = ? AND status = ?;

-- 应该建立组合索引：
CREATE INDEX idx_user_status ON orders(user_id, status);
```

#### 3. 避免冗余索引

```sql
-- 冗余索引示例
CREATE INDEX idx_a ON t(a);
CREATE INDEX idx_a_b ON t(a, b);
-- idx_a 是冗余的，idx_a_b 可以覆盖 idx_a 的功能

-- 检查冗余索引
SELECT * FROM sys.schema_redundant_indexes;
```

#### 4. 考虑索引的维护成本

```sql
-- 写多读少的表：少建索引
-- 读多写少的表：可以多建索引

-- 频繁更新的列：谨慎建索引
-- 经常作为条件的列：应该建索引
```

#### 5. 使用前缀索引

对于很长的字符串列，可以只索引前缀部分。

```sql
-- 完整索引
CREATE INDEX idx_email ON users(email);

-- 前缀索引（只索引前 10 个字符）
CREATE INDEX idx_email ON users(email(10));

-- 如何选择前缀长度？
-- 保证足够的选择性
SELECT
    COUNT(DISTINCT LEFT(email, 5)) / COUNT(*) AS sel_5,
    COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS sel_10,
    COUNT(DISTINCT LEFT(email, 15)) / COUNT(*) AS sel_15,
    COUNT(DISTINCT email) / COUNT(*) AS sel_full
FROM users;
-- 选择选择性接近 sel_full 的最小长度
```

**前缀索引的限制**：
- 无法用于 ORDER BY
- 无法用于覆盖索引

#### 6. 利用覆盖索引

```sql
-- 如果经常执行：
SELECT name, age FROM users WHERE name = ?;

-- 建立覆盖索引：
CREATE INDEX idx_name_age ON users(name, age);
-- 查询不需要回表
```

### 索引优化实战示例

```sql
-- 原始表结构
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT,
    product_id BIGINT,
    status TINYINT,
    amount DECIMAL(10,2),
    create_time DATETIME,
    update_time DATETIME
);

-- 常见查询：
-- 1. 查询用户的所有订单
SELECT * FROM orders WHERE user_id = 123;

-- 2. 查询用户某状态的订单
SELECT * FROM orders WHERE user_id = 123 AND status = 1;

-- 3. 查询用户某时间段的订单
SELECT * FROM orders
WHERE user_id = 123
AND create_time >= '2024-01-01' AND create_time < '2024-02-01';

-- 4. 统计用户订单金额
SELECT SUM(amount) FROM orders WHERE user_id = 123;

-- 索引设计方案：
-- 方案 1：为每个查询单独建索引（不推荐，索引太多）
CREATE INDEX idx_user ON orders(user_id);
CREATE INDEX idx_user_status ON orders(user_id, status);
CREATE INDEX idx_user_time ON orders(user_id, create_time);

-- 方案 2：设计一个综合索引（推荐）
CREATE INDEX idx_user_status_time ON orders(user_id, status, create_time);
-- 可以覆盖查询 1, 2, 3

-- 方案 3：如果查询 4 很频繁，可以加覆盖索引
CREATE INDEX idx_user_amount ON orders(user_id, amount);
-- 查询 4 不需要回表
```

---

## 执行计划分析 ⭐⭐⭐⭐⭐

### EXPLAIN 基础用法

```sql
-- 基本用法
EXPLAIN SELECT * FROM users WHERE id = 1;

-- 查看更详细信息
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE id = 1;

-- MySQL 8.0+ 可以查看实际执行情况
EXPLAIN ANALYZE SELECT * FROM users WHERE id = 1;
```

### EXPLAIN 输出字段详解

```sql
EXPLAIN SELECT * FROM users WHERE name = 'Zhang';

+----+-------------+-------+------+---------------+----------+---------+-------+------+-------+
| id | select_type | table | type | possible_keys | key      | key_len | ref   | rows | Extra |
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------+
|  1 | SIMPLE      | users | ref  | idx_name      | idx_name | 153     | const |    1 | NULL  |
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------+
```

#### id - 查询序列号

```sql
-- id 相同：从上往下顺序执行
-- id 不同：id 大的先执行

EXPLAIN
SELECT * FROM users
WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
-- 子查询可能有不同的 id
```

#### select_type - 查询类型

| 值 | 含义 |
|----|------|
| SIMPLE | 简单查询（不含子查询或 UNION） |
| PRIMARY | 最外层查询 |
| SUBQUERY | 子查询中的第一个 SELECT |
| DERIVED | 派生表（FROM 子句中的子查询） |
| UNION | UNION 中第二个及以后的 SELECT |

#### type - 访问类型 ⭐⭐⭐⭐⭐

**性能从好到差**：

```
system > const > eq_ref > ref > range > index > ALL

┌────────┬───────────────────────────────────────────────────────────┐
│ system │ 表只有一行数据                                            │
├────────┼───────────────────────────────────────────────────────────┤
│ const  │ 通过主键或唯一索引查询，最多返回一行                        │
│        │ SELECT * FROM t WHERE id = 1                              │
├────────┼───────────────────────────────────────────────────────────┤
│ eq_ref │ 多表 JOIN 时，使用主键或唯一索引关联                        │
│        │ SELECT * FROM t1 JOIN t2 ON t1.id = t2.t1_id              │
├────────┼───────────────────────────────────────────────────────────┤
│ ref    │ 使用非唯一索引查询                                         │
│        │ SELECT * FROM t WHERE name = 'Zhang'                      │
├────────┼───────────────────────────────────────────────────────────┤
│ range  │ 索引范围查询                                               │
│        │ SELECT * FROM t WHERE id > 10                             │
│        │ SELECT * FROM t WHERE id IN (1, 2, 3)                     │
├────────┼───────────────────────────────────────────────────────────┤
│ index  │ 全索引扫描（比 ALL 好，因为索引比数据小）                   │
│        │ SELECT COUNT(*) FROM t                                    │
├────────┼───────────────────────────────────────────────────────────┤
│ ALL    │ 全表扫描（最差，应该避免）                                  │
│        │ SELECT * FROM t WHERE no_index_col = 'xxx'                │
└────────┴───────────────────────────────────────────────────────────┘

优化目标：至少达到 range 级别，最好能达到 ref 或更好
```

#### key_len - 索引长度

用于判断使用了组合索引的哪些列。

```sql
-- 假设有索引 idx(a, b, c)
-- a: INT (4 字节)
-- b: VARCHAR(50) (50*3 + 2 = 152 字节，UTF8MB4)
-- c: INT (4 字节)

-- key_len = 4：只使用了 a
-- key_len = 156：使用了 a, b
-- key_len = 160：使用了 a, b, c

-- key_len 计算规则：
-- INT: 4 字节
-- BIGINT: 8 字节
-- VARCHAR(n): n * 字符集字节数 + 2（长度标识）
-- 允许 NULL：额外 +1 字节
```

#### rows - 预估扫描行数

```sql
-- rows 越小越好
-- 这是估计值，不是精确值

-- 如果 rows 很大但 type 不是 ALL，检查：
-- 1. 索引选择性是否太低
-- 2. 是否需要优化索引
```

#### Extra - 额外信息 ⭐⭐⭐⭐

| 值 | 含义 | 说明 |
|----|------|------|
| **Using index** | 覆盖索引 | 好，不需要回表 |
| **Using where** | 使用 WHERE 过滤 | 正常 |
| **Using index condition** | 索引下推（ICP） | 好 |
| **Using temporary** | 使用临时表 | 需要优化 |
| **Using filesort** | 文件排序 | 需要优化 |
| **Using join buffer** | 使用连接缓冲 | JOIN 无索引 |

**优化示例**：

```sql
-- ❌ Using filesort
EXPLAIN SELECT * FROM users ORDER BY no_index_col;

-- ✅ 优化：给排序列加索引
CREATE INDEX idx_col ON users(no_index_col);

-- ❌ Using temporary
EXPLAIN SELECT DISTINCT no_index_col FROM users;

-- ✅ 优化：给列加索引
CREATE INDEX idx_col ON users(no_index_col);
```

### 执行计划分析实战

```sql
-- 案例 1：全表扫描
EXPLAIN SELECT * FROM orders WHERE amount > 100;
-- type: ALL（全表扫描）
-- 优化：CREATE INDEX idx_amount ON orders(amount);

-- 案例 2：索引失效
EXPLAIN SELECT * FROM users WHERE YEAR(create_time) = 2024;
-- type: ALL（函数导致索引失效）
-- 优化：改写 SQL
SELECT * FROM users
WHERE create_time >= '2024-01-01' AND create_time < '2025-01-01';

-- 案例 3：回表优化
EXPLAIN SELECT name, age FROM users WHERE name = 'Zhang';
-- Extra: NULL（需要回表）
-- 优化：创建覆盖索引
CREATE INDEX idx_name_age ON users(name, age);
-- Extra: Using index（覆盖索引，无需回表）

-- 案例 4：排序优化
EXPLAIN SELECT * FROM orders WHERE user_id = 1 ORDER BY create_time;
-- Extra: Using filesort（文件排序）
-- 优化：创建组合索引
CREATE INDEX idx_user_time ON orders(user_id, create_time);
-- Extra: NULL（利用索引排序）
```

---

## 面试高频问题 ⭐⭐⭐⭐⭐

### Q1: 为什么 MySQL 选择 B+ Tree 作为索引结构？

**答案要点**：

1. **对比 B Tree**：
   - B+ Tree 非叶子节点不存数据，能存更多键
   - B+ Tree 更矮，IO 次数更少
   - B+ Tree 叶子节点形成链表，范围查询更高效

2. **对比红黑树**：
   - 红黑树是二叉树，层数太高
   - 1000 万数据，红黑树约 24 层，B+ Tree 约 3-4 层

3. **对比哈希表**：
   - 哈希表不支持范围查询
   - 哈希表不支持排序
   - 哈希表不支持最左前缀

---

### Q2: 什么是聚簇索引和非聚簇索引？

**答案要点**：

| 特性 | 聚簇索引 | 非聚簇索引 |
|------|---------|-----------|
| 叶子节点 | 存完整行数据 | 存主键值 |
| 数量 | 一个表只有一个 | 可以有多个 |
| 查询 | 不需要回表 | 可能需要回表 |
| InnoDB | 主键索引 | 非主键索引 |

---

### Q3: 什么是回表？如何避免？

**答案要点**：

1. **回表**：通过非聚簇索引查询时，需要再去聚簇索引获取完整数据
2. **避免方法**：使用覆盖索引，让查询的列都在索引中

```sql
-- 回表查询
SELECT * FROM users WHERE name = 'Zhang';

-- 覆盖索引（无回表）
SELECT name, age FROM users WHERE name = 'Zhang';
-- 前提：有 (name, age) 的组合索引
```

---

### Q4: 什么是最左前缀原则？

**答案要点**：

组合索引 `(a, b, c)` 只能按从左到右的顺序使用：
- `WHERE a = 1` ✅
- `WHERE a = 1 AND b = 2` ✅
- `WHERE b = 2` ❌（没有最左列 a）

**原因**：B+ Tree 按 (a, b, c) 顺序排序，单独看 b 或 c 是无序的。

---

### Q5: 索引失效的常见场景有哪些？

**答案要点**：

1. 对索引列使用函数或表达式
2. 隐式类型转换
3. 前导模糊查询（`LIKE '%abc'`）
4. OR 条件中有无索引的列
5. 不等于条件（`!=`, `<>`）
6. 联合索引不满足最左前缀

---

### Q6: 如何选择合适的索引？

**答案要点**：

1. **选择性高的列**：不重复值多的列
2. **经常查询的列**：WHERE、ORDER BY、GROUP BY 中的列
3. **避免冗余**：(a, b) 索引可覆盖 (a) 的功能
4. **考虑写入成本**：写多读少的表少建索引
5. **利用覆盖索引**：减少回表

---

### Q7: EXPLAIN 中哪些情况需要优化？

**答案要点**：

| 问题 | 表现 | 优化方向 |
|------|------|---------|
| 全表扫描 | type: ALL | 添加合适的索引 |
| 文件排序 | Extra: Using filesort | 给排序列加索引 |
| 使用临时表 | Extra: Using temporary | 优化 GROUP BY |
| 扫描行数多 | rows 值很大 | 优化索引或 SQL |

---

### Q8: 自增主键有什么优势？

**答案要点**：

1. **顺序插入**：新数据追加在末尾，不需要移动其他数据
2. **避免页分裂**：随机主键会导致频繁页分裂
3. **占用空间小**：INT/BIGINT 比 UUID 小
4. **查询效率高**：整数比较比字符串比较快

---

### Q9: 什么是索引下推（ICP）？

**答案要点**：

MySQL 5.6 引入的优化，将部分 WHERE 条件下推到存储引擎层判断，减少回表次数。

```sql
-- 索引 (name, age)
SELECT * FROM users WHERE name LIKE 'Zhang%' AND age = 25;

-- 无 ICP：索引找到所有 Zhang%，全部回表后再判断 age
-- 有 ICP：索引找到 Zhang% 后，先在索引层判断 age，只有满足的才回表
```

---

### Q10: 前缀索引有什么限制？

**答案要点**：

1. **无法 ORDER BY**：前缀索引不包含完整值
2. **无法覆盖索引**：无法确定完整值
3. **选择性可能降低**：前缀太短会增加重复

```sql
-- 选择合适的前缀长度
SELECT
    COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS selectivity
FROM users;
```

---

## 总结

### 核心要点 ⭐⭐⭐⭐⭐

**1. 索引数据结构**：
- B+ Tree：支持范围查询、排序，3-4 层可存千万数据
- 非叶子节点只存键，叶子节点存数据并形成链表

**2. 聚簇 vs 非聚簇**：
- 聚簇索引：数据和索引在一起，一个表只有一个
- 非聚簇索引：叶子节点存主键值，可能需要回表

**3. 索引优化**：
- 最左前缀原则
- 覆盖索引避免回表
- 避免索引失效场景

**4. 执行计划**：
- type 至少 range，避免 ALL
- 注意 Using filesort 和 Using temporary

### 记住这些关键点

- ✅ **B+ Tree 比 B Tree 更适合数据库**（更矮、范围查询更快）
- ✅ **聚簇索引的叶子节点存完整行数据**
- ✅ **非聚簇索引需要回表，覆盖索引不需要**
- ✅ **组合索引遵循最左前缀原则**
- ✅ **对索引列使用函数会导致索引失效**
- ✅ **自增主键效率更高**

---

**相关文档**：
- [MySQL 锁机制](lock.md) - 锁与索引的关系
- [MySQL 事务](transaction.md) - 事务原理
- [MySQL MVCC](mvcc.md) - 多版本并发控制

**下一步**：学习 [MySQL 锁机制](lock.md)，理解不同索引类型对加锁的影响。
