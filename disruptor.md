# LMAX Disruptor

## 概述

LMAX Disruptor 是一个高性能的线程间消息传递框架,由英国外汇交易公司 LMAX 开发并开源。它能够在单线程中每秒处理 600 万笔订单,是 Java 并发编程领域的重要创新。

**核心价值**: 通过无锁算法和消除伪共享,实现极低延迟的线程间通信。

## 核心原理

### 1. 整体架构

Disruptor 的核心是一个环形缓冲区(RingBuffer),生产者向其中写入数据,消费者从中读取数据。

```
生产者 → RingBuffer → 消费者
           ↑
        序列号控制
```

**关键组件**:
- **RingBuffer**: 环形数组,存储数据
- **Sequence**: 序列号,标识位置
- **Sequencer**: 协调生产者访问
- **SequenceBarrier**: 协调消费者等待
- **WaitStrategy**: 等待策略

### 2. 为什么不用队列?

传统队列(如 ArrayBlockingQueue)的问题:
- **锁竞争**: 使用 ReentrantLock,高并发下性能差
- **伪共享**: 队列头尾在同一缓存行,导致 CPU 缓存失效
- **垃圾回收**: 频繁创建/销毁对象,GC 压力大

Disruptor 的优势:
- **无锁**: 使用 CAS 操作,避免锁竞争
- **消除伪共享**: 通过缓存行填充(Padding)
- **预分配**: RingBuffer 预先分配对象,避免 GC

## RingBuffer 设计

### 1. 环形数组结构

```java
public final class RingBuffer<E> {
    private final Object[] entries;  // 实际存储数据的数组
    private final int bufferSize;    // 必须是 2 的幂次方
    private final int indexMask;     // bufferSize - 1,用于快速取模
    
    // 获取元素
    public E get(long sequence) {
        return (E) entries[(int) (sequence & indexMask)];
    }
}
```

**为什么是 2 的幂次方?**
- 取模运算 `sequence % bufferSize` 可以优化为 `sequence & (bufferSize - 1)`
- 位运算比取模快得多

### 2. 序列号机制

```java
// Sequence 类 - 带缓存行填充
class LhsPadding {
    protected long p1, p2, p3, p4, p5, p6, p7;  // 填充 56 字节
}

class Value extends LhsPadding {
    protected volatile long value;              // 实际值 8 字节
}

class RhsPadding extends Value {
    protected long p9, p10, p11, p12, p13, p14, p15;  // 填充 56 字节
}

public class Sequence extends RhsPadding {
    // 总共 128 字节,占满两个缓存行
}
```

**序列号特点**:
- 单调递增的 long 类型
- 环形缓冲区的逻辑位置
- 通过 `& indexMask` 映射到数组索引

### 3. 生产者序列控制

```java
// 单生产者
public class SingleProducerSequencer {
    private final Sequence cursor = new Sequence();  // 当前发布位置
    
    public long next() {
        long nextSequence = cursor.get() + 1;
        // 检查是否会覆盖未消费的数据
        if (nextSequence > cachedGatingSequence) {
            // 获取最慢消费者的序列号
            long minSequence = getMinimumSequence(gatingSequences);
            if (nextSequence > minSequence + bufferSize) {
                // 缓冲区已满,等待
                LockSupport.parkNanos(1L);
            }
        }
        return nextSequence;
    }
    
    public void publish(long sequence) {
        cursor.set(sequence);  // 发布序列号
    }
}
```

