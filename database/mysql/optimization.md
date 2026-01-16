# MySQL 性能优化

> 性能优化是 DBA 和后端开发者的必备技能，掌握 MySQL 性能优化能让你在面试中脱颖而出。

## SQL 执行全流程 ⭐⭐⭐⭐⭐

理解 SQL 执行流程是性能优化的基础。

### MySQL 架构概览

```
                           ┌─────────────────────────────────────┐
                           │           客户端                     │
                           └────────────────┬────────────────────┘
                                            │
                                            ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Server 层                                        │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │    连接器        │ →  │    查询缓存     │ →  │    解析器        │          │
│  │  (Connector)    │    │ (Query Cache)   │    │   (Parser)      │          │
│  │  连接管理/权限   │    │   8.0 已移除    │    │   词法/语法分析  │          │
│  └─────────────────┘    └─────────────────┘    └────────┬────────┘          │
│                                                         │                    │
│                                                         ▼                    │
│                         ┌─────────────────┐    ┌─────────────────┐          │
│                         │    执行器        │ ←  │    优化器        │          │
│                         │   (Executor)    │    │  (Optimizer)    │          │
│                         │   调用存储引擎   │    │   生成执行计划   │          │
│                         └────────┬────────┘    └─────────────────┘          │
└──────────────────────────────────┼───────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                             存储引擎层                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                          InnoDB                                      │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │    │
│  │  │ Buffer Pool  │  │ Change Buffer│  │  Log Buffer  │              │    │
│  │  │   数据缓存    │  │   写缓冲      │  │   日志缓冲   │              │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              磁盘存储                                         │
│          表空间文件(.ibd)  │  Redo Log  │  Undo Log  │  Binlog              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### SQL 执行步骤详解

```sql
-- 假设执行这条 SQL
SELECT * FROM users WHERE name = 'Zhang' AND age > 25;
```

**Step 1: 连接器（Connector）**
```
1. 建立 TCP 连接
2. 验证用户名和密码
3. 获取用户权限（权限在连接时读取，修改需重连生效）
4. 维护连接状态

-- 查看连接状态
SHOW PROCESSLIST;
```

**Step 2: 查询缓存（Query Cache）** [MySQL 8.0 已移除]
```
1. 将 SQL 作为 key，查询结果作为 value 缓存
2. 命中则直接返回结果
3. 问题：任何表更新都会清空该表所有缓存
4. 8.0 移除原因：命中率低，维护成本高
```

**Step 3: 解析器（Parser）**
```
词法分析：识别关键字、表名、列名等
语法分析：检查 SQL 语法是否正确

-- 语法错误示例
SELECT * FORM users;  -- 报错：FORM 应为 FROM
```

**Step 4: 优化器（Optimizer）** ⭐⭐⭐⭐⭐
```
1. 选择使用哪个索引
2. 决定多表 JOIN 的顺序
3. 生成执行计划

优化器会考虑：
├─ 扫描行数（通过索引统计信息估算）
├─ 是否需要排序
├─ 是否需要使用临时表
└─ 各种执行方案的成本
```

**Step 5: 执行器（Executor）**
```
1. 检查表和列的访问权限
2. 打开表，调用存储引擎接口
3. 根据执行计划逐行读取数据
4. 返回结果集
```

---

## 慢查询分析 ⭐⭐⭐⭐⭐

### 开启慢查询日志

```sql
-- 查看慢查询是否开启
SHOW VARIABLES LIKE 'slow_query%';

-- 查看慢查询阈值（默认 10 秒）
SHOW VARIABLES LIKE 'long_query_time';

-- 动态开启慢查询日志
SET GLOBAL slow_query_log = ON;
SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';
SET GLOBAL long_query_time = 1;  -- 超过 1 秒记录

-- 记录没有使用索引的查询
SET GLOBAL log_queries_not_using_indexes = ON;

-- 永久配置（my.cnf）
[mysqld]
slow_query_log = ON
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1
log_queries_not_using_indexes = ON
```

### 分析慢查询日志

**使用 mysqldumpslow**
```bash
# 按查询时间排序，取前 10 条
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# 按查询次数排序
mysqldumpslow -s c -t 10 /var/log/mysql/slow.log

# 按锁定时间排序
mysqldumpslow -s l -t 10 /var/log/mysql/slow.log

# 按返回行数排序
mysqldumpslow -s r -t 10 /var/log/mysql/slow.log
```

**使用 pt-query-digest（推荐）**
```bash
# 安装 Percona Toolkit
apt-get install percona-toolkit

# 分析慢查询日志
pt-query-digest /var/log/mysql/slow.log

# 输出示例
# Profile
# Rank Query ID                           Response time  Calls R/Call
# ==== ================================== ============== ===== ======
#    1 0x5E5C9C1C3D9F7B8A2E3F4D5C6B7A8E9F 1234.5678 50.0%  1234 1.0000
#    2 0x1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D  567.8901 23.0%   567 1.0000
```

### EXPLAIN 执行计划详解

```sql
EXPLAIN SELECT * FROM users WHERE name = 'Zhang';

