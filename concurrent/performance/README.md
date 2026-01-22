# 性能优化

> 线程池、伪共享和性能分析工具是并发编程性能优化的三大支柱，也是面试高频考点。

## 线程池原理 ⭐⭐⭐⭐⭐

### 为什么使用线程池

**不使用线程池的问题**：
```java
// 每次创建新线程
new Thread(() -> {
    // 执行任务
}).start();

// 问题：
// 1. 频繁创建/销毁线程，开销大
// 2. 无法控制线程数量，可能 OOM
// 3. 无法复用线程，资源浪费
```

**线程池的优势**：
- 降低资源消耗：线程复用
- 提高响应速度：无需创建线程
- 提高线程可管理性：统一分配、调优、监控

### ThreadPoolExecutor 核心参数 ⭐⭐⭐⭐⭐

```java
public ThreadPoolExecutor(
    int corePoolSize,              // 核心线程数
    int maximumPoolSize,           // 最大线程数
    long keepAliveTime,            // 空闲线程存活时间
    TimeUnit unit,                 // 时间单位
    BlockingQueue<Runnable> workQueue,  // 工作队列
    ThreadFactory threadFactory,   // 线程工厂
    RejectedExecutionHandler handler    // 拒绝策略
)
```

**参数详解**：

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| **corePoolSize** | 核心线程数，即使空闲也不会销毁 | CPU 密集型：CPU 核数+1<br>IO 密集型：2*CPU 核数 |
| **maximumPoolSize** | 最大线程数 | 根据业务场景设置 |
| **keepAliveTime** | 非核心线程空闲存活时间 | 30-60 秒 |
| **workQueue** | 任务队列 | 有界队列（防止 OOM） |
| **handler** | 拒绝策略 | 根据业务选择 |

### 线程池执行流程

```
提交任务
   ↓
核心线程数未满？
   ├── 是 → 创建核心线程执行
   └── 否 → 工作队列未满？
             ├── 是 → 任务入队
             └── 否 → 最大线程数未满？
                       ├── 是 → 创建非核心线程
                       └── 否 → 执行拒绝策略
```

**示例**：
```java
// 核心线程数=2，最大线程数=4，队列容量=2
ThreadPoolExecutor pool = new ThreadPoolExecutor(
    2, 4, 60, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(2),
    new ThreadPoolExecutor.AbortPolicy()
);

// 提交 7 个任务
// 任务 1, 2 → 创建核心线程执行
// 任务 3, 4 → 进入队列
// 任务 5, 6 → 创建非核心线程执行
// 任务 7   → 拒绝（队列满，线程数已达最大值）
```

### 工作队列选择

**1. ArrayBlockingQueue（有界队列）**
```java
new ArrayBlockingQueue<>(100);

// 优点：防止 OOM
// 缺点：队列满后触发拒绝策略
// 适用：有明确容量预估的场景
```

**2. LinkedBlockingQueue（无界/有界队列）**
```java
new LinkedBlockingQueue<>();         // 无界
new LinkedBlockingQueue<>(1000);     // 有界

// 优点：吞吐量高
// 缺点：无界可能 OOM
// 适用：异步任务、消息消费
```

**3. SynchronousQueue（同步队列）**
```java
new SynchronousQueue<>();

// 特点：不存储元素，直接交给线程
// 适用：任务量不确定，快速响应
// 典型：Executors.newCachedThreadPool()
```

**4. PriorityBlockingQueue（优先队列）**
```java
new PriorityBlockingQueue<>();

// 特点：按优先级执行
// 适用：有优先级需求的任务
```

### 拒绝策略

**1. AbortPolicy（默认）**
```java
new ThreadPoolExecutor.AbortPolicy();

// 行为：抛出 RejectedExecutionException
// 适用：任务不能丢失的场景
```

**2. CallerRunsPolicy**
```java
new ThreadPoolExecutor.CallerRunsPolicy();

// 行为：调用者线程执行任务
// 优点：不丢失任务，降低提交速度
// 适用：允许降级的场景
```

**3. DiscardPolicy**
```java
new ThreadPoolExecutor.DiscardPolicy();

// 行为：静默丢弃任务
// 适用：允许丢失任务的场景
```

