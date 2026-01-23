# 服务治理与微服务

## 1. 服务注册与发现

### 1.1 注册中心作用
- 服务注册：服务启动时注册到注册中心
- 服务发现：客户端从注册中心获取服务列表
- 健康检查：检测服务是否可用
- 负载均衡：选择服务实例

### 1.2 常见注册中心
- **ZooKeeper**
  - CP 系统，强一致性
  - 集群模式，ZAB 协议
  - 适合对一致性要求高的场景
- **Eureka**
  - AP 系统，最终一致性
  - 自我保护机制
  - 适合云环境，容忍网络分区
- **Consul**
  - CP/AP 可配置
  - 支持多数据中心
  - 内置健康检查和 KV 存储
- **Nacos**
  - 阿里开源，支持配置管理
  - CP/AP 双模式
  - 动态配置更新

### 1.3 注册中心对比
| 特性 | ZooKeeper | Eureka | Consul | Nacos |
|------|-----------|--------|--------|-------|
| CAP | CP | AP | CP/AP | CP/AP |
| 健康检查 | 心跳 | 心跳 | 多种 | 心跳/TCP |
| 配置管理 | 支持 | 不支持 | 支持 | 支持 |
| 多数据中心 | 不支持 | 不支持 | 支持 | 支持 |
| 语言 | Java | Java | Go | Java |

### 1.4 服务注册流程
```java
/**
 * 服务注册示例
 */
public class ServiceRegistration {

    /**
     * 服务启动时注册
     */
    public void register(ServiceInstance instance) {
        // 1. 构建服务实例信息
        ServiceInstance instance = ServiceInstance.builder()
            .serviceName("user-service")
            .host("192.168.1.100")
            .port(8080)
            .metadata(Map.of("version", "1.0", "weight", "100"))
            .build();

        // 2. 注册到注册中心
        registryClient.register(instance);

        // 3. 启动心跳任务
        heartbeatScheduler.scheduleAtFixedRate(
            () -> registryClient.heartbeat(instance),
            0, 30, TimeUnit.SECONDS
        );
    }

    /**
     * 服务关闭时注销
     */
    public void deregister(ServiceInstance instance) {
        registryClient.deregister(instance);
        heartbeatScheduler.shutdown();
    }
}
```

## 2. 服务间通信

### 2.1 RPC 框架
- **Dubbo**
  - 阿里开源，成熟稳定
  - 支持多种协议和序列化
  - 服务治理功能丰富
- **gRPC**
  - Google 开源，基于 HTTP/2
  - Protobuf 序列化
  - 跨语言支持好

### 2.2 负载均衡策略
- 随机（Random）
- 轮询（Round Robin）
- 加权轮询（Weighted Round Robin）
- 最少活跃调用（Least Active）
- 一致性哈希（Consistent Hash）

### 2.3 负载均衡实现
```java
/**
 * 负载均衡策略实现
 */
public interface LoadBalancer {
    ServiceInstance select(List<ServiceInstance> instances);
}

/**
 * 加权轮询
 */
public class WeightedRoundRobinLoadBalancer implements LoadBalancer {
    private AtomicInteger position = new AtomicInteger(0);

    @Override
    public ServiceInstance select(List<ServiceInstance> instances) {
        // 计算权重总和
        int totalWeight = instances.stream()
            .mapToInt(ServiceInstance::getWeight)
            .sum();

        // 当前位置
        int current = position.getAndIncrement() % totalWeight;

        // 选择实例
        int weightSum = 0;
        for (ServiceInstance instance : instances) {
            weightSum += instance.getWeight();
            if (current < weightSum) {
                return instance;
            }
        }
        return instances.get(0);
    }
}

/**
 * 最少活跃调用
 */
public class LeastActiveLoadBalancer implements LoadBalancer {
    // 记录每个实例的活跃请求数
    private Map<ServiceInstance, AtomicInteger> activeCount = new ConcurrentHashMap<>();

    @Override
    public ServiceInstance select(List<ServiceInstance> instances) {
        return instances.stream()
            .min(Comparator.comparingInt(
                inst -> activeCount.getOrDefault(inst, new AtomicInteger(0)).get()
            ))
            .orElse(instances.get(0));
    }

    public void onStart(ServiceInstance instance) {
        activeCount.computeIfAbsent(instance, k -> new AtomicInteger(0)).incrementAndGet();
    }

    public void onComplete(ServiceInstance instance) {
        activeCount.computeIfAbsent(instance, k -> new AtomicInteger(0)).decrementAndGet();
    }
}
```

