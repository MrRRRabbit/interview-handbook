# Redis 应用场景

> Redis 最常用于缓存和分布式锁，理解这两个场景的核心问题及解决方案是面试重点。

## 缓存设计 ⭐⭐⭐⭐⭐

### 缓存架构

```
Client → 应用服务器 → Redis(缓存) → MySQL(数据库)
         ↓
      1. 查询缓存
      2. 缓存命中 → 返回
      3. 缓存未命中 → 查 DB → 写缓存 → 返回
```

---

## 缓存穿透 ⭐⭐⭐⭐⭐

### 问题

查询一个**不存在的数据**，缓存和数据库都没有，导致每次请求都打到数据库。

```
请求不存在的 user_id = -1
→ Redis 没有
→ MySQL 没有
→ 大量请求直接打到 MySQL
→ 数据库压力暴增
```

### 解决方案

**方案1：缓存空值**
```java
String user = redis.get("user:-1");
if (user == null) {
    user = db.query("user:-1");
    if (user == null) {
        // 缓存空值，设置较短过期时间
        redis.setex("user:-1", 60, "");
    }
}
```

**优点**：简单
**缺点**：占用内存；恶意攻击大量不同 ID 仍会缓存大量空值

**方案2：布隆过滤器（推荐）**
```java
// 初始化：将所有存在的 user_id 加入布隆过滤器
BloomFilter<Long> bf = BloomFilter.create(...);
for (Long userId : allUserIds) {
    bf.put(userId);
}

// 查询
if (!bf.mightContain(userId)) {
    // 不存在，直接返回
    return null;
}
// 可能存在，查缓存和数据库
```

**优点**：内存占用小（1亿数据约 12MB）
**缺点**：有误判率（可能存在实际不存在）

---

## 缓存击穿 ⭐⭐⭐⭐⭐

### 问题

**热点 key 过期**，瞬间大量请求打到数据库。

```
热点商品 key 过期
→ 1000个并发请求同时到达
→ 缓存都没有
→ 1000个请求同时查 MySQL
→ 数据库压力瞬间飙升
```

### 解决方案

**方案1：互斥锁（推荐）**
```java
public String getUser(Long userId) {
    String key = "user:" + userId;
    String user = redis.get(key);

    if (user == null) {
        String lockKey = "lock:user:" + userId;
        // 尝试获取锁
        if (redis.setnx(lockKey, "1", 10)) {
            try {
                // 获取锁成功，查询数据库
                user = db.query(userId);
                redis.setex(key, 3600, user);
            } finally {
                redis.del(lockKey);
            }
        } else {
            // 获取锁失败，等待后重试
            Thread.sleep(50);
            return getUser(userId);
        }
    }
    return user;
}
```

**优点**：保证只有一个请求打到数据库
**缺点**：其他请求需要等待

**方案2：热点数据永不过期**
```java
// 逻辑过期：在缓存值中存储过期时间
class CacheValue {
    Object data;
    long expireTime;
}

// 异步更新
if (System.currentTimeMillis() > value.expireTime) {
    // 已过期，异步刷新
    threadPool.execute(() -> {
        refreshCache(key);
    });
}
// 仍返回旧数据
return value.data;
```

**优点**：不阻塞请求，保证可用性
**缺点**：短时间内返回旧数据

---

## 缓存雪崩 ⭐⭐⭐⭐⭐

### 问题

**大量 key 同时过期**或 **Redis 宕机**，导致请求全部打到数据库。

```
场景1：大量 key 在同一时间过期
商品缓存都设置 1小时过期
→ 1小时后同时失效
→ 大量请求打到 MySQL

场景2：Redis 宕机
→ 所有请求打到 MySQL
→ 数据库崩溃
```

### 解决方案

**防止同时过期**：
```java
// 过期时间加随机值
int expire = 3600 + new Random().nextInt(300); // 3600-3900秒
redis.setex(key, expire, value);
```

**高可用架构**：
- 主从 + 哨兵：自动故障转移
- Redis 集群：分片 + 高可用

**限流降级**：
```java
// 使用 Guava 限流
RateLimiter limiter = RateLimiter.create(1000); // 每秒1000请求

if (!limiter.tryAcquire()) {
    // 超过限流，返回降级数据或错误
    return fallbackData;
}
```

**多级缓存**：
```
本地缓存(Caffeine) → Redis → MySQL
```

---

## 缓存一致性 ⭐⭐⭐⭐⭐

### 双写一致性问题

更新数据库后，如何保证缓存和数据库一致？

**4种更新策略**：

| 策略 | 问题 |
|------|------|
| 先更新缓存，再更新数据库 | ❌ 数据库更新失败，数据不一致 |
| 先更新数据库，再更新缓存 | ❌ 并发时，后完成的请求可能写入旧数据 |
| 先删除缓存，再更新数据库 | ❌ 更新 DB 期间，其他请求可能读到旧数据并写入缓存 |
| **先更新数据库，再删除缓存（推荐）** | ✅ 最佳方案，极小概率不一致 |

### 推荐方案：Cache Aside Pattern

```java
// 读请求
public User getUser(Long id) {
    User user = redis.get(id);
    if (user == null) {
        user = db.query(id);
        redis.setex(id, 3600, user);
    }
    return user;
}

// 写请求
public void updateUser(User user) {
    db.update(user);       // 1. 先更新数据库
    redis.del(user.getId()); // 2. 再删除缓存
}
```

