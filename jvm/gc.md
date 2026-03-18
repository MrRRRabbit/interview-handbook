# JVM 垃圾回收机制

## 核心概念

垃圾回收（Garbage Collection）是 JVM 自动内存管理的核心机制。理解 GC 原理是 JVM 调优和面试的重中之重。

## 垃圾判定算法

### 1. 引用计数法（Reference Counting）

- 每个对象维护一个引用计数器
- 有引用指向时 +1，引用失效时 -1
- 计数为 0 时可回收

**缺陷**：无法解决**循环引用**问题

```java
// 循环引用示例
public class CircularReferenceDemo {
    Object instance = null;

    public static void main(String[] args) {
        CircularReferenceDemo a = new CircularReferenceDemo();
        CircularReferenceDemo b = new CircularReferenceDemo();
        a.instance = b;
        b.instance = a;
        a = null;
        b = null;
        // 引用计数法无法回收 a 和 b 指向的对象
        System.gc();
    }
}
```

### 2. 可达性分析（Reachability Analysis）⭐

JVM 实际使用的算法。从 **GC Roots** 出发，能到达的对象为存活对象。

#### GC Roots 包括

1. **虚拟机栈中引用的对象**（局部变量）
2. **方法区中类静态属性引用的对象**（static 字段）
3. **方法区中常量引用的对象**（final static 字段）
4. **本地方法栈中 JNI 引用的对象**
5. **JVM 内部引用**（基本类型的 Class 对象、常驻异常对象等）
6. **被同步锁（synchronized）持有的对象**

### 四种引用类型

```java
// 1. 强引用 - 不会被回收
Object obj = new Object();

// 2. 软引用 - 内存不足时回收（适合做缓存）
SoftReference<Object> softRef = new SoftReference<>(new Object());

// 3. 弱引用 - 下次 GC 时回收
WeakReference<Object> weakRef = new WeakReference<>(new Object());

// 4. 虚引用 - 无法通过虚引用获取对象，用于跟踪回收活动
PhantomReference<Object> phantomRef =
    new PhantomReference<>(new Object(), new ReferenceQueue<>());
```

| 引用类型 | 回收时机 | 典型应用 |
|---------|---------|---------|
| 强引用 | 不回收 | 普通对象引用 |
| 软引用 | 内存不足时 | 缓存 |
| 弱引用 | 下次 GC | WeakHashMap、ThreadLocal |
| 虚引用 | 随时 | 堆外内存管理、回收跟踪 |

### finalize() 方法

- 对象被判定不可达后，会检查是否覆盖了 `finalize()`
- 如果覆盖且未执行过，放入 F-Queue 队列，由 Finalizer 线程执行
- **不推荐使用**：执行时机不确定，可能导致对象"复活"
- JDK 9 起已被标记为 `@Deprecated`

## 垃圾回收算法

### 1. 标记-清除（Mark-Sweep）

```
标记前:  [A] [B] [C] [D] [E] [F]
标记后:  [A] [×] [C] [×] [E] [×]   ← 标记不可达对象
清除后:  [A] [_] [C] [_] [E] [_]   ← 直接清除
```

- **优点**：实现简单
- **缺点**：产生**内存碎片**，分配大对象时可能触发提前 GC

### 2. 标记-复制（Mark-Copy）

```
From:    [A] [×] [C] [×] [E]
                  ↓ 复制存活对象
To:      [A] [C] [E] [_] [_]
```

- **优点**：无内存碎片，分配速度快（指针碰撞）
- **缺点**：可用内存减半
- **应用**：新生代（Eden + S0 → S1）

### 3. 标记-整理（Mark-Compact）

```
标记后:  [A] [_] [C] [_] [E] [_]
整理后:  [A] [C] [E] [_] [_] [_]   ← 向一端移动
```

- **优点**：无内存碎片
- **缺点**：需要移动对象，开销较大
- **应用**：老年代

### 4. 分代收集（Generational Collection）

```
                   对象分配
                      ↓
┌────────────────────────────────────┐
│  新生代 (Young Generation)         │ ← Minor GC（频繁、速度快）
│  Eden → S0/S1（标记-复制算法）      │    对象年龄 +1，达到阈值晋升
├────────────────────────────────────┤
│  老年代 (Old Generation)           │ ← Major GC / Full GC（较慢）
│  （标记-清除 或 标记-整理）          │
└────────────────────────────────────┘
```

