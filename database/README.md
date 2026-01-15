# ：数据库知识体系大纲

## 第一部分：MySQL 核心原理

### 1. MySQL 架构与存储引擎

#### 1.1 MySQL 架构
- 连接器：连接管理、权限验证
- 查询缓存（MySQL 8.0 已移除）
- 分析器：词法分析、语法分析
- 优化器：执行计划生成、索引选择
- 执行器：调用存储引擎 API

#### 1.2 存储引擎对比
- InnoDB：事务型存储引擎
  - ACID 特性
  - 行级锁
  - MVCC（多版本并发控制）
  - 外键支持
  - 聚簇索引
- MyISAM：非事务型存储引擎
  - 表级锁
  - 全文索引（5.7 前）
  - 不支持事务
  - 压缩表
- Memory：内存存储引擎
- Archive：归档存储引擎

#### 1.3 InnoDB 架构详解
- 内存结构
  - Buffer Pool（缓冲池）
  - Change Buffer（写缓冲）
  - Adaptive Hash Index（自适应哈希索引）
  - Log Buffer（日志缓冲）
- 磁盘结构
  - 表空间（Tablespace）
  - Redo Log（重做日志）
  - Undo Log（回滚日志）
  - 数据字典

### 2. 索引原理与优化 ⭐⭐⭐⭐⭐

#### 2.1 索引数据结构
- B+ Tree 索引
  - 为什么不用 B Tree
  - 为什么不用红黑树
  - 为什么不用哈希表
  - B+ Tree 的特点
    - 所有数据在叶子节点
    - 叶子节点形成有序链表
    - 非叶子节点只存索引
- Hash 索引
  - Memory 引擎
  - 自适应哈希索引
  - 使用场景和限制

#### 2.2 索引类型
- 主键索引（Primary Key）
  - 聚簇索引
  - 自增主键的优势
- 唯一索引（Unique Index）
- 普通索引（Normal Index）
- 全文索引（Full-Text Index）
- 组合索引（Composite Index）
  - 最左前缀原则
  - 索引下推（Index Condition Pushdown）

#### 2.3 聚簇索引 vs 非聚簇索引
- 聚簇索引（InnoDB 主键索引）
  - 数据和索引存在一起
  - 一个表只能有一个聚簇索引
  - 叶子节点存储完整行数据
- 非聚簇索引（二级索引）
  - 叶子节点存储主键值
  - 需要回表查询
  - 覆盖索引优化

#### 2.4 索引优化
- 索引失效场景
  - 使用函数或表达式
  - 隐式类型转换
  - 前导模糊查询（%abc）
  - OR 条件
  - 不等于（!=、<>）
  - IS NULL / IS NOT NULL
  - 联合索引不满足最左前缀
- 索引设计原则
  - 选择性高的列建索引
  - 最左前缀原则
  - 避免冗余索引
  - 考虑索引的维护成本
  - 使用前缀索引
  - 利用覆盖索引

#### 2.5 执行计划分析
- EXPLAIN 详解
  - id：查询序列号
  - select_type：查询类型
  - table：表名
  - type：访问类型（性能从优到差）
    - system > const > eq_ref > ref > range > index > ALL
  - possible_keys：可能使用的索引
  - key：实际使用的索引
  - key_len：索引长度
  - ref：索引比较的列
  - rows：扫描的行数
  - filtered：过滤百分比
  - Extra：额外信息
    - Using index（覆盖索引）
    - Using where
    - Using temporary（使用临时表）
    - Using filesort（文件排序）

### 3. 锁机制 ⭐⭐⭐⭐⭐ 重点

#### 3.1 锁的分类

**按锁的粒度分类**：
- 全局锁
  - FLUSH TABLES WITH READ LOCK
  - 使用场景：全库逻辑备份
  - 影响：整个数据库只读