```java
// 多生产者
public class MultiProducerSequencer {
    private final Sequence cursor = new Sequence();
    private final Sequence gatingSequenceCache = new Sequence();
    private final int[] availableBuffer;  // 标记位置是否可用
    
    public long next() {
        long current;
        long next;
        do {
            current = cursor.get();
            next = current + 1;
            // 检查是否会覆盖
            if (next > cachedValue) {
                long minSequence = getMinimumSequence(gatingSequences);
                if (next > minSequence + bufferSize) {
                    LockSupport.parkNanos(1L);
                    continue;
                }
                gatingSequenceCache.set(minSequence);
            }
        } while (!cursor.compareAndSet(current, next));  // CAS 竞争序列号
        
        return next;
    }
    
    public void publish(long sequence) {
        setAvailable(sequence);  // 标记该位置可用
        // 等待前面的序列号都发布后,才更新 cursor
        waitFor(sequence - 1);
        cursor.set(sequence);
    }
}
```

**关键点**:
- 单生产者直接递增,无需 CAS
- 多生产者使用 CAS 竞争序列号
- 必须等待所有前序序列号发布

## 无锁实现

### 1. CAS 操作

```java
// Sequence 的 CAS 更新
public boolean compareAndSet(long expectedValue, long newValue) {
    return UNSAFE.compareAndSwapLong(this, VALUE_OFFSET, expectedValue, newValue);
}

// 生产者竞争序列号
do {
    current = cursor.get();
    next = current + 1;
} while (!cursor.compareAndSet(current, next));
```

### 2. 内存屏障

```java
// volatile 写 - 使用 StoreLoad 屏障
cursor.set(sequence);  

// volatile 读 - 使用 LoadLoad 和 LoadStore 屏障
long current = cursor.get();
```

**内存可见性保证**:
- 生产者 publish 后,消费者能立即看到
- volatile 的 happens-before 语义

### 3. 等待策略

```java
// BlockingWaitStrategy - 使用锁和条件变量
public long waitFor(long sequence) {
    lock.lock();
    try {
        while (cursor.get() < sequence) {
            condition.await();  // 等待
        }
    } finally {
        lock.unlock();
    }
    return cursor.get();
}

// BusySpinWaitStrategy - 忙轮询
public long waitFor(long sequence) {
    while (cursor.get() < sequence) {
        // 自旋等待
    }
    return cursor.get();
}

// YieldingWaitStrategy - 让出 CPU
public long waitFor(long sequence) {
    int counter = SPIN_TRIES;
    while (cursor.get() < sequence) {
        if (--counter == 0) {
            Thread.yield();  // 让出 CPU
            counter = SPIN_TRIES;
        }
    }
    return cursor.get();
}

// SleepingWaitStrategy - 渐进式休眠
public long waitFor(long sequence) {
    int counter = RETRIES;
    while (cursor.get() < sequence) {
        if (--counter > 100) {
            // 自旋
        } else if (counter > 0) {
            Thread.yield();
        } else {
            LockSupport.parkNanos(1L);  // 休眠 1 纳秒
        }
    }
    return cursor.get();
}
```

**选择建议**:
- **BusySpinWaitStrategy**: 延迟最低,CPU 占用高
- **YieldingWaitStrategy**: 延迟低,CPU 占用中等
- **SleepingWaitStrategy**: 延迟中等,CPU 占用低
- **BlockingWaitStrategy**: 延迟高,CPU 占用最低

## 性能优化

### 1. 消除伪共享

**什么是伪共享?**

CPU 缓存以缓存行(Cache Line)为单位,通常 64 字节。如果两个线程频繁修改同一缓存行中的不同变量,会导致缓存行在 CPU 核心间来回失效。

```java
// 问题代码
class Counter {
    volatile long producerCount;  // 8 字节
    volatile long consumerCount;  // 8 字节 - 可能在同一缓存行
}

// Disruptor 的解决方案 - 缓存行填充
class LhsPadding {
    protected long p1, p2, p3, p4, p5, p6, p7;  // 56 字节
}

class Value extends LhsPadding {
    protected volatile long value;              // 8 字节
}

class RhsPadding extends Value {
    protected long p9, p10, p11, p12, p13, p14, p15;  // 56 字节
}

public class Sequence extends RhsPadding {
    // 总共 128 字节,独占两个缓存行
}
```

**效果**: 避免不同线程的 Sequence 对象相互影响。

