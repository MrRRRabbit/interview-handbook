# Kafka 消费者

> 消费者是 Kafka 消息的出口，理解 Consumer Group、Offset 管理和 Rebalance 机制是掌握 Kafka 的关键。

## Consumer Group

### 什么是 Consumer Group

Consumer Group 是 Kafka 的核心消费模型：

```
                    Topic: orders (3 partitions)
                    ┌───────────────────────────┐
                    │ P0      P1      P2        │
                    └───┬───────┬───────┬───────┘
                        │       │       │
        ┌───────────────┼───────┼───────┼───────────────┐
        │               │       │       │               │
        │  Consumer Group A     │       │               │
        │  ┌─────────┐  │  ┌────┴────┐  │  ┌─────────┐ │
        │  │Consumer │◀─┘  │Consumer │◀─┘  │Consumer │◀┘
        │  │   1     │     │   2     │     │   3     │  │
        │  └─────────┘     └─────────┘     └─────────┘  │
        │                                               │
        └───────────────────────────────────────────────┘

        ┌───────────────────────────────────────────────┐
        │  Consumer Group B                             │
        │  ┌─────────────────────────────────────────┐ │
        │  │         Consumer 1                       │ │
        │  │         (消费所有 3 个分区)              │ │
        │  └─────────────────────────────────────────┘ │
        └───────────────────────────────────────────────┘
```

### Consumer Group 特性

```
1. 同一 Group 内的 Consumer 共同消费 Topic
2. 一个 Partition 只能被 Group 内的一个 Consumer 消费
3. 不同 Group 独立消费，互不影响
4. Consumer 数量 > Partition 数量时，多余 Consumer 空闲
```

### 消费模型对比

| 模型 | 实现方式 | 适用场景 |
|------|----------|----------|
| 队列模式 | 所有 Consumer 同一 Group | 任务分发、负载均衡 |
| 发布订阅 | 每个 Consumer 不同 Group | 广播、多系统消费 |

## 分区分配策略

### Range 策略

```
按 Topic 分配，可能不均匀

Topic1: P0, P1, P2
Topic2: P0, P1, P2
Consumer: C0, C1

分配结果：
C0: Topic1-P0, Topic1-P1, Topic2-P0, Topic2-P1
C1: Topic1-P2, Topic2-P2

问题：订阅多个 Topic 时，C0 总是多分配
```

### RoundRobin 策略

```
轮询分配，较均匀

Topic1: P0, P1, P2
Consumer: C0, C1

分配结果：
C0: Topic1-P0, Topic1-P2
C1: Topic1-P1
```

### Sticky 策略（推荐）

```
特点：
1. 尽量均匀分配
2. Rebalance 时尽量保持原分配
3. 减少分区迁移

适用场景：Consumer 频繁上下线
```

### CooperativeSticky 策略

```
协作式 Sticky，Kafka 2.4+ 支持

特点：
1. 增量式 Rebalance
2. 不停止全部消费
3. 平滑过渡

配置：
partition.assignment.strategy=
  org.apache.kafka.clients.consumer.CooperativeStickyAssignor
```

## Offset 管理

### Offset 概念

```
Partition 0
┌─────────────────────────────────────────────────┐
│ Offset:   0    1    2    3    4    5    6    7  │
│         ┌───┬───┬───┬───┬───┬───┬───┬───┐      │
│  Data:  │ A │ B │ C │ D │ E │ F │ G │ H │      │
│         └───┴───┴───┴───┴───┴───┴───┴───┘      │
│                     ▲           ▲         ▲    │
│                     │           │         │    │
│          Committed Offset  Current    LEO      │
│              (已提交)       (当前)    (最新)   │
└─────────────────────────────────────────────────┘

- Committed Offset：Consumer 重启后从这里继续消费
- Current Offset：Consumer 当前消费到的位置
- LEO (Log End Offset)：Partition 最新消息的位置
```

### 自动提交 vs 手动提交

```java
// 自动提交（默认）
props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, true);
props.put(ConsumerConfig.AUTO_COMMIT_INTERVAL_MS_CONFIG, 5000);

// 手动提交
props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
```

### 手动提交方式

