# 并发编程基础理论

> 理解 Java 内存模型和并发三大特性是掌握并发编程的基础，也是面试必考内容。

## 并发三大特性 ⭐⭐⭐⭐⭐

### 1. 原子性（Atomicity）

**定义**：一个或多个操作要么全部执行成功，要么全部不执行。

**问题示例**：
```java
// i++ 不是原子操作
private int count = 0;

public void increment() {
    count++; // 分为三步：读取、+1、写回
}

// 多线程执行可能丢失更新
Thread1: 读取 count=0
Thread2: 读取 count=0
Thread1: count+1=1，写回
Thread2: count+1=1，写回
// 结果：count=1（预期应该是2）
```

**解决方案**：
```java
// 方案1：synchronized
public synchronized void increment() {
    count++;
}

// 方案2：AtomicInteger
private AtomicInteger count = new AtomicInteger(0);
public void increment() {
    count.incrementAndGet();
}

// 方案3：Lock
private Lock lock = new ReentrantLock();
public void increment() {
    lock.lock();
    try {
        count++;
    } finally {
        lock.unlock();
    }
}
```

### 2. 可见性（Visibility）

**定义**：一个线程修改了共享变量，其他线程能立即看到最新值。

**问题根源**：CPU 缓存导致的可见性问题
```
CPU1 缓存: count = 0
CPU2 缓存: count = 0
主内存:    count = 0

CPU1 修改: count = 1 (仅写入 CPU1 缓存)
CPU2 读取: count = 0 (从 CPU2 缓存读取，看不到最新值)
```

**示例**：
```java
public class VisibilityDemo {
    private boolean flag = false; // 没有 volatile

    // 线程1
    public void writer() {
        flag = true; // 可能只写入 CPU 缓存
    }

    // 线程2
    public void reader() {
        while (!flag) {
            // 可能一直读取旧值，死循环
        }
        System.out.println("Flag changed!");
    }
}
```

**解决方案**：
```java
// 方案1：volatile
private volatile boolean flag = false;

// 方案2：synchronized
private boolean flag = false;
public synchronized void setFlag(boolean value) {
    flag = value;
}
public synchronized boolean getFlag() {
    return flag;
}

// 方案3：final（构造后不可变）
private final int value = 10;
```

### 3. 有序性（Ordering）

**定义**：程序执行的顺序按照代码的先后顺序执行。

**问题根源**：指令重排序
```java
// 单例模式的双重检查锁问题
public class Singleton {
    private static Singleton instance;

    public static Singleton getInstance() {
        if (instance == null) { // 1
            synchronized (Singleton.class) {
                if (instance == null) { // 2
                    instance = new Singleton(); // 3
                }
            }
        }
        return instance;
    }
}

// 问题：第3步可能被重排序为：
// 3.1 分配内存
// 3.2 instance 指向内存（此时对象还未初始化）
// 3.3 初始化对象
// 如果重排序为 3.1 → 3.2 → 3.3，其他线程可能看到未初始化的对象
```

**解决方案**：
```java
// 使用 volatile 禁止重排序
private static volatile Singleton instance;
```

---

## Java 内存模型（JMM）⭐⭐⭐⭐⭐

### JMM 定义

Java 内存模型规定了：
- **所有变量存储在主内存**
- **每个线程有自己的工作内存**（CPU 缓存的抽象）
- **线程对变量的操作必须在工作内存中进行**

```
线程1 工作内存          主内存          线程2 工作内存
┌──────────┐         ┌──────────┐      ┌──────────┐
│ count=0  │ ◄─读取─ │ count=0  │ ─读取─► │ count=0  │
│ count=1  │ ─写回─► │ count=1  │ ◄─写回─ │ count=1  │
└──────────┘         └──────────┘      └──────────┘
```

### JMM 的八种操作

| 操作 | 说明 |
|------|------|
| **lock** | 锁定主内存变量 |
| **unlock** | 解锁主内存变量 |
| **read** | 从主内存读取变量到工作内存 |
| **load** | 将 read 的值放入工作内存的变量副本 |
| **use** | 将工作内存变量值传给执行引擎 |
| **assign** | 将执行引擎的值赋给工作内存变量 |
| **store** | 将工作内存变量值传到主内存 |
| **write** | 将 store 的值写入主内存变量 |

---

## happens-before 原则 ⭐⭐⭐⭐⭐

**定义**：如果操作 A happens-before 操作 B，则 A 的结果对 B 可见。

### 8 大原则

**1. 程序顺序规则**
```java
int a = 1; // 操作1
int b = 2; // 操作2
// 操作1 happens-before 操作2（单线程内）
```