### 2. 预分配对象

```java
// 初始化时预分配所有 Event 对象
for (int i = 0; i < bufferSize; i++) {
    entries[i] = eventFactory.newInstance();
}

// 使用时重用对象,不创建新对象
Event event = ringBuffer.get(sequence);
event.setValue(newValue);  // 更新现有对象
```

**优势**:
- 避免 GC 压力
- 避免对象分配开销
- 内存布局连续,缓存友好

### 3. 批量操作

```java
// 消费者批量处理
long nextSequence = sequence + 1;
long availableSequence = sequenceBarrier.waitFor(nextSequence);

// 批量处理 [nextSequence, availableSequence] 范围内的所有事件
while (nextSequence <= availableSequence) {
    Event event = ringBuffer.get(nextSequence);
    eventHandler.onEvent(event, nextSequence, nextSequence == availableSequence);
    nextSequence++;
}
```

**优势**:
- 减少等待次数
- 提高吞吐量
- 降低平均延迟

## 使用场景

### 1. 适用场景

- **高并发写入**: 日志系统、监控系统
- **低延迟要求**: 交易系统、实时计算
- **事件驱动**: 事件溯源、CQRS 架构
- **生产者-消费者**: 任务队列、消息分发

### 2. 实际应用

**Log4j 2**: 使用 Disruptor 实现异步日志

```java
// AsyncLogger 内部使用 Disruptor
RingBuffer<LogEvent> ringBuffer = disruptor.getRingBuffer();
long sequence = ringBuffer.next();
try {
    LogEvent event = ringBuffer.get(sequence);
    event.setValues(...);  // 设置日志内容
} finally {
    ringBuffer.publish(sequence);
}
```

**Storm**: 使用 Disruptor 进行线程间消息传递

**HBase**: 使用 Disruptor 处理 WAL 写入

### 3. 不适用场景

- **消费者需要阻塞**: Disruptor 的消费者是推模式
- **需要持久化**: RingBuffer 是内存结构
- **数据量大**: RingBuffer 大小固定,不适合无界队列

## 面试要点

### 核心问题

**Q1: Disruptor 为什么快?**

A: 三个核心原因:
1. **无锁设计**: 使用 CAS 替代锁,避免上下文切换
2. **消除伪共享**: 缓存行填充,避免缓存失效
3. **预分配内存**: 避免 GC 和对象分配开销

**Q2: RingBuffer 为什么用 2 的幂次方?**

A: 为了快速取模运算:
- `sequence % size` 等价于 `sequence & (size - 1)`
- 位运算比取模快数十倍

**Q3: 如何保证多生产者的顺序性?**

A: 
- 使用 CAS 竞争序列号,保证全局顺序
- 使用 availableBuffer 标记每个位置是否已发布
- cursor 只有在所有前序序列号都发布后才更新

**Q4: Disruptor 和 BlockingQueue 的区别?**

| 特性 | Disruptor | BlockingQueue |
|------|-----------|---------------|
| 锁机制 | 无锁 CAS | ReentrantLock |
| 伪共享 | 消除 | 存在 |
| 内存分配 | 预分配 | 动态分配 |
| 吞吐量 | 极高 | 中等 |
| 延迟 | 极低 | 中等 |
| CPU 占用 | 高(BusySpin) | 低 |

**Q5: 什么是缓存行填充(Padding)?**

A: 
- CPU 缓存行通常 64 字节
- 在 value 前后各填充 56 字节(7 个 long)
- 确保 value 独占缓存行,避免伪共享

```java
// 填充前: value 可能和其他变量在同一缓存行
volatile long value;

// 填充后: value 独占缓存行
long p1,p2,p3,p4,p5,p6,p7;
volatile long value;
long p9,p10,p11,p12,p13,p14,p15;
```

**Q6: 等待策略如何选择?**