```java
// 1. 同步提交（阻塞，可靠）
consumer.commitSync();

// 2. 异步提交（非阻塞，可能失败）
consumer.commitAsync((offsets, exception) -> {
    if (exception != null) {
        log.error("提交失败", exception);
    }
});

// 3. 指定 Offset 提交
Map<TopicPartition, OffsetAndMetadata> offsets = new HashMap<>();
offsets.put(new TopicPartition("orders", 0),
            new OffsetAndMetadata(lastOffset + 1));
consumer.commitSync(offsets);
```

### 提交策略选择

| 策略 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| 自动提交 | 简单 | 可能丢消息或重复消费 | 容忍少量重复 |
| 同步提交 | 可靠 | 阻塞，性能差 | 强一致性要求 |
| 异步提交 | 非阻塞 | 可能失败 | 高吞吐场景 |
| 批量+异步 | 平衡 | 复杂 | 大多数场景 |

## Rebalance 机制

### 什么是 Rebalance

Rebalance 是 Consumer Group 重新分配 Partition 的过程：

```
触发条件：
1. Consumer 加入 Group
2. Consumer 离开 Group（主动/异常）
3. 订阅的 Topic 变化
4. 订阅的 Topic 分区数变化
```

### Rebalance 流程

```
                    Coordinator
                        │
    ┌───────────────────┼───────────────────┐
    │                   │                   │
    ▼                   ▼                   ▼
Consumer 1         Consumer 2         Consumer 3

Phase 1: JoinGroup
┌─────────┐  JoinGroup Request  ┌───────────┐
│Consumer │────────────────────▶│Coordinator│
│   1     │                     │           │
├─────────┤  JoinGroup Request  │           │
│Consumer │────────────────────▶│           │
│   2     │                     │           │
├─────────┤  JoinGroup Request  │           │
│Consumer │────────────────────▶│           │
│   3     │                     └─────┬─────┘
└─────────┘                           │
                                      │ 选出 Leader
                                      ▼
Phase 2: SyncGroup
┌─────────┐◀──JoinGroup Response──┌───────────┐
│Consumer │   (你是 Leader)       │Coordinator│
│ 1(Leader)│                      │           │
└────┬────┘                       └───────────┘
     │
     │ 计算分区分配方案
     │
     ▼
Phase 3: SyncGroup
┌─────────┐  SyncGroup Request   ┌───────────┐
│Consumer │─────(分配方案)──────▶│Coordinator│
│ 1(Leader)│                     │           │
└─────────┘                      └─────┬─────┘
                                       │
           ┌───────────────────────────┼───────────────────────────┐
           │                           │                           │
           ▼                           ▼                           ▼
    SyncGroup Response          SyncGroup Response          SyncGroup Response
    (P0, P1)                   (P2, P3)                   (P4, P5)
    ┌─────────┐                ┌─────────┐                ┌─────────┐
    │Consumer │                │Consumer │                │Consumer │
    │   1     │                │   2     │                │   3     │
    └─────────┘                └─────────┘                └─────────┘
```

### Rebalance 的影响

```
问题：
1. Stop The World：Rebalance 期间所有 Consumer 停止消费
2. 重复消费：未提交的 Offset 导致重复
3. 性能抖动：大量 Partition 重分配

优化手段：
1. 合理设置 session.timeout.ms 和 heartbeat.interval.ms
2. 增加 max.poll.interval.ms
3. 使用 CooperativeSticky 分配策略
4. 静态成员（Static Membership）
```

### 避免不必要的 Rebalance

```java
// 关键配置
// 心跳超时时间（默认 10s，建议 6s）
session.timeout.ms=6000

// 心跳间隔（建议 session.timeout.ms 的 1/3）
heartbeat.interval.ms=2000

// 最大 poll 间隔（处理慢时增加此值）
max.poll.interval.ms=300000

// 静态成员 ID（Kafka 2.3+）
group.instance.id=consumer-1
```

## 消费语义

### 三种语义

```
1. At Most Once（最多一次）
   - 先提交 Offset，再处理消息
   - 可能丢消息

   poll() → commitOffset() → process()

2. At Least Once（至少一次）
   - 先处理消息，再提交 Offset
   - 可能重复消费

   poll() → process() → commitOffset()

3. Exactly Once（精确一次）
   - 处理和提交原子化
   - 需要外部支持（事务、幂等）

   poll() → process + commitOffset (事务)
```

### Exactly Once 实现

