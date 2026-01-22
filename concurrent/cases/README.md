# 实战案例

> 通过秒杀系统、高并发计数器和限流算法三个经典案例，综合运用并发编程技术。

## 秒杀系统设计 ⭐⭐⭐⭐⭐

### 核心挑战

**秒杀场景特点**：
- 瞬时高并发（10 万+ QPS）
- 库存有限（100 件商品）
- 超卖风险（并发扣减库存）
- 恶意请求（刷单、爬虫）

### 架构设计

```
客户端
  ↓
CDN/Nginx（静态资源）
  ↓
网关层（限流、鉴权）
  ↓
业务层（秒杀服务）
  ↓
缓存层（Redis）
  ↓
数据库层（MySQL）
```

### 方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **数据库行锁** | 简单 | 性能差，易死锁 | 低并发 |
| **Redis 缓存库存** | 性能高 | 可能超卖 | 高并发 |
| **Redis 锁** | 可靠性高 | 性能一般 | 中等并发 |
| **消息队列削峰** | 削峰填谷 | 延迟高 | 超高并发 |

### 方案 1：Redis 原子扣减

**实现**：
```java
@Service
public class SeckillService {

    @Autowired
    private StringRedisTemplate redisTemplate;

    @Autowired
    private OrderService orderService;

    /**
     * 初始化库存
     */
    public void initStock(String productId, int stock) {
        String key = "seckill:stock:" + productId;
        redisTemplate.opsForValue().set(key, String.valueOf(stock));
    }

    /**
     * 秒杀下单
     */
    public boolean seckill(String userId, String productId, int count) {
        String stockKey = "seckill:stock:" + productId;
        String userKey = "seckill:user:" + productId + ":" + userId;

        // 1. 检查用户是否已购买（防止重复下单）
        Boolean hasBought = redisTemplate.hasKey(userKey);
        if (Boolean.TRUE.equals(hasBought)) {
            throw new BusinessException("您已经参与过该商品的秒杀");
        }

        // 2. Lua 脚本原子扣减库存
        String script =
            "local stock = redis.call('get', KEYS[1]) " +
            "if not stock or tonumber(stock) < tonumber(ARGV[1]) then " +
            "    return 0 " +
            "end " +
            "redis.call('decrby', KEYS[1], ARGV[1]) " +
            "redis.call('setex', KEYS[2], 86400, '1') " +  // 标记用户已购买，24小时
            "return 1";

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Arrays.asList(stockKey, userKey),
            String.valueOf(count)
        );

        if (result == 1) {
            // 3. 异步创建订单
            asyncCreateOrder(userId, productId, count);
            return true;
        }
        return false;
    }

    /**
     * 异步创建订单
     */
    @Async
    private void asyncCreateOrder(String userId, String productId, int count) {
        try {
            orderService.createOrder(userId, productId, count);
        } catch (Exception e) {
            // 订单创建失败，回滚库存
            String stockKey = "seckill:stock:" + productId;
            redisTemplate.opsForValue().increment(stockKey, count);
            log.error("Create order failed, rollback stock", e);
        }
    }
}
```

**优点**：
- 性能高（Redis 内存操作）
- 原子性（Lua 脚本）
- 防止重复下单

**缺点**：
- Redis 宕机风险
- 需要数据同步

### 方案 2：分布式锁 + 预扣库存