### 延迟双删

解决极端并发场景下的不一致：
```java
public void updateUser(User user) {
    redis.del(user.getId());      // 1. 删除缓存
    db.update(user);              // 2. 更新数据库
    Thread.sleep(500);            // 3. 延迟
    redis.del(user.getId());      // 4. 再次删除缓存
}
```

---

## 分布式锁 ⭐⭐⭐⭐⭐

### 基本实现

**加锁**：
```java
// SET key value NX EX seconds
boolean lock = redis.set("lock:resource", uuid, "NX", "EX", 30);
```

**解锁**（Lua 脚本保证原子性）：
```lua
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
```

```java
public void unlock(String lockKey, String uuid) {
    String script = "if redis.call('get', KEYS[1]) == ARGV[1] then " +
                    "return redis.call('del', KEYS[1]) else return 0 end";
    redis.eval(script, Collections.singletonList(lockKey),
               Collections.singletonList(uuid));
}
```

### 存在的问题

**问题1：锁过期，业务未完成**
```
线程A 获取锁，设置 30秒过期
→ 业务执行超过 30秒，锁自动释放
→ 线程B 获取到锁
→ 线程A 和线程B 同时执行（锁失效）
```

**解决方案**：**自动续期**（Redisson 实现）
```java
// Redisson 的看门狗机制
RLock lock = redisson.getLock("myLock");
lock.lock(); // 默认 30秒，每 10秒自动续期
try {
    // 业务逻辑
} finally {
    lock.unlock();
}
```

**问题2：主从架构下的锁丢失**
```
客户端A 在 Master 上加锁
→ Master 宕机，还未同步到 Slave
→ Slave 升级为新 Master
→ 客户端B 在新 Master 上加锁成功
→ A 和 B 同时持有锁
```

### Redlock 算法 ⭐⭐⭐⭐

**原理**：向多个独立的 Redis 实例（N 个，通常 5 个）加锁，超过半数成功才算加锁成功。

```
1. 获取当前时间戳 T1
2. 依次向 N 个 Redis 实例请求加锁
3. 统计成功个数
4. 如果成功个数 > N/2，且总耗时 < 锁过期时间，则加锁成功
5. 否则，释放所有锁
```

**优点**：解决主从架构的锁丢失问题
**缺点**：性能开销大，实现复杂

**实际建议**：
- 普通场景：单 Redis + Redisson
- 强一致性要求：使用 ZooKeeper 或 etcd

---

## 其他应用场景

### 排行榜（ZSet）

```java
// 增加分数
redis.zincrby("game:rank", 100, "player1");

// 获取 Top 10
Set<String> top10 = redis.zrevrange("game:rank", 0, 9);

// 查看排名
Long rank = redis.zrevrank("game:rank", "player1");
```

### 计数器与限流

**简单计数器**：
```java
redis.incr("page:view:123");
```

**滑动窗口限流**（ZSet）：
```java
long now = System.currentTimeMillis();
String key = "limiter:" + userId;

// 移除 1分钟前的记录
redis.zremrangeByScore(key, 0, now - 60000);

// 统计 1分钟内的请求数
long count = redis.zcard(key);
if (count >= 100) {
    return false; // 限流
}

// 记录本次请求
redis.zadd(key, now, UUID.randomUUID().toString());
redis.expire(key, 60);
return true;
```

### 消息队列（List / Stream）

**简单队列（List）**：
```java
// 生产者
redis.lpush("queue:tasks", task);

// 消费者
String task = redis.brpop(0, "queue:tasks");
```

**Stream（推荐）**：
```bash
# 生产消息
XADD stream:orders * order_id 123 amount 99.99

# 消费组消费
XREADGROUP GROUP group1 consumer1 COUNT 1 STREAMS stream:orders >
```

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 缓存穿透、击穿、雪崩的区别？**
- 穿透：查询不存在的数据，缓存和 DB 都没有（布隆过滤器）
- 击穿：热点 key 过期，大量请求打到 DB（互斥锁）
- 雪崩：大量 key 同时过期或 Redis 宕机（随机过期时间 + 高可用）

**Q2: 如何保证缓存和数据库一致性？**
- 推荐：先更新数据库，再删除缓存（Cache Aside Pattern）
- 极端场景：延迟双删

**Q3: Redis 分布式锁如何实现？**
- 加锁：`SET key uuid NX EX 30`
- 解锁：Lua 脚本判断 uuid，保证原子性
- 续期：Redisson 看门狗机制

**Q4: Redlock 算法的原理？**
- 向 N 个独立 Redis 实例加锁
- 超过半数成功且耗时 < 过期时间才算成功
- 解决主从架构下的锁丢失问题

**Q5: 布隆过滤器的误判率如何优化？**
- 增加位数组大小
- 增加哈希函数个数
- 实际需要权衡内存和误判率

**Q6: 为什么不推荐先删缓存再更新数据库？**
- 更新 DB 期间，其他请求可能读到旧数据并写入缓存
- 导致后续一直读到旧数据，直到缓存过期

---

## 参考资料

1. **官方文档**：[Redis Use Cases](https://redis.io/docs/manual/patterns/)
2. **分布式锁**：[Redlock 算法](https://redis.io/docs/manual/patterns/distributed-locks/)
3. **书籍推荐**：《Redis 深度历险》