## 3. 微服务架构核心问题 ⭐⭐⭐⭐⭐

### 3.1 服务拆分
- **拆分原则**
  - 单一职责
  - 业务边界清晰
  - 高内聚低耦合
- **拆分粒度**
  - 不宜过细（增加复杂度）
  - 不宜过粗（失去微服务优势）

### 3.2 分布式事务 ⭐⭐⭐⭐⭐

#### 两阶段提交（2PC）
```
阶段一：准备阶段
┌──────────────────────────────────────────────────────┐
│ Coordinator                                          │
│      │                                               │
│      ├──── Prepare ────> Participant A ──── OK ────┤ │
│      │                                               │
│      ├──── Prepare ────> Participant B ──── OK ────┤ │
│      │                                               │
│      └──── Prepare ────> Participant C ──── OK ────┘ │
└──────────────────────────────────────────────────────┘

阶段二：提交阶段
┌──────────────────────────────────────────────────────┐
│ Coordinator                                          │
│      │                                               │
│      ├──── Commit ────> Participant A ──── ACK ────┤ │
│      │                                               │
│      ├──── Commit ────> Participant B ──── ACK ────┤ │
│      │                                               │
│      └──── Commit ────> Participant C ──── ACK ────┘ │
└──────────────────────────────────────────────────────┘

问题：
1. 同步阻塞：准备阶段锁定资源
2. 单点故障：协调者宕机导致参与者阻塞
3. 数据不一致：部分节点提交成功
```

#### TCC（Try-Confirm-Cancel）
```java
/**
 * TCC 接口定义
 */
public interface TccService {
    /**
     * Try：尝试执行，预留资源
     */
    boolean tryExecute(BusinessContext context);

    /**
     * Confirm：确认执行，提交预留资源
     */
    boolean confirm(BusinessContext context);

    /**
     * Cancel：取消执行，释放预留资源
     */
    boolean cancel(BusinessContext context);
}

/**
 * TCC 订单服务示例
 */
public class OrderTccService implements TccService {

    @Override
    public boolean tryExecute(BusinessContext context) {
        // 创建订单，状态为 TRYING
        Order order = new Order();
        order.setStatus(OrderStatus.TRYING);
        order.setAmount(context.getAmount());
        orderRepository.save(order);

        context.put("orderId", order.getId());
        return true;
    }

    @Override
    public boolean confirm(BusinessContext context) {
        // 确认订单，状态改为 CONFIRMED
        Long orderId = context.get("orderId");
        Order order = orderRepository.findById(orderId);
        order.setStatus(OrderStatus.CONFIRMED);
        orderRepository.save(order);
        return true;
    }

    @Override
    public boolean cancel(BusinessContext context) {
        // 取消订单，状态改为 CANCELLED
        Long orderId = context.get("orderId");
        Order order = orderRepository.findById(orderId);
        order.setStatus(OrderStatus.CANCELLED);
        orderRepository.save(order);
        return true;
    }
}

/**
 * TCC 库存服务示例
 */
public class InventoryTccService implements TccService {

    @Override
    public boolean tryExecute(BusinessContext context) {
        // 冻结库存（不实际扣减）
        String productId = context.get("productId");
        int quantity = context.get("quantity");

        // 检查库存
        Inventory inventory = inventoryRepository.findByProductId(productId);
        if (inventory.getAvailable() < quantity) {
            return false;
        }

        // 冻结
        inventory.setFrozen(inventory.getFrozen() + quantity);
        inventory.setAvailable(inventory.getAvailable() - quantity);
        inventoryRepository.save(inventory);
        return true;
    }

    @Override
    public boolean confirm(BusinessContext context) {
        // 确认扣减：释放冻结
        String productId = context.get("productId");
        int quantity = context.get("quantity");

        Inventory inventory = inventoryRepository.findByProductId(productId);
        inventory.setFrozen(inventory.getFrozen() - quantity);
        inventoryRepository.save(inventory);
        return true;
    }

    @Override
    public boolean cancel(BusinessContext context) {
        // 取消：恢复库存
        String productId = context.get("productId");
        int quantity = context.get("quantity");

        Inventory inventory = inventoryRepository.findByProductId(productId);
        inventory.setFrozen(inventory.getFrozen() - quantity);
        inventory.setAvailable(inventory.getAvailable() + quantity);
        inventoryRepository.save(inventory);
        return true;
    }
}
```