**实现**：
```java
@Service
public class SeckillServiceV2 {

    @Autowired
    private RedissonClient redisson;

    @Autowired
    private StockService stockService;

    /**
     * 秒杀下单（使用分布式锁）
     */
    public boolean seckill(String userId, String productId, int count) {
        String lockKey = "lock:seckill:" + productId;
        RLock lock = redisson.getLock(lockKey);

        try {
            // 尝试加锁，最多等待 5s
            if (lock.tryLock(5, 30, TimeUnit.SECONDS)) {
                try {
                    // 1. 检查库存
                    int stock = stockService.getStock(productId);
                    if (stock < count) {
                        return false;
                    }

                    // 2. 预扣库存（Redis）
                    String stockKey = "seckill:stock:" + productId;
                    redisTemplate.opsForValue().decrement(stockKey, count);

                    // 3. 异步扣减数据库库存
                    asyncDeductDbStock(productId, count);

                    // 4. 创建订单
                    orderService.createOrder(userId, productId, count);
                    return true;
                } finally {
                    lock.unlock();
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return false;
    }

    /**
     * 异步扣减数据库库存
     */
    @Async
    private void asyncDeductDbStock(String productId, int count) {
        jdbcTemplate.update(
            "UPDATE stock SET count = count - ? WHERE product_id = ? AND count >= ?",
            count, productId, count
        );
    }
}
```

### 方案 3：消息队列削峰

**实现**：
```java
@Service
public class SeckillServiceV3 {

    @Autowired
    private RabbitTemplate rabbitTemplate;

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 秒杀下单（消息队列异步处理）
     */
    public boolean seckill(String userId, String productId, int count) {
        String stockKey = "seckill:stock:" + productId;

        // 1. 预检查库存
        String stock = redisTemplate.opsForValue().get(stockKey);
        if (stock == null || Integer.parseInt(stock) < count) {
            return false;
        }

        // 2. 发送到消息队列
        SeckillMessage message = new SeckillMessage(userId, productId, count);
        rabbitTemplate.convertAndSend("seckill.exchange", "seckill.order", message);

        return true;  // 返回排队中
    }
}

@Component
public class SeckillConsumer {

    @Autowired
    private StringRedisTemplate redisTemplate;

    @Autowired
    private OrderService orderService;

    /**
     * 消费秒杀消息
     */
    @RabbitListener(queues = "seckill.order.queue")
    public void consume(SeckillMessage message) {
        String stockKey = "seckill:stock:" + message.getProductId();

        // Lua 脚本扣减库存
        String script =
            "local stock = redis.call('get', KEYS[1]) " +
            "if not stock or tonumber(stock) < tonumber(ARGV[1]) then " +
            "    return 0 " +
            "end " +
            "redis.call('decrby', KEYS[1], ARGV[1]) " +
            "return 1";

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Collections.singletonList(stockKey),
            String.valueOf(message.getCount())
        );

        if (result == 1) {
            // 创建订单
            orderService.createOrder(
                message.getUserId(),
                message.getProductId(),
                message.getCount()
            );
        }
    }
}
```

**优点**：
- 削峰填谷
- 异步解耦
- 提高吞吐量

**缺点**：
- 延迟高
- 消息丢失风险

### 优化点总结

**1. 前端优化**
- 按钮置灰（防止重复提交）
- 验证码（防止机器刷单）
- 页面静态化（CDN 加速）

**2. 网关层优化**
- IP 限流（每秒 10 次）
- 用户限流（每秒 1 次）
- 恶意请求过滤

**3. 缓存层优化**
- Redis 预热（提前加载库存）
- 本地缓存（减少 Redis 访问）
- 读写分离（主写从读）

**4. 数据库层优化**
- 主从复制
- 分库分表
- 异步落库

---

## 高并发计数器 ⭐⭐⭐⭐⭐

### 场景分析

**典型场景**：
- 接口 QPS 统计
- 视频播放次数
- 文章阅读量
- 点赞数

**要求**：
- 高并发写入（10 万+ TPS）
- 实时读取
- 数据不丢失

### 方案对比

| 方案 | 性能 | 准确性 | 实现复杂度 |
|------|------|--------|-----------|
| **AtomicLong** | 低 | 高 | 低 |
| **LongAdder** | 高 | 高 | 低 |
| **Redis INCR** | 中 | 高 | 中 |
| **异步批量更新** | 极高 | 最终一致 | 高 |

### 方案 1：LongAdder（单机）

