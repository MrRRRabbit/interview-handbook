# 分布式存储

## 1. 分布式存储基础

### 1.1 数据分片（Sharding）

#### 哈希分片
- 对 key 计算哈希值，取模得到分片
- 优点：分布均匀
- 缺点：扩缩容需要数据迁移

```java
/**
 * 简单哈希分片
 */
public class HashSharding {
    private int shardCount;

    public HashSharding(int shardCount) {
        this.shardCount = shardCount;
    }

    public int getShard(String key) {
        int hash = key.hashCode();
        // 处理负数哈希值
        return Math.abs(hash % shardCount);
    }
}

// 问题：扩容时几乎所有数据需要迁移
// 3 节点 -> 4 节点：约 75% 数据需要迁移
```

#### 范围分片
- 按 key 的范围分片
- 优点：支持范围查询
- 缺点：可能数据倾斜

```
范围分片示例：

分片1: [A-F]  -> 用户 A-F
分片2: [G-L]  -> 用户 G-L
分片3: [M-R]  -> 用户 M-R
分片4: [S-Z]  -> 用户 S-Z

问题：如果姓 Wang 的用户特别多，分片4 会成为热点
```

### 1.2 一致性哈希详解 ⭐⭐⭐⭐⭐

#### 基本原理
```
传统哈希：hash(key) % N
问题：N 变化时，几乎所有 key 的映射都会改变

一致性哈希：
1. 将哈希空间组织成环形（0 ~ 2^32-1）
2. 节点和数据都映射到环上
3. 数据存储在顺时针方向第一个遇到的节点

优势：
- 增减节点只影响相邻节点
- 平均只需迁移 K/N 的数据（K=数据量，N=节点数）
```

#### 一致性哈希实现
```java
/**
 * 一致性哈希实现
 */
public class ConsistentHash<T> {
    // 哈希环，使用 TreeMap 实现有序映射
    private final TreeMap<Long, T> ring = new TreeMap<>();
    // 每个物理节点的虚拟节点数
    private final int virtualNodes;
    // 哈希函数
    private final HashFunction hashFunction;

    public ConsistentHash(int virtualNodes) {
        this.virtualNodes = virtualNodes;
        this.hashFunction = Hashing.murmur3_128();
    }

    /**
     * 添加节点
     */
    public void addNode(T node) {
        for (int i = 0; i < virtualNodes; i++) {
            // 为每个虚拟节点计算哈希值
            long hash = hash(node.toString() + "#" + i);
            ring.put(hash, node);
        }
    }

    /**
     * 移除节点
     */
    public void removeNode(T node) {
        for (int i = 0; i < virtualNodes; i++) {
            long hash = hash(node.toString() + "#" + i);
            ring.remove(hash);
        }
    }

    /**
     * 获取 key 对应的节点
     */
    public T getNode(String key) {
        if (ring.isEmpty()) {
            return null;
        }

        long hash = hash(key);
        // 找到第一个大于等于 hash 的节点
        Map.Entry<Long, T> entry = ring.ceilingEntry(hash);
        if (entry == null) {
            // 环形：回到第一个节点
            entry = ring.firstEntry();
        }
        return entry.getValue();
    }

    /**
     * 获取 key 对应的多个副本节点
     */
    public List<T> getNodes(String key, int replicaCount) {
        if (ring.isEmpty()) {
            return Collections.emptyList();
        }

        List<T> nodes = new ArrayList<>();
        Set<T> seen = new HashSet<>();
        long hash = hash(key);

        // 从 key 的位置开始顺时针查找
        SortedMap<Long, T> tailMap = ring.tailMap(hash);
        Iterator<T> iterator = Iterators.concat(
            tailMap.values().iterator(),
            ring.values().iterator()
        );

        while (nodes.size() < replicaCount && iterator.hasNext()) {
            T node = iterator.next();
            // 跳过同一物理节点的虚拟节点
            if (!seen.contains(node)) {
                seen.add(node);
                nodes.add(node);
            }
        }

        return nodes;
    }

    private long hash(String key) {
        return hashFunction.hashString(key, StandardCharsets.UTF_8).asLong();
    }
}
```

