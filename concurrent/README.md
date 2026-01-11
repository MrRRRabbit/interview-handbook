# 并发编程知识体系

> 本章节涵盖高并发编程与无锁技术的完整知识体系，从基础理论到实战应用。

## 📚 学习路线

```
基础理论 → 传统同步 → 无锁编程 → 高级技术 → 性能优化 → 实战案例
```

## 🎯 核心内容

### 第一部分：基础理论

掌握并发编程的理论基础，理解底层原理。

- **并发编程基础**：并发 vs 并行、线程模型、竞态条件
- **Java 内存模型**：JMM、happens-before、重排序
- **CPU 缓存架构**：多级缓存、MESI 协议、伪共享

**学习时长**：2-3 周  
**难度**：⭐⭐⭐

### 第二部分：传统同步机制

了解基于锁的并发控制方式。

- **锁机制**：synchronized、ReentrantLock、读写锁、死锁
- **线程协作**：wait/notify、Semaphore、CountDownLatch、CyclicBarrier

**学习时长**：1-2 周  
**难度**：⭐⭐

### 第三部分：无锁编程核心 ⭐ 重点

深入理解无锁编程的核心技术。

- **原子操作与 CAS**：CAS 原理、ABA 问题、原子类、LongAdder
- **无锁数据结构**：无锁栈、无锁队列、跳表、Disruptor
- **内存顺序与屏障**：volatile、final、内存屏障

**学习时长**：2-3 周  
**难度**：⭐⭐⭐⭐

### 第四部分：高级无锁技术

学习业界高性能并发框架的设计思想。

- **LMAX Disruptor**：RingBuffer、序列号、无锁发布、消除伪共享
- **Netty 无锁设计**：EventLoop、MpscQueue、对象池
- **Lock-Free 算法**：Wait-Free、Hazard Pointer、RCU
- **并发容器**：ConcurrentHashMap、ConcurrentSkipListMap

**学习时长**：2-3 周  
**难度**：⭐⭐⭐⭐⭐

### 第五部分：性能优化

掌握并发程序的性能分析与调优技巧。

- **性能分析**：JMH、JProfiler、性能指标
- **最佳实践**：设计原则、编码规范、常见陷阱

**学习时长**：1-2 周  
**难度**：⭐⭐⭐

### 第六部分：分布式并发

扩展到分布式场景的并发控制。

- **分布式锁**：Redis、ZooKeeper、数据库
- **分布式无锁**：CAS 在分布式中的应用、一致性协议

**学习时长**：1-2 周  
**难度**：⭐⭐⭐⭐

### 第七部分：实战案例

通过真实场景巩固所学知识。

- **秒杀系统**：库存扣减、限流、削峰
- **计数器设计**：AtomicLong vs LongAdder
- **缓存方案**：双重检查锁定、缓存穿透

**学习时长**：持续实践  
**难度**：⭐⭐⭐⭐

## 🔥 面试高频考点

### 必须掌握（⭐⭐⭐⭐⭐）

1. **Java 内存模型（JMM）**
   - 主内存与工作内存
   - happens-before 原则
   - 重排序规则

2. **volatile 关键字**
   - 可见性保证
   - 禁止指令重排序
   - 使用场景

3. **CAS 与 ABA 问题**
   - CAS 原理
   - ABA 问题的产生与解决
   - AtomicStampedReference

4. **synchronized vs ReentrantLock**
   - 区别与选择
   - 锁优化（偏向锁、轻量级锁）
   - 使用场景

5. **ConcurrentHashMap**
   - JDK 7 vs JDK 8 实现
   - put/get 流程
   - 扩容机制

6. **伪共享（False Sharing）**
   - 产生原因
   - 性能影响
   - 解决方案（@Contended）

### 深入理解（⭐⭐⭐⭐）

7. **LMAX Disruptor**
   - RingBuffer 设计
   - 为什么快
   - 与队列的区别

8. **ThreadLocal**
   - 原理与实现
   - 内存泄漏问题
   - 使用场景

9. **AQS（AbstractQueuedSynchronizer）**
   - 同步器框架
   - 独占模式与共享模式
   - Condition 实现

10. **线程池**
    - 核心参数
    - 拒绝策略
    - 最佳实践

