# 分布式并发

> 分布式锁和一致性算法是分布式系统中解决并发问题的核心技术，也是面试必考内容。

## 分布式锁概述 ⭐⭐⭐⭐⭐

### 为什么需要分布式锁

**单机锁的局限**：
```java
// 单机环境：synchronized 有效
public synchronized void deductStock() {
    if (stock > 0) {
        stock--;
    }
}

// 分布式环境：多个 JVM，synchronized 失效
// 服务器1：stock=1，扣减成功
// 服务器2：stock=1，同时扣减成功
// 结果：超卖！
```

**分布式锁的场景**：
- 库存扣减（防止超卖）
- 订单号生成（防止重复）
- 定时任务（防止重复执行）
- 缓存重建（防止缓存击穿）

### 分布式锁的要求

| 要求 | 说明 |
|------|------|
| **互斥性** | 同一时刻只有一个客户端持有锁 |
| **安全性** | 不会死锁，即使客户端崩溃 |
| **容错性** | 只要多数节点存活，就能加锁/解锁 |
| **唯一性** | 加锁和解锁必须是同一个客户端 |

---

## Redis 分布式锁 ⭐⭐⭐⭐⭐

### 基础实现（SETNX）

**错误版本 1：SETNX + EXPIRE 分两步**
```java
// 问题：SETNX 成功后，EXPIRE 前崩溃 → 死锁
jedis.setnx("lock_key", "value");
jedis.expire("lock_key", 30);  // 如果这步失败，锁永不过期
```

**错误版本 2：SET NX EX 但不校验身份**
```java
// 加锁
jedis.set("lock_key", "value", "NX", "EX", 30);

// 解锁问题：可能删除别人的锁
jedis.del("lock_key");  // 如果自己的锁超时，删除的是别人的锁
```

### 正确实现

**1. 加锁**
```java
public boolean tryLock(String key, String requestId, int expireTime) {
    // SET key value NX EX seconds
    // NX：只在键不存在时设置
    // EX：设置过期时间（秒）
    String result = jedis.set(
        key,
        requestId,          // 唯一标识（UUID）
        "NX",               // 不存在才设置
        "EX",               // 秒级过期
        expireTime
    );
    return "OK".equals(result);
}

// 使用
String requestId = UUID.randomUUID().toString();
if (tryLock("stock_lock", requestId, 30)) {
    try {
        // 执行业务
        deductStock();
    } finally {
        unlock("stock_lock", requestId);
    }
}
```

**2. 解锁（Lua 脚本保证原子性）**
```java
public boolean unlock(String key, String requestId) {
    // Lua 脚本保证原子性
    String script =
        "if redis.call('get', KEYS[1]) == ARGV[1] then " +
        "    return redis.call('del', KEYS[1]) " +
        "else " +
        "    return 0 " +
        "end";

    Object result = jedis.eval(
        script,
        Collections.singletonList(key),
        Collections.singletonList(requestId)
    );
    return Long.valueOf(1).equals(result);
}
```

### 存在的问题

**1. 锁超时问题**
```java
// 场景：业务执行时间 > 锁过期时间
tryLock("lock", requestId, 30);  // 30秒后锁自动释放
try {
    // 业务执行 40 秒
    longTimeOperation();  // 35秒时，锁已被其他线程获取
} finally {
    unlock("lock", requestId);  // 删除的是别人的锁！
}
```

**解决方案：Redisson 看门狗**
```java
// Redisson 自动续期
RLock lock = redisson.getLock("myLock");
lock.lock();  // 默认 30s，每 10s 自动续期
try {
    // 业务逻辑，不用担心超时
} finally {
    lock.unlock();
}
```

**2. 主从复制延迟**
```
时刻1：客户端1 在 Master 加锁成功
时刻2：Master 宕机，锁未同步到 Slave
时刻3：Slave 升级为 Master
时刻4：客户端2 在新 Master 加锁成功
结果：两个客户端同时持有锁
```

**解决方案：RedLock 算法（后文）**