#### 虚拟节点
```
为什么需要虚拟节点？

问题：节点少时，数据分布不均匀
      Node1         Node2         Node3
        │             │             │
   ─────┼─────────────┼─────────────┼─────
        ↑             ↑             ↑
      分布不均匀，Node2 负责的范围过大

解决：每个物理节点映射多个虚拟节点
      V1-1  V2-1  V1-2  V3-1  V2-2  V3-2  V1-3  V2-3  V3-3
        │     │     │     │     │     │     │     │     │
   ─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────
        ↑     ↑     ↑     ↑     ↑     ↑     ↑     ↑     ↑
      虚拟节点分散，数据分布更均匀

虚拟节点数量建议：
- 100-200 个虚拟节点可以使数据分布较均匀
- 太多会增加内存开销
```

#### 带权重的一致性哈希
```java
/**
 * 带权重的一致性哈希
 * 权重大的节点分配更多虚拟节点
 */
public class WeightedConsistentHash<T> {
    private final TreeMap<Long, T> ring = new TreeMap<>();
    private final int baseVirtualNodes;

    public void addNode(T node, int weight) {
        // 权重决定虚拟节点数量
        int virtualNodes = baseVirtualNodes * weight;
        for (int i = 0; i < virtualNodes; i++) {
            long hash = hash(node.toString() + "#" + i);
            ring.put(hash, node);
        }
    }
}

// 应用场景：
// - 不同配置的服务器（内存大的权重高）
// - 跨机房部署（本机房权重高）
```

### 1.3 数据副本

#### 副本策略
```
副本放置策略（以 Cassandra 为例）：

1. SimpleStrategy
   - 顺时针放置副本
   - 适用于单数据中心

2. NetworkTopologyStrategy
   - 跨机架、跨数据中心放置
   - 每个数据中心可配置不同副本数

副本数量选择：
- 3 副本：常见配置，容忍 1 节点故障
- 5 副本：高可用要求，容忍 2 节点故障
```

#### 副本一致性
| 模式 | 特点 | 应用 |
|------|------|------|
| 主从复制 | 写主节点，读从节点 | MySQL, Redis |
| 多主复制 | 多个节点可写 | Cassandra |
| 无主复制 | Quorum 机制 | DynamoDB |

### 1.4 Quorum 机制 ⭐⭐⭐⭐

```
Quorum 参数：
- N：副本数
- W：写成功需要的确认数
- R：读需要的副本数

一致性保证：
- 强一致性：W + R > N
- 最终一致性：W + R <= N

常见配置：
N=3, W=2, R=2：强一致性，写入需要 2 节点确认
N=3, W=1, R=1：最终一致性，高可用低延迟
N=3, W=3, R=1：写入强一致，读取快速

示例：N=3, W=2, R=2
写入：
  Client -> Node1, Node2, Node3
  Node1: ACK
  Node2: ACK (W=2 满足，返回成功)
  Node3: 后续同步

读取：
  Client <- Node1, Node2
  比较版本，返回最新值
```

## 2. LSM Tree 深入分析 ⭐⭐⭐⭐⭐

### 2.1 LSM Tree 原理

```
LSM Tree（Log-Structured Merge Tree）

核心思想：
- 牺牲部分读性能换取写性能
- 将随机写转换为顺序写
- 适合写多读少的场景

结构：
┌─────────────────────────────────────────┐
│              内存（MemTable）             │
│         红黑树/跳表，有序存储              │
└─────────────────────────────────────────┘
                    │ Flush
                    ▼
┌─────────────────────────────────────────┐
│         Level 0 (SSTable)               │
│    可能有重叠，直接从内存刷下来            │
└─────────────────────────────────────────┘
                    │ Compaction
                    ▼
┌─────────────────────────────────────────┐
│         Level 1 (SSTable)               │
│    不重叠，有序，大小约为 Level0 的 10 倍  │
└─────────────────────────────────────────┘
                    │ Compaction
                    ▼
┌─────────────────────────────────────────┐
│         Level 2 (SSTable)               │
│    不重叠，有序，大小约为 Level1 的 10 倍  │
└─────────────────────────────────────────┘
                    │
                    ▼
                  ......
```

