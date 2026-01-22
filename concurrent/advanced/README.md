# 高级无锁技术

> StampedLock 和 LongAdder 是 JDK 8 引入的高性能并发工具，结合 Disruptor 构成高级无锁技术的核心。

## StampedLock ⭐⭐⭐⭐⭐

### 基本概念

**StampedLock** 是 JDK 8 引入的读写锁，比 `ReentrantReadWriteLock` 性能更高。

**核心特性**：
- 支持三种模式：**写锁、悲观读锁、乐观读**
- 不可重入（与 ReentrantLock 不同）
- 支持锁升级/降级
- 性能更好（无需维护线程所有权）

### 三种锁模式

**1. 写锁（独占锁）**

```java
StampedLock lock = new StampedLock();

public void write(int value) {
    long stamp = lock.writeLock();  // 获取写锁
    try {
        data = value;
    } finally {
        lock.unlockWrite(stamp);     // 释放写锁
    }
}
```

**2. 悲观读锁（共享锁）**

```java
public int read() {
    long stamp = lock.readLock();   // 获取读锁
    try {
        return data;
    } finally {
        lock.unlockRead(stamp);      // 释放读锁
    }
}
```

**3. 乐观读（重点）**

```java
public int optimisticRead() {
    long stamp = lock.tryOptimisticRead();  // 乐观读
    int value = data;                       // 读取数据

    if (!lock.validate(stamp)) {            // 验证是否被修改
        // 乐观读失败，升级为悲观读
        stamp = lock.readLock();
        try {
            value = data;
        } finally {
            lock.unlockRead(stamp);
        }
    }
    return value;
}
```

### 乐观读原理

**乐观读 vs 悲观读**：
```
悲观读锁：假设会有写操作，先加锁
乐观读：  假设没有写操作，先读取，事后验证
```

**示例对比**：
```java
// 悲观读：每次都加锁
public Point read() {
    long stamp = lock.readLock();
    try {
        return new Point(x, y);
    } finally {
        lock.unlockRead(stamp);
    }
}

// 乐观读：大部分情况不加锁
public Point optimisticRead() {
    long stamp = lock.tryOptimisticRead();  // 获取版本号
    int currentX = x;
    int currentY = y;

    if (!lock.validate(stamp)) {            // 检查版本号
        // 有写操作，升级为悲观读
        stamp = lock.readLock();
        try {
            currentX = x;
            currentY = y;
        } finally {
            lock.unlockRead(stamp);
        }
    }
    return new Point(currentX, currentY);
}

// 读多写少场景：乐观读性能提升 50%+
```

### 锁转换

**写锁 → 读锁（锁降级）**：
```java
long stamp = lock.writeLock();
try {
    // 写操作
    data = newValue;

    // 降级为读锁
    stamp = lock.tryConvertToReadLock(stamp);
    if (stamp == 0L) {
        // 降级失败，重新获取读锁
        lock.unlockWrite(stamp);
        stamp = lock.readLock();
    }

    // 使用数据（持有读锁）
    processData(data);
} finally {
    lock.unlock(stamp);  // 统一释放
}
```

**乐观读 → 悲观读（锁升级）**：
```java
long stamp = lock.tryOptimisticRead();
int value = data;

if (!lock.validate(stamp)) {
    // 升级为悲观读
    stamp = lock.readLock();
    try {
        value = data;
    } finally {
        lock.unlockRead(stamp);
    }
}
```

### StampedLock vs ReadWriteLock

| 特性 | StampedLock | ReentrantReadWriteLock |
|------|-------------|------------------------|
| **乐观读** | ✅ 支持 | ❌ 不支持 |
| **性能** | 高（读多写少） | 中 |
| **可重入** | ❌ 不可重入 | ✅ 可重入 |
| **条件变量** | ❌ 不支持 | ✅ 支持 |
| **锁转换** | ✅ 支持 | ❌ 不支持 |
| **适用场景** | 读远多于写 | 读多写少 |

### 完整示例