#### Saga 模式
```
Saga 模式：长事务拆分为多个本地事务

正向流程：T1 -> T2 -> T3 -> T4
补偿流程：C4 <- C3 <- C2 <- C1

执行过程：
T1（创建订单）
    ↓ 成功
T2（扣减库存）
    ↓ 成功
T3（扣减余额）
    ↓ 失败！
C2（恢复库存）
    ↓
C1（取消订单）

实现方式：
1. 编排式（Choreography）
   - 事件驱动
   - 服务间通过事件通信
   - 去中心化

2. 协调式（Orchestration）
   - 中央协调器
   - 协调器调用各服务
   - 集中管理
```

#### 本地消息表
```
本地消息表方案：

1. 发送方
   ┌─────────────────────────────────────┐
   │ 本地事务：                           │
   │   - 业务数据写入业务表               │
   │   - 消息写入消息表（状态：待发送）    │
   └─────────────────────────────────────┘
            │
            ▼
   ┌─────────────────────────────────────┐
   │ 定时任务：                           │
   │   - 扫描待发送消息                   │
   │   - 发送到 MQ                       │
   │   - 更新状态为已发送                 │
   └─────────────────────────────────────┘

2. 接收方
   ┌─────────────────────────────────────┐
   │ 消费消息：                           │
   │   - 幂等检查（去重表）               │
   │   - 执行业务逻辑                     │
   │   - 返回确认                         │
   └─────────────────────────────────────┘

代码示例：
```

```java
/**
 * 本地消息表实现
 */
public class LocalMessageTableService {

    @Transactional
    public void createOrderWithMessage(Order order) {
        // 1. 保存订单
        orderRepository.save(order);

        // 2. 保存消息到本地消息表
        LocalMessage message = new LocalMessage();
        message.setMessageId(UUID.randomUUID().toString());
        message.setContent(JSON.toJSONString(order));
        message.setStatus(MessageStatus.PENDING);
        message.setRetryCount(0);
        message.setCreateTime(new Date());
        localMessageRepository.save(message);
    }

    /**
     * 定时任务：发送消息
     */
    @Scheduled(fixedRate = 5000)
    public void sendPendingMessages() {
        List<LocalMessage> messages = localMessageRepository
            .findByStatusAndRetryCountLessThan(MessageStatus.PENDING, 3);

        for (LocalMessage message : messages) {
            try {
                // 发送到 MQ
                messageQueue.send(message.getContent());

                // 更新状态
                message.setStatus(MessageStatus.SENT);
                localMessageRepository.save(message);
            } catch (Exception e) {
                // 重试计数
                message.setRetryCount(message.getRetryCount() + 1);
                localMessageRepository.save(message);
            }
        }
    }
}
```