-- 输出字段解释
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------+
| id | select_type | table | type | possible_keys | key      | key_len | ref   | rows | Extra |
+----+-------------+-------+------+---------------+----------+---------+-------+------+-------+
```

#### type 列（访问类型）⭐⭐⭐⭐⭐

**从最优到最差**：

```
system > const > eq_ref > ref > range > index > ALL

┌─────────┬────────────────────────────────────────────────────┬─────────────┐
│  type   │                      说明                          │   优化目标   │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ system  │ 表只有一行数据（系统表）                            │     ✅      │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ const   │ 主键或唯一索引等值查询，最多返回一行                 │     ✅      │
│         │ SELECT * FROM t WHERE id = 1                       │             │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ eq_ref  │ 多表 JOIN 时，使用主键或唯一索引                    │     ✅      │
│         │ SELECT * FROM t1 JOIN t2 ON t1.id = t2.id          │             │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ ref     │ 非唯一索引等值查询                                  │     ✅      │
│         │ SELECT * FROM t WHERE name = 'Zhang'               │             │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ range   │ 索引范围查询                                        │     ✅      │
│         │ SELECT * FROM t WHERE id > 10                      │             │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ index   │ 全索引扫描（比 ALL 好，索引文件更小）               │   ⚠️ 注意   │
│         │ SELECT COUNT(*) FROM t                             │             │
├─────────┼────────────────────────────────────────────────────┼─────────────┤
│ ALL     │ 全表扫描（最差，必须优化）                          │   ❌ 避免   │
│         │ SELECT * FROM t WHERE no_index_col = 'x'           │             │
└─────────┴────────────────────────────────────────────────────┴─────────────┘

优化目标：至少达到 range 级别，最好能达到 ref 或更好
```

#### Extra 列（重要提示）⭐⭐⭐⭐

```
┌───────────────────────────┬────────────────────────────────┬───────────┐
│          Extra            │             说明               │   建议    │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using index               │ 覆盖索引，不需要回表            │    ✅     │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using index condition     │ 索引下推（ICP）                 │    ✅     │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using where               │ 使用 WHERE 过滤                │   正常    │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using temporary           │ 使用临时表                      │   ⚠️优化  │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using filesort            │ 文件排序                        │   ⚠️优化  │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Using join buffer         │ JOIN 无索引                    │   ⚠️优化  │
├───────────────────────────┼────────────────────────────────┼───────────┤
│ Select tables optimized   │ 仅通过索引即可返回结果          │    ✅     │
│ away                      │ （如 MIN/MAX 优化）            │           │
└───────────────────────────┴────────────────────────────────┴───────────┘
```

### EXPLAIN FORMAT=JSON

```sql
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE name = 'Zhang';

-- 输出包含更多详细信息
{
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "1.20"  -- 查询成本
    },
    "table": {
      "table_name": "users",
      "access_type": "ref",
      "possible_keys": ["idx_name"],
      "key": "idx_name",
      "used_key_parts": ["name"],
      "rows_examined_per_scan": 1,
      "rows_produced_per_join": 1,
      "filtered": "100.00",
      "cost_info": {
        "read_cost": "1.00",
        "eval_cost": "0.20",
        "prefix_cost": "1.20",
        "data_read_per_join": "432"
      }
    }
  }
}
```

### EXPLAIN ANALYZE（MySQL 8.0.18+）

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE name = 'Zhang';

-- 实际执行并显示真实统计信息
-> Index lookup on users using idx_name (name='Zhang')
   (cost=1.10 rows=1) (actual time=0.028..0.031 rows=1 loops=1)

-- 关键信息：
-- cost: 预估成本
-- rows: 预估行数
-- actual time: 实际耗时（首行时间..最后一行时间）
-- rows: 实际行数
-- loops: 循环次数
```

---

## SQL 优化技巧 ⭐⭐⭐⭐⭐

### 索引优化

#### 1. 避免索引失效

```sql
-- ❌ 对索引列使用函数
SELECT * FROM orders WHERE YEAR(create_time) = 2024;

-- ✅ 改写为范围查询
SELECT * FROM orders
WHERE create_time >= '2024-01-01' AND create_time < '2025-01-01';

-- ❌ 隐式类型转换
SELECT * FROM users WHERE phone = 13800138000;  -- phone 是 VARCHAR

-- ✅ 使用正确的类型
SELECT * FROM users WHERE phone = '13800138000';

-- ❌ 前导模糊查询
SELECT * FROM users WHERE name LIKE '%Zhang';

-- ✅ 后缀模糊（可使用索引）
SELECT * FROM users WHERE name LIKE 'Zhang%';

-- ❌ OR 连接无索引列
SELECT * FROM users WHERE name = 'Zhang' OR age = 25;  -- age 无索引

-- ✅ 使用 UNION
SELECT * FROM users WHERE name = 'Zhang'
UNION
SELECT * FROM users WHERE age = 25;
```

#### 2. 利用覆盖索引