### 2.2 写入流程

```java
/**
 * LSM Tree 写入流程
 */
public class LSMTree {
    private MemTable memTable;
    private MemTable immutableMemTable;  // 正在刷盘的 MemTable
    private WriteAheadLog wal;
    private List<Level> levels;
    private static final int MEMTABLE_SIZE_THRESHOLD = 64 * 1024 * 1024; // 64MB

    public void put(String key, String value) {
        // 1. 先写 WAL（预写日志）
        wal.append(key, value);

        // 2. 写入内存表
        memTable.put(key, value);

        // 3. 检查是否需要刷盘
        if (memTable.size() >= MEMTABLE_SIZE_THRESHOLD) {
            // 将当前 MemTable 转为不可变
            immutableMemTable = memTable;
            memTable = new MemTable();

            // 异步刷盘
            flushMemTable(immutableMemTable);
        }
    }

    private void flushMemTable(MemTable table) {
        // 将 MemTable 写入 Level 0 的 SSTable
        SSTable sst = table.toSSTable();
        levels.get(0).add(sst);

        // 清理 WAL
        wal.truncate();

        // 触发 Compaction
        maybeCompact();
    }
}
```

### 2.3 读取流程

```java
/**
 * LSM Tree 读取流程
 */
public String get(String key) {
    // 1. 先查 MemTable（最新数据）
    String value = memTable.get(key);
    if (value != null) {
        return value.equals(TOMBSTONE) ? null : value;
    }

    // 2. 查不可变 MemTable
    if (immutableMemTable != null) {
        value = immutableMemTable.get(key);
        if (value != null) {
            return value.equals(TOMBSTONE) ? null : value;
        }
    }

    // 3. 从 Level 0 到 Level N 依次查找
    for (Level level : levels) {
        // Level 0 需要查所有 SSTable（可能重叠）
        // Level 1+ 使用二分查找定位 SSTable
        value = level.get(key);
        if (value != null) {
            return value.equals(TOMBSTONE) ? null : value;
        }
    }

    return null;
}
```

### 2.4 Compaction 策略

```
Compaction 的作用：
1. 合并多个 SSTable，减少文件数量
2. 删除过期数据和墓碑标记
3. 将数据下推到更低层级

策略对比：

┌─────────────────────────────────────────────────────────────┐
│ Size-Tiered Compaction (STCS)                               │
├─────────────────────────────────────────────────────────────┤
│ 原理：相似大小的 SSTable 合并                                │
│ 优点：写放大小                                               │
│ 缺点：空间放大大（同一 key 可能存在多个 SSTable）             │
│ 适用：写密集型                                               │
│ 应用：Cassandra 默认                                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Leveled Compaction (LCS)                                    │
├─────────────────────────────────────────────────────────────┤
│ 原理：按层级合并，每层 SSTable 不重叠                         │
│ 优点：空间放大小，读性能好                                   │
│ 缺点：写放大大                                               │
│ 适用：读密集型                                               │
│ 应用：LevelDB, RocksDB 默认                                 │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ FIFO Compaction                                             │
├─────────────────────────────────────────────────────────────┤
│ 原理：按时间删除最老的 SSTable                               │
│ 优点：写放大极小                                             │
│ 缺点：不适合更新操作                                         │
│ 适用：时序数据                                               │
└─────────────────────────────────────────────────────────────┘
```

### 2.5 LSM Tree 优化

```
1. Bloom Filter
   - 快速判断 key 是否可能存在
   - 避免无效的磁盘读取
   - 假阳性率通常设置 1%

2. Block Cache
   - 缓存热点数据块
   - LRU 或 ARC 替换策略

3. 压缩
   - SSTable 支持压缩（Snappy, LZ4, ZSTD）
   - 减少磁盘占用和 IO

4. 索引
   - 稀疏索引：每 N 条记录一个索引
   - Block 索引：定位数据块
```

