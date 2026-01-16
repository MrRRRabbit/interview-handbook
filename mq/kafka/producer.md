# Kafka 生产者

> 生产者是 Kafka 消息的入口，理解生产者的工作原理是保证消息可靠投递的基础。

## 生产者架构

### 发送流程

```
┌─────────────────────────────────────────────────────────────┐
│                      Kafka Producer                          │
│                                                              │
│  ┌──────────┐    ┌────────────┐    ┌─────────────────────┐  │
│  │ 业务线程  │───▶│ Serializer │───▶│    Partitioner     │  │
│  │ send()   │    │  序列化器   │    │     分区器          │  │
│  └──────────┘    └────────────┘    └──────────┬──────────┘  │
│                                               │              │
│                                               ▼              │
│                              ┌────────────────────────────┐  │
│                              │      RecordAccumulator     │  │
│                              │   ┌─────┐ ┌─────┐ ┌─────┐ │  │
│                              │   │Batch│ │Batch│ │Batch│ │  │
│                              │   │ P0  │ │ P1  │ │ P2  │ │  │
│                              │   └─────┘ └─────┘ └─────┘ │  │
│                              └───────────────┬────────────┘  │
│                                              │               │
│  ┌────────────┐                              │               │
│  │  Sender    │◀─────────────────────────────┘               │
│  │  Thread    │                                              │
│  └─────┬──────┘                                              │
│        │                                                     │
└────────┼─────────────────────────────────────────────────────┘
         │
         ▼
    Kafka Broker
```

### 核心组件

| 组件 | 作用 |
|------|------|
| **Serializer** | 将消息 Key/Value 序列化为字节数组 |
| **Partitioner** | 决定消息发送到哪个 Partition |
| **RecordAccumulator** | 消息累加器，批量发送 |
| **Sender** | 发送线程，负责网络 I/O |
| **NetworkClient** | 网络客户端，管理连接 |

## 发送方式

### 三种发送方式

```java
// 1. 发送并忘记（Fire and Forget）
producer.send(record);

// 2. 同步发送
RecordMetadata metadata = producer.send(record).get();
System.out.println("Partition: " + metadata.partition());
System.out.println("Offset: " + metadata.offset());

// 3. 异步发送（推荐）
producer.send(record, (metadata, exception) -> {
    if (exception != null) {
        exception.printStackTrace();
    } else {
        System.out.println("发送成功: " + metadata.offset());
    }
});
```

### 发送方式对比

| 方式 | 特点 | 适用场景 |
|------|------|----------|
| 发送并忘记 | 不关心结果，可能丢消息 | 日志等可容忍丢失场景 |
| 同步发送 | 阻塞等待结果，性能差 | 对可靠性要求极高 |
| 异步发送 | 非阻塞，高性能 | 大多数场景 |

## 分区策略

### 默认分区策略

```java
// Kafka 默认分区逻辑
public int partition(String topic, Object key, byte[] keyBytes,
                     Object value, byte[] valueBytes, Cluster cluster) {
    List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
    int numPartitions = partitions.size();

    if (keyBytes == null) {
        // 无 Key：轮询或粘性分区
        return stickyPartitionCache.partition(topic, cluster);
    } else {
        // 有 Key：hash 取模
        return Utils.toPositive(Utils.murmur2(keyBytes)) % numPartitions;
    }
}
```

### 分区策略详解

```
1. 指定 Partition：直接发送到指定分区
   record = new ProducerRecord<>(topic, partition, key, value);

2. 有 Key：hash(key) % partitionCount
   - 相同 Key 总是发送到同一分区
   - 保证同一 Key 消息的顺序性

3. 无 Key：
   - 旧版本：轮询（Round Robin）
   - 新版本：粘性分区（Sticky Partitioner）
     - 批量发送到同一分区，提高批量效率
```

### 自定义分区器

```java
public class OrderPartitioner implements Partitioner {

    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        // 按订单 ID 的 hash 分区
        String orderId = (String) key;
        int numPartitions = cluster.partitionCountForTopic(topic);
        return Math.abs(orderId.hashCode()) % numPartitions;
    }

    @Override
    public void close() {}

    @Override
    public void configure(Map<String, ?> configs) {}
}

// 使用自定义分区器
props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG,
          OrderPartitioner.class.getName());
```

## 批量发送与压缩

### 批量发送

```
RecordAccumulator 工作原理：

┌────────────────────────────────────────────┐
│              RecordAccumulator             │
│                                            │
│  Partition 0    Partition 1    Partition 2 │
│  ┌────────┐     ┌────────┐     ┌────────┐ │
│  │ Batch  │     │ Batch  │     │ Batch  │ │
│  │ msg1   │     │ msg3   │     │ msg5   │ │
│  │ msg2   │     │ msg4   │     │        │ │
│  │ ...    │     │ ...    │     │        │ │
│  └────────┘     └────────┘     └────────┘ │
│       │              │              │      │
│       └──────────────┼──────────────┘      │
│                      │                     │
│                      ▼                     │
│              batch.size 或                 │
│              linger.ms 触发发送            │
│                                            │
└────────────────────────────────────────────┘
```

### 批量参数配置

```properties
# 批量大小（字节），达到此大小立即发送
batch.size=16384

# 等待时间（毫秒），即使未达到 batch.size 也发送
linger.ms=5

# 发送缓冲区总大小
buffer.memory=33554432
```

### 压缩配置

```properties
# 压缩算法：none, gzip, snappy, lz4, zstd
compression.type=lz4
```

压缩算法对比：

