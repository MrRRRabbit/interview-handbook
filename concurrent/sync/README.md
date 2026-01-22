# 传统同步机制

> synchronized 和 Lock 是 Java 并发编程的核心工具，理解它们的原理和使用场景是面试必备。

## synchronized 关键字 ⭐⭐⭐⭐⭐

### 三种使用方式

**1. 修饰实例方法**（锁当前对象）
```java
public synchronized void method() {
    // 等价于 synchronized(this)
}
```

**2. 修饰静态方法**（锁 Class 对象）
```java
public static synchronized void method() {
    // 等价于 synchronized(Demo.class)
}
```

**3. 修饰代码块**（锁指定对象）
```java
public void method() {
    synchronized (lock) {
        // 临界区
    }
}
```

### synchronized 原理 ⭐⭐⭐⭐⭐

**底层实现**：
- 修饰代码块：`monitorenter` 和 `monitorexit` 指令
- 修饰方法：`ACC_SYNCHRONIZED` 标志

**对象头**：
```
Java 对象内存布局：
┌──────────────┬──────────┬──────────┐
│  对象头       │ 实例数据  │ 对齐填充  │
└──────────────┴──────────┴──────────┘

对象头包含：
- Mark Word（存储锁信息、GC 年龄等）
- Class Pointer（指向类元数据）
```

**Mark Word 锁状态**：
| 锁状态 | 存储内容 | 标志位 |
|--------|---------|--------|
| 无锁 | hashCode、GC 年龄 | 01 |
| 偏向锁 | 线程 ID、epoch | 01 |
| 轻量级锁 | 指向栈中锁记录的指针 | 00 |
| 重量级锁 | 指向 Monitor 的指针 | 10 |

### 锁升级过程 ⭐⭐⭐⭐⭐

**偏向锁 → 轻量级锁 → 重量级锁**

```
1. 偏向锁（无竞争）
   - 第一次获取锁，记录线程 ID
   - 同一线程再次获取，无需 CAS

2. 轻量级锁（轻度竞争）
   - 其他线程竞争，升级为轻量级锁
   - 使用 CAS 自旋获取锁

3. 重量级锁（激烈竞争）
   - 自旋失败，升级为重量级锁
   - 阻塞等待（操作系统互斥量）
```

**示例**：
```java
Object lock = new Object();

// 线程1 第一次获取锁 → 偏向锁
synchronized (lock) {
    // 线程1 再次获取 → 直接进入（偏向锁）
}

// 线程2 竞争 → 升级为轻量级锁
synchronized (lock) {
    // CAS 自旋
}

// 多线程激烈竞争 → 升级为重量级锁
```

---

## ReentrantLock ⭐⭐⭐⭐⭐

### 基本使用

```java
private Lock lock = new ReentrantLock();

public void method() {
    lock.lock(); // 加锁
    try {
        // 临界区
    } finally {
        lock.unlock(); // 必须在 finally 中释放锁
    }
}
```

### ReentrantLock vs synchronized

| 特性 | synchronized | ReentrantLock |
|------|--------------|---------------|
| **锁类型** | JVM 内置锁 | API 层面锁 |
| **灵活性** | 低（自动释放） | 高（手动释放） |
| **公平锁** | 非公平锁 | 可选公平/非公平 |
| **可中断** | ❌ 不可中断 | ✅ `lockInterruptibly()` |
| **尝试获取锁** | ❌ 不支持 | ✅ `tryLock()` |
| **条件队列** | 1 个（wait/notify） | 多个（Condition） |
| **性能** | JDK 6+ 优化后相当 | 相当 |
| **使用场景** | 简单同步 | 需要高级特性 |

### ReentrantLock 高级特性

**1. 公平锁 vs 非公平锁**
```java
// 公平锁：按请求顺序获取锁
Lock lock = new ReentrantLock(true);

// 非公平锁（默认）：允许插队，性能更好
Lock lock = new ReentrantLock(false);
```

**2. 可中断锁**
```java
lock.lockInterruptibly(); // 可响应中断
try {
    // 临界区
} finally {
    lock.unlock();
}
```

**3. 尝试获取锁**
```java
if (lock.tryLock()) { // 立即返回
    try {
        // 获取锁成功
    } finally {
        lock.unlock();
    }
} else {
    // 获取锁失败
}

// 超时尝试
if (lock.tryLock(1, TimeUnit.SECONDS)) {
    // ...
}
```

---

## ReadWriteLock ⭐⭐⭐⭐

### 读写锁原理

**特点**：
- **读锁（共享锁）**：多个线程可同时持有
- **写锁（排他锁）**：只能一个线程持有，且阻塞读锁

```
场景：读多写少
不使用读写锁：读和写互斥，性能差
使用读写锁：读读并发，写写互斥，写读互斥
```

### 基本使用

```java
private ReadWriteLock rwLock = new ReentrantReadWriteLock();
private Lock readLock = rwLock.readLock();
private Lock writeLock = rwLock.writeLock();

// 读操作
public String read() {
    readLock.lock();
    try {
        return data; // 多个线程可并发读取
    } finally {
        readLock.unlock();
    }
}

// 写操作
public void write(String value) {
    writeLock.lock();
    try {
        data = value; // 独占写入
    } finally {
        writeLock.unlock();
    }
}
```

