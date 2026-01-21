# Redis 持久化机制

> Redis 是内存数据库，持久化机制确保数据不会因进程退出或服务器宕机而丢失。

## 持久化方式概览 ⭐⭐⭐⭐⭐

Redis 提供了 3 种持久化方式：

| 方式 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| **RDB** | 快照（Snapshot） | 文件小、恢复快、性能影响小 | 可能丢失最后一次快照之后的数据 |
| **AOF** | 追加日志（Append Only File） | 数据安全性高、可读性好 | 文件大、恢复慢、性能影响大 |
| **混合持久化** | RDB + AOF 混合（4.0+） | 结合两者优点 | Redis 4.0+ 才支持 |

---

## RDB 持久化 ⭐⭐⭐⭐⭐

### 工作原理

RDB 持久化是通过**创建快照**的方式，将某个时间点的所有数据保存到磁盘。

**触发方式**：
1. **手动触发**：`SAVE` 或 `BGSAVE` 命令
2. **自动触发**：配置文件中的 `save` 规则

### SAVE vs BGSAVE

| 命令 | 阻塞 | 实现方式 | 使用场景 |
|------|------|---------|---------|
| **SAVE** | 是 | 主进程直接执行，阻塞所有请求 | 几乎不用（会阻塞服务） |
| **BGSAVE** | 否 | fork 子进程执行，主进程继续处理请求 | 生产环境使用 |

**BGSAVE 流程**：
```
1. Redis 主进程 fork 一个子进程
2. 子进程将数据写入临时 RDB 文件
3. 写入完成后，原子性地替换旧的 RDB 文件
4. 子进程退出
```

**fork 时的 Copy-On-Write（COW）机制**：
```
fork 时不会复制整个内存，而是复制页表（Page Table）
只有当父进程或子进程修改数据时，才会复制对应的内存页

优点：fork 速度快，内存占用少
缺点：如果在 RDB 期间有大量写操作，可能占用 2 倍内存
```

### 配置详解

**redis.conf 配置**：
```bash
# 自动触发规则（满足任一条件就触发）
save 900 1      # 900 秒内至少 1 次修改
save 300 10     # 300 秒内至少 10 次修改
save 60 10000   # 60 秒内至少 10000 次修改

# 禁用自动保存（只能手动触发）
save ""

# RDB 文件名
dbfilename dump.rdb

# RDB 文件存储路径
dir /var/lib/redis

# 后台保存失败时是否停止写入
stop-writes-on-bgsave-error yes

# 是否压缩 RDB 文件（使用 LZF 压缩）
rdbcompression yes

# 是否对 RDB 文件进行校验（CRC64）
rdbchecksum yes
```

### RDB 文件格式

```
┌─────────────────────────────────────────────────────────────┐
│  REDIS 魔数  │  版本号  │  数据库选择  │  键值对  │  EOF  │  校验和  │
│   (5 bytes)  │ (4 bytes)│              │          │ (1 byte)│ (8 bytes)│
└─────────────────────────────────────────────────────────────┘
```

### 手动触发示例

```bash
# 同步保存（阻塞，不推荐）
SAVE

# 异步保存（推荐）
BGSAVE

# 查看最后一次保存时间
LASTSAVE

# 查看 RDB 保存状态
INFO persistence
```

### RDB 的优缺点

**优点**：
1. **文件紧凑**：全量快照，文件小，适合备份和灾难恢复
2. **恢复速度快**：直接加载 RDB 文件，速度快于 AOF
3. **性能影响小**：使用子进程，对主进程性能影响小
4. **适合大规模数据恢复**：可以快速恢复 GB 级数据

**缺点**：
1. **数据丢失风险**：两次快照之间的数据可能丢失
2. **fork 耗时**：数据量大时，fork 可能耗时较长（几百 ms）
3. **不适合实时性要求高的场景**：RDB 间隔时间长，可能丢失较多数据

### 使用场景