```sql
-- 假设有索引 idx_name_age(name, age)

-- ❌ 需要回表
SELECT * FROM users WHERE name = 'Zhang';

-- ✅ 覆盖索引，不需要回表
SELECT name, age FROM users WHERE name = 'Zhang';
-- EXPLAIN Extra: Using index

-- 优化：只查询需要的列，尽量使用覆盖索引
```

#### 3. 最左前缀原则

```sql
-- 索引 idx(a, b, c)

-- ✅ 可以使用索引
WHERE a = 1
WHERE a = 1 AND b = 2
WHERE a = 1 AND b = 2 AND c = 3
WHERE a = 1 AND c = 3  -- 只用到 a

-- ❌ 无法使用索引
WHERE b = 2
WHERE c = 3
WHERE b = 2 AND c = 3
```

### JOIN 优化

#### 1. 小表驱动大表

```sql
-- MySQL 优化器通常会自动选择，但可以用 STRAIGHT_JOIN 强制指定

-- 假设 orders 有 100 万行，users 有 1 万行

-- ✅ 小表驱动大表（users 驱动 orders）
SELECT * FROM users u
STRAIGHT_JOIN orders o ON u.id = o.user_id
WHERE u.status = 1;

-- 原理：
-- 1. 先扫描小表 users（假设 100 行）
-- 2. 每行去 orders 表查找（利用索引）
-- 3. 总扫描：100 + 100 * 索引查找 ≈ 很少

-- 如果大表驱动：
-- 1. 先扫描大表 orders（100 万行）
-- 2. 每行去 users 表查找
-- 3. 总扫描：100 万 + 100 万 * 索引查找 ≈ 很多
```

#### 2. JOIN 类型选择

```sql
-- 确保 JOIN 列有索引
-- 被驱动表的 JOIN 列必须有索引

-- ✅ 好的写法
SELECT * FROM users u
JOIN orders o ON u.id = o.user_id  -- orders.user_id 有索引
WHERE u.status = 1;

-- ❌ 差的写法
SELECT * FROM users u
JOIN orders o ON u.name = o.user_name  -- 没有索引
WHERE u.status = 1;
```

#### 3. 避免 JOIN 过多

```sql
-- ❌ 过多的 JOIN
SELECT * FROM t1
JOIN t2 ON ...
JOIN t3 ON ...
JOIN t4 ON ...
JOIN t5 ON ...
JOIN t6 ON ...;

-- ✅ 拆分查询或使用子查询
-- 方案 1：应用层拆分
-- 方案 2：适当冗余减少 JOIN
```

### 子查询优化

```sql
-- ❌ 使用 IN 子查询（可能导致全表扫描）
SELECT * FROM orders
WHERE user_id IN (SELECT id FROM users WHERE status = 1);

-- ✅ 改写为 JOIN
SELECT o.* FROM orders o
JOIN users u ON o.user_id = u.id
WHERE u.status = 1;

-- ❌ 使用 NOT IN（null 值问题 + 性能差）
SELECT * FROM orders
WHERE user_id NOT IN (SELECT id FROM users WHERE status = 0);

-- ✅ 改写为 LEFT JOIN + IS NULL
SELECT o.* FROM orders o
LEFT JOIN users u ON o.user_id = u.id AND u.status = 0
WHERE u.id IS NULL;

-- 或使用 NOT EXISTS
SELECT * FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = o.user_id AND u.status = 0
);
```

### ORDER BY 优化

```sql
-- ❌ 文件排序（Using filesort）
SELECT * FROM orders ORDER BY amount;  -- amount 无索引

-- ✅ 利用索引排序
SELECT * FROM orders ORDER BY id;  -- 主键自带索引

-- 组合索引排序规则
-- 索引 idx(a, b, c)

-- ✅ 可以利用索引排序
ORDER BY a
ORDER BY a, b
ORDER BY a, b, c
ORDER BY a DESC, b DESC, c DESC  -- 全部同向

-- ❌ 无法利用索引排序
ORDER BY b          -- 缺少最左列
ORDER BY a, c       -- 跳过了 b
ORDER BY a ASC, b DESC  -- 方向不一致（MySQL 8.0 前）

-- MySQL 8.0+ 支持降序索引
CREATE INDEX idx_a_b ON t(a ASC, b DESC);
```

### GROUP BY 优化

```sql
-- ❌ 使用临时表（Using temporary）
SELECT user_id, COUNT(*) FROM orders GROUP BY user_id;  -- user_id 无索引

-- ✅ 利用索引分组
CREATE INDEX idx_user ON orders(user_id);
SELECT user_id, COUNT(*) FROM orders GROUP BY user_id;
-- 利用索引有序性，避免临时表

-- 松散索引扫描（Loose Index Scan）
-- 索引 idx(a, b)
SELECT a, MIN(b) FROM t GROUP BY a;
-- Extra: Using index for group-by
```

### LIMIT 优化