**实现**：
```java
@Component
public class MetricsCollector {

    // 每个接口一个计数器
    private ConcurrentHashMap<String, LongAdder> counters = new ConcurrentHashMap<>();

    /**
     * 记录请求
     */
    public void record(String api) {
        counters.computeIfAbsent(api, k -> new LongAdder()).increment();
    }

    /**
     * 获取统计
     */
    public long getCount(String api) {
        LongAdder adder = counters.get(api);
        return adder == null ? 0 : adder.sum();
    }

    /**
     * 定时上报到 Redis
     */
    @Scheduled(fixedRate = 60000)  // 每分钟上报一次
    public void report() {
        counters.forEach((api, adder) -> {
            long count = adder.sumThenReset();  // 获取并重置
            if (count > 0) {
                redisTemplate.opsForValue().increment("metrics:" + api, count);
            }
        });
    }
}
```

**优点**：
- 性能极高（分段累加）
- 实现简单

**缺点**：
- 单机统计
- 需要定时上报

### 方案 2：Redis + 本地缓存

**实现**：
```java
@Component
public class DistributedCounter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    // 本地缓存，减少 Redis 访问
    private ConcurrentHashMap<String, LongAdder> localCache = new ConcurrentHashMap<>();

    // 本地累加阈值
    private static final int FLUSH_THRESHOLD = 100;

    /**
     * 计数（本地累加）
     */
    public void increment(String key) {
        LongAdder adder = localCache.computeIfAbsent(key, k -> new LongAdder());
        adder.increment();

        // 达到阈值，刷新到 Redis
        if (adder.sum() >= FLUSH_THRESHOLD) {
            flush(key);
        }
    }

    /**
     * 刷新到 Redis
     */
    private void flush(String key) {
        LongAdder adder = localCache.get(key);
        if (adder != null) {
            long count = adder.sumThenReset();
            if (count > 0) {
                redisTemplate.opsForValue().increment("counter:" + key, count);
            }
        }
    }

    /**
     * 获取总数（Redis + 本地缓存）
     */
    public long getCount(String key) {
        // Redis 中的计数
        String value = redisTemplate.opsForValue().get("counter:" + key);
        long redisCount = value == null ? 0 : Long.parseLong(value);

        // 本地缓存中的计数
        LongAdder adder = localCache.get(key);
        long localCount = adder == null ? 0 : adder.sum();

        return redisCount + localCount;
    }

    /**
     * 定时刷新（兜底）
     */
    @Scheduled(fixedRate = 5000)  // 每 5s 刷新一次
    public void scheduledFlush() {
        localCache.forEach((key, adder) -> flush(key));
    }
}
```

**优点**：
- 分布式统计
- 减少 Redis 访问
- 性能高

**缺点**：
- 实现复杂
- 最终一致性

### 方案 3：时间窗口计数器

**实现**（滑动窗口）：
```java
@Component
public class SlidingWindowCounter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 记录请求（按分钟统计）
     */
    public void record(String api) {
        long minute = System.currentTimeMillis() / 60000;  // 当前分钟
        String key = "metrics:" + api + ":" + minute;
        redisTemplate.opsForValue().increment(key);
        redisTemplate.expire(key, 1, TimeUnit.HOURS);  // 保留 1 小时
    }

    /**
     * 获取最近 N 分钟的请求数
     */
    public long getCount(String api, int minutes) {
        long currentMinute = System.currentTimeMillis() / 60000;
        long totalCount = 0;

        for (int i = 0; i < minutes; i++) {
            String key = "metrics:" + api + ":" + (currentMinute - i);
            String value = redisTemplate.opsForValue().get(key);
            if (value != null) {
                totalCount += Long.parseLong(value);
            }
        }
        return totalCount;
    }

    /**
     * 获取 QPS
     */
    public double getQps(String api) {
        long count = getCount(api, 1);  // 最近 1 分钟
        return count / 60.0;
    }
}
```

---

## 限流算法 ⭐⭐⭐⭐⭐

### 限流算法对比