#### 对象晋升老年代的条件

1. **年龄达到阈值**：默认 15 次 Minor GC（`-XX:MaxTenuringThreshold`）
2. **大对象直接进入老年代**：`-XX:PretenureSizeThreshold`
3. **动态年龄判断**：Survivor 中相同年龄对象大小总和 > Survivor 空间一半
4. **Survivor 空间不足**：Minor GC 后存活对象放不下

## 垃圾收集器

### 收集器总览

```
         新生代                        老年代
┌──────────────────┐        ┌──────────────────────┐
│  Serial           │───────▶│  Serial Old           │
│  ParNew           │───────▶│  CMS                  │
│  Parallel Scavenge│───────▶│  Parallel Old         │
└──────────────────┘        └──────────────────────┘

       整堆收集器
┌──────────────────────────────────────────────────┐
│  G1                                               │
│  ZGC                                              │
│  Shenandoah                                       │
└──────────────────────────────────────────────────┘
```

### Serial / Serial Old

- **单线程**收集器
- 收集时必须 **Stop The World (STW)**
- 适合：客户端模式、小内存应用

```bash
-XX:+UseSerialGC
```

### ParNew

- Serial 的**多线程**版本
- 常与 CMS 配合使用
- 除了多线程外和 Serial 几乎一样

```bash
-XX:+UseParNewGC
-XX:ParallelGCThreads=4
```

### Parallel Scavenge / Parallel Old

- **吞吐量优先**收集器
- 自适应调节策略：`-XX:+UseAdaptiveSizePolicy`
- JDK 8 默认收集器

```bash
-XX:+UseParallelGC
-XX:MaxGCPauseMillis=200    # 最大停顿时间目标
-XX:GCTimeRatio=99          # 吞吐量目标（GC 时间占比 1%）
```

### CMS（Concurrent Mark Sweep）⭐⭐⭐⭐⭐

以**最短停顿时间**为目标的收集器，使用**标记-清除**算法。

#### 四个阶段

```
1. 初始标记 (Initial Mark)     ← STW，仅标记 GC Roots 直接关联的对象，速度快
2. 并发标记 (Concurrent Mark)  ← 与用户线程并发，遍历对象图
3. 重新标记 (Remark)           ← STW，修正并发标记期间变动的引用
4. 并发清除 (Concurrent Sweep) ← 与用户线程并发，清除垃圾对象
```

#### 缺点

1. **CPU 敏感**：并发阶段占用 CPU 资源
2. **浮动垃圾**：并发清除阶段新产生的垃圾需下次 GC 处理
3. **内存碎片**：标记-清除算法导致碎片
4. **Concurrent Mode Failure**：预留内存不足时退化为 Serial Old

```bash
-XX:+UseConcMarkSweepGC
-XX:CMSInitiatingOccupancyFraction=75  # 触发 CMS 的老年代使用率
-XX:+UseCMSCompactAtFullCollection     # Full GC 后整理碎片
```

### G1（Garbage First）⭐⭐⭐⭐⭐

面向服务端的收集器，JDK 9 起成为默认收集器。

#### 核心设计

```
┌───┬───┬───┬───┬───┬───┬───┬───┐
│ E │ O │ S │ E │ H │ O │ E │ S │  ← Region 划分
├───┼───┼───┼───┼───┼───┼───┼───┤
│ O │   │ E │ O │ H │ E │   │ O │  E=Eden S=Survivor
├───┼───┼───┼───┼───┼───┼───┼───┤  O=Old  H=Humongous
│ E │ O │   │ S │ O │   │ E │ O │
└───┴───┴───┴───┴───┴───┴───┴───┘
```

- **Region**：堆被划分为大小相等的 Region（1MB-32MB）
- **Humongous Region**：存放大对象（超过 Region 50%）
- **Remembered Set**：记录跨 Region 引用，避免全堆扫描
- **Collection Set (CSet)**：每次 GC 选择回收价值最高的 Region

#### 回收过程