```sql
-- ❌ 深分页问题
SELECT * FROM orders ORDER BY id LIMIT 1000000, 10;
-- 需要扫描 1000010 行，丢弃前 1000000 行

-- ✅ 方案 1：使用上次查询的最大 ID
SELECT * FROM orders
WHERE id > 1000000  -- 上一页最后的 ID
ORDER BY id
LIMIT 10;

-- ✅ 方案 2：延迟关联
SELECT o.* FROM orders o
JOIN (
    SELECT id FROM orders ORDER BY id LIMIT 1000000, 10
) tmp ON o.id = tmp.id;
-- 子查询只扫描索引，减少回表

-- ✅ 方案 3：业务限制
-- 不允许用户跳转到很后面的页码
-- 只提供"上一页/下一页"的翻页方式
```

### COUNT 优化

```sql
-- 统计表总行数的几种方式

-- 1. COUNT(*)：推荐
SELECT COUNT(*) FROM orders;
-- InnoDB 会选择最小的索引来统计
-- 8.0 有并行查询优化

-- 2. COUNT(1)：与 COUNT(*) 等效
SELECT COUNT(1) FROM orders;

-- 3. COUNT(column)：只统计非 NULL 值
SELECT COUNT(user_id) FROM orders;
-- 如果列有 NULL，结果可能不同

-- 优化方案
-- 方案 1：维护计数表
CREATE TABLE table_counts (
    table_name VARCHAR(100) PRIMARY KEY,
    row_count BIGINT
);
-- 插入/删除时更新计数

-- 方案 2：使用 Redis 缓存
-- 定期同步或实时更新

-- 方案 3：估算值
SHOW TABLE STATUS LIKE 'orders';  -- Rows 列是估算值
-- 或者
SELECT table_rows FROM information_schema.tables
WHERE table_name = 'orders';
```

---

## 表结构优化 ⭐⭐⭐⭐

### 数据类型选择

```sql
-- 原则：选择满足需求的最小数据类型

-- ❌ 错误示例
CREATE TABLE users (
    id INT,                    -- 不用自增？
    age VARCHAR(10),           -- 年龄用字符串？
    status INT,                -- 状态只有 0/1 用 INT？
    price DOUBLE,              -- 金额用 DOUBLE 有精度问题
    create_time VARCHAR(20)    -- 时间用字符串？
);

-- ✅ 正确示例
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,  -- 无符号自增
    age TINYINT UNSIGNED,                           -- 0-255 足够
    status TINYINT UNSIGNED DEFAULT 0,              -- 0/1 用 TINYINT
    price DECIMAL(10,2),                            -- 金额用 DECIMAL
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP  -- 用 DATETIME
);
```

**数据类型选择指南**：

| 场景 | 推荐类型 | 说明 |
|------|---------|------|
| 主键 | BIGINT UNSIGNED | 防止溢出 |
| 状态/枚举 | TINYINT | 0-255 |
| 年龄 | TINYINT UNSIGNED | 0-255 |
| 金额 | DECIMAL(M,N) | 精确计算 |
| 时间 | DATETIME | 8 字节，范围大 |
| IP 地址 | INT UNSIGNED | 用 INET_ATON() 转换 |
| UUID | BINARY(16) | 比 CHAR(36) 省空间 |
| 大文本 | TEXT | 不要用 VARCHAR(65535) |
| 是/否 | TINYINT(1) | 不要用 CHAR(1) |

### 字符集选择

```sql
-- 推荐 utf8mb4
CREATE TABLE t (
    name VARCHAR(100)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- utf8 vs utf8mb4
-- utf8：最多 3 字节，不支持 emoji
-- utf8mb4：最多 4 字节，支持 emoji（推荐）

-- 排序规则
-- utf8mb4_general_ci：速度快，但排序不够精确
-- utf8mb4_unicode_ci：排序更精确（推荐）
-- utf8mb4_bin：区分大小写，二进制比较
```

### 范式与反范式

```sql
-- 第三范式（3NF）：消除传递依赖
-- 优点：减少数据冗余，更新方便
-- 缺点：查询需要 JOIN

-- 规范化设计
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    user_id BIGINT,
    total_amount DECIMAL(10,2)
);

CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    name VARCHAR(50),
    phone VARCHAR(20)
);

-- 反范式设计（适当冗余）
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    user_id BIGINT,
    user_name VARCHAR(50),     -- 冗余字段
    user_phone VARCHAR(20),    -- 冗余字段
    total_amount DECIMAL(10,2)
);

-- 优点：减少 JOIN，查询更快
-- 缺点：数据冗余，更新需要同步

-- 适用场景
-- 1. 读多写少
-- 2. 冗余字段很少更新
-- 3. 查询性能要求高
```

### 垂直拆分

```sql
-- 将大表按列拆分

-- 原表
CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    name VARCHAR(50),
    phone VARCHAR(20),
    avatar BLOB,           -- 大字段
    bio TEXT,              -- 大字段
    create_time DATETIME
);

-- 拆分后
CREATE TABLE users (
    id BIGINT PRIMARY KEY,
    name VARCHAR(50),
    phone VARCHAR(20),
    create_time DATETIME
);

CREATE TABLE user_profiles (
    user_id BIGINT PRIMARY KEY,
    avatar BLOB,
    bio TEXT
);

-- 优点：
-- 1. 常用字段查询更快（行更小）
-- 2. 不常用的大字段单独存储
-- 3. 减少 IO
```

