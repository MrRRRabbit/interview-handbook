# Kafka 高可用与可靠性

> 消息系统的可靠性是核心指标。本文深入讲解 Kafka 的副本机制、ISR、消息可靠性保证等关键特性。

## 副本机制

### 副本架构

```
Topic: orders, Partition: 0, Replication Factor: 3

┌─────────────────────────────────────────────────────┐
│                                                     │
│   Broker 0         Broker 1         Broker 2       │
│  ┌─────────┐      ┌─────────┐      ┌─────────┐    │
│  │ Leader  │      │Follower │      │Follower │    │
│  │         │─────▶│         │      │         │    │
│  │  P0     │      │  P0     │◀─────│  P0     │    │
│  └────▲────┘      └─────────┘      └─────────┘    │
│       │                                            │
│       │ 所有读写请求                               │
│       │                                            │
└───────┼────────────────────────────────────────────┘
        │
   Producer / Consumer
```

### Leader 与 Follower

```
职责划分：

Leader:
- 处理所有读写请求
- 维护 ISR 列表
- 向 Follower 发送数据

Follower:
- 从 Leader 拉取数据（Fetch 请求）
- 不处理客户端请求
- 作为 Leader 的热备份
```

### 副本同步流程

```
Producer 发送消息的同步流程：

┌──────────┐                              ┌──────────┐
│ Producer │                              │  Leader  │
└────┬─────┘                              └────┬─────┘
     │                                         │
     │  1. 发送消息                            │
     │────────────────────────────────────────▶│
     │                                         │
     │                                         │ 2. 写入本地 Log
     │                                         │
     │         ┌──────────┐    ┌──────────┐  │
     │         │Follower 1│    │Follower 2│  │
     │         └────┬─────┘    └────┬─────┘  │
     │              │               │         │
     │              │ 3. Fetch      │ 3. Fetch│
     │              │◀──────────────┼─────────│
     │              │               │         │
     │              │ 4. 写入本地   │ 4. 写入 │
     │              │               │         │
     │                                         │
     │  5. ACK（根据 acks 配置）               │
     │◀────────────────────────────────────────│
     │                                         │
```

## ISR 机制

### ISR 概念

ISR（In-Sync Replicas）是与 Leader 保持同步的副本集合：

```
ISR = { Leader, Follower1, Follower2, ... }

同步条件：
1. 副本与 Leader 的滞后时间 < replica.lag.time.max.ms
2. 副本正常连接到 ZooKeeper/Controller

ISR 变化：
- Follower 落后过多 → 移出 ISR
- Follower 追上 Leader → 加入 ISR
```

### HW 与 LEO

```
HW (High Watermark) 和 LEO (Log End Offset)：

Partition 0
┌─────────────────────────────────────────────────────┐
│                                                     │
│  Leader:                                           │
│  Offset: 0   1   2   3   4   5   6   7   8        │
│        ┌───┬───┬───┬───┬───┬───┬───┬───┬───┐     │
│        │ A │ B │ C │ D │ E │ F │ G │ H │   │     │
│        └───┴───┴───┴───┴───┴───┴───┴───┴───┘     │
│                            ▲           ▲          │
│                            │           │          │
│                           HW          LEO         │
│                                                     │
│  Follower 1:                                       │
│  Offset: 0   1   2   3   4   5   6                │
│        ┌───┬───┬───┬───┬───┬───┬───┐             │
│        │ A │ B │ C │ D │ E │ F │   │             │
│        └───┴───┴───┴───┴───┴───┴───┘             │
│                            ▲       ▲              │
│                            │       │              │
│                           HW      LEO             │
│                                                     │
│  Follower 2:                                       │
│  Offset: 0   1   2   3   4   5   6   7           │
│        ┌───┬───┬───┬───┬───┬───┬───┬───┐        │
│        │ A │ B │ C │ D │ E │ F │ G │   │        │
│        └───┴───┴───┴───┴───┴───┴───┴───┘        │
│                            ▲           ▲         │
│                            │           │         │
│                           HW          LEO        │
│                                                     │
└─────────────────────────────────────────────────────┘

LEO：日志末端偏移，下一条消息要写入的位置
HW：高水位，Consumer 可见的最大 Offset
HW = min(所有 ISR 副本的 LEO)
```

### ISR 相关配置