- 表级锁
  - 表锁（Table Lock）
    - LOCK TABLES ... READ/WRITE
    - 读锁（共享锁）
    - 写锁（排他锁）
  - 元数据锁（MDL，Metadata Lock）
    - 自动加锁
    - DDL 操作时的锁等待
    - 长事务持有 MDL 的危害
  - 意向锁（Intention Lock）
    - 意向共享锁（IS）
    - 意向排他锁（IX）
    - 作用：快速判断是否可以加表锁
  - AUTO-INC 锁
    - 自增主键的锁机制
    - innodb_autoinc_lock_mode 参数
- 行级锁（InnoDB）
  - 记录锁（Record Lock）
  - 间隙锁（Gap Lock）
  - 临键锁（Next-Key Lock）
  - 插入意向锁（Insert Intention Lock）

**按锁的模式分类**：
- 共享锁（Shared Lock，S 锁）
  - SELECT ... LOCK IN SHARE MODE
  - 也叫读锁
  - 多个事务可以同时持有
- 排他锁（Exclusive Lock，X 锁）
  - SELECT ... FOR UPDATE
  - 也叫写锁
  - 只能一个事务持有

**按锁的算法分类**：
- 记录锁（Record Lock）
  - 锁定单个行记录
  - 总是锁定索引记录
  - 如果表没有索引，InnoDB 创建隐藏的聚簇索引
- 间隙锁（Gap Lock）
  - 锁定索引记录之间的间隙
  - 防止幻读
  - 只在 RR 隔离级别下有效
  - 间隙锁之间不互斥（都是为了防插入）
- 临键锁（Next-Key Lock）
  - 记录锁 + 间隙锁
  - 左开右闭区间：(a, b]
  - InnoDB 的默认行锁算法
  - 防止幻读的关键

#### 3.2 锁的实现原理

**行锁的实现**：
- 锁加在索引上
  - 主键索引：锁主键索引
  - 唯一索引：锁唯一索引 + 主键索引（如需回表）
  - 普通索引：锁普通索引 + 主键索引
  - 无索引：锁全表（退化为表锁）

**不同场景的加锁分析**：

```sql
-- 假设有表：CREATE TABLE t (id INT PRIMARY KEY, a INT, b INT, KEY(a));

-- 1. 唯一索引等值查询（记录存在）
SELECT * FROM t WHERE id = 10 FOR UPDATE;
-- 加锁：id = 10 的记录锁

-- 2. 唯一索引等值查询（记录不存在）
SELECT * FROM t WHERE id = 15 FOR UPDATE;
-- 加锁：(10, 20) 的间隙锁

-- 3. 唯一索引范围查询
SELECT * FROM t WHERE id >= 10 AND id < 20 FOR UPDATE;
-- 加锁：[10, 20) 的临键锁

-- 4. 非唯一索引等值查询
SELECT * FROM t WHERE a = 10 FOR UPDATE;
-- 加锁：a = 10 的记录锁 + (a 值前后的间隙锁)

-- 5. 非唯一索引范围查询
SELECT * FROM t WHERE a >= 10 AND a < 20 FOR UPDATE;
-- 加锁：a 索引上的临键锁 + 主键索引上的记录锁

-- 6. 无索引条件
SELECT * FROM t WHERE b = 10 FOR UPDATE;
-- 加锁：全表扫描，所有记录都加锁（表锁）
```

#### 3.3 死锁

**死锁的产生**：
- 定义：两个或多个事务互相持有对方需要的锁
- 四个必要条件：
  - 互斥条件
  - 请求与保持条件
  - 不可剥夺条件
  - 循环等待条件

**死锁案例分析**：

```sql
-- 事务 A                      事务 B
BEGIN;                         BEGIN;
UPDATE t SET a=1 WHERE id=1;
                               UPDATE t SET a=2 WHERE id=2;
UPDATE t SET a=3 WHERE id=2;
                               UPDATE t SET a=4 WHERE id=1;
-- 死锁！
```

**死锁检测与处理**：
- 死锁检测：innodb_deadlock_detect = ON
- 超时机制：innodb_lock_wait_timeout（默认 50 秒）
- 死锁处理：回滚持有最少行级写锁的事务
- 查看死锁日志：SHOW ENGINE INNODB STATUS