### 水平拆分

```sql
-- 将大表按行拆分

-- 方案 1：按范围分表
orders_2023    -- 2023 年的订单
orders_2024    -- 2024 年的订单

-- 方案 2：按哈希分表
orders_0       -- user_id % 4 = 0
orders_1       -- user_id % 4 = 1
orders_2       -- user_id % 4 = 2
orders_3       -- user_id % 4 = 3

-- 适用场景：
-- 单表数据量超过 1000 万或 2GB
-- 详见 [分库分表](../sharding/README.md)
```

---

## InnoDB 参数调优 ⭐⭐⭐⭐⭐

### Buffer Pool 配置

```sql
-- Buffer Pool 是 InnoDB 最重要的缓存
-- 用于缓存数据页和索引页

-- 查看当前配置
SHOW VARIABLES LIKE 'innodb_buffer_pool%';

-- 推荐配置
-- 专用数据库服务器：物理内存的 70-80%
-- 混合服务器：物理内存的 50%

-- my.cnf 配置
[mysqld]
innodb_buffer_pool_size = 8G          -- 总大小
innodb_buffer_pool_instances = 8       -- 实例数（建议 = CPU 核心数）
innodb_buffer_pool_chunk_size = 128M   -- 每个 chunk 大小

-- 监控 Buffer Pool 命中率
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';

-- 命中率计算
-- 命中率 = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
-- 建议 > 99%
```

**Buffer Pool 结构**：

```
┌─────────────────────────────────────────────────────────────┐
│                      Buffer Pool                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                    LRU List                           │   │
│  │  ┌────────────────────┬─────────────────────────┐    │   │
│  │  │    Young 区域       │      Old 区域           │    │   │
│  │  │   (热数据，5/8)     │    (冷数据，3/8)        │    │   │
│  │  │                    │                         │    │   │
│  │  │  ← 新数据先放这里    │    ← 再移到 Young      │    │   │
│  │  └────────────────────┴─────────────────────────┘    │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   Free List     │  │   Flush List    │                  │
│  │   (空闲页)       │  │  (脏页，待刷盘)  │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Redo Log 配置

```sql
-- Redo Log 保证事务持久性

-- 查看当前配置
SHOW VARIABLES LIKE 'innodb_log%';

-- 推荐配置
[mysqld]
innodb_log_file_size = 1G              -- 单个日志文件大小
innodb_log_files_in_group = 2          -- 日志文件数量（MySQL 8.0.30+ 固定为 2）
innodb_log_buffer_size = 64M           -- 日志缓冲区大小

-- 刷盘策略
innodb_flush_log_at_trx_commit = 1     -- 每次提交都刷盘（最安全）
-- 0：每秒刷盘一次（可能丢失 1 秒数据）
-- 1：每次提交都刷盘（默认，最安全）
-- 2：每次提交写入 OS 缓存，每秒刷盘

-- 监控 Redo Log
SHOW ENGINE INNODB STATUS\G
-- Log sequence number：当前 LSN
-- Log flushed up to：已刷盘 LSN
-- Last checkpoint at：最后检查点 LSN
```

### 其他重要参数

```sql
-- 并发相关
innodb_thread_concurrency = 0          -- 0 表示不限制（推荐）
innodb_read_io_threads = 4             -- 读 IO 线程数
innodb_write_io_threads = 4            -- 写 IO 线程数

-- 刷盘相关
innodb_flush_method = O_DIRECT         -- 避免双重缓存（Linux）
innodb_io_capacity = 2000              -- IO 能力（SSD 可设 10000+）
innodb_io_capacity_max = 4000          -- 最大 IO 能力

-- 事务相关
innodb_lock_wait_timeout = 50          -- 锁等待超时（秒）
innodb_deadlock_detect = ON            -- 死锁检测

-- 临时表
tmp_table_size = 64M                   -- 内存临时表最大大小
max_heap_table_size = 64M              -- MEMORY 表最大大小

-- 排序缓冲
sort_buffer_size = 256K                -- 每个连接的排序缓冲
join_buffer_size = 256K                -- 每个连接的 JOIN 缓冲
read_buffer_size = 128K                -- 顺序读缓冲
read_rnd_buffer_size = 256K            -- 随机读缓冲
```

---

## 连接池优化 ⭐⭐⭐

### MySQL 连接数配置

```sql
-- 查看连接数
SHOW VARIABLES LIKE 'max_connections';
SHOW STATUS LIKE 'Threads%';

-- 推荐配置
[mysqld]
max_connections = 500                  -- 最大连接数
max_user_connections = 400             -- 单用户最大连接数
wait_timeout = 600                     -- 非交互连接超时（秒）
interactive_timeout = 600              -- 交互连接超时（秒）

-- 连接数公式（经验值）
-- max_connections = (可用内存 - 全局缓存) / 每个连接使用的内存
-- 每个连接约使用 256K - 10MB（取决于操作）
```

### 应用层连接池

```yaml
# HikariCP 配置（推荐）
spring:
  datasource:
    hikari:
      minimum-idle: 10           # 最小空闲连接
      maximum-pool-size: 50      # 最大连接数
      idle-timeout: 300000       # 空闲超时（毫秒）
      max-lifetime: 1800000      # 连接最大生命周期（毫秒）
      connection-timeout: 30000  # 获取连接超时（毫秒）

