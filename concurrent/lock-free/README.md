# 无锁编程核心

> CAS 和原子类是 Java 无锁编程的基石，理解其原理和使用场景是面试必考内容。

## CAS 原理 ⭐⭐⭐⭐⭐

### 什么是 CAS

**CAS（Compare-And-Swap）** 是一种乐观锁机制，实现无锁并发控制。

**三个操作数**：
- **V（内存地址）**：要更新的变量
- **E（预期值）**：期望的旧值
- **N（新值）**：要设置的新值

**执行逻辑**：
```java
// 伪代码
boolean compareAndSwap(V, E, N) {
    if (V == E) {
        V = N;
        return true;
    }
    return false;
}
```

### CAS 底层实现

**硬件层面**：
```java
// Java 层面
public final boolean compareAndSet(int expect, int update) {
    return unsafe.compareAndSwapInt(this, valueOffset, expect, update);
}

// 底层调用 CPU 指令
// x86: LOCK CMPXCHG
// ARM: LDREX/STREX
```

**内存屏障**：
```
CAS 操作具有 volatile 读写的内存语义
- 读操作：LoadLoad + LoadStore 屏障
- 写操作：StoreStore + StoreLoad 屏障
```

### CAS 使用示例

**线程安全的计数器**：
```java
public class CASCounter {
    private AtomicInteger count = new AtomicInteger(0);

    public void increment() {
        int oldValue;
        int newValue;
        do {
            oldValue = count.get();
            newValue = oldValue + 1;
        } while (!count.compareAndSet(oldValue, newValue));
    }

    public int get() {
        return count.get();
    }
}
```

**自旋锁实现**：
```java
public class SpinLock {
    private AtomicReference<Thread> owner = new AtomicReference<>();

    public void lock() {
        Thread current = Thread.currentThread();
        // 自旋等待，直到 CAS 成功
        while (!owner.compareAndSet(null, current)) {
            // 自旋
        }
    }

    public void unlock() {
        Thread current = Thread.currentThread();
        owner.compareAndSet(current, null);
    }
}
```

### CAS vs 锁

| 特性 | CAS | synchronized/Lock |
|------|-----|-------------------|
| **阻塞** | 非阻塞（自旋） | 阻塞（等待队列） |
| **上下文切换** | 无 | 有 |
| **适用场景** | 低竞争、操作简单 | 高竞争、复杂操作 |
| **性能** | 高（低竞争时） | 低（需加锁） |
| **公平性** | 不公平 | 可配置 |
| **问题** | ABA、自旋开销 | 死锁、性能差 |

---

## ABA 问题 ⭐⭐⭐⭐⭐

### 问题描述

**场景**：线程 T1 读取值 A，准备 CAS 更新；线程 T2 将 A 改为 B，再改回 A；T1 的 CAS 成功，但中间状态已改变。

```java
// 栈的 ABA 问题
class Stack {
    AtomicReference<Node> top = new AtomicReference<>();

    void push(int value) {
        Node newNode = new Node(value);
        Node oldTop;
        do {
            oldTop = top.get();
            newNode.next = oldTop;
        } while (!top.compareAndSet(oldTop, newNode));
    }

    Node pop() {
        Node oldTop;
        Node newTop;
        do {
            oldTop = top.get();
            if (oldTop == null) return null;
            newTop = oldTop.next;
        } while (!top.compareAndSet(oldTop, newTop));
        return oldTop;
    }
}

// ABA 问题场景
// 线程1：读取 top = A
// 线程2：pop(A) → pop(B) → push(A)
// 线程1：CAS(A, B) 成功，但 A 已经是新对象！
```

**危害**：
- 栈结构被破坏
- 内存泄漏
- 数据不一致

### 解决方案

**1. 版本号（AtomicStampedReference）**

```java
// 带版本号的引用
AtomicStampedReference<Integer> asr = new AtomicStampedReference<>(100, 0);

// 线程1：读取值和版本号
int[] stamp = new int[1];
Integer value = asr.get(stamp);
int version = stamp[0];

// 线程2：修改值，版本号+1
asr.compareAndSet(100, 200, 0, 1);
asr.compareAndSet(200, 100, 1, 2);

// 线程1：CAS 失败，因为版本号不匹配
asr.compareAndSet(value, 200, version, version + 1); // false
```

**完整示例**：
```java
public class ABADemo {
    static AtomicStampedReference<Integer> asr =
        new AtomicStampedReference<>(100, 0);

    public static void main(String[] args) {
        // 线程1：读取初始值
        new Thread(() -> {
            int[] stamp = new int[1];
            Integer value = asr.get(stamp);
            System.out.println("Thread1 读取: value=" + value + ", stamp=" + stamp[0]);

            try {
                Thread.sleep(1000); // 模拟延迟
            } catch (InterruptedException e) {}

            // 尝试 CAS
            boolean success = asr.compareAndSet(value, 200, stamp[0], stamp[0] + 1);
            System.out.println("Thread1 CAS: " + success); // false
        }).start();

        // 线程2：制造 ABA
        new Thread(() -> {
            int[] stamp = new int[1];
            Integer value = asr.get(stamp);

            // A -> B
            asr.compareAndSet(value, 200, stamp[0], stamp[0] + 1);
            System.out.println("Thread2 修改为 200");

            value = asr.get(stamp);
            // B -> A
            asr.compareAndSet(value, 100, stamp[0], stamp[0] + 1);
            System.out.println("Thread2 修改回 100");
        }).start();
    }
}
```