#### 分布式事务对比
| 方案 | 一致性 | 性能 | 复杂度 | 适用场景 |
|------|--------|------|--------|----------|
| 2PC | 强一致 | 低 | 中 | 数据库层事务 |
| TCC | 最终一致 | 中 | 高 | 金融业务 |
| Saga | 最终一致 | 高 | 中 | 长事务 |
| 本地消息表 | 最终一致 | 高 | 低 | 异步场景 |

### 3.3 服务熔断与降级 ⭐⭐⭐⭐⭐

#### 熔断器原理
```
熔断器状态机：

        ┌─────────────────────────────────────┐
        │                                     │
        ▼                                     │
   ┌─────────┐    失败率超阈值    ┌─────────┐ │
   │  CLOSED │ ──────────────> │  OPEN   │ │
   │  (关闭)  │                 │  (打开)  │ │
   └─────────┘                 └─────────┘ │
        ▲                           │      │
        │                           │ 超时  │
        │                           ▼      │
        │                    ┌───────────┐ │
        │     探测成功       │ HALF_OPEN │ │
        └─────────────────── │  (半开)   │ ─┘
                探测失败     └───────────┘
```

#### 熔断器实现
```java
/**
 * 熔断器实现
 */
public class CircuitBreaker {
    private State state = State.CLOSED;
    private AtomicInteger failureCount = new AtomicInteger(0);
    private AtomicInteger successCount = new AtomicInteger(0);
    private long lastFailureTime = 0;

    // 配置参数
    private final int failureThreshold;      // 失败阈值
    private final long resetTimeout;         // 重置超时（毫秒）
    private final int halfOpenMaxCalls;      // 半开状态最大调用次数

    public CircuitBreaker(int failureThreshold, long resetTimeout, int halfOpenMaxCalls) {
        this.failureThreshold = failureThreshold;
        this.resetTimeout = resetTimeout;
        this.halfOpenMaxCalls = halfOpenMaxCalls;
    }

    public <T> T execute(Supplier<T> action, Supplier<T> fallback) {
        if (!allowRequest()) {
            return fallback.get();
        }

        try {
            T result = action.get();
            onSuccess();
            return result;
        } catch (Exception e) {
            onFailure();
            return fallback.get();
        }
    }

    private boolean allowRequest() {
        switch (state) {
            case CLOSED:
                return true;
            case OPEN:
                // 检查是否可以进入半开状态
                if (System.currentTimeMillis() - lastFailureTime > resetTimeout) {
                    state = State.HALF_OPEN;
                    successCount.set(0);
                    return true;
                }
                return false;
            case HALF_OPEN:
                // 半开状态只允许有限的请求通过
                return successCount.get() < halfOpenMaxCalls;
            default:
                return false;
        }
    }

    private void onSuccess() {
        switch (state) {
            case CLOSED:
                failureCount.set(0);
                break;
            case HALF_OPEN:
                successCount.incrementAndGet();
                if (successCount.get() >= halfOpenMaxCalls) {
                    // 探测成功，恢复关闭状态
                    state = State.CLOSED;
                    failureCount.set(0);
                }
                break;
        }
    }

    private void onFailure() {
        lastFailureTime = System.currentTimeMillis();
        switch (state) {
            case CLOSED:
                if (failureCount.incrementAndGet() >= failureThreshold) {
                    state = State.OPEN;
                }
                break;
            case HALF_OPEN:
                // 半开状态下失败，重新打开熔断器
                state = State.OPEN;
                break;
        }
    }

    enum State {
        CLOSED, OPEN, HALF_OPEN
    }
}
```