## 3. Cassandra 详解 ⭐⭐⭐⭐

### 3.1 架构特点
- 完全去中心化，无单点故障
- P2P 架构，节点对等
- AP 系统：最终一致性

### 3.2 数据模型

```
Cassandra 数据模型：

Keyspace（类似数据库）
└── Table（类似表）
    └── Partition（分区，基本存储单元）
        └── Row（行）
            └── Column（列）

主键设计：
PRIMARY KEY ((partition_key), clustering_column1, clustering_column2)

- partition_key：决定数据存储在哪个节点
- clustering_column：决定分区内数据的排序

示例：
CREATE TABLE user_activities (
    user_id UUID,
    activity_time TIMESTAMP,
    activity_type TEXT,
    details TEXT,
    PRIMARY KEY ((user_id), activity_time)
) WITH CLUSTERING ORDER BY (activity_time DESC);

-- user_id 是分区键：同一用户的数据在同一分区
-- activity_time 是聚集列：按时间倒序排列
```

### 3.3 写入路径详解

```
Cassandra 写入流程：

Client
   │
   ▼
Coordinator Node（任意节点）
   │
   ├──────────────────────────────────────┐
   │                                      │
   ▼                                      ▼
Replica Node 1                      Replica Node 2
   │                                      │
   ▼                                      ▼
┌─────────────────┐              ┌─────────────────┐
│  Commit Log     │              │  Commit Log     │
│  (顺序写磁盘)    │              │  (顺序写磁盘)    │
└─────────────────┘              └─────────────────┘
   │                                      │
   ▼                                      ▼
┌─────────────────┐              ┌─────────────────┐
│   MemTable      │              │   MemTable      │
│  (内存写入)      │              │  (内存写入)      │
└─────────────────┘              └─────────────────┘
   │                                      │
   ▼ (异步刷盘)                           ▼
┌─────────────────┐              ┌─────────────────┐
│    SSTable      │              │    SSTable      │
│   (磁盘文件)     │              │   (磁盘文件)     │
└─────────────────┘              └─────────────────┘

写入特点：
1. 无需读取旧数据（append-only）
2. Commit Log 保证持久性
3. MemTable 提供高速写入
4. 最终一致性：W 个副本确认即返回
```

### 3.4 读取路径详解

```
Cassandra 读取流程：

                    Client
                       │
                       ▼
            Coordinator Node
                       │
      ┌────────────────┼────────────────┐
      ▼                ▼                ▼
  Replica 1        Replica 2        Replica 3
      │                │                │
      ▼                ▼                ▼
┌──────────────────────────────────────────────┐
│ 1. 检查 Row Cache（行缓存）                   │
│    命中 → 直接返回                            │
└──────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────┐
│ 2. 检查 MemTable                             │
│    可能找到最新写入的数据                     │
└──────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────┐
│ 3. 检查 Bloom Filter                         │
│    快速排除不包含该 key 的 SSTable           │
└──────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────┐
│ 4. 检查 Partition Key Cache                  │
│    缓存分区索引位置                           │
└──────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────┐
│ 5. 读取 SSTable                              │
│    - Partition Summary → Partition Index     │
│    - Compression Offset → 数据位置           │
│    - 读取数据块                               │
└──────────────────────────────────────────────┘
      │
      ▼
┌──────────────────────────────────────────────┐
│ 6. 合并结果                                   │
│    - 合并 MemTable 和多个 SSTable            │
│    - 按时间戳选择最新版本                     │
└──────────────────────────────────────────────┘
      │
      ▼
  Coordinator 汇总结果
      │
      ▼
  返回给 Client
```

### 3.5 核心机制