```properties
# 副本最大延迟时间（默认 30s）
# 超过此时间未同步，移出 ISR
replica.lag.time.max.ms=30000

# 最小 ISR 数量
# acks=all 时，ISR 数量 < 此值，拒绝写入
min.insync.replicas=2

# 不干净的 Leader 选举
# true：允许非 ISR 副本成为 Leader（可能丢数据）
# false：等待 ISR 副本恢复（可能不可用）
unclean.leader.election.enable=false
```

## Leader 选举

### 选举触发条件

```
1. Controller 选举
   - Broker 启动时
   - Controller 所在 Broker 宕机

2. Partition Leader 选举
   - Leader 所在 Broker 宕机
   - 手动触发 Preferred Leader 选举
```

### Controller 选举

```
Controller 是集群的管理者：

职责：
1. 管理分区和副本状态
2. 执行分区 Leader 选举
3. 监控 Broker 上下线
4. 处理 Topic 创建/删除

选举过程：
1. 所有 Broker 尝试在 ZK 创建 /controller 临时节点
2. 第一个创建成功的成为 Controller
3. 其他 Broker 监听该节点
4. Controller 宕机后，重新选举
```

### Partition Leader 选举

```
选举策略：

1. ISR 优先
   - 优先从 ISR 中选择第一个副本
   - 保证数据不丢失

2. 不干净选举（unclean.leader.election.enable=true）
   - ISR 为空时，从非 ISR 副本中选择
   - 可能丢失数据

选举流程：
┌────────────────────────────────────────────────┐
│                 Controller                      │
│                     │                          │
│  Leader 宕机        ▼                          │
│  ┌─────────────────────────────────────┐      │
│  │ 从 ISR 列表中选择第一个存活的副本    │      │
│  │ 作为新 Leader                        │      │
│  └─────────────────────────────────────┘      │
│                     │                          │
│                     ▼                          │
│  ┌─────────────────────────────────────┐      │
│  │ 更新 ZK 中的 Leader 信息             │      │
│  │ 通知所有 Broker                      │      │
│  └─────────────────────────────────────┘      │
│                                                │
└────────────────────────────────────────────────┘
```

## 消息可靠性

### ACK 机制

```java
// acks=0：不等待确认
// Producer 发送后立即返回，可能丢消息
props.put("acks", "0");

// acks=1：等待 Leader 确认
// Leader 写入成功即返回，Leader 宕机可能丢消息
props.put("acks", "1");

// acks=all（或 -1）：等待所有 ISR 确认
// 最可靠，但延迟最高
props.put("acks", "all");
```

### 三端可靠性保证

```
完整的消息可靠性需要 Producer、Broker、Consumer 三端配合：

┌─────────────────────────────────────────────────────────┐
│                     Producer 端                          │
│                                                         │
│  acks=all                    # 等待所有 ISR 确认         │
│  retries=3                   # 失败重试                  │
│  enable.idempotence=true     # 幂等性                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                     Broker 端                            │
│                                                         │
│  replication.factor=3        # 3 副本                    │
│  min.insync.replicas=2       # 最少 2 个 ISR             │
│  unclean.leader.election=false # 禁止不干净选举         │
│                                                         │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                     Consumer 端                          │
│                                                         │
│  enable.auto.commit=false    # 手动提交 Offset          │
│  处理完消息后再提交           # 避免消息丢失             │
│  业务幂等设计                 # 处理重复消费             │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 消息丢失场景分析

```
场景 1：acks=0
┌──────────┐    发送    ┌──────────┐
│ Producer │───────────▶│  Broker  │ ✗ Broker 未收到
└──────────┘            └──────────┘
             消息丢失

场景 2：acks=1，Leader 宕机
┌──────────┐    发送    ┌──────────┐    同步中    ┌──────────┐
│ Producer │───────────▶│  Leader  │─────────────▶│ Follower │
└──────────┘            └──────────┘              └──────────┘
                             ✗ Leader 宕机
                             Follower 未同步完成
                             消息丢失

场景 3：Consumer 自动提交
┌──────────┐    消费    ┌──────────┐    自动提交   ┌──────────┐
│ Consumer │◀───────────│  Broker  │◀─────────────│  Offset  │
└──────────┘            └──────────┘              └──────────┘
       ✗ 处理失败
       但 Offset 已提交
       消息丢失（对业务而言）
```

## 消息顺序性

### 单分区顺序

```
Kafka 只保证单分区内消息有序：

Partition 0:
┌───┬───┬───┬───┬───┐
│ 1 │ 2 │ 3 │ 4 │ 5 │  ✓ 有序
└───┴───┴───┴───┴───┘