| 算法 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| **固定窗口** | 简单 | 临界突刺 | 粗粒度限流 |
| **滑动窗口** | 平滑 | 内存占用 | 精确限流 |
| **漏桶** | 匀速处理 | 无法应对突发 | 消息队列 |
| **令牌桶** | 应对突发 | 实现复杂 | API 网关 |

### 算法 1：固定窗口

**实现**：
```java
@Component
public class FixedWindowRateLimiter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 限流检查
     * @param key 限流键
     * @param limit 限流阈值（每秒）
     */
    public boolean tryAcquire(String key, int limit) {
        long second = System.currentTimeMillis() / 1000;
        String redisKey = "rate_limit:" + key + ":" + second;

        // Lua 脚本原子操作
        String script =
            "local count = redis.call('incr', KEYS[1]) " +
            "if count == 1 then " +
            "    redis.call('expire', KEYS[1], 2) " +  // 过期时间 2s（冗余）
            "end " +
            "if count > tonumber(ARGV[1]) then " +
            "    return 0 " +
            "else " +
            "    return 1 " +
            "end";

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Collections.singletonList(redisKey),
            String.valueOf(limit)
        );

        return result != null && result == 1;
    }
}
```

**问题**：临界突刺
```
时间窗口1：0:00-0:01，100 个请求（允许）
时间窗口2：0:01-0:02，100 个请求（允许）
问题：0:00.5-0:01.5，实际 200 个请求！
```

### 算法 2：滑动窗口

**实现**：
```java
@Component
public class SlidingWindowRateLimiter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 滑动窗口限流
     * @param key 限流键
     * @param limit 限流阈值（每秒）
     */
    public boolean tryAcquire(String key, int limit) {
        long now = System.currentTimeMillis();
        long windowStart = now - 1000;  // 1秒窗口
        String redisKey = "rate_limit:sliding:" + key;

        // Lua 脚本
        String script =
            "redis.call('zremrangebyscore', KEYS[1], 0, ARGV[1]) " +  // 删除过期数据
            "local count = redis.call('zcard', KEYS[1]) " +           // 当前计数
            "if count < tonumber(ARGV[3]) then " +
            "    redis.call('zadd', KEYS[1], ARGV[2], ARGV[2]) " +   // 添加当前请求
            "    redis.call('expire', KEYS[1], 2) " +
            "    return 1 " +
            "else " +
            "    return 0 " +
            "end";

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Collections.singletonList(redisKey),
            String.valueOf(windowStart),  // ARGV[1]
            String.valueOf(now),          // ARGV[2]
            String.valueOf(limit)         // ARGV[3]
        );

        return result != null && result == 1;
    }
}
```

### 算法 3：令牌桶（Guava RateLimiter）

**实现**：
```java
@Component
public class TokenBucketRateLimiter {

    // 每个 API 一个限流器
    private ConcurrentHashMap<String, RateLimiter> limiters = new ConcurrentHashMap<>();

    /**
     * 获取或创建限流器
     */
    private RateLimiter getLimiter(String key, double permitsPerSecond) {
        return limiters.computeIfAbsent(key, k -> RateLimiter.create(permitsPerSecond));
    }

    /**
     * 尝试获取令牌
     */
    public boolean tryAcquire(String key, double permitsPerSecond) {
        RateLimiter limiter = getLimiter(key, permitsPerSecond);
        return limiter.tryAcquire();  // 不等待，立即返回
    }

    /**
     * 阻塞获取令牌
     */
    public void acquire(String key, double permitsPerSecond) {
        RateLimiter limiter = getLimiter(key, permitsPerSecond);
        limiter.acquire();  // 阻塞等待
    }
}
```

### 算法 4：漏桶（队列实现）