#### 降级策略
```java
/**
 * 降级策略
 */
public interface FallbackStrategy<T> {
    T fallback(Throwable cause);
}

/**
 * 返回默认值
 */
public class DefaultValueFallback<T> implements FallbackStrategy<T> {
    private final T defaultValue;

    public DefaultValueFallback(T defaultValue) {
        this.defaultValue = defaultValue;
    }

    @Override
    public T fallback(Throwable cause) {
        return defaultValue;
    }
}

/**
 * 返回缓存
 */
public class CacheFallback<T> implements FallbackStrategy<T> {
    private final Cache<String, T> cache;
    private final String cacheKey;

    @Override
    public T fallback(Throwable cause) {
        return cache.getIfPresent(cacheKey);
    }
}

/**
 * 使用示例
 */
public class UserService {
    private final CircuitBreaker circuitBreaker;
    private final Cache<String, User> userCache;

    public User getUser(String userId) {
        return circuitBreaker.execute(
            // 正常调用
            () -> {
                User user = remoteUserService.getUser(userId);
                userCache.put(userId, user);
                return user;
            },
            // 降级：返回缓存
            () -> userCache.getIfPresent(userId)
        );
    }
}
```

### 3.4 限流 ⭐⭐⭐⭐⭐

#### 限流算法详解

##### 固定窗口计数器
```java
/**
 * 固定窗口计数器
 */
public class FixedWindowRateLimiter {
    private final int limit;           // 窗口内最大请求数
    private final long windowSize;     // 窗口大小（毫秒）
    private long windowStart;
    private AtomicInteger count = new AtomicInteger(0);

    public FixedWindowRateLimiter(int limit, long windowSize) {
        this.limit = limit;
        this.windowSize = windowSize;
        this.windowStart = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 检查是否需要重置窗口
        if (now - windowStart >= windowSize) {
            windowStart = now;
            count.set(0);
        }

        // 检查是否超过限制
        if (count.get() < limit) {
            count.incrementAndGet();
            return true;
        }
        return false;
    }
}

/*
问题：临界点突发
窗口1: |---99请求---|---0请求---|
窗口2:             |---99请求---|---0请求---|
          ↑           ↑
      窗口1末尾    窗口2开头
      1秒内可能有 198 个请求通过
*/
```

##### 滑动窗口计数器
```java
/**
 * 滑动窗口计数器
 */
public class SlidingWindowRateLimiter {
    private final int limit;
    private final long windowSize;
    private final int subWindowCount;  // 子窗口数量
    private final long subWindowSize;
    private final AtomicInteger[] subWindows;
    private volatile long currentSubWindowStart;

    public SlidingWindowRateLimiter(int limit, long windowSize, int subWindowCount) {
        this.limit = limit;
        this.windowSize = windowSize;
        this.subWindowCount = subWindowCount;
        this.subWindowSize = windowSize / subWindowCount;
        this.subWindows = new AtomicInteger[subWindowCount];
        for (int i = 0; i < subWindowCount; i++) {
            subWindows[i] = new AtomicInteger(0);
        }
        this.currentSubWindowStart = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 滑动窗口：清理过期的子窗口
        int expiredWindows = (int) ((now - currentSubWindowStart) / subWindowSize);
        if (expiredWindows > 0) {
            for (int i = 0; i < Math.min(expiredWindows, subWindowCount); i++) {
                int index = (int) ((currentSubWindowStart / subWindowSize + i) % subWindowCount);
                subWindows[index].set(0);
            }
            currentSubWindowStart = now - (now % subWindowSize);
        }

        // 计算当前窗口总请求数
        int totalCount = 0;
        for (AtomicInteger subWindow : subWindows) {
            totalCount += subWindow.get();
        }

        if (totalCount < limit) {
            int currentIndex = (int) ((now / subWindowSize) % subWindowCount);
            subWindows[currentIndex].incrementAndGet();
            return true;
        }
        return false;
    }
}
```