```java
public class Point {
    private double x, y;
    private final StampedLock lock = new StampedLock();

    // 写操作
    public void move(double deltaX, double deltaY) {
        long stamp = lock.writeLock();
        try {
            x += deltaX;
            y += deltaY;
        } finally {
            lock.unlockWrite(stamp);
        }
    }

    // 乐观读
    public double distanceFromOrigin() {
        long stamp = lock.tryOptimisticRead();  // 乐观读
        double currentX = x;
        double currentY = y;

        if (!lock.validate(stamp)) {            // 验证
            stamp = lock.readLock();            // 升级
            try {
                currentX = x;
                currentY = y;
            } finally {
                lock.unlockRead(stamp);
            }
        }
        return Math.sqrt(currentX * currentX + currentY * currentY);
    }

    // 悲观读
    public void moveIfAtOrigin(double newX, double newY) {
        long stamp = lock.readLock();
        try {
            while (x == 0.0 && y == 0.0) {
                // 尝试升级为写锁
                long ws = lock.tryConvertToWriteLock(stamp);
                if (ws != 0L) {
                    stamp = ws;
                    x = newX;
                    y = newY;
                    break;
                } else {
                    // 升级失败，释放读锁，获取写锁
                    lock.unlockRead(stamp);
                    stamp = lock.writeLock();
                }
            }
        } finally {
            lock.unlock(stamp);
        }
    }
}
```

---

## LongAdder ⭐⭐⭐⭐⭐

### 原理分析

**AtomicLong 的问题**：
```java
// 高并发场景
AtomicLong counter = new AtomicLong(0);

// 1000 个线程同时执行
counter.incrementAndGet();

// 问题：所有线程竞争同一个变量，CAS 冲突严重
```

**LongAdder 的优化**：
```
思路：分段累加，减少竞争

AtomicLong:  所有线程 → 竞争一个变量
LongAdder:   每个线程 → 自己的槽位 → 最后汇总

类比：
AtomicLong = 一个收银台
LongAdder  = 多个收银台，最后汇总营业额
```

### 实现原理

**核心数据结构**：
```java
public class LongAdder extends Striped64 {
    // Striped64 内部结构
    transient volatile Cell[] cells;     // 槽位数组
    transient volatile long base;        // 基础值
    transient volatile int cellsBusy;    // 初始化标志

    static final class Cell {
        volatile long value;             // 填充以避免伪共享
        // ... 缓存行填充 ...
    }
}
```

**累加流程**：
```java
public void add(long x) {
    Cell[] as;
    long b, v;
    int m;
    Cell a;

    // 1. 尝试直接更新 base
    if ((as = cells) != null || !casBase(b = base, b + x)) {
        // 2. base 更新失败，使用 Cell 槽位
        boolean uncontended = true;
        if (as == null || (m = as.length - 1) < 0 ||
            (a = as[getProbe() & m]) == null ||    // 获取当前线程的槽位
            !(uncontended = a.cas(v = a.value, v + x))) {
            // 3. 槽位冲突，扩容或重试
            longAccumulate(x, null, uncontended);
        }
    }
}

public long sum() {
    Cell[] as = cells;
    long sum = base;
    if (as != null) {
        // 汇总所有槽位
        for (int i = 0; i < as.length; ++i) {
            Cell a = as[i];
            if (a != null) sum += a.value;
        }
    }
    return sum;
}
```

**关键点**：
1. **低竞争**：直接更新 base（等价于 AtomicLong）
2. **中竞争**：使用 Cell 槽位，每个线程有自己的槽位
3. **高竞争**：扩容 Cell 数组（最大为 CPU 核数）
4. **读取**：sum = base + Cell[0] + Cell[1] + ... + Cell[n]

### 性能对比

**基准测试**：
```java
// 64 线程，每线程累加 1000 万次
AtomicLong:  3000ms
LongAdder:   500ms

// 提升 6 倍！
```

**为什么快？**
- AtomicLong：所有线程竞争一个变量，CAS 失败频繁
- LongAdder：每个线程使用自己的槽位，竞争减少

### 使用示例