1. **Young GC**：回收所有 Eden 和 Survivor Region
2. **并发标记**：类似 CMS，与用户线程并发
3. **混合回收（Mixed GC）**：回收 Young + 部分 Old Region（优先回收垃圾最多的）

#### 停顿预测模型

- 记录每个 Region 的回收耗时和垃圾比例
- 在 `-XX:MaxGCPauseMillis` 约束内选择回收收益最大的 Region

```bash
-XX:+UseG1GC
-XX:MaxGCPauseMillis=200        # 停顿时间目标
-XX:G1HeapRegionSize=4m         # Region 大小
-XX:InitiatingHeapOccupancyPercent=45  # 触发并发标记的堆占用率
```

### ZGC ⭐⭐⭐⭐

超低延迟收集器，停顿时间不超过 **1ms**。

#### 核心技术

- **着色指针（Colored Pointers）**：在指针中存储 GC 元数据
- **读屏障（Load Barrier）**：在对象引用被读取时检查并修正
- **并发处理**：几乎所有阶段都与用户线程并发

```bash
-XX:+UseZGC
-XX:SoftMaxHeapSize=4g   # 软性堆大小上限
```

#### 适用场景

- 超大堆（TB 级别）
- 对延迟极其敏感的应用
- JDK 15+ 生产可用

### Shenandoah

- 与 ZGC 类似的低延迟收集器
- 使用**转发指针（Brooks Pointer）** 实现并发整理
- OpenJDK 项目，非 Oracle JDK

## GC 日志分析

### 开启 GC 日志

```bash
# JDK 8
-XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:gc.log

# JDK 9+（统一日志框架）
-Xlog:gc*:file=gc.log:time,uptime,level,tags
```

### G1 GC 日志示例

```
[2026-03-18T10:15:30.123+0800] GC(12) Pause Young (Normal) (G1 Evacuation Pause)
[2026-03-18T10:15:30.123+0800] GC(12)   Eden regions: 24->0(24)
[2026-03-18T10:15:30.123+0800] GC(12)   Survivor regions: 3->3(4)
[2026-03-18T10:15:30.123+0800] GC(12)   Old regions: 10->12
[2026-03-18T10:15:30.123+0800] GC(12)   Humongous regions: 0->0
[2026-03-18T10:15:30.123+0800] GC(12) Pause Young (Normal) 37M->15M(256M) 8.234ms
```

关键指标：
- **回收前后堆大小**：37M -> 15M
- **停顿时间**：8.234ms
- **各区域变化**：Eden 24->0，Old 10->12

## 面试要点

### 高频问题

1. **如何判断对象是否可以被回收？**
   - 可达性分析，从 GC Roots 出发不可达的对象

2. **CMS 和 G1 的区别？**
   - CMS 用标记-清除，G1 用标记-复制/整理
   - CMS 只收集老年代，G1 整堆收集
   - G1 可预测停顿时间，CMS 不可以
   - G1 无内存碎片问题

3. **Minor GC、Major GC、Full GC 的区别？**
   - Minor GC：只回收新生代
   - Major GC：只回收老年代（常与 Full GC 混用）
   - Full GC：回收整个堆 + 方法区

4. **什么时候触发 Full GC？**
   - 老年代空间不足
   - 方法区空间不足
   - 调用 `System.gc()`（建议，不保证）
   - CMS Concurrent Mode Failure
   - 晋升失败（Promotion Failed）

5. **如何选择垃圾收集器？**
   - 延迟敏感 → G1 / ZGC
   - 吞吐量优先 → Parallel Scavenge
   - 小内存（< 100MB）→ Serial
   - 大堆 + 超低延迟 → ZGC

### 常见陷阱

- `System.gc()` 只是建议 JVM 做 GC，不保证执行
- Minor GC 并不只回收 Eden，也包括 Survivor
- G1 并不是完全无停顿，只是停顿时间可控

## 参考资料

- 《深入理解 Java 虚拟机》第 3 章 - 周志明
- [HotSpot Virtual Machine Garbage Collection Tuning Guide](https://docs.oracle.com/en/java/javase/17/gctuning/)
- [JEP 333: ZGC: A Scalable Low-Latency Garbage Collector](https://openjdk.org/jeps/333)