**4. DiscardOldestPolicy**
```java
new ThreadPoolExecutor.DiscardOldestPolicy();

// 行为：丢弃最老的任务，重试提交
// 适用：最新任务优先级高的场景
```

**自定义拒绝策略**：
```java
RejectedExecutionHandler handler = (r, executor) -> {
    // 记录日志
    log.error("Task rejected: {}", r);
    // 降级处理
    fallbackService.handle(r);
};
```

### 线程池监控

```java
ThreadPoolExecutor pool = ...;

// 线程池状态
int activeCount = pool.getActiveCount();         // 活跃线程数
int poolSize = pool.getPoolSize();               // 当前线程数
long completedTaskCount = pool.getCompletedTaskCount();  // 已完成任务数
long taskCount = pool.getTaskCount();            // 总任务数

// 队列状态
int queueSize = pool.getQueue().size();          // 队列任务数
int remainingCapacity = pool.getQueue().remainingCapacity();  // 队列剩余容量

// 监控示例
public class PoolMonitor implements Runnable {
    private ThreadPoolExecutor pool;

    @Override
    public void run() {
        while (true) {
            log.info("Pool - Active: {}, Pool: {}, Queue: {}, Completed: {}",
                pool.getActiveCount(),
                pool.getPoolSize(),
                pool.getQueue().size(),
                pool.getCompletedTaskCount()
            );
            Thread.sleep(5000);
        }
    }
}
```

### 线程池参数动态调整

```java
ThreadPoolExecutor pool = ...;

// 动态调整核心线程数
pool.setCorePoolSize(4);

// 动态调整最大线程数
pool.setMaximumPoolSize(8);

// 动态调整拒绝策略
pool.setRejectedExecutionHandler(new CallerRunsPolicy());

// 实战：根据监控指标动态调整
if (pool.getQueue().size() > threshold) {
    // 队列积压，增加线程数
    pool.setMaximumPoolSize(pool.getMaximumPoolSize() + 2);
}
```

### 线程池最佳实践

**1. 参数设置原则**

```java
// CPU 密集型任务
int cpuCount = Runtime.getRuntime().availableProcessors();
ThreadPoolExecutor pool = new ThreadPoolExecutor(
    cpuCount + 1,      // 核心线程数
    cpuCount + 1,      // 最大线程数
    0, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(100)
);

// IO 密集型任务
ThreadPoolExecutor pool = new ThreadPoolExecutor(
    cpuCount * 2,      // 核心线程数
    cpuCount * 2,      // 最大线程数
    60, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(1000)
);

// 混合型任务
// 根据 IO 等待时间占比调整
// 线程数 = CPU 核数 * (1 + IO 耗时 / CPU 耗时)
```

**2. 使用有界队列**
```java
// 错误：无界队列可能 OOM
new LinkedBlockingQueue<>();

// 正确：有界队列
new LinkedBlockingQueue<>(1000);
```

**3. 给线程池命名**
```java
ThreadFactory factory = new ThreadFactoryBuilder()
    .setNameFormat("my-pool-%d")
    .build();

ThreadPoolExecutor pool = new ThreadPoolExecutor(
    10, 20, 60, TimeUnit.SECONDS,
    new ArrayBlockingQueue<>(100),
    factory  // 自定义线程工厂
);

// 优点：方便问题排查
```

**4. 优雅关闭线程池**
```java
// 关闭线程池
pool.shutdown();  // 不接受新任务，等待已提交任务完成

// 等待终止
if (!pool.awaitTermination(60, TimeUnit.SECONDS)) {
    // 超时强制关闭
    pool.shutdownNow();
}
```

---

## 伪共享和缓存行填充 ⭐⭐⭐⭐⭐

### 什么是伪共享

**CPU 缓存层次**：
```
CPU Core 1                  CPU Core 2
├── L1 Cache (32KB)         ├── L1 Cache (32KB)
├── L2 Cache (256KB)        ├── L2 Cache (256KB)
└── L3 Cache (8MB, 共享) ←→ └── L3 Cache (8MB, 共享)
        ↑                           ↑
        └───────── 主内存 ───────────┘
```

**缓存行（Cache Line）**：
- CPU 缓存以缓存行为单位，通常 64 字节
- 读取变量时，会加载整个缓存行