**2. 标记位（AtomicMarkableReference）**

```java
// 只关心是否被修改过，不关心修改次数
AtomicMarkableReference<Integer> amr = new AtomicMarkableReference<>(100, false);

// 检查是否被标记
boolean[] marked = new boolean[1];
Integer value = amr.get(marked);

if (!marked[0]) {
    amr.compareAndSet(value, 200, false, true);
}
```

---

## Atomic 原子类 ⭐⭐⭐⭐⭐

### 基本类型原子类

**AtomicInteger / AtomicLong / AtomicBoolean**

```java
AtomicInteger ai = new AtomicInteger(0);

// 常用方法
int get();                          // 获取当前值
void set(int newValue);             // 设置新值
int getAndSet(int newValue);        // 获取旧值并设置新值
int getAndIncrement();              // i++
int incrementAndGet();              // ++i
int getAndAdd(int delta);           // i += delta
int addAndGet(int delta);           // i += delta，返回新值
boolean compareAndSet(int expect, int update);  // CAS

// 示例
ai.incrementAndGet();               // 线程安全的 i++
ai.compareAndSet(10, 20);           // 如果当前值是 10，则改为 20
```

**性能对比**：
```java
// synchronized 方式
public synchronized void increment() {
    count++;
}

// AtomicInteger 方式
public void increment() {
    count.incrementAndGet();  // 更快，无锁
}
```

### 数组类型原子类

**AtomicIntegerArray / AtomicLongArray / AtomicReferenceArray**

```java
AtomicIntegerArray array = new AtomicIntegerArray(10);

// 原子操作数组元素
array.set(0, 100);
array.getAndIncrement(0);           // array[0]++
array.compareAndSet(0, 100, 200);   // 如果 array[0]==100，改为 200

// 批量操作示例
public class ParallelSum {
    static AtomicIntegerArray arr = new AtomicIntegerArray(1000);

    public static void main(String[] args) {
        // 多线程并发写入
        for (int i = 0; i < 10; i++) {
            new Thread(() -> {
                for (int j = 0; j < 100; j++) {
                    arr.incrementAndGet(j);
                }
            }).start();
        }
    }
}
```

### 引用类型原子类

**AtomicReference**

```java
public class User {
    private String name;
    private int age;
}

AtomicReference<User> userRef = new AtomicReference<>();

// 原子更新引用
User oldUser = userRef.get();
User newUser = new User("Alice", 25);
userRef.compareAndSet(oldUser, newUser);

// 实战：单例模式
public class Singleton {
    private static AtomicReference<Singleton> instance = new AtomicReference<>();

    public static Singleton getInstance() {
        while (true) {
            Singleton current = instance.get();
            if (current != null) {
                return current;
            }
            current = new Singleton();
            if (instance.compareAndSet(null, current)) {
                return current;
            }
        }
    }
}
```

### 字段更新器

**AtomicIntegerFieldUpdater / AtomicLongFieldUpdater / AtomicReferenceFieldUpdater**

```java
public class User {
    volatile int age;  // 必须是 volatile

    static AtomicIntegerFieldUpdater<User> ageUpdater =
        AtomicIntegerFieldUpdater.newUpdater(User.class, "age");

    public void increaseAge() {
        ageUpdater.incrementAndGet(this);
    }
}

// 优势：节省内存
// 如果有 100 万个 User 对象
// 使用 AtomicInteger：每个对象额外 16 字节（对象头）
// 使用 FieldUpdater：共享一个 Updater 对象
```

### 累加器（JDK 8+）

**LongAdder / DoubleAdder**

```java
// LongAdder 比 AtomicLong 更快
LongAdder adder = new LongAdder();

// 多线程累加
adder.increment();      // +1
adder.add(10);          // +10
long sum = adder.sum(); // 获取总和

// 原理：分段累加，减少竞争
// AtomicLong: 所有线程竞争一个变量
// LongAdder:  每个线程有自己的累加槽，最后汇总
```

**性能对比**：
```java
// 高并发场景（64 线程，每线程累加 1000 万次）
AtomicLong:  耗时 3000ms
LongAdder:   耗时 500ms   // 6倍提升！
```

---

## 无锁队列 ⭐⭐⭐⭐

### ConcurrentLinkedQueue

**特点**：
- 基于 CAS 的无锁队列
- FIFO 顺序
- 线程安全
- 适合高并发场景

