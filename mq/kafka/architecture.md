# Kafka 架构与核心概念

> 理解 Kafka 的架构设计是掌握 Kafka 的第一步，本文介绍 Kafka 的核心组件和设计思想。

## Kafka 简介

### 什么是 Kafka？

Kafka 是由 LinkedIn 开发的分布式流处理平台，后捐献给 Apache 基金会。它具有以下特点：

- **高吞吐**：单机可达百万级 TPS
- **低延迟**：毫秒级延迟
- **高可用**：支持多副本、自动故障转移
- **可扩展**：支持水平扩展
- **持久化**：消息持久化到磁盘

### Kafka 的应用场景

```
1. 消息系统：解耦、异步、削峰
2. 日志收集：ELK 架构中的数据管道
3. 流处理：实时数据处理
4. 事件溯源：事件驱动架构
5. 数据同步：CDC、ETL
```

## 核心架构

### 整体架构图

```
                    Kafka Cluster
┌─────────────────────────────────────────────────────┐
│                                                     │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐       │
│   │ Broker  │    │ Broker  │    │ Broker  │       │
│   │   0     │    │   1     │    │   2     │       │
│   │         │    │         │    │         │       │
│   │ ┌─────┐ │    │ ┌─────┐ │    │ ┌─────┐ │       │
│   │ │P0-L │ │    │ │P0-F │ │    │ │P1-L │ │       │
│   │ │P1-F │ │    │ │P2-L │ │    │ │P2-F │ │       │
│   │ └─────┘ │    │ └─────┘ │    │ └─────┘ │       │
│   └────▲────┘    └────▲────┘    └────▲────┘       │
│        │              │              │             │
└────────┼──────────────┼──────────────┼─────────────┘
         │              │              │
    ┌────┴────┐    ┌────┴────┐    ┌────┴────┐
    │Producer │    │Producer │    │Consumer │
    │   A     │    │   B     │    │ Group   │
    └─────────┘    └─────────┘    └─────────┘

P0-L: Partition 0 Leader
P0-F: Partition 0 Follower
```

### 核心组件

| 组件 | 说明 |
|------|------|
| **Broker** | Kafka 服务节点，负责消息存储和转发 |
| **Topic** | 消息的逻辑分类，类似数据库的表 |
| **Partition** | Topic 的物理分片，实现并行处理 |
| **Replica** | 分区的副本，实现高可用 |
| **Producer** | 消息生产者 |
| **Consumer** | 消息消费者 |
| **Consumer Group** | 消费者组，实现负载均衡 |
| **ZooKeeper/KRaft** | 集群元数据管理（新版本使用 KRaft） |

## Broker

### Broker 的职责

```
1. 接收 Producer 发送的消息
2. 将消息持久化到磁盘
3. 响应 Consumer 的拉取请求
4. 参与副本同步
5. 处理集群元数据
```

### Broker 配置示例

```properties
# server.properties
broker.id=0
listeners=PLAINTEXT://localhost:9092
log.dirs=/var/kafka-logs
num.partitions=3
default.replication.factor=3
```

## Topic 与 Partition

### Topic

Topic 是消息的逻辑分类：

```bash
# 创建 Topic
kafka-topics.sh --create \
  --topic orders \
  --partitions 3 \
  --replication-factor 2 \
  --bootstrap-server localhost:9092

# 查看 Topic 详情
kafka-topics.sh --describe \
  --topic orders \
  --bootstrap-server localhost:9092
```

### Partition

Partition 是 Topic 的物理分片：

```
Topic: orders (3 partitions)
┌────────────────────────────────────────────────┐
│                                                │
│  Partition 0    Partition 1    Partition 2    │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    │
│  │ 0 1 2 3 │    │ 0 1 2 3 │    │ 0 1 2   │    │
│  │ 4 5 6 7 │    │ 4 5 6   │    │ 3 4 5   │    │
│  │ 8 9 ...│    │ 7 8 ... │    │ 6 7 ... │    │
│  └─────────┘    └─────────┘    └─────────┘    │
│     │               │               │          │
│     ▼               ▼               ▼          │
│   Offset          Offset          Offset       │
│                                                │
└────────────────────────────────────────────────┘
```

### Partition 的作用

1. **并行处理**：不同 Partition 可以被不同 Consumer 并行消费
2. **负载均衡**：消息分散到多个 Partition
3. **顺序保证**：单个 Partition 内消息有序
4. **扩展性**：通过增加 Partition 提升吞吐

### 分区数选择

```
分区数考虑因素：
1. 期望的吞吐量 / 单分区吞吐量
2. Consumer 并发数（分区数 >= 消费者数）
3. 不宜过多（增加 Broker 负担）

经验值：
- 小规模：3-6 个分区
- 中规模：6-12 个分区
- 大规模：根据吞吐量计算
```

## Replica（副本机制）

### 副本角色