##### 漏桶算法
```java
/**
 * 漏桶算法
 * 以恒定速率处理请求
 */
public class LeakyBucketRateLimiter {
    private final int capacity;        // 桶容量
    private final double leakRate;     // 漏出速率（请求/毫秒）
    private double water = 0;          // 当前水量
    private long lastLeakTime;

    public LeakyBucketRateLimiter(int capacity, double leakRatePerSecond) {
        this.capacity = capacity;
        this.leakRate = leakRatePerSecond / 1000.0;
        this.lastLeakTime = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        long now = System.currentTimeMillis();

        // 漏水：计算流出的水量
        double leaked = (now - lastLeakTime) * leakRate;
        water = Math.max(0, water - leaked);
        lastLeakTime = now;

        // 尝试加水
        if (water < capacity) {
            water++;
            return true;
        }
        return false;
    }
}

/*
特点：
- 请求以恒定速率被处理
- 即使有突发流量，处理速度也不变
- 适合需要平滑流量的场景
*/
```

##### 令牌桶算法
```java
/**
 * 令牌桶算法
 * 允许一定程度的突发流量
 */
public class TokenBucketRateLimiter {
    private final int capacity;        // 桶容量
    private final double refillRate;   // 填充速率（令牌/毫秒）
    private double tokens;             // 当前令牌数
    private long lastRefillTime;

    public TokenBucketRateLimiter(int capacity, double refillRatePerSecond) {
        this.capacity = capacity;
        this.refillRate = refillRatePerSecond / 1000.0;
        this.tokens = capacity;  // 初始满桶
        this.lastRefillTime = System.currentTimeMillis();
    }

    public synchronized boolean tryAcquire() {
        return tryAcquire(1);
    }

    public synchronized boolean tryAcquire(int permits) {
        refill();

        if (tokens >= permits) {
            tokens -= permits;
            return true;
        }
        return false;
    }

    private void refill() {
        long now = System.currentTimeMillis();
        double newTokens = (now - lastRefillTime) * refillRate;
        tokens = Math.min(capacity, tokens + newTokens);
        lastRefillTime = now;
    }
}

/*
特点：
- 允许突发流量（最多 capacity 个请求）
- 平均速率由 refillRate 控制
- 比漏桶更灵活
*/
```

##### 算法对比
```
┌────────────────────────────────────────────────────────────────┐
│ 算法对比                                                       │
├─────────────┬───────────────────────────────────────────────────┤
│ 固定窗口     │ 简单，但有临界突发问题                            │
├─────────────┼───────────────────────────────────────────────────┤
│ 滑动窗口     │ 解决临界问题，实现复杂                            │
├─────────────┼───────────────────────────────────────────────────┤
│ 漏桶        │ 平滑流量，无法应对突发                             │
├─────────────┼───────────────────────────────────────────────────┤
│ 令牌桶       │ 允许突发，实际应用最广                            │
└─────────────┴───────────────────────────────────────────────────┘
```

### 3.5 链路追踪
- **核心概念**
  - TraceID：全局唯一 ID
  - SpanID：单次调用 ID
  - 父子关系
- **常见框架**
  - Zipkin
  - SkyWalking
  - Jaeger

### 3.6 配置中心
- **配置管理需求**
  - 集中管理
  - 动态更新
  - 版本管理
  - 权限控制
- **常见方案**
  - Apollo（携程）
  - Nacos（阿里）
  - Spring Cloud Config

## 4. API 网关

### 4.1 网关职责
- 路由转发
- 统一认证鉴权
- 限流熔断
- 日志监控
- 协议转换

### 4.2 常见网关
- **Nginx + Lua**
  - 性能高
  - 配置灵活
- **Kong**
  - 基于 OpenResty
  - 插件丰富
- **Spring Cloud Gateway**
  - 异步非阻塞
  - 与 Spring 生态集成好
- **Zuul**
  - Netflix 开源
  - 同步阻塞（Zuul 1.x）

## 5. 服务网格（Service Mesh）⭐⭐⭐⭐