```java
// 方式 1：Consumer + 外部存储事务
// 处理消息和保存 Offset 在同一事务中

@Transactional
public void consumeAndProcess(ConsumerRecords<String, String> records) {
    for (ConsumerRecord<String, String> record : records) {
        // 处理业务
        processMessage(record);
        // 保存 Offset 到数据库
        saveOffset(record.topic(), record.partition(), record.offset());
    }
}

// 方式 2：Kafka 事务（Consume-Transform-Produce）
consumer.subscribe(Collections.singleton("input-topic"));
producer.initTransactions();

while (true) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));

    producer.beginTransaction();
    for (ConsumerRecord<String, String> record : records) {
        // 处理并发送到新 Topic
        producer.send(new ProducerRecord<>("output-topic", transform(record)));
    }
    // 提交 Offset 到事务
    producer.sendOffsetsToTransaction(getOffsets(records), "my-group");
    producer.commitTransaction();
}
```

## 完整代码示例

```java
public class KafkaConsumerExample {

    public static void main(String[] args) {
        Properties props = new Properties();

        // 基础配置
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "order-consumer-group");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,
                  StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
                  StringDeserializer.class.getName());

        // Offset 配置
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");

        // Rebalance 优化
        props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 6000);
        props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 2000);
        props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 500);

        // 分区分配策略
        props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
                  CooperativeStickyAssignor.class.getName());

        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {

            consumer.subscribe(Collections.singletonList("orders"));

            while (true) {
                ConsumerRecords<String, String> records =
                    consumer.poll(Duration.ofMillis(100));

                for (ConsumerRecord<String, String> record : records) {
                    System.out.printf("partition=%d, offset=%d, key=%s, value=%s%n",
                            record.partition(), record.offset(),
                            record.key(), record.value());

                    // 处理业务逻辑
                    processOrder(record.value());
                }

                // 手动提交 Offset
                if (!records.isEmpty()) {
                    consumer.commitAsync((offsets, exception) -> {
                        if (exception != null) {
                            System.err.println("提交失败: " + exception.getMessage());
                        }
                    });
                }
            }
        }
    }

    private static void processOrder(String orderJson) {
        // 处理订单逻辑
    }
}
```

## 面试高频问题

### 1. Consumer Group 如何实现负载均衡？

```
1. 同一 Group 内的 Consumer 共同消费 Topic
2. 一个 Partition 只能被一个 Consumer 消费
3. 通过 Rebalance 动态调整分配
4. Consumer 数 <= Partition 数时，负载均衡
5. Consumer 数 > Partition 数时，有 Consumer 空闲
```

### 2. Rebalance 过程中会发生什么？

```
1. 所有 Consumer 停止消费（STW）
2. Consumer 重新加入 Group
3. 重新分配 Partition
4. 未提交的 Offset 可能导致重复消费

影响：
- 消费延迟增加
- 可能重复消费
- 短暂不可用
```

### 3. 如何避免重复消费？

```
1. 业务幂等：
   - 数据库唯一约束
   - Redis 去重
   - 版本号机制

2. Offset 管理：
   - 减少自动提交间隔
   - 处理完立即手动提交
   - 事务提交

3. Exactly Once：
   - 开启 Kafka 事务
   - 业务层幂等设计
```

### 4. auto.offset.reset 的作用？

```
当 Consumer 没有初始 Offset 或 Offset 无效时：

earliest：从最早的消息开始消费
latest：从最新的消息开始消费（默认）
none：抛出异常

使用场景：
- earliest：不想丢失消息
- latest：只关心新消息
```

### 5. max.poll.records 和 max.poll.interval.ms 的关系？

```
max.poll.records：单次 poll 最大返回记录数
max.poll.interval.ms：两次 poll 的最大间隔

配置建议：
- 处理慢：增大 max.poll.interval.ms
- 减少 Rebalance：减小 max.poll.records
- 公式：max.poll.interval.ms > max.poll.records * 单条处理时间
```

## 总结

```
Consumer 核心要点：
1. Consumer Group：实现负载均衡和发布订阅
2. 分区分配策略：Range、RoundRobin、Sticky、CooperativeSticky
3. Offset 管理：自动提交 vs 手动提交
4. Rebalance：触发条件、流程、优化
5. 消费语义：At Most Once、At Least Once、Exactly Once
```