# 连接池大小公式
# 最大连接数 ≈ CPU 核心数 * 2 + 磁盘数
# 例如：4 核 + 1 磁盘 → 4 * 2 + 1 = 9 个连接
```

### ProxySQL 中间层

```sql
-- ProxySQL 是 MySQL 代理，提供：
-- 1. 连接池复用
-- 2. 读写分离
-- 3. 查询路由
-- 4. 查询缓存

-- 安装
apt-get install proxysql

-- 配置后端 MySQL
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight)
VALUES (0, '192.168.1.1', 3306, 1);

-- 配置连接池
UPDATE global_variables
SET variable_value = 100
WHERE variable_name = 'mysql-max_connections';

LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
```

---

## 缓存策略 ⭐⭐⭐⭐

### 应用层缓存

```java
// Cache-Aside 模式（旁路缓存）

// 读取数据
public User getUser(Long userId) {
    String key = "user:" + userId;

    // 1. 先查缓存
    User user = redis.get(key);
    if (user != null) {
        return user;
    }

    // 2. 缓存未命中，查数据库
    user = userMapper.selectById(userId);
    if (user != null) {
        // 3. 写入缓存
        redis.setex(key, 3600, user);
    }
    return user;
}

// 更新数据
public void updateUser(User user) {
    // 1. 更新数据库
    userMapper.updateById(user);

    // 2. 删除缓存（而不是更新缓存）
    redis.del("user:" + user.getId());
}
```

**缓存问题与解决**：

```
┌─────────────────┬───────────────────────────────────────────────────┐
│      问题       │                     解决方案                       │
├─────────────────┼───────────────────────────────────────────────────┤
│ 缓存穿透        │ 1. 缓存空对象（设置较短过期时间）                   │
│ (查不存在的数据) │ 2. 布隆过滤器                                      │
├─────────────────┼───────────────────────────────────────────────────┤
│ 缓存击穿        │ 1. 互斥锁（只有一个请求去查数据库）                 │
│ (热点key过期)   │ 2. 永不过期 + 异步更新                             │
├─────────────────┼───────────────────────────────────────────────────┤
│ 缓存雪崩        │ 1. 过期时间加随机值                                │
│ (大量key同时过期)│ 2. 多级缓存                                       │
│                 │ 3. 熔断降级                                        │
├─────────────────┼───────────────────────────────────────────────────┤
│ 数据不一致      │ 1. 先更新数据库，再删除缓存                        │
│                 │ 2. 延迟双删                                        │
│                 │ 3. 消息队列异步同步                                │
└─────────────────┴───────────────────────────────────────────────────┘
```

### 数据库缓存

```sql
-- 1. Buffer Pool（最重要）
-- 缓存数据页和索引页
-- 配置见上文 "Buffer Pool 配置"

-- 2. Query Cache（MySQL 8.0 已移除）
-- 命中率太低，维护成本高

-- 3. Thread Cache
-- 缓存线程，避免频繁创建销毁
SHOW VARIABLES LIKE 'thread_cache_size';
SET GLOBAL thread_cache_size = 64;

-- 监控
SHOW STATUS LIKE 'Threads_created';
-- 如果 Threads_created 增长很快，增大 thread_cache_size

-- 4. Table Cache
-- 缓存表的文件描述符
SHOW VARIABLES LIKE 'table_open_cache%';
SET GLOBAL table_open_cache = 4000;
SET GLOBAL table_open_cache_instances = 16;
```

---

## 读写分离 ⭐⭐⭐⭐

### 主从架构

```
                      ┌─────────────┐
                      │   应用服务   │
                      └──────┬──────┘
                             │
                    ┌────────┴────────┐
                    │                  │
               写请求│             读请求│
                    ▼                  ▼
            ┌───────────┐      ┌───────────┐
            │   Master   │      │   Slave   │
            │  (主库)    │ ───→ │  (从库)   │
            │   可读写   │ 复制  │   只读    │
            └───────────┘      └───────────┘
```

### 实现方案

```java
// 方案 1：应用层实现
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
public @interface DataSource {
    String value() default "master";
}

// 使用
@DataSource("slave")
public List<User> queryUsers() {
    return userMapper.selectList(null);
}

@DataSource("master")
@Transactional
public void updateUser(User user) {
    userMapper.updateById(user);
}

// 方案 2：中间件实现
// - MyCat
// - ShardingSphere
// - ProxySQL
// 对应用透明，但增加运维复杂度
```

### 主从延迟处理

```sql
-- 监控主从延迟
SHOW SLAVE STATUS\G
-- Seconds_Behind_Master: 延迟秒数

-- 解决方案

-- 1. 强制走主库
@DataSource("master")
public User getUserForUpdate(Long id) {
    return userMapper.selectById(id);
}

