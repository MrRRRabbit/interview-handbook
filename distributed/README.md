# 分布式系统知识体系大纲

## 内容导航

- [基础理论](theory.md) - CAP、BASE、一致性级别
- [一致性算法](consensus.md) - Paxos、Raft、ZAB
- [分布式存储](storage.md) - 数据分片、Cassandra、HBase
- [服务治理与微服务](microservices.md) - 服务发现、RPC、限流熔断

## 面试高频考点

### 必须掌握（⭐⭐⭐⭐⭐）

1. **CAP 理论**
   - 三者含义和权衡
   - 常见系统的 CAP 选择
   - 为什么分布式系统无法同时满足 CAP

2. **Raft 算法**
   - Leader 选举流程
   - 日志复制流程
   - 如何保证一致性和可用性
   - Raft vs Paxos

3. **分布式事务**
   - 2PC、TCC、Saga 的区别
   - 如何选择分布式事务方案
   - 本地消息表实现原理

4. **服务注册与发现**
   - ZooKeeper vs Eureka
   - CP vs AP 的选择
   - 服务发现的实现原理

5. **微服务限流熔断**
   - 熔断器的三种状态
   - 限流算法及其区别
   - 如何设计限流方案

### 深入理解（⭐⭐⭐⭐）

6. **一致性哈希**
   - 解决的问题
   - 虚拟节点的作用
   - 实现原理

7. **Quorum 机制**
   - N、W、R 的含义
   - 如何保证一致性
   - Dynamo、Cassandra 的应用

8. **ZAB 协议**
   - ZAB vs Raft
   - 崩溃恢复和消息广播
   - ZXID 的作用

9. **分布式存储**
   - HBase vs Cassandra
   - LSM Tree 原理
   - 数据分片策略

10. **服务治理**
    - Dubbo 架构和特性
    - 负载均衡策略
    - 链路追踪原理

### 实战能力（⭐⭐⭐⭐⭐）

- 设计一个分布式锁
- 设计一个 ID 生成器（雪花算法）
- 设计一个微服务架构
- 解决分布式事务一致性问题
- 设计一个高可用的注册中心
- 分析一个服务雪崩的场景并给出解决方案

## 学习路径

### 第一阶段：分布式理论（2-3 周）
1. CAP 和 BASE 理论
2. 一致性级别
3. 数据分片和副本

### 第二阶段：一致性算法（3-4 周）⭐ 重点
1. Paxos 算法
2. Raft 算法（重点）
3. ZAB 协议
4. 动手实现 Raft

### 第三阶段：分布式存储（2-3 周）
1. 一致性哈希
2. Quorum 机制
3. Cassandra 原理
4. HBase 原理

### 第四阶段：服务治理（3-4 周）
1. 服务注册与发现
2. RPC 框架（Dubbo）
3. 负载均衡
4. 限流熔断降级

### 第五阶段：微服务架构（2-3 周）
1. Spring Cloud 全家桶
2. 分布式事务
3. 链路追踪
4. 配置中心

### 第六阶段：实战项目（持续）
1. 搭建微服务架构
2. 实现分布式锁
3. 实现 ID 生成器
4. 解决实际问题

## 推荐学习资源

### 书籍
- 《分布式系统原理与范型》 - Andrew S. Tanenbaum
- 《数据密集型应用系统设计》（DDIA） - Martin Kleppmann
- 《深入理解分布式系统》 - 陈现麟

### 论文
- Paxos Made Simple - Leslie Lamport
- In Search of an Understandable Consensus Algorithm (Raft) - Diego Ongaro
- Dynamo: Amazon's Highly Available Key-value Store

### 博客文章
- Raft 动画演示：https://raft.github.io/
- 分布式系统领域经典论文
- 阿里技术博客

### 开源项目
- [etcd](https://github.com/etcd-io/etcd) - Raft 实现
- [ZooKeeper](https://github.com/apache/zookeeper) - ZAB 实现
- [Spring Cloud](https://github.com/spring-cloud) - 微服务全家桶
- [Dubbo](https://github.com/apache/dubbo) - RPC 框架

## 学习建议

### 1. 理论与实践结合
- 阅读论文理解算法原理
- 看动画演示加深理解
- 动手实现核心算法
- 部署开源项目验证

### 2. 画图理解
- 画出 Raft 选举和日志复制流程
- 画出一致性哈希环
- 画出微服务调用链路
- 画出各种架构图

### 3. 源码阅读
推荐阅读顺序：
1. etcd 的 Raft 实现
2. ZooKeeper 的 ZAB 实现
3. Dubbo 的服务治理实现
4. Sentinel 的限流熔断实现

### 4. 真实案例分析
- 分析大厂的分布式系统架构
- 研究开源项目的设计决策
- 总结生产环境的经验教训

---

**重点章节**：
- 一致性算法（Raft）
- 分布式事务
- 服务治理与限流熔断

**学习建议**：
1. Raft 算法是重中之重，务必彻底理解
2. 动手实践：部署 ZooKeeper、etcd、Dubbo
3. 阅读经典论文和开源代码
4. 关注大厂技术博客和分享

掌握分布式系统，是成为高级工程师的必经之路！