**实现原理**：
```java
public class ConcurrentLinkedQueue<E> {
    private static class Node<E> {
        volatile E item;
        volatile Node<E> next;
    }

    private transient volatile Node<E> head;
    private transient volatile Node<E> tail;

    // 入队：CAS 更新 tail
    public boolean offer(E e) {
        Node<E> newNode = new Node<>(e);
        for (Node<E> t = tail, p = t;;) {
            Node<E> q = p.next;
            if (q == null) {
                // p 是尾节点，尝试 CAS
                if (p.casNext(null, newNode)) {
                    // CAS 成功，更新 tail（允许滞后）
                    if (p != t) {
                        casTail(t, newNode);
                    }
                    return true;
                }
            } else {
                // p 不是尾节点，继续找
                p = (p != t && t != (t = tail)) ? t : q;
            }
        }
    }

    // 出队：CAS 更新 head
    public E poll() {
        restartFromHead:
        for (;;) {
            for (Node<E> h = head, p = h, q;;) {
                E item = p.item;
                if (item != null && p.casItem(item, null)) {
                    // CAS 成功取出元素
                    if (p != h) {
                        updateHead(h, (q = p.next) != null ? q : p);
                    }
                    return item;
                } else if ((q = p.next) == null) {
                    updateHead(h, p);
                    return null;
                } else if (p == q) {
                    continue restartFromHead;
                } else {
                    p = q;
                }
            }
        }
    }
}
```

**使用示例**：
```java
ConcurrentLinkedQueue<Integer> queue = new ConcurrentLinkedQueue<>();

// 生产者
new Thread(() -> {
    for (int i = 0; i < 1000; i++) {
        queue.offer(i);
    }
}).start();

// 消费者
new Thread(() -> {
    while (true) {
        Integer value = queue.poll();
        if (value != null) {
            System.out.println(value);
        }
    }
}).start();
```

### ConcurrentLinkedDeque

**双端队列**，支持头尾两端操作：
```java
ConcurrentLinkedDeque<Integer> deque = new ConcurrentLinkedDeque<>();

deque.offerFirst(1);   // 头部插入
deque.offerLast(2);    // 尾部插入
deque.pollFirst();     // 头部取出
deque.pollLast();      // 尾部取出
```

### 队列对比

| 队列 | 阻塞 | 有界 | 实现 | 性能 |
|------|------|------|------|------|
| **ConcurrentLinkedQueue** | ❌ 非阻塞 | ❌ 无界 | CAS 无锁 | 高 |
| **ArrayBlockingQueue** | ✅ 阻塞 | ✅ 有界 | ReentrantLock | 中 |
| **LinkedBlockingQueue** | ✅ 阻塞 | ✅ 可选 | 分段锁 | 中 |
| **LinkedTransferQueue** | ✅ 阻塞 | ❌ 无界 | CAS 无锁 | 高 |

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: CAS 是什么？如何实现？**
- CAS = Compare-And-Swap，比较并交换
- 三个操作数：内存地址 V、预期值 E、新值 N
- 底层调用 CPU 指令（x86: LOCK CMPXCHG）
- 具有 volatile 读写的内存语义

**Q2: CAS 有什么问题？**
- **ABA 问题**：值从 A 改为 B 再改回 A，中间状态丢失
- **自旋开销**：高竞争时，大量线程自旋消耗 CPU
- **只能保证一个变量**：需要多个变量原子操作时无能为力

**Q3: 如何解决 ABA 问题？**
- 使用 `AtomicStampedReference`：增加版本号
- 使用 `AtomicMarkableReference`：增加标记位
- 不可变对象：每次修改都创建新对象

**Q4: AtomicInteger 和 synchronized 的区别？**
- AtomicInteger 基于 CAS，非阻塞，性能更高
- synchronized 基于互斥锁，阻塞等待，有上下文切换
- AtomicInteger 适合简单计数，synchronized 适合复杂临界区

**Q5: LongAdder 为什么比 AtomicLong 快？**
- AtomicLong：所有线程竞争一个变量，CAS 冲突严重
- LongAdder：分段累加，每个线程有自己的槽位，最后汇总
- 高并发下，LongAdder 性能提升 5-10 倍

**Q6: ConcurrentLinkedQueue 的实现原理？**
- 基于单向链表，使用 CAS 更新 head 和 tail
- 允许 tail 滞后（延迟更新），减少 CAS 次数
- 入队和出队都是无锁的，适合高并发

**Q7: 什么时候使用 CAS，什么时候使用锁？**
- **CAS 适用**：低竞争、操作简单（计数、状态标志）
- **锁适用**：高竞争、复杂操作、需要公平性

**Q8: volatile 和 AtomicInteger 的区别？**
- volatile 只保证可见性和有序性，不保证原子性
- AtomicInteger 保证原子性（基于 CAS）
- `volatile int i; i++` 不是线程安全的
- `AtomicInteger i; i.incrementAndGet()` 线程安全

---

## 参考资料

1. **书籍推荐**：《Java 并发编程的艺术》、《Java 并发编程实战》
2. **论文**：《Practical lock-freedom》- Keir Fraser
3. **源码**：java.util.concurrent.atomic 包