### 实战能力（⭐⭐⭐⭐⭐）

- 设计线程安全的单例模式
- 实现一个简单的无锁队列
- 分析并发 bug
- 秒杀系统的库存扣减方案
- 性能调优经验

## 📖 推荐学习资源

### 书籍

- 《Java 并发编程实战》 - Brian Goetz（必读）
- 《Java 并发编程的艺术》 - 方腾飞等
- 《深入理解 Java 虚拟机》 - 周志明
- 《The Art of Multiprocessor Programming》 - Maurice Herlihy

### 博客与文章

- [Martin Thompson's Blog](https://mechanical-sympathy.blogspot.com/) - LMAX Disruptor 作者
- [Doug Lea's Home Page](http://gee.cs.oswego.edu/dl/) - Java 并发大师
- [Mechanical Sympathy](https://mechanical-sympathy.blogspot.com/) - 机械同情

### 开源项目

- [JDK 并发包源码](https://github.com/openjdk/jdk)
- [LMAX Disruptor](https://github.com/LMAX-Exchange/disruptor)
- [Netty](https://github.com/netty/netty)

## 🎓 学习建议

### 1. 理论与实践结合

每学一个知识点，必须写代码验证：
```java
// 示例：验证 volatile 的可见性
public class VolatileTest {
    private volatile boolean flag = false;
    // 实验代码...
}
```

### 2. 画图理解

- 用图表示内存模型
- 画出缓存一致性流程
- 绘制数据结构示意图

### 3. 阅读源码

按优先级阅读：
1. `java.util.concurrent.atomic` 包
2. `ConcurrentHashMap`
3. `ThreadPoolExecutor`
4. `AbstractQueuedSynchronizer`
5. LMAX Disruptor

### 4. 性能测试

使用 JMH 验证性能差异：
```java
@Benchmark
public void testAtomicLong() {
    atomicLong.incrementAndGet();
}

@Benchmark
public void testLongAdder() {
    longAdder.increment();
}
```

### 5. 写博客总结

- 每个重要知识点写一篇总结
- 用自己的话解释原理
- 记录遇到的问题和解决方案

## 💡 学习检查清单

完成每个阶段后，检查是否达到以下标准：

### 基础理论
- [ ] 能画出 JMM 的内存模型图
- [ ] 能列举并解释 happens-before 规则
- [ ] 理解 CPU 缓存一致性协议（MESI）
- [ ] 知道什么是伪共享及如何避免

### 传统同步
- [ ] 能对比 synchronized 和 ReentrantLock
- [ ] 知道如何避免死锁
- [ ] 理解锁优化的几种方式
- [ ] 能正确使用 wait/notify

### 无锁编程
- [ ] 理解 CAS 的原理
- [ ] 能解释 ABA 问题并给出解决方案
- [ ] 知道 volatile 的三个特性
- [ ] 能实现一个简单的无锁栈或队列

### 高级技术
- [ ] 理解 Disruptor 为什么快
- [ ] 能分析 ConcurrentHashMap 的源码
- [ ] 知道 AQS 的基本原理
- [ ] 了解 Lock-Free 算法的设计思想

### 性能优化
- [ ] 会使用 JMH 进行基准测试
- [ ] 能分析并发性能瓶颈
- [ ] 知道常见的性能优化手段
- [ ] 有实际的调优经验

### 实战应用
- [ ] 实现过线程安全的单例
- [ ] 设计过高并发的计数器
- [ ] 解决过实际的并发问题
- [ ] 能讲出秒杀系统的设计方案

## 🚀 开始学习

选择适合你的起点：

- **完全新手**：从「基础理论」开始，打好基础
- **有一定基础**：直接进入「无锁编程核心」，这是重点
- **准备面试**：重点看「面试高频考点」，结合实战案例
- **深度学习**：研读源码，实现自己的并发工具

---

**预计总学习时间**：10-15 周（根据个人情况调整）

**建议学习节奏**：
- 工作日：每天 1-2 小时理论学习 + 代码实践
- 周末：3-4 小时深度学习 + 源码阅读

**记住**：并发编程是一个需要大量实践的领域，理论学习的同时一定要动手写代码验证！

开始你的并发编程之旅吧！💪