### 锁降级

```java
writeLock.lock();
try {
    // 更新数据
    data = newData;

    // 锁降级：先获取读锁
    readLock.lock();
} finally {
    writeLock.unlock(); // 释放写锁
}

try {
    // 使用数据（持有读锁）
    return process(data);
} finally {
    readLock.unlock();
}
```

---

## 线程协作工具 ⭐⭐⭐⭐⭐

### wait/notify（Object 方法）

**注意**：必须在 synchronized 块中使用

```java
synchronized (lock) {
    while (条件不满足) {
        lock.wait(); // 释放锁，等待
    }
    // 条件满足，继续执行
}

synchronized (lock) {
    // 修改条件
    lock.notify(); // 唤醒一个等待线程
    lock.notifyAll(); // 唤醒所有等待线程
}
```

**生产者-消费者示例**：
```java
class Queue {
    private List<Integer> list = new ArrayList<>();
    private int capacity = 10;

    public synchronized void produce(int value) throws InterruptedException {
        while (list.size() == capacity) {
            wait(); // 队列满，等待
        }
        list.add(value);
        notifyAll(); // 唤醒消费者
    }

    public synchronized int consume() throws InterruptedException {
        while (list.isEmpty()) {
            wait(); // 队列空，等待
        }
        int value = list.remove(0);
        notifyAll(); // 唤醒生产者
        return value;
    }
}
```

### Condition（Lock 的等待/通知）

**优势**：支持多个条件队列

```java
private Lock lock = new ReentrantLock();
private Condition notFull = lock.newCondition();
private Condition notEmpty = lock.newCondition();

public void produce(int value) throws InterruptedException {
    lock.lock();
    try {
        while (list.size() == capacity) {
            notFull.await(); // 等待非满条件
        }
        list.add(value);
        notEmpty.signal(); // 通知消费者
    } finally {
        lock.unlock();
    }
}

public int consume() throws InterruptedException {
    lock.lock();
    try {
        while (list.isEmpty()) {
            notEmpty.await(); // 等待非空条件
        }
        int value = list.remove(0);
        notFull.signal(); // 通知生产者
        return value;
    } finally {
        lock.unlock();
    }
}
```

---

## 并发工具类 ⭐⭐⭐⭐

### CountDownLatch（倒计数门闩）

**用途**：等待多个线程完成

```java
CountDownLatch latch = new CountDownLatch(3);

// 3 个工作线程
for (int i = 0; i < 3; i++) {
    new Thread(() -> {
        System.out.println("任务完成");
        latch.countDown(); // 计数减1
    }).start();
}

// 主线程等待
latch.await(); // 等待计数为0
System.out.println("所有任务完成");
```

### CyclicBarrier（循环屏障）

**用途**：多个线程相互等待，到达屏障后一起执行

```java
CyclicBarrier barrier = new CyclicBarrier(3, () -> {
    System.out.println("所有线程到达屏障");
});

for (int i = 0; i < 3; i++) {
    new Thread(() -> {
        System.out.println("到达屏障");
        barrier.await(); // 等待其他线程
        System.out.println("继续执行");
    }).start();
}
```

**CountDownLatch vs CyclicBarrier**：
- CountDownLatch：一次性，计数不可重置
- CyclicBarrier：可重复使用，适合循环任务

### Semaphore（信号量）

**用途**：控制同时访问资源的线程数

```java
Semaphore semaphore = new Semaphore(3); // 最多3个线程

for (int i = 0; i < 10; i++) {
    new Thread(() -> {
        semaphore.acquire(); // 获取许可
        try {
            System.out.println("访问资源");
            Thread.sleep(1000);
        } finally {
            semaphore.release(); // 释放许可
        }
    }).start();
}
```

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: synchronized 和 ReentrantLock 的区别？**
- synchronized 是 JVM 层面，ReentrantLock 是 API 层面
- ReentrantLock 支持公平锁、可中断、tryLock
- synchronized 简单，ReentrantLock 灵活

**Q2: synchronized 的锁升级过程？**
- 偏向锁 → 轻量级锁 → 重量级锁
- 减少锁竞争时的性能开销

**Q3: wait() 和 sleep() 的区别？**
- wait() 释放锁，sleep() 不释放锁
- wait() 是 Object 方法，sleep() 是 Thread 方法
- wait() 需要在 synchronized 中使用

**Q4: 什么时候使用 ReadWriteLock？**
- 读多写少的场景
- 读操作并发，提升性能

**Q5: CountDownLatch 和 CyclicBarrier 的区别？**
- CountDownLatch 一次性，CyclicBarrier 可重复使用
- CountDownLatch 主线程等待工作线程，CyclicBarrier 工作线程相互等待

**Q6: 公平锁和非公平锁的区别？**
- 公平锁按请求顺序获取，非公平锁允许插队
- 非公平锁性能更好，但可能导致线程饥饿

---

## 参考资料

1. **书籍推荐**：《Java 并发编程实战》、《Java 并发编程的艺术》
2. **源码**：java.util.concurrent 包