```
Partition 0 (replication-factor=3)
┌────────────────────────────────────────────┐
│                                            │
│   Broker 0        Broker 1       Broker 2  │
│  ┌────────┐     ┌────────┐     ┌────────┐ │
│  │ Leader │ ──▶ │Follower│     │Follower│ │
│  │        │     │        │ ◀── │        │ │
│  └────────┘     └────────┘     └────────┘ │
│      │              ▲              ▲       │
│      │              │              │       │
│      └──────────────┴──────────────┘       │
│            Replica Sync (Fetch)            │
│                                            │
└────────────────────────────────────────────┘

- Leader：处理所有读写请求
- Follower：从 Leader 同步数据，不处理客户端请求
```

### ISR（In-Sync Replicas）

ISR 是与 Leader 保持同步的副本集合：

```
ISR 机制：
1. 初始状态：ISR = {Leader, Follower1, Follower2}
2. Follower2 落后过多：ISR = {Leader, Follower1}
3. Follower2 追上：ISR = {Leader, Follower1, Follower2}

关键参数：
- replica.lag.time.max.ms：副本最大延迟时间（默认 30s）
- min.insync.replicas：最小 ISR 数量
```

## Offset

### 什么是 Offset

Offset 是消息在 Partition 中的唯一标识：

```
Partition 0
┌─────────────────────────────────────────────┐
│ Offset:  0    1    2    3    4    5    6    │
│        ┌───┬───┬───┬───┬───┬───┬───┐       │
│ Data:  │ A │ B │ C │ D │ E │ F │ G │       │
│        └───┴───┴───┴───┴───┴───┴───┘       │
│                          ▲                  │
│                          │                  │
│                   Current Offset            │
│                   (Consumer 已消费到这里)    │
└─────────────────────────────────────────────┘
```

### Offset 管理

```
Consumer 需要管理三个 Offset：
1. Current Offset：当前消费到的位置
2. Committed Offset：已提交的位置（重启后从这里继续）
3. Log End Offset (LEO)：Partition 的最新位置

Offset 存储：
- 旧版本：ZooKeeper
- 新版本：__consumer_offsets Topic
```

## 与传统 MQ 对比

### Kafka vs RabbitMQ

| 特性 | Kafka | RabbitMQ |
|------|-------|----------|
| **协议** | 自定义协议 | AMQP |
| **消息模型** | 发布订阅 | 点对点 + 发布订阅 |
| **消息保留** | 可配置保留时间 | 消费后删除 |
| **吞吐量** | 百万级 TPS | 万级 TPS |
| **延迟** | 毫秒级 | 微秒级 |
| **消息顺序** | 分区内有序 | 队列内有序 |
| **消息回溯** | 支持 | 不支持 |
| **适用场景** | 日志、流处理、大数据 | 业务消息、RPC |

### Kafka vs RocketMQ

| 特性 | Kafka | RocketMQ |
|------|-------|----------|
| **开发语言** | Scala/Java | Java |
| **事务消息** | 支持（较复杂） | 原生支持 |
| **延迟消息** | 不支持 | 原生支持 |
| **消息过滤** | 不支持 | Tag/SQL 过滤 |
| **顺序消息** | 分区有序 | 队列有序 |
| **消息轨迹** | 不支持 | 支持 |

## 面试高频问题

### 1. Kafka 为什么吞吐量高？

```
1. 顺序写磁盘：追加写入，避免随机 I/O
2. 零拷贝：使用 sendfile 系统调用
3. 批量处理：批量发送、批量压缩
4. 分区并行：多 Partition 并行处理
5. Page Cache：利用操作系统缓存
```

### 2. Kafka 如何保证消息有序？

```
1. 单 Partition 内有序
2. 相同 Key 的消息发送到同一 Partition
3. Producer 配置：max.in.flight.requests.per.connection=1
4. Consumer 单线程消费
```

### 3. Partition 数量如何选择？

```
考虑因素：
1. 目标吞吐量 / 单 Partition 吞吐量
2. Consumer 并发数（分区数 >= 消费者数）
3. Broker 磁盘数量
4. 不宜过多（文件句柄、内存、选举耗时）
```

### 4. Kafka 的 ZooKeeper 作用？

```
ZooKeeper 职责（旧版本）：
1. Broker 注册与发现
2. Topic 和 Partition 元数据
3. Controller 选举
4. Consumer Group 管理（旧版本）

KRaft 模式（新版本）：
- 移除 ZooKeeper 依赖
- Controller 自管理元数据
- 简化运维复杂度
```

## 总结

```
Kafka 架构要点：
1. Broker：消息存储和转发的核心节点
2. Topic：消息的逻辑分类
3. Partition：Topic 的物理分片，实现并行和扩展
4. Replica：副本机制，实现高可用
5. ISR：同步副本集合，保证数据一致性
6. Offset：消息在 Partition 中的唯一标识
```
