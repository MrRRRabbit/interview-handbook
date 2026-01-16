# Kafka 核心原理

> Apache Kafka 是一个分布式流处理平台，具有高吞吐、低延迟、高可用的特点，广泛应用于日志收集、消息系统、流处理等场景。

## 内容概览

本章深入讲解 Kafka 的核心原理和实践，帮助你掌握 Kafka 的设计思想和使用方法。

## 主要内容

- ⭐ [架构与核心概念](architecture.md) - Broker、Topic、Partition、Replica
- ⭐ [生产者](producer.md) - 发送流程、分区策略、幂等性
- ⭐ [消费者](consumer.md) - Consumer Group、Offset、Rebalance
- ⭐ [存储机制](storage.md) - Log Segment、索引、零拷贝
- ⭐ [高可用与可靠性](reliability.md) - 副本机制、ISR、消息可靠性

## 待添加的主题

- [ ] Kafka Streams 流处理
- [ ] Kafka Connect 数据集成
- [ ] Schema Registry
- [ ] 性能调优实践
