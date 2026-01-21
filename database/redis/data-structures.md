# Redis 数据结构

> Redis 的高性能很大程度上得益于其精心设计的底层数据结构。理解这些数据结构是掌握 Redis 的关键。

## 数据类型概览 ⭐⭐⭐⭐⭐

Redis 提供了 5 种基本数据类型和多种高级数据类型：

| 数据类型 | 底层编码 | 应用场景 |
|---------|---------|---------|
| **String** | int、embstr、raw | 缓存、计数器、分布式锁 |
| **List** | quicklist (ziplist + linkedlist) | 消息队列、时间线 |
| **Hash** | ziplist、hashtable | 对象存储、购物车 |
| **Set** | intset、hashtable | 去重、共同好友 |
| **ZSet** | ziplist、skiplist + hashtable | 排行榜、延时队列 |

### 对象编码机制

Redis 内部使用 **redisObject** 结构来表示所有数据类型：

```c
typedef struct redisObject {
    unsigned type:4;        // 数据类型（String、List、Hash等）
    unsigned encoding:4;    // 编码方式（int、embstr、raw等）
    unsigned lru:24;        // LRU 时间或 LFU 数据
    int refcount;          // 引用计数
    void *ptr;             // 指向实际数据的指针
} robj;
```

**查看对象编码**：
```bash
# 查看 key 的编码类型
OBJECT ENCODING key
```

---

## String 类型 ⭐⭐⭐⭐⭐

### 底层实现

String 类型根据值的不同，有 **3 种编码方式**：

| 编码 | 条件 | 说明 |
|------|------|------|
| **int** | 值是整数且在 long 范围内 | 直接存储在 redisObject 的 ptr 中 |
| **embstr** | 字符串长度 ≤ 44 字节 | redisObject 和 SDS 连续分配，只需一次内存分配 |
| **raw** | 字符串长度 > 44 字节 | redisObject 和 SDS 分开分配 |

### SDS（Simple Dynamic String）

Redis 自己实现的字符串结构，而不是使用 C 语言的 `char*`：

```c
struct sdshdr {
    int len;        // 已使用长度
    int free;       // 剩余可用空间
    char buf[];     // 字节数组
};
```

**SDS vs C 字符串**：

| 特性 | C 字符串 | SDS |
|------|---------|-----|
| **获取长度** | O(n) 遍历 | O(1) 直接读取 len |
| **二进制安全** | 否（遇到 \0 结束） | 是（通过 len 判断） |
| **缓冲区溢出** | 可能溢出 | 自动扩容，杜绝溢出 |
| **内存分配** | 每次修改都重新分配 | 空间预分配、惰性释放 |

**空间预分配策略**：
```
- len < 1MB: 分配 len 大小的未使用空间（free = len）
- len ≥ 1MB: 分配 1MB 的未使用空间（free = 1MB）
```

### 常用命令

```bash
# 基本操作
SET key value [EX seconds] [PX milliseconds] [NX|XX]
GET key
MSET key1 value1 key2 value2 ...
MGET key1 key2 ...

# 计数器
INCR key          # 自增1
INCRBY key 10     # 自增指定值
DECR key          # 自减1

# 位操作
SETBIT key offset value
GETBIT key offset
BITCOUNT key

# 示例：分布式锁
SET lock:resource unique_value NX EX 10

# 示例：计数器
INCR page:views:123
```

### 应用场景

**1. 缓存对象**
```bash
# 缓存用户信息（序列化为 JSON）
SET user:1001 '{"id":1001,"name":"Zhang","age":25}'
```

**2. 分布式锁**
```bash
# 加锁
SET lock:order:123 uuid123 NX EX 30

# 解锁（使用 Lua 脚本保证原子性）
if redis.call("get",KEYS[1]) == ARGV[1] then
    return redis.call("del",KEYS[1])
else
    return 0
end
```

**3. 计数器**
```bash
# 文章点赞数
INCR article:1001:likes

# 限流（固定窗口）
INCR api:user:123:20240117
EXPIRE api:user:123:20240117 60
```

---

## List 类型 ⭐⭐⭐⭐

### 底层实现：QuickList

Redis 3.2 之前使用 **ziplist** 或 **linkedlist**，3.2 之后统一使用 **quicklist**（ziplist 和 linkedlist 的混合体）。