### Redisson 实现

**基本使用**：
```java
Config config = new Config();
config.useSingleServer().setAddress("redis://127.0.0.1:6379");
RedissonClient redisson = Redisson.create(config);

RLock lock = redisson.getLock("myLock");

// 1. 普通加锁
lock.lock();  // 阻塞等待
try {
    // 业务
} finally {
    lock.unlock();
}

// 2. 尝试加锁
if (lock.tryLock()) {
    try {
        // 业务
    } finally {
        lock.unlock();
    }
}

// 3. 带超时的尝试加锁
if (lock.tryLock(100, 30, TimeUnit.SECONDS)) {  // 等待100s，锁30s
    try {
        // 业务
    } finally {
        lock.unlock();
    }
}
```

**看门狗机制**：
```java
// Redisson 看门狗原理
lock.lock();
// 1. 默认锁时间 30s
// 2. 每 10s（30/3）检查一次
// 3. 如果锁还在，续期到 30s
// 4. unlock() 时停止续期

// 自定义锁时间（不启用看门狗）
lock.lock(10, TimeUnit.SECONDS);  // 10s 后自动释放，不续期
```

### RedLock 算法

**原理**：向多个独立的 Redis 实例加锁，多数成功则认为加锁成功。

**流程**：
```
1. 获取当前时间戳 T1
2. 依次向 N 个 Redis 实例加锁（使用相同的 key 和 value）
3. 计算加锁耗时 T = T2 - T1
4. 判断：
   - 加锁成功的实例数 > N/2
   - 加锁耗时 T < 锁有效期
   则认为加锁成功
5. 如果失败，向所有实例释放锁
```

**Redisson 实现**：
```java
Config config1 = new Config();
config1.useSingleServer().setAddress("redis://127.0.0.1:6379");
RedissonClient redisson1 = Redisson.create(config1);

Config config2 = new Config();
config2.useSingleServer().setAddress("redis://127.0.0.1:6380");
RedissonClient redisson2 = Redisson.create(config2);

Config config3 = new Config();
config3.useSingleServer().setAddress("redis://127.0.0.1:6381");
RedissonClient redisson3 = Redisson.create(config3);

RLock lock1 = redisson1.getLock("myLock");
RLock lock2 = redisson2.getLock("myLock");
RLock lock3 = redisson3.getLock("myLock");

// RedLock
RedissonRedLock redLock = new RedissonRedLock(lock1, lock2, lock3);

redLock.lock();
try {
    // 业务逻辑
} finally {
    redLock.unlock();
}
```

**优缺点**：
- ✅ 解决主从复制延迟问题
- ❌ 需要多个独立 Redis 实例
- ❌ 性能开销大

---

## Zookeeper 分布式锁 ⭐⭐⭐⭐⭐

### 实现原理

**基于临时顺序节点**：
```
/locks/mylock_0000000001  (客户端1)
/locks/mylock_0000000002  (客户端2)
/locks/mylock_0000000003  (客户端3)

规则：
1. 创建临时顺序节点
2. 获取所有子节点，排序
3. 如果自己是最小节点 → 获得锁
4. 否则，监听前一个节点的删除事件
5. 前一个节点删除 → 尝试获取锁
```

### 手动实现

```java
public class ZkLock {
    private ZooKeeper zk;
    private String lockPath;
    private String currentNode;

    public void lock() throws Exception {
        // 1. 创建临时顺序节点
        currentNode = zk.create(
            lockPath + "/lock_",
            new byte[0],
            ZooDefs.Ids.OPEN_ACL_UNSAFE,
            CreateMode.EPHEMERAL_SEQUENTIAL
        );

        // 2. 尝试获取锁
        while (true) {
            List<String> children = zk.getChildren(lockPath, false);
            Collections.sort(children);

            String minNode = children.get(0);
            if (currentNode.endsWith(minNode)) {
                // 自己是最小节点，获得锁
                return;
            }

            // 3. 监听前一个节点
            int index = children.indexOf(currentNode.substring(lockPath.length() + 1));
            String preNode = lockPath + "/" + children.get(index - 1);

            CountDownLatch latch = new CountDownLatch(1);
            zk.exists(preNode, event -> {
                if (event.getType() == Watcher.Event.EventType.NodeDeleted) {
                    latch.countDown();
                }
            });

            // 4. 等待前一个节点删除
            latch.await();
        }
    }

    public void unlock() throws Exception {
        // 删除节点，释放锁
        zk.delete(currentNode, -1);
    }
}
```