**如何避免死锁**：
1. 按相同顺序访问资源
2. 尽量使用索引访问数据（避免锁全表）
3. 减小事务粒度，缩短事务时间
4. 使用较低的隔离级别（如 RC）
5. 为表添加合理的索引
6. 避免大事务，拆分成小事务
7. 使用 SELECT ... FOR UPDATE 要慎重

#### 3.4 锁的监控与诊断

**查看锁信息**：
```sql
-- 查看当前锁等待
SELECT * FROM information_schema.INNODB_LOCKS;
SELECT * FROM information_schema.INNODB_LOCK_WAITS;

-- MySQL 8.0 使用 performance_schema
SELECT * FROM performance_schema.data_locks;
SELECT * FROM performance_schema.data_lock_waits;

-- 查看事务信息
SELECT * FROM information_schema.INNODB_TRX;

-- 查看死锁日志
SHOW ENGINE INNODB STATUS;
```

**分析锁等待**：
- 找出被阻塞的事务
- 找出阻塞其他事务的事务
- 分析锁持有时间
- 定位慢 SQL

### 4. 事务 ⭐⭐⭐⭐⭐ 重点

#### 4.1 事务的 ACID 特性

**Atomicity（原子性）**：
- 定义：事务是不可分割的最小单位
- 实现：Undo Log
  - 记录数据修改前的值
  - 事务回滚时恢复数据
  - 保证原子性

**Consistency（一致性）**：
- 定义：事务执行前后数据保持一致
- 实现：由其他三个特性共同保证
  - 原子性 + 隔离性 + 持久性 → 一致性
  - 应用层的约束（外键、唯一索引等）

**Isolation（隔离性）**：
- 定义：并发事务之间互不干扰
- 实现：锁机制 + MVCC
  - 锁：解决写-写冲突
  - MVCC：解决读-写冲突

**Durability（持久性）**：
- 定义：事务提交后永久保存
- 实现：Redo Log
  - WAL（Write-Ahead Logging）
  - 先写日志，再写磁盘
  - 崩溃恢复

#### 4.2 事务隔离级别

**四种隔离级别**：

| 隔离级别 | 脏读 | 不可重复读 | 幻读 |
|---------|------|-----------|------|
| READ UNCOMMITTED（读未提交） | ✓ | ✓ | ✓ |
| READ COMMITTED（读已提交） | ✗ | ✓ | ✓ |
| REPEATABLE READ（可重复读） | ✗ | ✗ | ✗ |
| SERIALIZABLE（串行化） | ✗ | ✗ | ✗ |

**问题说明**：

1. **脏读（Dirty Read）**：
   - 读到其他事务未提交的数据
   - 其他事务可能回滚，导致读到的是无效数据
   ```sql
   -- 事务 A                事务 B
   BEGIN;
                           BEGIN;
                           UPDATE t SET a=100 WHERE id=1;
   SELECT * FROM t WHERE id=1;  -- 读到 a=100（脏读）
                           ROLLBACK;  -- 回滚了
   ```

2. **不可重复读（Non-Repeatable Read）**：
   - 同一事务内，多次读取同一数据，结果不一致
   - 其他事务修改并提交了数据
   ```sql
   -- 事务 A                     事务 B
   BEGIN;
   SELECT * FROM t WHERE id=1;  -- a=10
                                BEGIN;
                                UPDATE t SET a=100 WHERE id=1;
                                COMMIT;
   SELECT * FROM t WHERE id=1;  -- a=100（不可重复读）
   ```

3. **幻读（Phantom Read）**：
   - 同一事务内，多次查询，结果集不一致
   - 其他事务插入或删除了数据
   ```sql
   -- 事务 A                         事务 B
   BEGIN;
   SELECT * FROM t WHERE id>10;     -- 返回 3 条
                                    BEGIN;
                                    INSERT INTO t VALUES(15, ...);
                                    COMMIT;
   SELECT * FROM t WHERE id>10;     -- 返回 4 条（幻读）
   ```