```java
LongAdder adder = new LongAdder();

// 累加
adder.increment();              // +1
adder.add(10);                  // +10
adder.decrement();              // -1

// 获取结果
long sum = adder.sum();         // 汇总所有槽位
long sumThenReset = adder.sumThenReset();  // 汇总并重置

// 实战：统计接口调用次数
public class ApiStats {
    private LongAdder requestCount = new LongAdder();
    private LongAdder errorCount = new LongAdder();

    public void recordRequest() {
        requestCount.increment();
    }

    public void recordError() {
        errorCount.increment();
    }

    public Stats getStats() {
        return new Stats(
            requestCount.sum(),
            errorCount.sum()
        );
    }
}
```

### 注意事项

**sum() 不是强一致性**：
```java
// 错误用法
if (adder.sum() < threshold) {
    adder.increment();  // 可能超过 threshold！
}

// 原因：sum() 只是当前快照，不保证实时准确性

// 正确用法
LongAdder adder = new LongAdder();  // 只用于统计，不用于流程控制
```

### LongAdder vs AtomicLong

| 特性 | LongAdder | AtomicLong |
|------|-----------|------------|
| **性能（高并发）** | 高（分段累加） | 低（单点竞争） |
| **内存占用** | 高（Cell 数组） | 低（单个变量） |
| **sum() 复杂度** | O(n) | O(1) |
| **强一致性** | ❌ 弱一致 | ✅ 强一致 |
| **适用场景** | 统计、监控 | 序列号、流程控制 |

---

## Disruptor 高性能队列 ⭐⭐⭐⭐⭐

> Disruptor 已在 [disruptor.md](/home/user/interview-handbook/concurrent/advanced/disruptor.md) 详细讲解。

### 核心要点

**1. 为什么快？**
- 无锁设计（CAS）
- 消除伪共享（缓存行填充）
- 预分配内存（避免 GC）
- 批量处理

**2. RingBuffer**
- 环形数组，大小为 2 的幂次方
- 使用序列号定位：`sequence & (size - 1)`

**3. 等待策略**
- **BusySpinWaitStrategy**：CPU 占用高，延迟最低
- **YieldingWaitStrategy**：平衡 CPU 和延迟
- **SleepingWaitStrategy**：CPU 占用低
- **BlockingWaitStrategy**：延迟高，CPU 占用最低

**4. 使用场景**
- 日志系统（Log4j 2）
- 交易系统（LMAX）
- 消息队列（Storm、HBase）

详细内容请参考：[LMAX Disruptor](/home/user/interview-handbook/concurrent/advanced/disruptor.md)

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: StampedLock 和 ReentrantReadWriteLock 的区别？**
- StampedLock 支持乐观读，性能更高（读多写少场景）
- StampedLock 不可重入，ReentrantReadWriteLock 可重入
- StampedLock 支持锁转换（升级/降级）

**Q2: 什么是乐观读？**
- 不加锁直接读取，事后验证是否被修改
- 如果验证失败，升级为悲观读锁
- 适合读远多于写的场景

**Q3: LongAdder 为什么比 AtomicLong 快？**
- AtomicLong：所有线程竞争一个变量
- LongAdder：分段累加，每个线程有自己的槽位
- 高并发下性能提升 5-10 倍

**Q4: LongAdder 的 sum() 是强一致性吗？**
- 不是，sum() 只是当前快照
- 只用于统计，不能用于流程控制
- 如果需要强一致性，使用 AtomicLong

**Q5: Disruptor 的核心优化？**
- 无锁 CAS + 序列号
- 消除伪共享（缓存行填充）
- 预分配内存（避免 GC）
- 批量处理

**Q6: 什么时候使用 StampedLock？**
- 读远多于写（读占比 > 90%）
- 不需要可重入
- 不需要条件变量

**Q7: 如何选择 LongAdder 和 AtomicLong？**
- **LongAdder**：高并发统计（QPS、错误数）
- **AtomicLong**：序列号生成、流程控制

**Q8: 缓存行填充的作用？**
- 避免伪共享（False Sharing）
- CPU 缓存行 64 字节，填充使变量独占缓存行
- 避免多线程修改不同变量导致缓存失效

---

## 参考资料

1. **JDK 文档**：StampedLock、LongAdder
2. **书籍推荐**：《Java 并发编程的艺术》
3. **Disruptor 详解**：[disruptor.md](/home/user/interview-handbook/concurrent/advanced/disruptor.md)
4. **Doug Lea 论文**：Striped64 设计