### Curator 实现

**基本使用**：
```java
CuratorFramework client = CuratorFrameworkFactory.builder()
    .connectString("127.0.0.1:2181")
    .retryPolicy(new ExponentialBackoffRetry(1000, 3))
    .build();
client.start();

InterProcessMutex lock = new InterProcessMutex(client, "/locks/mylock");

// 加锁
lock.acquire();
try {
    // 业务逻辑
} finally {
    lock.release();
}

// 尝试加锁
if (lock.acquire(10, TimeUnit.SECONDS)) {
    try {
        // 业务逻辑
    } finally {
        lock.release();
    }
}
```

**读写锁**：
```java
InterProcessReadWriteLock rwLock = new InterProcessReadWriteLock(client, "/locks/mylock");

// 读锁
InterProcessMutex readLock = rwLock.readLock();
readLock.acquire();
try {
    // 读操作
} finally {
    readLock.release();
}

// 写锁
InterProcessMutex writeLock = rwLock.writeLock();
writeLock.acquire();
try {
    // 写操作
} finally {
    writeLock.release();
}
```

### ZK vs Redis 锁对比

| 特性 | Redis | Zookeeper |
|------|-------|-----------|
| **性能** | 高（内存） | 中（磁盘 + 网络） |
| **可靠性** | 中（可能丢锁） | 高（CP 模型） |
| **实现复杂度** | 高（需处理超时、续期） | 低（框架封装） |
| **死锁** | 可能（超时未处理） | 不会（临时节点） |
| **公平性** | 不公平 | 公平（顺序节点） |
| **适用场景** | 高性能、允许偶尔失败 | 强一致性、不能失败 |

---

## 一致性算法概述 ⭐⭐⭐⭐

### Raft 算法

**核心概念**：

**1. 角色**
- **Leader**：处理所有客户端请求
- **Follower**：被动接收请求，转发给 Leader
- **Candidate**：选举时的临时角色

**2. 选举流程**
```
1. 初始状态：所有节点都是 Follower
2. 超时未收到心跳 → Follower 变为 Candidate
3. Candidate 向其他节点请求投票
4. 获得多数票 → 成为 Leader
5. Leader 定期发送心跳，维持地位
```

**3. 日志复制**
```
1. 客户端请求发送到 Leader
2. Leader 追加日志，发送给 Follower
3. Follower 收到日志，追加并回复
4. Leader 收到多数回复 → 提交日志
5. Leader 通知 Follower 提交
```

**特点**：
- 强一致性
- 易于理解和实现
- 应用：etcd、Consul

### Paxos 算法

**核心概念**：

**1. 角色**
- **Proposer**：提议者
- **Acceptor**：接受者
- **Learner**：学习者

**2. 两阶段提交**

**Phase 1（准备阶段）**：
```
Proposer → Acceptor: Prepare(n)
Acceptor → Proposer: Promise(n, accepted_value)
```

**Phase 2（接受阶段）**：
```
Proposer → Acceptor: Accept(n, value)
Acceptor → Proposer: Accepted(n, value)
Proposer → Learner: Success(value)
```

**特点**：
- 理论基础
- 实现复杂
- 应用：Google Chubby、Zookeeper（ZAB 协议，Paxos 变种）

### Raft vs Paxos

| 特性 | Raft | Paxos |
|------|------|-------|
| **易理解性** | 高 | 低 |
| **实现复杂度** | 低 | 高 |
| **性能** | 相当 | 相当 |
| **应用** | etcd、Consul | Chubby、ZK |