**MySQL 默认隔离级别**：
- InnoDB：REPEATABLE READ
- 其他数据库：READ COMMITTED（Oracle、SQL Server）

**设置隔离级别**：
```sql
-- 查看全局隔离级别
SELECT @@global.transaction_isolation;

-- 查看会话隔离级别
SELECT @@transaction_isolation;

-- 设置会话隔离级别
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

#### 4.3 MVCC（多版本并发控制）⭐⭐⭐⭐⭐

**MVCC 原理**：

**核心组件**：
1. **隐藏列**：
   - DB_TRX_ID（6 字节）：最后修改该行的事务 ID
   - DB_ROLL_PTR（7 字节）：回滚指针，指向 Undo Log
   - DB_ROW_ID（6 字节）：隐藏主键（如果表没有主键）

2. **Undo Log 版本链**：
   ```
   最新版本 → 版本 3 → 版本 2 → 版本 1
   (TRX_ID: 100) (TRX_ID: 90) (TRX_ID: 80)
   ```

3. **Read View（读视图）**：
   - m_ids：当前活跃的事务 ID 列表
   - min_trx_id：m_ids 中最小的事务 ID
   - max_trx_id：生成 Read View 时系统应该分配给下一个事务的 ID
   - creator_trx_id：创建该 Read View 的事务 ID

**可见性判断规则**：

对于版本链上的某个版本，其 trx_id 记为 version_trx_id：

1. 如果 `version_trx_id == creator_trx_id`：
   - 说明是当前事务自己修改的，**可见**

2. 如果 `version_trx_id < min_trx_id`：
   - 说明是在当前事务开始前已经提交的，**可见**

3. 如果 `version_trx_id >= max_trx_id`：
   - 说明是在当前事务开始后才开启的，**不可见**

4. 如果 `min_trx_id <= version_trx_id < max_trx_id`：
   - 如果 `version_trx_id` 在 `m_ids` 中，说明创建 Read View 时事务还活跃，**不可见**
   - 如果 `version_trx_id` 不在 `m_ids` 中，说明已经提交，**可见**

如果不可见，沿着 Undo Log 版本链继续查找，直到找到可见的版本。

**RC 和 RR 隔离级别的 MVCC 区别**：

- **READ COMMITTED**：
  - 每次读取数据前都生成一个新的 Read View
  - 可以读到其他事务已提交的修改
  - 会导致不可重复读

- **REPEATABLE READ**：
  - 只在第一次读取数据时生成 Read View
  - 之后的读取都复用这个 Read View
  - 保证可重复读

**MVCC 解决的问题**：
- ✅ 读-写不冲突：读不加锁，写不阻塞读
- ✅ 提高并发性能
- ✅ 在 RR 级别下解决了幻读（快照读）

**MVCC 的局限**：
- ❌ 只对快照读（普通 SELECT）有效
- ❌ 对当前读（SELECT FOR UPDATE）无效
- ❌ 仍需要 Next-Key Lock 防止幻读（当前读场景）

#### 4.4 当前读 vs 快照读

**快照读（Snapshot Read）**：
- 普通的 SELECT 语句
- 读取的是历史版本（通过 MVCC）
- 不加锁
```sql
SELECT * FROM t WHERE id = 1;
```

**当前读（Current Read）**：
- 读取的是最新版本
- 会加锁
- 包括：
  ```sql
  SELECT * FROM t WHERE id = 1 LOCK IN SHARE MODE;  -- 加 S 锁
  SELECT * FROM t WHERE id = 1 FOR UPDATE;           -- 加 X 锁
  INSERT INTO t VALUES (...);                        -- 加 X 锁
  UPDATE t SET ... WHERE ...;                        -- 加 X 锁
  DELETE FROM t WHERE ...;                           -- 加 X 锁
  ```

**幻读的完整防范**：
- 快照读：MVCC 解决
- 当前读：Next-Key Lock 解决

#### 4.5 Redo Log 与 Undo Log

**Redo Log（重做日志）**：

**作用**：保证事务的持久性

**工作原理**：
1. 事务修改数据时，先写 Redo Log Buffer
2. 事务提交时，将 Redo Log Buffer 刷到磁盘（Redo Log File）
3. 后台线程异步将脏页刷到磁盘

**WAL（Write-Ahead Logging）**：
- 先写日志，再写磁盘
- 日志是顺序写，比随机写磁盘快
- 即使数据库崩溃，也能通过 Redo Log 恢复

**Redo Log 两阶段提交**：
1. Prepare 阶段：写 Redo Log，状态为 prepare
2. Commit 阶段：写 Binlog，然后写 Redo Log，状态为 commit

**参数配置**：
```sql
-- Redo Log 刷盘策略
innodb_flush_log_at_trx_commit:
  0: 每秒刷一次（性能最好，可能丢 1 秒数据）
  1: 每次提交都刷盘（最安全，性能最差）
  2: 每次提交写到 OS 缓存（折中）