**伪共享问题**：
```java
public class FalseSharing {
    volatile long x;  // 8 字节
    volatile long y;  // 8 字节，可能与 x 在同一缓存行
}

// 线程1 修改 x → 缓存行失效
// 线程2 读取 y → 必须从主内存重新加载
// 即使 x 和 y 无关，但在同一缓存行，相互影响
```

### 伪共享的危害

**性能测试**：
```java
// 无填充
public class NoPadding {
    volatile long x;
    volatile long y;
}

// 有填充
public class WithPadding {
    volatile long x;
    long p1, p2, p3, p4, p5, p6, p7;  // 填充 56 字节
    volatile long y;
}

// 测试结果（2 个线程，各自递增 x 和 y，1000 万次）
NoPadding:    1200ms
WithPadding:  300ms   // 性能提升 4 倍！
```

### 缓存行填充方案

**1. 手动填充（JDK 6/7）**
```java
public class Padded {
    long p1, p2, p3, p4, p5, p6, p7;  // 前填充 56 字节
    volatile long value;               // 实际值 8 字节
    long p9, p10, p11, p12, p13, p14, p15;  // 后填充 56 字节
}

// 总共 128 字节，独占 2 个缓存行
```

**2. 继承填充（Disruptor 方案）**
```java
class LhsPadding {
    protected long p1, p2, p3, p4, p5, p6, p7;
}

class Value extends LhsPadding {
    protected volatile long value;
}

class RhsPadding extends Value {
    protected long p9, p10, p11, p12, p13, p14, p15;
}

public class Sequence extends RhsPadding {
    // value 独占缓存行
}
```

**3. @Contended 注解（JDK 8+）**
```java
@sun.misc.Contended
public class Padded {
    volatile long value;
}

// 需要 JVM 参数：-XX:-RestrictContended
// JVM 自动填充
```

### 什么时候使用缓存行填充

**适用场景**：
- 多线程频繁修改不同变量
- 变量在内存中相邻
- 性能要求极高

**不适用场景**：
- 单线程
- 读多写少
- 内存敏感（填充增加内存占用）

**实战案例**：
```java
// 高性能计数器
public class HighPerfCounter {
    @Contended
    volatile long writeCount;  // 写计数

    @Contended
    volatile long readCount;   // 读计数

    public void write() {
        writeCount++;
    }

    public void read() {
        readCount++;
    }
}
```

---

## 性能分析工具 ⭐⭐⭐⭐

### JDK 自带工具

**1. jps（查看 Java 进程）**
```bash
jps -v

# 输出：
# 12345 MyApp -Xmx1g -Xms1g
```

**2. jstack（线程堆栈）**
```bash
jstack 12345 > thread.txt

# 分析死锁
jstack 12345 | grep -A 10 "deadlock"

# 分析 CPU 占用高的线程
# 1. 找到占 CPU 高的线程 ID
top -H -p 12345

# 2. 转换为 16 进制
printf "%x\n" 23456

# 3. 查找线程堆栈
jstack 12345 | grep 5ba0 -A 20
```

**常见问题排查**：
```java
// 1. 死锁
Found one Java-level deadlock:
"Thread-1":
  waiting to lock monitor 0x00007f8b4c004c00
  which is held by "Thread-2"

// 2. 线程阻塞
"pool-1-thread-1" waiting for monitor entry
  at com.example.MyClass.method()
  - locked <0x00007f8b4c123456>

// 3. 线程等待
"pool-1-thread-2" in Object.wait()
  at java.lang.Object.wait()
```

**3. jstat（GC 统计）**
```bash
# 查看 GC 统计
jstat -gc 12345 1000 10

# 输出：
# S0C    S1C    S0U    S1U      EC       EU        OC         OU       MC     MU
# 10240  10240   0     1024   81920    40960    204800    102400   51200  48000
```

**4. jmap（内存映像）**
```bash
# 堆内存快照
jmap -dump:format=b,file=heap.bin 12345

# 查看堆内存使用
jmap -heap 12345

# 查看对象统计
jmap -histo 12345 | head -20
```

### 可视化工具

**1. JConsole**
```bash
jconsole

# 功能：
# - 线程监控：死锁检测、线程状态
# - 内存监控：堆内存、非堆内存
# - GC 监控：GC 次数、耗时
```