**QuickList 结构**：
```
quicklist = linkedlist of ziplists

┌─────────┐    ┌─────────┐    ┌─────────┐
│ ziplist │ -> │ ziplist │ -> │ ziplist │
│ [1,2,3] │    │ [4,5,6] │    │ [7,8,9] │
└─────────┘    └─────────┘    └─────────┘
```

**优点**：
- 每个 ziplist 存储多个元素，减少内存碎片
- ziplist 内部连续存储，缓存友好
- linkedlist 提供灵活的插入删除

**配置**：
```bash
# 每个 ziplist 的大小限制
list-max-ziplist-size -2  # -2 表示 8KB

# 是否压缩中间节点（两端不压缩，便于 push/pop）
list-compress-depth 0
```

### 常用命令

```bash
# 左侧操作
LPUSH key value1 value2 ...    # 左侧插入
LPOP key                       # 左侧弹出
LRANGE key 0 -1                # 查看所有元素

# 右侧操作
RPUSH key value
RPOP key

# 阻塞操作
BLPOP key timeout              # 阻塞式左侧弹出
BRPOP key timeout

# 列表操作
LLEN key                       # 长度
LINDEX key index               # 获取指定索引元素
LINSERT key BEFORE|AFTER pivot value

# 示例：消息队列
LPUSH queue:tasks task1 task2
BRPOP queue:tasks 0           # 消费者阻塞等待
```

### 应用场景

**1. 消息队列**
```bash
# 生产者
LPUSH queue:tasks '{"type":"email","to":"user@example.com"}'

# 消费者
BRPOP queue:tasks 0
```

**2. 最新动态（时间线）**
```bash
# 用户发布动态
LPUSH timeline:user:123 "post_id:1001"

# 获取最新 10 条动态
LRANGE timeline:user:123 0 9
```

**3. 固定长度列表**
```bash
# 保留最新 100 条日志
LPUSH logs:app message
LTRIM logs:app 0 99
```

---

## Hash 类型 ⭐⭐⭐⭐⭐

### 底层实现

Hash 类型有 **2 种编码方式**：

| 编码 | 条件 | 说明 |
|------|------|------|
| **ziplist** | 元素个数 ≤ 512 且所有值 ≤ 64 字节 | 紧凑存储，节省内存 |
| **hashtable** | 超过阈值 | 标准哈希表，O(1) 查找 |

**配置**：
```bash
hash-max-ziplist-entries 512   # 最大元素个数
hash-max-ziplist-value 64      # 单个值最大字节数
```

**ziplist 编码示例**：
```
假设执行：HSET user:1 name "Zhang" age "25"

ziplist 内部存储：
[name] [Zhang] [age] [25]
  ↑      ↑      ↑     ↑
 field  value  field value
```

### 常用命令

```bash
# 基本操作
HSET key field value
HGET key field
HMSET key field1 value1 field2 value2
HMGET key field1 field2
HGETALL key

# 判断和删除
HEXISTS key field
HDEL key field1 field2

# 计数器
HINCRBY key field increment

# 示例：用户对象
HSET user:1001 name "Zhang" age 25 email "zhang@example.com"
HGET user:1001 name
HINCRBY user:1001 login_count 1
```

### 应用场景

**1. 对象存储**
```bash
# 存储用户信息（比 String 更节省内存，可单独修改字段）
HSET user:1001 name "Zhang" age 25 city "Beijing"

# 只更新年龄
HSET user:1001 age 26
```

**2. 购物车**
```bash
# 商品 ID 为 field，数量为 value
HSET cart:user:123 product:1001 2
HSET cart:user:123 product:1002 1

# 查看购物车
HGETALL cart:user:123

# 增加商品数量
HINCRBY cart:user:123 product:1001 1
```

**3. 统计信息**
```bash
# 网站统计
HINCRBY stats:website:20240117 pv 1
HINCRBY stats:website:20240117 uv 1
```

---

## Set 类型 ⭐⭐⭐⭐

### 底层实现

Set 类型有 **2 种编码方式**：

| 编码 | 条件 | 说明 |
|------|------|------|
| **intset** | 所有元素都是整数且个数 ≤ 512 | 整数集合，紧凑存储 |
| **hashtable** | 超过阈值或包含非整数 | 哈希表，value 为 NULL |

**配置**：
```bash
set-max-intset-entries 512
```

**intset 结构**：
```c
typedef struct intset {
    uint32_t encoding;  // 编码方式（int16/int32/int64）
    uint32_t length;    // 元素个数
    int8_t contents[];  // 整数数组（有序）
} intset;
```