-- 2. 半同步复制
SET GLOBAL rpl_semi_sync_master_enabled = ON;
SET GLOBAL rpl_semi_sync_master_timeout = 1000;  -- 等待从库确认的超时时间

-- 3. 并行复制（MySQL 5.7+）
SET GLOBAL slave_parallel_type = 'LOGICAL_CLOCK';
SET GLOBAL slave_parallel_workers = 8;

-- 4. GTID + 等待
-- 在主库执行后获取 GTID
-- 在从库等待 GTID 回放完成
SELECT WAIT_FOR_EXECUTED_GTID_SET('uuid:1-100', 1);
```

---

## 监控与诊断 ⭐⭐⭐⭐

### 关键指标监控

```sql
-- 1. 查询吞吐量
SHOW GLOBAL STATUS LIKE 'Questions';      -- 总查询数
SHOW GLOBAL STATUS LIKE 'Com_select';     -- SELECT 数
SHOW GLOBAL STATUS LIKE 'Com_insert';     -- INSERT 数
SHOW GLOBAL STATUS LIKE 'Com_update';     -- UPDATE 数
SHOW GLOBAL STATUS LIKE 'Com_delete';     -- DELETE 数

-- 2. 连接数
SHOW GLOBAL STATUS LIKE 'Threads_connected';  -- 当前连接数
SHOW GLOBAL STATUS LIKE 'Threads_running';    -- 正在运行的连接
SHOW GLOBAL STATUS LIKE 'Max_used_connections';  -- 历史最大连接数

-- 3. 缓冲池命中率
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';  -- 逻辑读
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';          -- 物理读
-- 命中率 = 1 - 物理读/逻辑读

-- 4. 锁等待
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
-- Innodb_row_lock_current_waits: 当前等待锁的数量
-- Innodb_row_lock_time: 总等待时间
-- Innodb_row_lock_time_avg: 平均等待时间

-- 5. 临时表
SHOW GLOBAL STATUS LIKE 'Created_tmp%';
-- Created_tmp_tables: 创建的临时表数
-- Created_tmp_disk_tables: 磁盘临时表数（应该尽量少）
```

### Performance Schema

```sql
-- 开启 Performance Schema
[mysqld]
performance_schema = ON

-- 查看最耗时的 SQL
SELECT
    DIGEST_TEXT AS sql_text,
    COUNT_STAR AS exec_count,
    SUM_TIMER_WAIT / 1000000000000 AS total_time_sec,
    AVG_TIMER_WAIT / 1000000000 AS avg_time_ms,
    SUM_ROWS_EXAMINED AS rows_examined
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- 查看表 IO 情况
SELECT
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COUNT_READ,
    COUNT_WRITE,
    SUM_TIMER_WAIT / 1000000000 AS total_time_ms
FROM performance_schema.table_io_waits_summary_by_table
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 10;

-- 查看索引使用情况
SELECT
    OBJECT_SCHEMA,
    OBJECT_NAME,
    INDEX_NAME,
    COUNT_FETCH,
    COUNT_INSERT,
    COUNT_UPDATE,
    COUNT_DELETE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE INDEX_NAME IS NOT NULL
ORDER BY COUNT_FETCH DESC
LIMIT 10;
```

### sys Schema（MySQL 5.7+）

```sql
-- sys schema 是 performance_schema 的视图封装，更易读

-- 查看最耗时的 SQL
SELECT * FROM sys.statements_with_runtimes_in_95th_percentile;

-- 查看未使用的索引
SELECT * FROM sys.schema_unused_indexes;

-- 查看冗余索引
SELECT * FROM sys.schema_redundant_indexes;

-- 查看表统计信息
SELECT * FROM sys.schema_table_statistics;

-- 查看等待事件
SELECT * FROM sys.wait_classes_global_by_avg_latency;

-- 查看 IO 热点
SELECT * FROM sys.io_global_by_file_by_bytes;
```

---

## 面试高频问题 ⭐⭐⭐⭐⭐

### Q1: MySQL 慢查询如何优化？

**优化步骤**：

```
1. 开启慢查询日志
   SET GLOBAL slow_query_log = ON;
   SET GLOBAL long_query_time = 1;

2. 分析慢查询
   mysqldumpslow 或 pt-query-digest

3. 使用 EXPLAIN 分析执行计划
   重点关注：type、key、rows、Extra

4. 优化方向：
   ├─ 索引优化：添加合适索引、避免索引失效
   ├─ SQL 改写：避免 SELECT *、优化 JOIN
   ├─ 表结构优化：合适的数据类型、适当冗余
   └─ 参数调优：Buffer Pool、连接数等
```

---

### Q2: 如何判断一条 SQL 是否需要优化？

**判断标准**：

```
1. 执行时间 > 1秒（或业务要求的阈值）

2. EXPLAIN 结果：
   ├─ type = ALL（全表扫描）
   ├─ rows 很大
   ├─ Extra 包含 Using filesort
   ├─ Extra 包含 Using temporary
   └─ key = NULL（没有使用索引）

3. 监控指标：
   ├─ 锁等待时间长
   ├─ 临时表创建多
   └─ 缓冲池命中率低