| 算法 | 压缩率 | CPU 消耗 | 适用场景 |
|------|--------|----------|----------|
| none | 无 | 无 | CPU 敏感 |
| gzip | 最高 | 高 | 网络带宽受限 |
| snappy | 中等 | 低 | 通用 |
| lz4 | 中等 | 最低 | 推荐 |
| zstd | 高 | 中等 | Kafka 2.1+ |

## 关键配置参数

### 可靠性相关

```properties
# ACK 确认机制
# 0：不等待确认（可能丢消息）
# 1：等待 Leader 确认
# all/-1：等待所有 ISR 确认（最可靠）
acks=all

# 重试次数
retries=3

# 重试间隔
retry.backoff.ms=100

# 幂等性（防止重复）
enable.idempotence=true
```

### 性能相关

```properties
# 批量大小
batch.size=16384

# 等待时间
linger.ms=5

# 缓冲区大小
buffer.memory=33554432

# 最大请求大小
max.request.size=1048576

# 单个连接最大未确认请求数
# 设为 1 可保证顺序，但降低吞吐
max.in.flight.requests.per.connection=5
```

## 幂等性与事务

### 幂等性 Producer

```java
// 开启幂等性
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

// 幂等性要求
// acks=all
// retries > 0
// max.in.flight.requests.per.connection <= 5
```

幂等性原理：

```
Producer ID (PID) + Sequence Number

┌──────────┐                    ┌──────────┐
│ Producer │                    │  Broker  │
│ PID=100  │                    │          │
└────┬─────┘                    └────┬─────┘
     │                               │
     │  msg1 (PID=100, Seq=0)       │
     │──────────────────────────────▶│ ✓ 接收
     │                               │
     │  msg2 (PID=100, Seq=1)       │
     │──────────────────────────────▶│ ✓ 接收
     │                               │
     │  重试 msg2 (PID=100, Seq=1)  │
     │──────────────────────────────▶│ ✗ 去重
     │                               │
```

### 事务 Producer

```java
// 事务配置
props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, "my-transactional-id");
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

KafkaProducer<String, String> producer = new KafkaProducer<>(props);

// 初始化事务
producer.initTransactions();

try {
    // 开始事务
    producer.beginTransaction();

    // 发送消息
    producer.send(new ProducerRecord<>("topic1", "key1", "value1"));
    producer.send(new ProducerRecord<>("topic2", "key2", "value2"));

    // 提交事务
    producer.commitTransaction();
} catch (Exception e) {
    // 回滚事务
    producer.abortTransaction();
}
```

事务使用场景：

```
1. 跨 Topic 原子写入
2. Consume-Transform-Produce 模式
3. Exactly-Once 语义
```

## 完整代码示例

```java
public class KafkaProducerExample {

    public static void main(String[] args) {
        Properties props = new Properties();

        // 基础配置
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG,
                  StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
                  StringSerializer.class.getName());

        // 可靠性配置
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.RETRIES_CONFIG, 3);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

        // 性能配置
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, 16384);
        props.put(ProducerConfig.LINGER_MS_CONFIG, 5);
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {

            for (int i = 0; i < 100; i++) {
                String key = "order-" + i;
                String value = "{\"orderId\": " + i + ", \"amount\": 100}";

                ProducerRecord<String, String> record =
                    new ProducerRecord<>("orders", key, value);

                // 异步发送
                producer.send(record, (metadata, exception) -> {
                    if (exception != null) {
                        System.err.println("发送失败: " + exception.getMessage());
                    } else {
                        System.out.printf("发送成功: topic=%s, partition=%d, offset=%d%n",
                                metadata.topic(), metadata.partition(), metadata.offset());
                    }
                });
            }

            // 确保所有消息发送完成
            producer.flush();
        }
    }
}
```

## 面试高频问题

### 1. 如何保证消息不丢失？

```
Producer 端：
1. acks=all：等待所有 ISR 副本确认
2. retries > 0：失败重试
3. 回调处理发送失败
4. 使用同步发送或确认异步结果

配置示例：
acks=all
retries=3
enable.idempotence=true
```

### 2. 如何保证消息有序？

```
1. 单分区有序：相同 Key 发送到同一分区
2. max.in.flight.requests.per.connection=1
   - 限制未确认请求数为 1
   - 避免重试导致乱序
3. 开启幂等性（enable.idempotence=true）
   - Kafka 2.0+ 支持最多 5 个未确认请求时保持顺序
```

### 3. batch.size 和 linger.ms 的关系？

```
发送触发条件（满足任一即发送）：
1. batch.size：批次达到指定大小
2. linger.ms：等待时间超过指定值

权衡：
- 大 batch.size + 长 linger.ms：高吞吐，高延迟
- 小 batch.size + 短 linger.ms：低延迟，低吞吐
```

### 4. 幂等性如何实现的？

```
原理：Producer ID + Sequence Number

1. Producer 初始化时获取 PID
2. 每条消息携带 <PID, Partition, Sequence>
3. Broker 记录每个 <PID, Partition> 的最大 Sequence
4. 收到重复 Sequence 的消息时丢弃

局限性：
- 单 Producer 单 Partition
- Producer 重启后 PID 变化
- 跨 Partition 需要事务
```

## 总结

```
Producer 核心要点：
1. 发送流程：序列化 → 分区 → 批量累积 → 发送
2. 分区策略：指定分区 > Key hash > 轮询/粘性
3. 批量发送：batch.size + linger.ms 权衡吞吐和延迟
4. 可靠性：acks=all + retries + 幂等性
5. 事务：跨 Topic 原子写入，Exactly-Once 语义
```