### 常用命令

```bash
# 基本操作
SADD key member1 member2 ...
SMEMBERS key
SISMEMBER key member
SREM key member

# 集合运算
SINTER key1 key2 ...       # 交集
SUNION key1 key2 ...       # 并集
SDIFF key1 key2 ...        # 差集

# 随机元素
SRANDMEMBER key [count]    # 随机返回元素（不删除）
SPOP key [count]           # 随机弹出元素

# 示例：标签系统
SADD tags:article:1001 "Redis" "Database" "NoSQL"
SINTER tags:article:1001 tags:article:1002  # 共同标签
```

### 应用场景

**1. 去重**
```bash
# 统计独立访客（UV）
SADD uv:page:123:20240117 user_id_1
SADD uv:page:123:20240117 user_id_2
SCARD uv:page:123:20240117  # 获取 UV 数
```

**2. 共同好友**
```bash
# 用户的好友列表
SADD friends:user:1 100 101 102 103
SADD friends:user:2 101 102 104 105

# 共同好友
SINTER friends:user:1 friends:user:2  # 101, 102
```

**3. 抽奖系统**
```bash
# 参与抽奖的用户
SADD lottery:2024 user:1 user:2 user:3 ... user:10000

# 抽取 3 个幸运用户
SRANDMEMBER lottery:2024 3
# 或者抽取后移除
SPOP lottery:2024 3
```

---

## ZSet 类型 ⭐⭐⭐⭐⭐

### 底层实现

ZSet（有序集合）有 **2 种编码方式**：

| 编码 | 条件 | 说明 |
|------|------|------|
| **ziplist** | 元素个数 ≤ 128 且所有值 ≤ 64 字节 | 紧凑存储 |
| **skiplist + hashtable** | 超过阈值 | 跳表 + 哈希表 |

**配置**：
```bash
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
```

### 跳表（Skip List）⭐⭐⭐⭐⭐

跳表是 ZSet 的核心数据结构，支持 **O(log N)** 查找、插入、删除。

**跳表结构示例**：
```
Level 3:  1 --------------------------> 25
Level 2:  1 -------> 7 -------> 18 --> 25
Level 1:  1 --> 4 -> 7 -> 10 -> 18 --> 25
Level 0:  1 -> 4 -> 7 -> 10 -> 18 -> 25 -> 30
```

**为什么用跳表而不是红黑树？**
1. **实现简单**：跳表比红黑树容易实现和调试
2. **范围查询友好**：跳表的有序链表结构更适合 ZRANGE
3. **内存局部性**：跳表的层级遍历对缓存友好

**跳表 + 哈希表**：
- **跳表**：按 score 排序，支持范围查询
- **哈希表**：member -> score 映射，O(1) 查找

### 常用命令

```bash
# 基本操作
ZADD key score1 member1 score2 member2 ...
ZSCORE key member
ZCARD key
ZCOUNT key min max

# 范围查询
ZRANGE key start stop [WITHSCORES]        # 按 score 升序
ZREVRANGE key start stop [WITHSCORES]     # 按 score 降序
ZRANGEBYSCORE key min max [WITHSCORES]

# 排名
ZRANK key member         # 升序排名（从 0 开始）
ZREVRANK key member      # 降序排名

# 增减分数
ZINCRBY key increment member

# 示例：排行榜
ZADD leaderboard 1000 "player1" 950 "player2" 1200 "player3"
ZREVRANGE leaderboard 0 9 WITHSCORES  # Top 10
ZREVRANK leaderboard "player1"         # 查看排名
```

### 应用场景

**1. 排行榜**
```bash
# 游戏积分榜
ZADD game:rank 1500 "player:1001" 1800 "player:1002"

# 获取 Top 10
ZREVRANGE game:rank 0 9 WITHSCORES

# 查看自己的排名
ZREVRANK game:rank "player:1001"

# 查看自己的分数
ZSCORE game:rank "player:1001"
```

**2. 延时队列**
```bash
# 将任务加入延时队列（score 为执行时间戳）
ZADD delay:queue 1705478400 "task:1001"  # 2024-01-17 12:00:00

# 消费者定时扫描到期任务
ZRANGEBYSCORE delay:queue 0 #{当前时间戳} LIMIT 0 100
```