### 5.1 Service Mesh 概念
```
传统微服务架构问题：
1. SDK 侵入：每种语言需要实现 SDK
2. 升级困难：SDK 升级需要重新部署所有服务
3. 功能分散：限流、熔断等功能分散在各服务

Service Mesh 解决方案：
- 将服务治理能力下沉到基础设施层
- 通过 Sidecar 代理所有网络流量
- 服务只关注业务逻辑

架构示意：
┌────────────────────────────────────────────────────────┐
│ Service A                     Service B               │
│ ┌─────────┐                   ┌─────────┐            │
│ │  业务    │                   │  业务    │            │
│ │  代码    │                   │  代码    │            │
│ └────┬────┘                   └────┬────┘            │
│      │                             │                 │
│ ┌────┴────┐                   ┌────┴────┐            │
│ │ Sidecar │ ←───── mTLS ─────→ │ Sidecar │            │
│ │ (Envoy) │                   │ (Envoy) │            │
│ └─────────┘                   └─────────┘            │
│                                                      │
│                 Control Plane                        │
│ ┌─────────────────────────────────────────────────┐ │
│ │ Pilot │ Citadel │ Galley │ Mixer                 │ │
│ └─────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────┘
```

### 5.2 Istio 架构

#### 数据平面（Data Plane）
```
Envoy Proxy 功能：
1. 服务发现
2. 负载均衡
3. TLS 终止
4. 健康检查
5. 熔断
6. 故障注入
7. 流量镜像
8. 丰富的可观测性

流量拦截原理：
通过 iptables 规则将流量重定向到 Envoy

入站流量：
  外部请求 → iptables → Envoy Inbound → 应用

出站流量：
  应用请求 → iptables → Envoy Outbound → 目标服务
```

#### 控制平面（Control Plane）
```
Istiod（Istio 1.5+ 统一组件）：

1. Pilot（服务发现与配置分发）
   - 将服务信息转换为 Envoy 配置
   - 支持多种注册中心（Kubernetes, Consul）
   - xDS API 分发配置

2. Citadel（安全）
   - 证书管理
   - mTLS 双向认证
   - 身份认证

3. Galley（配置验证）
   - 配置验证和处理
   - 隔离 Istio 与底层平台
```

### 5.3 Service Mesh 功能

#### 流量管理
```yaml
# VirtualService 示例：金丝雀发布
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service
spec:
  hosts:
    - user-service
  http:
    - match:
        - headers:
            x-user-type:
              exact: "beta"
      route:
        - destination:
            host: user-service
            subset: v2
    - route:
        - destination:
            host: user-service
            subset: v1
          weight: 90
        - destination:
            host: user-service
            subset: v2
          weight: 10
---
# DestinationRule 示例：定义子集和负载均衡
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: user-service
spec:
  host: user-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
    loadBalancer:
      simple: ROUND_ROBIN
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

#### 弹性功能
```yaml
# 熔断配置
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: user-service
spec:
  host: user-service
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        maxRequestsPerConnection: 10
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

#### 安全功能
```yaml
# mTLS 配置
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
---
# 授权策略
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: user-service-policy
  namespace: production
spec:
  selector:
    matchLabels:
      app: user-service
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/order-service"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/users/*"]
```

## 6. 面试要点总结

### 6.1 核心知识点
| 知识点 | 重要程度 | 考察频率 |
|--------|----------|----------|
| 分布式事务 | ⭐⭐⭐⭐⭐ | 非常高 |
| 限流算法 | ⭐⭐⭐⭐⭐ | 高 |
| 熔断降级 | ⭐⭐⭐⭐⭐ | 高 |
| 服务注册发现 | ⭐⭐⭐⭐ | 高 |
| Service Mesh | ⭐⭐⭐⭐ | 中 |
| 负载均衡 | ⭐⭐⭐⭐ | 高 |