- **数据备份**：定期备份 RDB 文件到其他服务器
- **灾难恢复**：RDB 文件可快速恢复数据
- **从节点持久化**：主从架构中，从节点使用 RDB
- **可接受分钟级数据丢失的场景**

---

## AOF 持久化 ⭐⭐⭐⭐⭐

### 工作原理

AOF（Append Only File）通过**记录写命令**的方式持久化数据。

**流程**：
```
1. 客户端发送写命令（SET、HSET、LPUSH 等）
2. Redis 执行命令并将命令追加到 AOF 缓冲区
3. 根据 appendfsync 策略将缓冲区内容写入 AOF 文件
4. 定期重写 AOF 文件，压缩文件大小
```

### 开启 AOF

**redis.conf 配置**：
```bash
# 启用 AOF
appendonly yes

# AOF 文件名
appendfilename "appendonly.aof"

# AOF 文件存储路径（与 RDB 相同）
dir /var/lib/redis
```

### 同步策略：appendfsync ⭐⭐⭐⭐⭐

| 策略 | 说明 | 性能 | 安全性 | 数据丢失 |
|------|------|------|--------|---------|
| **always** | 每个写命令都同步到磁盘 | 差 | 高 | 几乎不丢失 |
| **everysec** | 每秒同步一次（默认） | 好 | 较高 | 最多丢失 1 秒数据 |
| **no** | 由操作系统决定何时同步 | 最好 | 低 | 可能丢失多秒数据 |

**推荐配置**：
```bash
# 生产环境推荐
appendfsync everysec

# 平衡性能和安全性
# 最多丢失 1 秒数据，性能影响小
```

### AOF 重写 ⭐⭐⭐⭐⭐

**为什么需要重写？**
```
AOF 文件会越来越大，因为它记录了所有写命令。

例如：
SET key value1
SET key value2
SET key value3
...
SET key value100

重写后：
SET key value100   # 只保留最终状态
```

**重写方式**：

**1. 手动触发**：
```bash
BGREWRITEAOF
```

**2. 自动触发**：
```bash
# 当前 AOF 文件大小超过上次重写后的 100%，且大于 64MB 时触发
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

**重写流程**：
```
1. Redis fork 一个子进程
2. 子进程遍历内存中的数据，生成新的 AOF 文件
3. 期间主进程的写命令同时写入：
   - AOF 缓冲区（写入旧 AOF 文件）
   - AOF 重写缓冲区（子进程完成后追加到新 AOF 文件）
4. 子进程完成后，主进程将重写缓冲区内容追加到新 AOF 文件
5. 原子性地替换旧 AOF 文件
```

**重写优化**：
```bash
# 重写期间是否允许 AOF 追加（no 性能更好但可能阻塞）
aof-rewrite-incremental-fsync yes

# AOF 重写期间主进程是否执行 fsync（no 性能更好）
no-appendfsync-on-rewrite no
```

### AOF 文件格式

AOF 文件是纯文本格式，使用 **RESP 协议**：

```
# SET name "Zhang"
*3           # 3 个参数
$3           # 第一个参数长度 3
SET
$4           # 第二个参数长度 4
name
$5           # 第三个参数长度 5
Zhang
```

**查看 AOF 文件**：
```bash
cat appendonly.aof
```

### AOF 损坏修复

**检查 AOF 文件**：
```bash
redis-check-aof appendonly.aof
```

**修复 AOF 文件**：
```bash
redis-check-aof --fix appendonly.aof
```

### AOF 的优缺点

**优点**：
1. **数据安全性高**：everysec 模式最多丢失 1 秒数据
2. **可读性好**：AOF 文件是文本格式，易于分析和修改
3. **支持增量备份**：可以通过 AOF 文件回放历史操作
4. **自动重写**：避免文件过大

**缺点**：
1. **文件大**：比 RDB 文件大得多
2. **恢复慢**：需要回放所有命令，速度慢于 RDB
3. **性能影响**：写入频繁时，fsync 会影响性能
4. **可能出现 Bug**：AOF 重写逻辑复杂，曾有 Bug 导致数据不一致

### 使用场景

- **数据安全性要求高**：金融、电商等场景
- **可容忍一定性能损耗**：写入不是特别频繁的场景
- **需要数据审计**：可通过 AOF 文件回溯操作历史

---

## 混合持久化 ⭐⭐⭐⭐⭐

### 什么是混合持久化？

Redis 4.0 引入了**混合持久化**（RDB-AOF Hybrid Persistence），结合了 RDB 和 AOF 的优点。

**原理**：
```
AOF 重写时：
1. 子进程先将内存数据以 RDB 格式写入 AOF 文件（快照部分）
2. 然后将重写期间的写命令以 AOF 格式追加到文件末尾（增量部分）