```

---

### Q3: 深分页问题如何解决？

**问题**：
```sql
SELECT * FROM orders LIMIT 1000000, 10;
-- 需要扫描 1000010 行
```

**解决方案**：

```sql
-- 方案 1：游标分页（推荐）
SELECT * FROM orders
WHERE id > 1000000  -- 上一页最后的 ID
ORDER BY id
LIMIT 10;

-- 方案 2：延迟关联
SELECT o.* FROM orders o
JOIN (
    SELECT id FROM orders ORDER BY id LIMIT 1000000, 10
) tmp ON o.id = tmp.id;

-- 方案 3：业务限制
-- 不允许跳转到太后面的页
-- 使用"上一页/下一页"方式
```

---

### Q4: 如何优化 COUNT(*) 查询？

**方案**：

```sql
-- 1. InnoDB 自身优化
-- 8.0 有并行查询
SELECT COUNT(*) FROM t;

-- 2. 维护计数表
-- 插入/删除时同步更新

-- 3. Redis 缓存计数
-- 定期同步或实时更新

-- 4. 近似值
SHOW TABLE STATUS LIKE 't';  -- Rows 列
-- 或 information_schema.tables
```

---

### Q5: Buffer Pool 如何配置？

**配置建议**：

```
专用数据库服务器：物理内存的 70-80%
混合服务器：物理内存的 50%

innodb_buffer_pool_size = 8G
innodb_buffer_pool_instances = 8  （= CPU 核心数）

监控命中率：> 99%
命中率 = 1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)
```

---

### Q6: 如何处理主从延迟？

**解决方案**：

```
1. 写后立即读 → 强制走主库

2. 半同步复制
   等待至少一个从库确认

3. 并行复制
   slave_parallel_workers = 8

4. GTID 等待
   SELECT WAIT_FOR_EXECUTED_GTID_SET(...)
```

---

### Q7: 如何定位线上 MySQL 问题？

**排查步骤**：

```sql
-- 1. 查看当前连接
SHOW PROCESSLIST;
-- 或
SELECT * FROM information_schema.PROCESSLIST WHERE Command != 'Sleep';

-- 2. 查看锁等待
SELECT * FROM information_schema.INNODB_TRX;
SELECT * FROM performance_schema.data_locks;  -- MySQL 8.0

-- 3. 查看 InnoDB 状态
SHOW ENGINE INNODB STATUS\G

-- 4. 查看慢查询
-- 分析慢查询日志

-- 5. 查看系统负载
-- top, vmstat, iostat
```

---

### Q8: innodb_flush_log_at_trx_commit 参数如何选择？

**选项说明**：

| 值 | 行为 | 性能 | 安全性 |
|----|------|------|--------|
| 0 | 每秒刷盘一次 | 最高 | 可能丢失 1 秒数据 |
| 1 | 每次提交都刷盘 | 较低 | 最安全（默认） |
| 2 | 每次提交写入 OS 缓存，每秒刷盘 | 中等 | 系统崩溃可能丢数据 |

**建议**：
- 金融系统：1（最安全）
- 普通业务：2（平衡）
- 允许少量丢失：0（最快）

---

## 总结

### 核心要点

**1. SQL 优化**：
- 避免索引失效
- 利用覆盖索引
- 小表驱动大表
- 优化深分页

**2. 表结构优化**：
- 选择合适的数据类型
- 适当反范式设计
- 垂直/水平拆分

**3. 参数调优**：
- Buffer Pool 配置
- Redo Log 配置
- 连接数配置

**4. 架构优化**：
- 读写分离
- 应用层缓存
- 连接池优化

### 优化方法论

```
1. 定位问题
   ├─ 慢查询日志
   ├─ EXPLAIN 分析
   └─ 监控指标

2. 分析原因
   ├─ 索引问题？
   ├─ SQL 写法问题？
   ├─ 表结构问题？
   └─ 参数配置问题？

3. 制定方案
   ├─ 添加索引
   ├─ 改写 SQL
   ├─ 调整参数
   └─ 架构调整

4. 验证效果
   ├─ 测试环境验证
   ├─ 灰度发布
   └─ 监控对比
```

### 记住这些关键点

- ✅ **开启慢查询日志**（long_query_time = 1）
- ✅ **EXPLAIN 看 type、key、Extra**
- ✅ **避免 SELECT ***
- ✅ **深分页用游标分页**
- ✅ **Buffer Pool 设为内存的 70-80%**
- ✅ **innodb_flush_log_at_trx_commit 根据业务选择**
- ✅ **主从延迟用强制走主库或半同步复制**

---

**相关文档**：
- [MySQL 索引原理与优化](index.md) - 索引基础知识
- [MySQL 锁机制](lock.md) - 锁与并发控制
- [MySQL 事务](transaction.md) - 事务原理
- [MySQL 日志系统](logs.md) - Redo Log、Binlog 等

**推荐阅读**：
- 《高性能 MySQL》- Baron Schwartz
- 《MySQL 技术内幕：InnoDB 存储引擎》- 姜承尧