```
1. Gossip 协议
   - 节点间状态交换
   - 每秒随机选择节点通信
   - 传播节点状态（UP/DOWN）

2. Hinted Handoff
   - 目标节点不可用时，暂存数据
   - 节点恢复后发送
   - 解决临时故障

3. Read Repair
   - 读取时检测不一致
   - 自动修复过期副本
   - 分为同步和异步模式

4. Anti-Entropy Repair
   - Merkle Tree 比较数据
   - 定期运行 nodetool repair
   - 修复长时间不一致
```

## 4. HBase 详解 ⭐⭐⭐⭐

### 4.1 架构设计

```
HBase 架构：

┌─────────────────────────────────────────────────────────┐
│                        Client                           │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                      ZooKeeper                          │
│     - HMaster 选举                                       │
│     - RegionServer 注册                                  │
│     - META 表位置                                        │
└─────────────────────────────────────────────────────────┘
           │                              │
           ▼                              ▼
┌─────────────────────┐      ┌─────────────────────────────┐
│      HMaster        │      │      RegionServer           │
│  - Region 分配       │      │  - 管理多个 Region          │
│  - 负载均衡          │      │  - 处理读写请求             │
│  - Schema 管理       │      │  - MemStore + HFile        │
│  - 故障恢复          │      │  - Compaction              │
└─────────────────────┘      └─────────────────────────────┘
                                          │
                                          ▼
                             ┌─────────────────────────────┐
                             │          HDFS               │
                             │   - HFile 存储              │
                             │   - WAL 存储                │
                             └─────────────────────────────┘
```

### 4.2 Region 管理

```
Region 概念：
- 表的水平分片
- 包含连续的 Row Key 范围
- 由单个 RegionServer 管理

Region 分裂（Split）：
┌─────────────────────────────────────┐
│         Region (A-Z)                │
│      大小达到阈值（默认10GB）         │
└─────────────────────────────────────┘
                 │ Split
                 ▼
┌─────────────────┐  ┌─────────────────┐
│  Region (A-M)   │  │  Region (N-Z)   │
└─────────────────┘  └─────────────────┘

分裂策略：
1. ConstantSizeRegionSplitPolicy
   - 固定大小阈值
   - 简单但可能导致热点

2. IncreasingToUpperBoundRegionSplitPolicy（默认）
   - 动态阈值：min(maxRegionFileSize, 初始大小 * region数量^3)
   - 早期分裂更积极

3. SteppingSplitPolicy
   - 大表固定阈值
   - 小表快速分裂
```

### 4.3 Region 负载均衡

```java
/**
 * HBase 负载均衡策略
 */
public class LoadBalancer {

    /**
     * 计算每个 RegionServer 应该有多少 Region
     */
    public int getTargetRegionCount(int totalRegions, int serverCount) {
        return (int) Math.ceil((double) totalRegions / serverCount);
    }

    /**
     * 简单负载均衡：Region 数量均衡
     */
    public List<RegionMove> balanceByRegionCount(
            Map<String, List<Region>> serverRegions) {

        List<RegionMove> moves = new ArrayList<>();
        int totalRegions = serverRegions.values().stream()
                .mapToInt(List::size).sum();
        int avgRegions = totalRegions / serverRegions.size();

        // 找出过载和空闲的 RegionServer
        List<String> overloaded = new ArrayList<>();
        List<String> underloaded = new ArrayList<>();

        for (Map.Entry<String, List<Region>> entry : serverRegions.entrySet()) {
            int count = entry.getValue().size();
            if (count > avgRegions + 1) {
                overloaded.add(entry.getKey());
            } else if (count < avgRegions) {
                underloaded.add(entry.getKey());
            }
        }

        // 从过载节点迁移 Region 到空闲节点
        for (String from : overloaded) {
            List<Region> regions = serverRegions.get(from);
            while (regions.size() > avgRegions && !underloaded.isEmpty()) {
                String to = underloaded.get(0);
                Region region = regions.remove(regions.size() - 1);
                moves.add(new RegionMove(region, from, to));

                if (serverRegions.get(to).size() >= avgRegions) {
                    underloaded.remove(0);
                }
            }
        }

        return moves;
    }
}
```