**2. VisualVM**
```bash
jvisualvm

# 功能：
# - CPU 采样
# - 内存分析
# - 线程分析
# - 堆转储分析
```

**3. JProfiler / YourKit**
- 商业工具，功能更强大
- 支持远程监控
- 内存泄漏检测
- 热点方法分析

### 性能测试框架

**JMH（Java Microbenchmark Harness）**
```java
@BenchmarkMode(Mode.Throughput)
@OutputTimeUnit(TimeUnit.SECONDS)
@State(Scope.Thread)
public class ConcurrentBenchmark {

    private AtomicLong atomicLong = new AtomicLong(0);
    private LongAdder longAdder = new LongAdder();

    @Benchmark
    public void testAtomicLong() {
        atomicLong.incrementAndGet();
    }

    @Benchmark
    public void testLongAdder() {
        longAdder.increment();
    }

    public static void main(String[] args) {
        Options opt = new OptionsBuilder()
            .include(ConcurrentBenchmark.class.getSimpleName())
            .forks(1)
            .threads(64)
            .warmupIterations(3)
            .measurementIterations(5)
            .build();
        new Runner(opt).run();
    }
}

// 结果：
// Benchmark                            Mode  Cnt    Score   Error  Units
// ConcurrentBenchmark.testAtomicLong  thrpt    5   50.123 ± 2.345  ops/s
// ConcurrentBenchmark.testLongAdder   thrpt    5  300.456 ± 5.678  ops/s
```

### 性能优化检查清单

**1. 线程池优化**
- [ ] 参数是否合理？
- [ ] 队列是否有界？
- [ ] 是否有监控？
- [ ] 拒绝策略是否合适？

**2. 锁优化**
- [ ] 能否用无锁（CAS）替代？
- [ ] 锁粒度是否够小？
- [ ] 是否有锁竞争？

**3. 内存优化**
- [ ] 是否有伪共享？
- [ ] 是否有内存泄漏？
- [ ] 对象池是否合理？

**4. 算法优化**
- [ ] 能否减少同步？
- [ ] 能否并行计算？
- [ ] 能否异步处理？

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 线程池的核心参数有哪些？**
- corePoolSize：核心线程数
- maximumPoolSize：最大线程数
- keepAliveTime：非核心线程存活时间
- workQueue：工作队列
- handler：拒绝策略

**Q2: 线程池的执行流程？**
1. 核心线程未满 → 创建核心线程
2. 核心线程已满 → 任务入队
3. 队列已满 → 创建非核心线程
4. 线程数达最大值 → 执行拒绝策略

**Q3: 如何设置线程池参数？**
- CPU 密集型：核心线程数 = CPU 核数 + 1
- IO 密集型：核心线程数 = 2 * CPU 核数
- 混合型：线程数 = CPU 核数 * (1 + IO 耗时 / CPU 耗时)

**Q4: 什么是伪共享？**
- CPU 缓存以缓存行（64 字节）为单位
- 多个线程修改同一缓存行中的不同变量
- 导致缓存行频繁失效，性能下降

**Q5: 如何解决伪共享？**
- 手动填充：增加填充字段（56 字节）
- @Contended 注解（JDK 8+）
- 使变量独占缓存行

**Q6: 常用的性能分析工具？**
- jstack：线程堆栈、死锁检测
- jstat：GC 统计
- jmap：堆内存快照
- VisualVM：可视化监控

**Q7: 线程池的拒绝策略有哪些？**
- AbortPolicy：抛异常（默认）
- CallerRunsPolicy：调用者执行
- DiscardPolicy：丢弃任务
- DiscardOldestPolicy：丢弃最老任务

**Q8: 如何优雅关闭线程池？**
```java
pool.shutdown();  // 停止接收新任务
pool.awaitTermination(60, TimeUnit.SECONDS);  // 等待完成
pool.shutdownNow();  // 超时强制关闭
```

---

## 参考资料

1. **书籍推荐**：《Java 并发编程实战》、《Java 性能调优实战》
2. **JDK 文档**：ThreadPoolExecutor、@Contended
3. **工具文档**：JMH、VisualVM
4. **论文**：《False Sharing》- Martin Thompson