AOF 文件结构：
┌─────────────────────────────────────────┐
│  RDB 格式的快照数据  │  AOF 格式的增量命令  │
└─────────────────────────────────────────┘
```

### 开启混合持久化

```bash
# Redis 4.0+ 默认开启
aof-use-rdb-preamble yes
```

### 混合持久化的优势

| 对比项 | RDB | AOF | 混合持久化 |
|--------|-----|-----|-----------|
| **文件大小** | 小 | 大 | 适中（RDB 部分小） |
| **恢复速度** | 快 | 慢 | 快（RDB 部分快速加载） |
| **数据安全** | 差 | 好 | 好（AOF 增量保证） |
| **兼容性** | 好 | 好 | Redis 4.0+ |

**最佳实践**：
```bash
# 启用 AOF
appendonly yes

# 启用混合持久化
aof-use-rdb-preamble yes

# 每秒同步
appendfsync everysec

# 自动重写配置
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

---

## RDB vs AOF vs 混合持久化 ⭐⭐⭐⭐⭐

### 对比表

| 特性 | RDB | AOF | 混合持久化 |
|------|-----|-----|-----------|
| **启动优先级** | 低 | 高 | 高（AOF 优先） |
| **文件大小** | 小 | 大 | 适中 |
| **恢复速度** | 快 | 慢 | 快 |
| **数据完整性** | 可能丢失分钟级数据 | 最多丢失 1 秒 | 最多丢失 1 秒 |
| **CPU 占用** | 低 | 高（fsync） | 适中 |
| **内存占用** | fork 时可能 2 倍 | 稍高（缓冲区） | fork 时可能 2 倍 |
| **适用场景** | 备份、从节点 | 生产主节点 | 生产主节点（推荐） |

### 启动时的加载优先级

```
Redis 启动时：
1. 如果 AOF 开启 → 加载 AOF 文件
2. 如果 AOF 关闭 → 加载 RDB 文件
3. 如果都没有 → 空实例启动
```

### 如何选择？

**纯缓存场景**（可接受数据丢失）：
```bash
# 只用 RDB
appendonly no
save 900 1
save 300 10
save 60 10000
```

**数据重要场景**（不能接受数据丢失）：
```bash
# 使用混合持久化（推荐）
appendonly yes
aof-use-rdb-preamble yes
appendfsync everysec
```

**极致性能场景**（内存充足）：
```bash
# 关闭持久化
appendonly no
save ""
```

---

## 持久化性能优化 ⭐⭐⭐⭐

### 1. 合理配置 fork 优化

```bash
# 内核参数优化（Linux）
# 允许内存过量分配
echo 1 > /proc/sys/vm/overcommit_memory

# 关闭透明大页（THP），避免 fork 时延迟
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

### 2. 避免磁盘 I/O 瓶颈

```bash
# 使用 SSD 磁盘存储 RDB/AOF 文件
dir /mnt/ssd/redis

# AOF 重写期间不执行 fsync（提升性能，略微降低安全性）
no-appendfsync-on-rewrite yes
```

### 3. 监控持久化状态

```bash
# 查看持久化信息
INFO persistence