### 4.4 热点问题与 Row Key 设计

```
热点问题：
- 连续的 Row Key 导致请求集中在少数 Region
- 写入/读取都可能产生热点

解决方案：

1. 加盐（Salting）
   原始：user_001, user_002, user_003
   加盐：0_user_001, 1_user_002, 2_user_003
   优点：数据分散
   缺点：范围扫描需要合并多个分区

2. 哈希前缀
   原始：2024-01-01_user_001
   哈希：hash(user_001)_2024-01-01_user_001
   优点：同一用户的数据分散
   缺点：无法按用户范围查询

3. 反转
   原始：www.example.com
   反转：com.example.www
   适用：URL、域名等天然热点数据

4. 预分区
   建表时预先创建多个 Region
   避免初期所有写入集中在一个 Region

CREATE 'user_table', 'cf',
  {SPLITS => ['10', '20', '30', '40', '50', '60', '70', '80', '90']}
```

## 5. Dynamo 设计原理 ⭐⭐⭐⭐

### 5.1 Dynamo 概述

```
Amazon Dynamo（2007）：
- 高可用 Key-Value 存储
- 启发了 Cassandra、Riak、Voldemort
- 核心目标：永远可写（Always Writable）

设计原则：
1. 增量可扩展性
2. 对称性（节点对等）
3. 去中心化
4. 异构性（支持不同配置的节点）
```

### 5.2 核心技术

```
Dynamo 使用的技术：

┌────────────────────┬───────────────────────────────────┐
│ 问题               │ 解决方案                           │
├────────────────────┼───────────────────────────────────┤
│ 数据分区           │ 一致性哈希 + 虚拟节点               │
├────────────────────┼───────────────────────────────────┤
│ 高可用写入         │ Vector Clock + 读时修复            │
├────────────────────┼───────────────────────────────────┤
│ 临时故障           │ Sloppy Quorum + Hinted Handoff    │
├────────────────────┼───────────────────────────────────┤
│ 永久故障恢复       │ Merkle Tree 反熵                   │
├────────────────────┼───────────────────────────────────┤
│ 成员检测           │ Gossip 协议                        │
└────────────────────┴───────────────────────────────────┘
```

### 5.3 版本控制与冲突解决

```
Vector Clock（向量时钟）：

场景：多个节点可能同时写入同一 key

写入流程：
T1: Client1 写入 key1=v1 到 Node1
    版本：[(Node1, 1)]

T2: Client2 写入 key1=v2 到 Node2（未同步 T1）
    版本：[(Node2, 1)]

T3: 读取时发现两个版本
    [(Node1, 1)] 和 [(Node2, 1)]
    这是冲突！无法判断哪个更新

冲突解决：
1. 客户端解决（Dynamo 方式）
   - 返回所有冲突版本给客户端
   - 客户端合并后写回

2. LWW（Last Write Wins）
   - 使用时间戳选择最新
   - 可能丢失数据

3. CRDT（Conflict-free Replicated Data Type）
   - 设计可自动合并的数据类型
   - 如：计数器、集合、LWW-Register
```

### 5.4 Sloppy Quorum

```
传统 Quorum：
- 必须从 N 个固定副本中获得 W/R 个响应
- 如果副本不可用，操作失败

Sloppy Quorum：
- 优先使用 N 个首选节点
- 首选节点不可用时，使用后续节点
- 保证操作成功，但可能写到非首选节点

示例：
Preference List: [A, B, C, D, E]
N=3, 正常副本：A, B, C

场景：A 宕机
- 传统 Quorum：等待 A 恢复或失败
- Sloppy Quorum：使用 B, C, D
  - D 存储数据并标记 "hinted for A"
  - A 恢复后，D 将数据发送给 A（Hinted Handoff）
```

## 6. 面试要点总结