**实现**：
```java
@Component
public class LeakyBucketRateLimiter {

    @Autowired
    private ThreadPoolExecutor executor;

    /**
     * 提交任务到漏桶
     */
    public boolean submit(Runnable task) {
        // 队列满则拒绝
        if (executor.getQueue().remainingCapacity() == 0) {
            return false;
        }
        executor.submit(task);
        return true;
    }

    /**
     * 配置漏桶（固定速率的线程池）
     */
    @Bean
    public ThreadPoolExecutor leakyBucketExecutor() {
        return new ThreadPoolExecutor(
            10,     // 固定线程数（漏桶出水速率）
            10,
            0, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(1000),  // 队列容量（桶大小）
            new ThreadPoolExecutor.AbortPolicy()
        );
    }
}
```

### 分布式限流（Redis + Lua）

**实现**（令牌桶）：
```java
@Component
public class DistributedTokenBucketLimiter {

    @Autowired
    private StringRedisTemplate redisTemplate;

    /**
     * 分布式令牌桶限流
     * @param key 限流键
     * @param capacity 桶容量
     * @param rate 令牌生成速率（个/秒）
     */
    public boolean tryAcquire(String key, int capacity, int rate) {
        String redisKey = "rate_limit:token_bucket:" + key;
        long now = System.currentTimeMillis();

        // Lua 脚本实现令牌桶
        String script =
            "local capacity = tonumber(ARGV[1]) " +
            "local rate = tonumber(ARGV[2]) " +
            "local now = tonumber(ARGV[3]) " +
            "local tokens = tonumber(redis.call('get', KEYS[1]) or capacity) " +
            "local last = tonumber(redis.call('get', KEYS[2]) or now) " +
            "local delta = math.max(0, now - last) " +
            "local newTokens = math.min(capacity, tokens + delta * rate / 1000) " +
            "if newTokens >= 1 then " +
            "    redis.call('setex', KEYS[1], 3600, newTokens - 1) " +
            "    redis.call('setex', KEYS[2], 3600, now) " +
            "    return 1 " +
            "else " +
            "    return 0 " +
            "end";

        Long result = redisTemplate.execute(
            new DefaultRedisScript<>(script, Long.class),
            Arrays.asList(redisKey, redisKey + ":last"),
            String.valueOf(capacity),
            String.valueOf(rate),
            String.valueOf(now)
        );

        return result != null && result == 1;
    }
}
```

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 秒杀系统如何防止超卖？**
- Redis Lua 脚本原子扣减库存
- 分布式锁
- 数据库乐观锁（version 字段）

**Q2: 秒杀系统如何提高性能？**
- 前端：按钮置灰、验证码
- 网关：IP 限流、用户限流
- 缓存：Redis 预热、本地缓存
- 异步：消息队列、异步落库

**Q3: 高并发计数器如何设计？**
- 单机：LongAdder（分段累加）
- 分布式：Redis + 本地缓存 + 定时上报
- 时间窗口：按分钟统计，滑动窗口查询

**Q4: 限流算法有哪些？**
- 固定窗口：简单，有临界突刺问题
- 滑动窗口：平滑，内存占用高
- 漏桶：匀速处理，无法应对突发
- 令牌桶：应对突发，实现复杂

**Q5: 固定窗口和滑动窗口的区别？**
- 固定窗口：按整秒统计，临界时刻可能超限
- 滑动窗口：按任意时间段统计，更精确

**Q6: 令牌桶和漏桶的区别？**
- 令牌桶：允许突发流量（积累令牌）
- 漏桶：匀速处理，削峰填谷

**Q7: 如何实现分布式限流？**
- Redis + Lua 脚本
- 滑动窗口（Sorted Set）
- 令牌桶（Hash 存储令牌数和时间戳）

**Q8: 秒杀系统如何防止恶意请求？**
- 验证码（防止机器刷单）
- IP 限流（每秒 10 次）
- 用户限流（每秒 1 次）
- Token 机制（一次性令牌）

---

## 参考资料

1. **书籍推荐**：《亿级流量网站架构核心技术》、《高并发系统设计 40 问》
2. **开源项目**：
   - Sentinel：阿里巴巴流控组件
   - Guava RateLimiter：Google 限流工具
3. **限流算法论文**：《Token Bucket Algorithm》