### 6.2 关键记忆点
```
分布式事务：
- 2PC：强一致，同步阻塞
- TCC：业务侵入，需要 Try/Confirm/Cancel
- Saga：长事务拆分，补偿机制
- 本地消息表：可靠消息，最终一致

限流算法：
- 令牌桶：允许突发，实际应用最广
- 漏桶：平滑流量，恒定速率
- 滑动窗口：解决固定窗口临界问题

熔断器：
- 三状态：CLOSED → OPEN → HALF_OPEN
- 失败率触发，超时恢复
- 半开状态探测
```

## 7. 常见面试题

### 7.1 分布式事务

**Q1：TCC 和 2PC 的区别？**
```
答：
2PC：
- 数据库层面的协议
- 需要数据库支持 XA 协议
- 资源锁定时间长
- 强一致性

TCC：
- 业务层面的协议
- 需要业务实现 Try/Confirm/Cancel
- 资源锁定时间短（预留而非锁定）
- 最终一致性
- 更灵活但开发成本高
```

**Q2：如何保证本地消息表的可靠性？**
```
答：
1. 业务操作和消息写入在同一事务
2. 定时任务扫描未发送的消息
3. 消息发送失败重试
4. 消费端幂等处理
5. 死信队列处理失败消息
```

### 7.2 限流

**Q3：令牌桶和漏桶的区别？**
```
答：
令牌桶：
- 以恒定速率生成令牌
- 请求需要获取令牌才能执行
- 允许突发流量（桶满时）
- 适合允许短时突发的场景

漏桶：
- 以恒定速率处理请求
- 请求进入桶等待处理
- 不允许突发，平滑流量
- 适合需要平滑处理的场景
```

**Q4：如何实现分布式限流？**
```
答：
1. Redis + Lua 脚本
   - 原子性操作
   - 集中式限流

2. 令牌桶 + Redis
   - 令牌存储在 Redis
   - 定时任务补充令牌

3. 网关限流
   - 在 API 网关层统一限流
   - 如 Sentinel、Kong

4. 服务端限流
   - Guava RateLimiter（单机）
   - 需要考虑分布式环境
```

### 7.3 熔断降级

**Q5：熔断器的三种状态及转换条件？**
```
答：
CLOSED（关闭）：
- 正常状态，请求正常通过
- 失败率达到阈值 → OPEN

OPEN（打开）：
- 熔断状态，请求直接失败
- 超时后 → HALF_OPEN

HALF_OPEN（半开）：
- 探测状态，允许部分请求通过
- 探测成功 → CLOSED
- 探测失败 → OPEN
```

**Q6：降级策略有哪些？**
```
答：
1. 返回默认值
   - 适合非核心功能
   - 如：推荐服务降级返回热门商品

2. 返回缓存数据
   - 适合数据时效性要求不高
   - 如：用户信息服务降级返回缓存

3. 快速失败
   - 直接返回错误
   - 适合宁可失败不可错误的场景

4. 排队等待
   - 限制并发，排队处理
   - 适合可接受延迟的场景

5. 功能降级
   - 关闭非核心功能
   - 如：双11关闭退款功能
```

### 7.4 Service Mesh

**Q7：Service Mesh 解决了什么问题？**
```
答：
1. SDK 侵入问题
   - 不再需要在每个服务集成 SDK
   - 服务治理逻辑下沉到 Sidecar

2. 多语言问题
   - 不同语言不需要各自实现 SDK
   - Sidecar 统一处理

3. 升级困难问题
   - 升级只需更新 Sidecar
   - 不需要重新部署业务服务

4. 可观测性问题
   - 统一的监控、追踪、日志
   - 无需修改业务代码
```

**Q8：Istio 的流量管理如何实现金丝雀发布？**
```
答：
1. 定义多个服务版本（Deployment）
2. 创建 DestinationRule 定义 subset
3. 创建 VirtualService 配置流量权重

示例：
- v1 版本接收 90% 流量
- v2 版本接收 10% 流量
- 可以基于 header、cookie 等路由到特定版本
- 逐步调整权重直到全量发布
```