```

**Undo Log（回滚日志）**：

**作用**：
1. 保证事务的原子性（回滚）
2. 实现 MVCC（读取历史版本）

**工作原理**：
- 记录数据修改前的值
- 形成版本链
- 事务回滚时，根据 Undo Log 恢复数据
- 事务提交后，Undo Log 不会立即删除（MVCC 可能需要）

**Undo Log 类型**：
- Insert Undo Log：插入操作产生，只在事务回滚时需要
- Update Undo Log：更新和删除操作产生，MVCC 需要

**Purge 操作**：
- 后台线程定期清理不再需要的 Undo Log
- 判断标准：没有事务需要读取这个版本

#### 4.6 事务的最佳实践

**事务设计原则**：
1. **保持事务简短**：
   - 减少锁持有时间
   - 降低死锁概率
   - 提高并发性能

2. **避免长事务**：
   - 长事务的危害：
     - 锁持有时间长
     - Undo Log 无法清理
     - 占用大量回滚段
     - 可能导致主从延迟

3. **合理使用隔离级别**：
   - 不需要可重复读时，使用 RC 级别
   - 减少间隙锁，提高并发

4. **显式开启事务**：
   ```sql
   BEGIN;
   -- SQL 语句
   COMMIT;
   ```

5. **异常处理**：
   ```sql
   BEGIN;
   -- SQL 语句
   IF error THEN
       ROLLBACK;
   ELSE
       COMMIT;
   END IF;
   ```

**避免常见问题**：
- ❌ 在事务中执行耗时操作（网络请求、文件 IO）
- ❌ 在事务中访问多个表（增加死锁风险）
- ❌ 在循环中开启事务
- ❌ 忘记提交或回滚事务

## 第二部分：MySQL 性能优化

### 5. 慢查询优化

#### 5.1 慢查询日志
- 开启慢查询日志
- long_query_time 配置
- 慢查询日志分析工具：mysqldumpslow、pt-query-digest

#### 5.2 SQL 优化技巧
- 避免 SELECT *
- 使用 LIMIT 限制返回行数
- 避免在 WHERE 子句中使用函数
- 使用 UNION ALL 替代 UNION
- 分批处理大量数据
- 使用 JOIN 替代子查询
- 优化 ORDER BY
- 优化 GROUP BY
- 合理使用临时表

#### 5.3 表结构优化
- 选择合适的数据类型
  - 整数类型：TINYINT、INT、BIGINT
  - 字符串类型：CHAR、VARCHAR、TEXT
  - 时间类型：TIMESTAMP、DATETIME
- 字段长度合理
- 范式与反范式设计
- 垂直分表
- 水平分表

### 6. 并发控制优化

#### 6.1 减少锁冲突
- 使用索引避免全表扫描
- 拆分大事务
- 使用较低的隔离级别
- 使用乐观锁
- 使用队列削峰

#### 6.2 批量操作优化
- 批量插入：INSERT INTO ... VALUES (...), (...), (...)
- 批量更新：使用 CASE WHEN
- 使用 LOAD DATA INFILE

### 7. 配置优化

#### 7.1 InnoDB 配置
```ini
# Buffer Pool 大小（建议为物理内存的 60-80%）
innodb_buffer_pool_size = 8G