# 关键指标：
# - rdb_last_save_time: 上次 RDB 保存时间
# - rdb_changes_since_last_save: 距上次保存的修改次数
# - aof_current_size: 当前 AOF 文件大小
# - aof_last_rewrite_time_sec: 上次 AOF 重写耗时
```

### 4. 避免大 key

```bash
# 大 key 会导致 RDB/AOF 操作变慢
# 建议单个 key 不超过 10MB

# 查找大 key
redis-cli --bigkeys
```

---

## 常见问题 ⭐⭐⭐⭐⭐

### Q1: Redis 挂了数据会丢失吗？

**答**：取决于持久化配置：
- **RDB**：可能丢失最后一次快照之后的所有数据（分钟级）
- **AOF（everysec）**：最多丢失 1 秒数据
- **AOF（always）**：几乎不丢失数据（性能差）
- **无持久化**：所有数据丢失

### Q2: RDB 和 AOF 能同时开启吗？

**答**：可以，且推荐同时开启。
- Redis 重启时优先加载 AOF 文件（数据更完整）
- RDB 可用于备份和灾难恢复

### Q3: fork 操作会阻塞主进程吗？

**答**：会，但时间很短（几毫秒到几百毫秒）。
- fork 只是复制页表，不复制数据
- 数据量越大，fork 耗时越长
- 可通过 `INFO stats` 查看 `latest_fork_usec`

### Q4: AOF 文件损坏怎么办？

**答**：使用 `redis-check-aof` 工具修复：
```bash
redis-check-aof --fix appendonly.aof
```

### Q5: 如何实现数据备份？

**答**：
1. **手动备份**：定期执行 `BGSAVE`，复制 RDB 文件到其他服务器
2. **自动备份**：定时任务（cron）备份 RDB 文件
3. **主从备份**：搭建从节点，从节点自动同步数据

```bash
# 备份脚本示例
#!/bin/bash
redis-cli BGSAVE
sleep 10
cp /var/lib/redis/dump.rdb /backup/dump-$(date +%Y%m%d).rdb
```

### Q6: Redis 4.0 之前没有混合持久化怎么办？

**答**：同时开启 RDB 和 AOF：
```bash
appendonly yes
appendfsync everysec
save 900 1
```

---

## 面试要点 ⭐⭐⭐⭐⭐

### 高频问题

**Q1: Redis 的持久化方式有哪些？**
- RDB（快照）、AOF（日志）、混合持久化（RDB + AOF）

**Q2: RDB 和 AOF 的区别？**
- RDB：全量快照，文件小，恢复快，可能丢失分钟级数据
- AOF：记录写命令，文件大，恢复慢，最多丢失 1 秒数据

**Q3: AOF 的三种同步策略是什么？**
- always：每次写入都同步，安全但慢
- everysec：每秒同步一次，推荐
- no：由 OS 决定，快但不安全

**Q4: 什么是 AOF 重写？**
- 遍历内存数据，生成最小命令集，压缩 AOF 文件大小
- 通过 fork 子进程异步执行，不阻塞主进程

**Q5: 混合持久化的优势是什么？**
- 文件大小适中（RDB 部分紧凑）
- 恢复速度快（RDB 部分快速加载）
- 数据安全性高（AOF 增量保证）

**Q6: Redis 重启时如何加载数据？**
- 优先加载 AOF（如果开启）
- 否则加载 RDB
- 都没有则空实例启动

**Q7: fork 操作的原理是什么？**
- 复制父进程的页表，不复制数据（Copy-On-Write）
- 只有修改时才复制对应内存页
- 数据量大时，fork 可能耗时较长

---

## 参考资料

1. **官方文档**：[Redis Persistence](https://redis.io/docs/management/persistence/)
2. **书籍推荐**：
   - 《Redis 设计与实现》（黄健宏）
   - 《Redis 开发与运维》（付磊、张益军）
3. **源码**：[Redis Persistence 源码](https://github.com/redis/redis/tree/unstable/src)