A: 根据业务需求权衡:
- **BusySpinWaitStrategy**: CPU 资源充足,要求极低延迟
- **YieldingWaitStrategy**: CPU 资源较充足,要求低延迟
- **SleepingWaitStrategy**: CPU 资源一般,延迟要求一般
- **BlockingWaitStrategy**: CPU 资源紧张,延迟要求不高

### 深入问题

**Q7: Disruptor 如何避免 ABA 问题?**

A: 
- Disruptor 的序列号单调递增,永不回退
- 即使 RingBuffer 循环使用,序列号也不会重复
- 因此不存在传统 CAS 的 ABA 问题

**Q8: 如果 RingBuffer 满了怎么办?**

A: 
- 生产者会等待最慢的消费者消费
- 使用 `waitFor` 方法等待可用空间
- 可以配置等待策略(自旋、让出、休眠)

**Q9: Disruptor 的内存占用如何?**

A: 
- RingBuffer 大小固定,预分配所有对象
- 每个 Event 对象占用内存 = 对象大小
- 额外开销: Sequence 对象的 Padding(每个 128 字节)

**Q10: 如何实现多个消费者?**

A: 
- **独立消费**: 每个消费者独立消费所有事件
- **分组消费**: WorkPool 模式,多个消费者分担工作
- **依赖消费**: 消费者 B 依赖消费者 A 的结果

```java
// 独立消费
disruptor.handleEventsWith(handler1, handler2);

// 分组消费  
disruptor.handleEventsWithWorkerPool(handler1, handler2);

// 依赖消费
disruptor.handleEventsWith(handler1).then(handler2);
```

## 代码示例

### 基本使用

```java
// 1. 定义 Event
class OrderEvent {
    private long orderId;
    private double price;
    
    // getters and setters
}

// 2. 定义 EventFactory
EventFactory<OrderEvent> factory = () -> new OrderEvent();

// 3. 创建 Disruptor
int bufferSize = 1024;  // 必须是 2 的幂次方
Disruptor<OrderEvent> disruptor = new Disruptor<>(
    factory,
    bufferSize,
    Executors.defaultThreadFactory(),
    ProducerType.SINGLE,  // 单生产者
    new YieldingWaitStrategy()
);

// 4. 定义消费者
disruptor.handleEventsWith((event, sequence, endOfBatch) -> {
    System.out.println("处理订单: " + event.getOrderId());
});

// 5. 启动
disruptor.start();

// 6. 发布事件
RingBuffer<OrderEvent> ringBuffer = disruptor.getRingBuffer();
long sequence = ringBuffer.next();
try {
    OrderEvent event = ringBuffer.get(sequence);
    event.setOrderId(12345L);
    event.setPrice(99.99);
} finally {
    ringBuffer.publish(sequence);
}

// 7. 关闭
disruptor.shutdown();
```

### 高级用法

```java
// 多消费者依赖关系
disruptor
    .handleEventsWith(journalHandler)  // 先记录日志
    .then(replicationHandler)          // 然后复制
    .then(applicationHandler);         // 最后处理业务

// 菱形依赖
disruptor.handleEventsWith(handler1, handler2)  // 并行
         .then(handler3);                       // 等待两个都完成

// 使用 Translator 简化发布
ringBuffer.publishEvent((event, sequence, arg0, arg1) -> {
    event.setOrderId(arg0);
    event.setPrice(arg1);
}, orderId, price);
```

## 总结

Disruptor 通过以下创新实现了极致性能:

1. **无锁并发**: CAS + 序列号
2. **消除伪共享**: 缓存行填充
3. **预分配内存**: 避免 GC
4. **批量处理**: 提高吞吐量

这些技术不仅适用于 Disruptor,也是高性能并发编程的通用原则。

---

**相关主题**:
- [CPU 缓存一致性协议](../concurrent/cache-coherence.md) (待添加)
- [CAS 与 ABA 问题](../concurrent/cas-aba.md) (待添加)
- [Java 内存模型](../concurrent/jmm.md) (待添加)