跨分区无序：
Partition 0: │ 1 │ 3 │ 5 │
Partition 1: │ 2 │ 4 │ 6 │

Consumer 可能消费顺序: 1, 2, 3, 4, 5, 6
                    或: 2, 1, 4, 3, 6, 5  ✗ 无序
```

### 保证顺序的方法

```java
// 方法 1：使用相同 Key
// 相同 Key 的消息发送到同一分区
producer.send(new ProducerRecord<>("orders", orderId, orderData));

// 方法 2：单分区 Topic
// 所有消息在同一分区，但牺牲并行性

// 方法 3：限制在途请求数
props.put("max.in.flight.requests.per.connection", 1);
// 配合幂等性可以设为 5
```

## 高可用部署

### 推荐配置

```properties
# Broker 配置
# 副本数（推荐 3）
default.replication.factor=3

# 最小 ISR（推荐 2）
min.insync.replicas=2

# 禁止不干净选举
unclean.leader.election.enable=false

# Producer 配置
acks=all
retries=3
enable.idempotence=true

# Consumer 配置
enable.auto.commit=false
```

### 集群部署建议

```
1. 节点数量
   - 最少 3 个 Broker
   - 推荐跨机架/可用区部署

2. 副本配置
   - replication.factor >= 3
   - min.insync.replicas >= 2

3. 磁盘配置
   - 使用多块磁盘
   - JBOD 或 RAID10

4. 网络配置
   - 高带宽网络
   - 单独的复制网络
```

## 面试高频问题

### 1. Kafka 如何保证消息不丢失？

```
Producer 端：
1. acks=all：等待所有 ISR 副本确认
2. retries > 0：失败重试
3. enable.idempotence=true：幂等性

Broker 端：
1. replication.factor >= 3：多副本
2. min.insync.replicas >= 2：最小 ISR
3. unclean.leader.election.enable=false：禁止不干净选举

Consumer 端：
1. enable.auto.commit=false：手动提交
2. 处理完成后再提交 Offset
3. 业务幂等设计
```

### 2. ISR 是什么？有什么作用？

```
ISR（In-Sync Replicas）是与 Leader 保持同步的副本集合。

作用：
1. 保证数据一致性
2. acks=all 时，只需 ISR 副本确认
3. Leader 选举时，优先从 ISR 选择

维护规则：
1. 副本滞后超过 replica.lag.time.max.ms 移出
2. 副本追上 Leader 后加入
3. min.insync.replicas 控制最小 ISR 数量
```

### 3. HW 和 LEO 的区别？

```
LEO（Log End Offset）：
- 日志末端偏移
- 下一条消息要写入的位置
- 每个副本各自维护

HW（High Watermark）：
- 高水位，所有 ISR 副本都已同步的位置
- Consumer 可见的最大 Offset
- HW = min(所有 ISR 副本的 LEO)

关系：
- HW <= LEO
- HW 之前的消息对 Consumer 可见
- HW 到 LEO 之间的消息还在同步中
```

### 4. acks=all 一定不丢消息吗？

```
不一定，还需要其他配置配合：

可能丢消息的情况：
1. min.insync.replicas=1
   - ISR 只有 Leader，acks=all 等同于 acks=1
   - Leader 宕机可能丢数据

2. unclean.leader.election.enable=true
   - 允许非 ISR 副本成为 Leader
   - 可能丢失未同步的数据

正确配置：
acks=all
min.insync.replicas=2
unclean.leader.election.enable=false
replication.factor=3
```

### 5. Controller 的作用是什么？

```
Controller 是 Kafka 集群的管理者，职责包括：

1. 分区管理
   - 分区状态变更
   - 副本状态变更

2. Leader 选举
   - Broker 宕机时选举新 Leader
   - Preferred Leader 选举

3. 集群成员管理
   - 监控 Broker 上下线
   - 维护集群元数据

4. Topic 管理
   - Topic 创建/删除
   - 分区扩容

选举方式：
- ZK 模式：抢占 /controller 节点
- KRaft 模式：Raft 协议选举
```

## 总结

```
Kafka 高可用与可靠性要点：
1. 副本机制：Leader 处理读写，Follower 同步数据
2. ISR 机制：维护同步副本集合，保证数据一致性
3. HW/LEO：控制消息可见性，协调副本同步
4. Leader 选举：优先从 ISR 选择，保证数据不丢
5. ACK 机制：acks=all 配合 min.insync.replicas
6. 三端配合：Producer + Broker + Consumer 共同保证
```