### 6.1 分布式存储核心
| 知识点 | 重要程度 | 考察频率 |
|--------|----------|----------|
| 一致性哈希 | ⭐⭐⭐⭐⭐ | 非常高 |
| LSM Tree | ⭐⭐⭐⭐⭐ | 高 |
| Quorum 机制 | ⭐⭐⭐⭐ | 高 |
| 数据分片 | ⭐⭐⭐⭐ | 高 |
| 副本策略 | ⭐⭐⭐⭐ | 中 |

### 6.2 关键记忆点
```
一致性哈希：
- 虚拟节点解决数据倾斜
- 只迁移 1/N 的数据
- 带权重支持异构节点

LSM Tree：
- 写入：WAL → MemTable → SSTable
- 读取：MemTable → Level0 → Level1 → ...
- Compaction：合并、删除、下推

Quorum：
- W + R > N：强一致性
- 读写权衡：高 W 保证写入一致，高 R 保证读取一致
```

## 7. 常见面试题

### 7.1 一致性哈希

**Q1：一致性哈希如何解决数据倾斜？**
```
答：使用虚拟节点。

1. 每个物理节点映射多个虚拟节点到哈希环
2. 虚拟节点分散分布，使数据更均匀
3. 通常使用 100-200 个虚拟节点
4. 支持带权重的虚拟节点分配
```

**Q2：一致性哈希节点下线时如何处理？**
```
答：
1. 移除该节点的所有虚拟节点
2. 原本存储在该节点的数据自动归属于
   顺时针方向的下一个节点
3. 只影响相邻的一个节点
4. 副本机制保证数据不丢失
```

### 7.2 LSM Tree

**Q3：LSM Tree 为什么写性能好？**
```
答：
1. 写入只需追加到内存（MemTable）
2. WAL 是顺序写磁盘（比随机写快 100 倍）
3. MemTable 满了才刷盘
4. 刷盘也是顺序写（生成新 SSTable）
5. 不需要读取-修改-写入循环
```

**Q4：LSM Tree 读取为什么可能慢？**
```
答：
1. 可能需要查找多个 SSTable
2. Level 0 的 SSTable 可能重叠
3. 需要合并多个版本
4. 空间放大导致更多磁盘读取

优化方案：
1. Bloom Filter：快速判断 key 不存在
2. Block Cache：缓存热点数据
3. Compaction：减少 SSTable 数量
4. 索引优化：稀疏索引定位数据块
```

**Q5：比较 B+ Tree 和 LSM Tree？**
```
答：
B+ Tree：
- 写入：随机 IO，需要更新原地
- 读取：O(log N)，一次定位
- 空间放大：小（数据只存一份）
- 写放大：小（只更新变化的页）
- 适用：读多写少，如 MySQL

LSM Tree：
- 写入：顺序 IO，追加写入
- 读取：可能需要查多个文件
- 空间放大：大（同一 key 可能存多份）
- 写放大：大（Compaction 重复写）
- 适用：写多读少，如 日志、时序数据
```

### 7.3 存储系统

**Q6：Cassandra 和 HBase 的区别？**
```
答：
Cassandra：
- AP 系统，最终一致性
- P2P 架构，无中心节点
- 适合跨数据中心部署
- CQL 查询语言

HBase：
- CP 系统，强一致性
- Master-Slave 架构
- 依赖 HDFS 和 ZooKeeper
- 适合大数据生态集成

选择建议：
- 需要强一致性 → HBase
- 需要高可用、跨机房 → Cassandra
- Hadoop 生态 → HBase
- 简单运维 → Cassandra
```

**Q7：如何设计一个支持高并发写入的 KV 存储？**
```
答：
1. 数据分片
   - 一致性哈希分散数据
   - 虚拟节点均衡负载

2. 写入优化
   - WAL 保证持久性
   - 内存缓冲批量写入
   - LSM Tree 顺序写磁盘

3. 副本机制
   - 多副本高可用
   - Quorum 读写平衡一致性和性能

4. 热点处理
   - 加盐/哈希分散热点 key
   - 本地缓存吸收读热点

5. 故障处理
   - Gossip 检测故障
   - Hinted Handoff 临时存储
   - 反熵修复数据
```