**3. 自动补全（前缀搜索）**
```bash
# 利用字典序
ZADD autocomplete 0 "redis" 0 "redisson" 0 "redlock" 0 "mysql"

# 查找以 "red" 开头的词（需要技巧实现）
```

**4. 时间范围查询**
```bash
# 存储文章（score 为发布时间戳）
ZADD articles:timeline 1705478400 "article:1001"

# 查询某个时间范围的文章
ZRANGEBYSCORE articles:timeline 1705392000 1705478400
```

---

## 高级数据类型

### HyperLogLog ⭐⭐⭐

**用途**：基数统计（去重计数），适合大数据量的 UV 统计。

**特点**：
- 误差率约 0.81%
- 只需 12KB 内存（无论统计多少元素）

```bash
# UV 统计
PFADD uv:page:123 user1 user2 user3
PFCOUNT uv:page:123  # 获取基数

# 合并多个 HyperLogLog
PFMERGE uv:total uv:page:123 uv:page:456
```

### Bitmap ⭐⭐⭐⭐

**用途**：位图，适合二值状态统计（签到、在线状态）。

```bash
# 用户签到（offset 为日期，如第几天）
SETBIT sign:user:1001:202401 16 1  # 1月17日签到

# 统计签到天数
BITCOUNT sign:user:1001:202401

# 查看某天是否签到
GETBIT sign:user:1001:202401 16
```

### Geospatial ⭐⭐⭐

**用途**：地理位置信息，基于 ZSet 实现。

```bash
# 添加位置（经度、纬度、名称）
GEOADD locations 116.404 39.915 "Beijing"
GEOADD locations 121.472 31.231 "Shanghai"

# 计算距离
GEODIST locations "Beijing" "Shanghai" km

# 查找附近的位置
GEORADIUS locations 116.404 39.915 100 km
```

### Stream ⭐⭐⭐

**用途**：消息队列（Redis 5.0+），比 List 更强大。

```bash
# 生产消息
XADD stream:tasks * task "send_email" user "123"

# 消费消息（消费者组）
XGROUP CREATE stream:tasks group1 0
XREADGROUP GROUP group1 consumer1 COUNT 1 STREAMS stream:tasks >
```

---

## 面试要点 ⭐⭐⭐⭐⭐

### 高频问题

**Q1: Redis 有哪些数据类型？**
- 5 种基本类型：String、List、Hash、Set、ZSet
- 高级类型：HyperLogLog、Bitmap、Geo、Stream

**Q2: String 的底层编码有哪几种？**
- int：整数
- embstr：短字符串（≤ 44 字节）
- raw：长字符串（> 44 字节）

**Q3: 为什么要用 SDS 而不是 C 字符串？**
- O(1) 获取长度
- 二进制安全
- 杜绝缓冲区溢出
- 减少内存分配次数（空间预分配、惰性释放）

**Q4: ZSet 为什么用跳表而不是红黑树？**
- 实现简单
- 范围查询友好
- 内存局部性好

**Q5: Hash 什么时候会从 ziplist 转为 hashtable？**
- 元素个数 > 512（hash-max-ziplist-entries）
- 单个值大小 > 64 字节（hash-max-ziplist-value）

**Q6: List 的 quicklist 是什么？**
- 双向链表 + 压缩列表的混合结构
- 每个节点是一个 ziplist，减少内存碎片
- 平衡了内存和性能

**Q7: 如何实现分布式锁？**
```bash
# 加锁
SET lock:resource uuid NX EX 30

# 解锁（Lua 脚本保证原子性）
if redis.call("get",KEYS[1]) == ARGV[1] then
    return redis.call("del",KEYS[1])
else
    return 0
end
```

### 常见误区

**误区1**：以为 Redis 只能存储字符串
- **真相**：Redis 支持多种数据类型，每种类型有不同的底层实现

**误区2**：认为 Hash 比 String 更占内存
- **真相**：Hash 使用 ziplist 编码时比 String 更节省内存

**误区3**：以为 ZSet 只能用于排行榜
- **真相**：ZSet 还可用于延时队列、时间范围查询等场景

---

## 参考资料

1. **官方文档**：[Redis Data Types](https://redis.io/docs/data-types/)
2. **源码**：[Redis GitHub](https://github.com/redis/redis)
3. **书籍推荐**：
   - 《Redis 设计与实现》（黄健宏）
   - 《Redis 深度历险》（钱文品）