---

## 分布式锁最佳实践 ⭐⭐⭐⭐⭐

### 选型建议

**Redis 适用场景**：
- 高性能要求
- 允许偶尔失败（如计数统计）
- 对可靠性要求不极致

**Zookeeper 适用场景**：
- 强一致性要求
- 不能丢锁（如扣款、库存）
- 需要公平锁

### 实战案例：秒杀库存扣减

**方案 1：Redis 锁 + Lua 脚本**
```java
public boolean deductStock(String productId, int count) {
    String lockKey = "lock:stock:" + productId;
    String requestId = UUID.randomUUID().toString();

    RLock lock = redisson.getLock(lockKey);
    try {
        // 尝试加锁，最多等待 5s，锁 30s
        if (lock.tryLock(5, 30, TimeUnit.SECONDS)) {
            try {
                // Lua 脚本原子扣减库存
                String script =
                    "local stock = redis.call('get', KEYS[1]) " +
                    "if not stock or tonumber(stock) < tonumber(ARGV[1]) then " +
                    "    return 0 " +
                    "end " +
                    "redis.call('decrby', KEYS[1], ARGV[1]) " +
                    "return 1";

                Object result = jedis.eval(
                    script,
                    Collections.singletonList("stock:" + productId),
                    Collections.singletonList(String.valueOf(count))
                );

                return Long.valueOf(1).equals(result);
            } finally {
                lock.unlock();
            }
        }
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
    }
    return false;
}
```

**方案 2：Zookeeper 锁 + MySQL**
```java
public boolean deductStock(String productId, int count) {
    String lockPath = "/locks/stock/" + productId;
    InterProcessMutex lock = new InterProcessMutex(zkClient, lockPath);

    try {
        // 加锁
        lock.acquire(5, TimeUnit.SECONDS);
        try {
            // 数据库扣减
            int updated = jdbcTemplate.update(
                "UPDATE stock SET count = count - ? WHERE product_id = ? AND count >= ?",
                count, productId, count
            );
            return updated > 0;
        } finally {
            lock.release();
        }
    } catch (Exception e) {
        log.error("Deduct stock failed", e);
    }
    return false;
}
```

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 分布式锁有哪些实现方式？**
- Redis：基于 SETNX 和 Lua 脚本
- Zookeeper：基于临时顺序节点
- 数据库：基于唯一索引或行锁

**Q2: Redis 分布式锁的正确实现？**
```java
// 加锁：SET key value NX EX seconds
jedis.set(key, requestId, "NX", "EX", 30);

// 解锁：Lua 脚本保证原子性
if redis.call('get', KEYS[1]) == ARGV[1] then
    return redis.call('del', KEYS[1])
end
```

**Q3: Redis 锁有什么问题？**
- 锁超时：业务执行时间超过锁过期时间
- 主从复制延迟：主节点宕机，锁未同步到从节点

**Q4: 什么是 Redisson 看门狗？**
- 自动续期机制
- 默认 30s 锁，每 10s 续期一次
- unlock() 时停止续期

**Q5: 什么是 RedLock？**
- 向多个独立 Redis 实例加锁
- 多数成功则认为加锁成功
- 解决主从复制延迟问题

**Q6: Zookeeper 锁的实现原理？**
- 创建临时顺序节点
- 最小节点获得锁
- 监听前一个节点，等待删除

**Q7: Redis 锁和 ZK 锁的区别？**
- Redis：高性能，可能丢锁，不公平
- Zookeeper：强一致，不会丢锁，公平

**Q8: Raft 和 Paxos 的区别？**
- Raft：易理解，实现简单
- Paxos：理论基础，实现复杂
- 性能相当

---

## 参考资料

1. **书籍推荐**：《分布式系统原理与实践》、《从 Paxos 到 Zookeeper》
2. **论文**：
   - 《In Search of an Understandable Consensus Algorithm (Raft)》
   - 《The Part-Time Parliament (Paxos)》
3. **开源项目**：Redisson、Curator