**2. volatile 变量规则**
```java
volatile boolean flag = false;

// 线程1
flag = true; // 写操作

// 线程2
if (flag) { // 读操作
    // 能看到 flag=true
}
// volatile 写 happens-before volatile 读
```

**3. 锁规则**
```java
synchronized (lock) {
    // 临界区1
} // 解锁

synchronized (lock) {
    // 临界区2
} // 能看到临界区1的修改
// 解锁 happens-before 加锁
```

**4. 线程启动规则**
```java
int x = 10;
Thread t = new Thread(() -> {
    // 能看到 x=10
});
t.start();
// start() 之前的操作 happens-before 线程内的操作
```

**5. 线程终止规则**
```java
Thread t = new Thread(() -> {
    x = 20;
});
t.start();
t.join();
System.out.println(x); // 能看到 x=20
// 线程内操作 happens-before join() 返回
```

**6. 中断规则**
```java
thread.interrupt(); // happens-before 检测到中断
```

**7. 对象终结规则**
```java
// 构造函数 happens-before finalize()
```

**8. 传递性**
```java
// A happens-before B, B happens-before C
// 则 A happens-before C
```

---

## volatile 关键字 ⭐⭐⭐⭐⭐

### 两大特性

**1. 保证可见性**
```java
volatile boolean flag = false;

// 线程1 修改 flag
flag = true; // 立即刷新到主内存

// 线程2 读取 flag
if (flag) { // 从主内存读取最新值
    // ...
}
```

**2. 禁止指令重排序**
```java
// DCL 单例模式
private static volatile Singleton instance;

public static Singleton getInstance() {
    if (instance == null) {
        synchronized (Singleton.class) {
            if (instance == null) {
                // volatile 保证这三步不会重排序
                instance = new Singleton();
            }
        }
    }
    return instance;
}
```

### volatile vs synchronized

| 特性 | volatile | synchronized |
|------|----------|--------------|
| **原子性** | ❌ 不保证 | ✅ 保证 |
| **可见性** | ✅ 保证 | ✅ 保证 |
| **有序性** | ✅ 禁止重排序 | ✅ 保证 |
| **性能** | 高（无锁） | 低（加锁） |
| **适用场景** | 状态标志、双重检查锁 | 复合操作、临界区 |

### volatile 使用场景

**场景1：状态标志**
```java
volatile boolean running = true;

public void run() {
    while (running) {
        // 工作
    }
}

public void stop() {
    running = false; // 其他线程立即可见
}
```

**场景2：双重检查锁（DCL）**
```java
private static volatile Singleton instance;
```

**场景3：读多写少的场景**
```java
public class Config {
    private volatile Map<String, String> config = new HashMap<>();

    public String get(String key) {
        return config.get(key); // 无锁读取
    }

    public synchronized void update(Map<String, String> newConfig) {
        this.config = newConfig; // 加锁写入
    }
}
```

### volatile 不适用场景

**不保证原子性**：
```java
volatile int count = 0;

public void increment() {
    count++; // 不是原子操作，多线程不安全！
}

// 应该使用 AtomicInteger
AtomicInteger count = new AtomicInteger(0);
count.incrementAndGet();
```

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 并发三大特性是什么？**
- 原子性：操作不可分割
- 可见性：修改对其他线程可见
- 有序性：禁止指令重排序

**Q2: volatile 能保证原子性吗？**
- 不能，volatile 只保证可见性和有序性
- count++ 不是原子操作，需要 synchronized 或 AtomicInteger

**Q3: happens-before 的作用是什么？**
- 定义了操作之间的可见性关系
- 如果 A happens-before B，则 A 的结果对 B 可见

**Q4: 为什么 DCL 单例需要 volatile？**
- 防止指令重排序
- new Singleton() 可能重排序为：分配内存 → 赋值引用 → 初始化对象
- 其他线程可能看到未初始化的对象

**Q5: volatile 和 synchronized 的区别？**
- volatile 不保证原子性，synchronized 保证
- volatile 性能更好（无锁）
- volatile 适合状态标志，synchronized 适合复合操作

**Q6: JMM 是什么？**
- Java 内存模型，规定了线程和主内存的交互规则
- 线程有自己的工作内存，变量存储在主内存
- 解决了多线程并发访问的可见性和有序性问题

**Q7: 如何保证可见性？**
- volatile
- synchronized
- final
- happens-before 原则

---

## 参考资料

1. **书籍推荐**：《Java 并发编程的艺术》、《深入理解 Java 虚拟机》
2. **JMM 规范**：JSR-133
3. **Doug Lea 论文**：《The Java Memory Model》