# Buffer Pool 实例数（大内存时增加）
innodb_buffer_pool_instances = 8

# Redo Log 大小
innodb_log_file_size = 2G
innodb_log_files_in_group = 2

# 刷盘策略
innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT

# 锁等待超时
innodb_lock_wait_timeout = 50

# 死锁检测
innodb_deadlock_detect = ON
```

#### 7.2 连接池配置
```ini
# 最大连接数
max_connections = 1000

# 连接超时
wait_timeout = 28800
interactive_timeout = 28800
```

## 第三部分：Redis

### 8. Redis 数据结构

#### 8.1 基本数据类型
- String：字符串、数字、bitmap
- Hash：对象存储
- List：队列、栈
- Set：去重、交并差集
- Sorted Set：排行榜

#### 8.2 高级数据类型
- Bitmap：位图
- HyperLogLog：基数统计
- Geo：地理位置
- Stream：消息队列（Redis 5.0+）

#### 8.3 底层数据结构
- SDS（Simple Dynamic String）
- ZipList（压缩列表）
- QuickList（快速列表）
- SkipList（跳表）
- IntSet（整数集合）
- HashTable（哈希表）

### 9. Redis 持久化

#### 9.1 RDB（快照）
- 工作原理：fork 子进程，写时复制
- 触发方式：SAVE、BGSAVE、自动触发
- 优缺点分析

#### 9.2 AOF（追加文件）
- 工作原理：记录写命令
- 重写机制：BGREWRITEAOF
- 三种刷盘策略：always、everysec、no
- 优缺点分析

#### 9.3 混合持久化（Redis 4.0+）
- RDB + AOF 结合
- 快速加载 + 完整性保证

### 10. Redis 高可用

#### 10.1 主从复制
- 全量同步 vs 部分同步
- 复制原理
- 复制延迟问题

#### 10.2 哨兵模式（Sentinel）
- 监控、通知、自动故障转移
- 哨兵配置与部署

#### 10.3 集群模式（Cluster）
- 分片算法：哈希槽
- 16384 个槽位
- 客户端路由：moved、ask
- 扩容与缩容

### 11. Redis 应用场景

#### 11.1 缓存
- 缓存穿透
- 缓存击穿
- 缓存雪崩
- 缓存更新策略

#### 11.2 分布式锁
- SETNX + EXPIRE
- RedLock 算法
- Redisson 实现

#### 11.3 其他应用
- 限流：令牌桶、漏桶
- 消息队列：List、Stream
- 延迟队列：Sorted Set
- 计数器：INCR
- 排行榜：Sorted Set

## 第四部分：分库分表

### 12. 分库分表策略

#### 12.1 垂直拆分
- 垂直分库：按业务拆分
- 垂直分表：按字段拆分

#### 12.2 水平拆分
- 水平分表：单表数据量大
- 水平分库：并发压力大

#### 12.3 分片算法
- 范围分片
- 哈希分片
- 一致性哈希
- 地理位置分片

### 13. 分库分表中间件

#### 13.1 ShardingSphere
- Sharding-JDBC
- Sharding-Proxy
- 分片键选择
- 分布式事务

#### 13.2 Mycat
- 配置与部署
- 读写分离
- 分库分表规则

### 14. 分布式事务

#### 14.1 两阶段提交（2PC）
- Prepare 阶段
- Commit 阶段
- 问题：阻塞、单点故障

#### 14.2 三阶段提交（3PC）
- CanCommit
- PreCommit
- DoCommit

#### 14.3 TCC（Try-Confirm-Cancel）
- Try：资源预留
- Confirm：确认提交
- Cancel：回滚

#### 14.4 Saga
- 正向补偿
- 反向补偿

#### 14.5 本地消息表
- 事务表记录消息
- 定时任务扫描发送

#### 14.6 最大努力通知
- 定时重试
- 最终一致性

## 面试高频考点

### 必须掌握（⭐⭐⭐⭐⭐）

1. **MySQL 索引原理**
   - B+ Tree 为什么适合做索引
   - 聚簇索引 vs 非聚簇索引
   - 回表查询 vs 覆盖索引
   - 索引失效的场景

2. **MySQL 锁机制**
   - 表锁、行锁、间隙锁、临键锁
   - 死锁产生的原因和解决方案
   - 不同 SQL 语句的加锁分析
   - MVCC 原理

3. **MySQL 事务**
   - ACID 特性的实现原理
   - 四种隔离级别及其问题
   - 脏读、不可重复读、幻读
   - Redo Log 和 Undo Log 的作用

4. **索引优化**
   - 如何设计索引
   - 如何分析慢查询
   - EXPLAIN 执行计划分析

5. **Redis 数据结构**
   - 五种基本类型及应用场景
   - 底层实现原理
   - 为什么快

### 深入理解（⭐⭐⭐⭐）

6. **MVCC 详解**
   - Read View 原理
   - RC 和 RR 级别的 MVCC 区别
   - 可见性判断算法

7. **Next-Key Lock**
   - 记录锁 + 间隙锁
   - 如何防止幻读
   - 不同索引类型的加锁规则

8. **Redis 持久化**
   - RDB vs AOF
   - 混合持久化
   - 如何保证数据不丢失

9. **缓存问题**
   - 缓存穿透、击穿、雪崩
   - 解决方案

10. **分库分表**
    - 为什么要分库分表
    - 如何选择分片键
    - 分布式事务解决方案

### 实战能力（⭐⭐⭐⭐⭐）

- 设计一个高并发秒杀系统的数据库方案
- 分析并优化一个慢 SQL
- 分析一个死锁场景并给出解决方案
- 设计一个分布式锁
- 设计一个分库分表方案

## 学习路径

### 第一阶段：MySQL 基础（2-3 周）
1. MySQL 架构与存储引擎
2. 索引原理与优化
3. 执行计划分析

### 第二阶段：锁与事务（3-4 周）⭐ 重点
1. 锁的分类与原理
2. 加锁规则分析
3. 死锁问题
4. 事务 ACID
5. 隔离级别
6. MVCC 原理

### 第三阶段：性能优化（2-3 周）
1. 慢查询优化
2. 表结构优化
3. 配置优化

### 第四阶段：Redis（2-3 周）
1. 数据结构
2. 持久化
3. 高可用
4. 应用场景

### 第五阶段：分库分表（2-3 周）
1. 分库分表策略
2. 中间件使用
3. 分布式事务

## 推荐学习资源

### 书籍
- 《MySQL 技术内幕：InnoDB 存储引擎》 - 姜承尧
- 《高性能 MySQL》 - Baron Schwartz
- 《Redis 设计与实现》 - 黄健宏

### 博客文章
- MySQL 官方文档
- 阿里云数据库内核月报
- 丁奇的《MySQL 实战 45 讲》

### 实践项目
- 搭建主从复制环境
- 使用 Sharding-JDBC 实现分库分表
- 实现一个 Redis 分布式锁

---

**预计总学习时间**：12-16 周

**重点章节**：
- MySQL 锁机制（第 3 章）
- MySQL 事务（第 4 章）
- MVCC 原理
- 索引优化

**学习建议**：
1. 理论 + 实践：每个知识点都要动手验证
2. 画图理解：锁、事务、MVCC 都适合用图表示
3. 源码阅读：理解 InnoDB 实现原理
4. 真实案例：分析生产环境的慢查询和死锁

开始你的数据库深度学习之旅吧！💪
