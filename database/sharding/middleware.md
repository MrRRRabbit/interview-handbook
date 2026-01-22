# 分库分表中间件

> 分库分表中间件屏蔽了底层分片逻辑，让应用像操作单库单表一样操作分布式数据库。

## 中间件架构模式 ⭐⭐⭐⭐⭐

### 客户端分片 vs 代理分片

| 特性 | 客户端分片 | 代理分片 |
|------|-----------|---------|
| **架构** | 应用内嵌分片逻辑 | 独立代理服务器 |
| **性能** | 高（直连数据库） | 稍低（多一跳） |
| **运维** | 复杂（需升级应用） | 简单（统一管理） |
| **语言支持** | 特定语言（如 Java） | 所有语言 |
| **代表** | ShardingSphere-JDBC | ShardingSphere-Proxy、MyCAT |

**客户端分片架构**：
```
Application (集成 JDBC)
    ↓ 直连
┌────────┬────────┬────────┐
│  DB 0  │  DB 1  │  DB 2  │
└────────┴────────┴────────┘
```

**代理分片架构**：
```
Application
    ↓
Proxy (分片代理)
    ↓
┌────────┬────────┬────────┐
│  DB 0  │  DB 1  │  DB 2  │
└────────┴────────┴────────┘
```

---

## ShardingSphere ⭐⭐⭐⭐⭐

### 简介

ShardingSphere 是 Apache 顶级项目，包含三个产品：
- **ShardingSphere-JDBC**：客户端分片（推荐）
- **ShardingSphere-Proxy**：代理分片
- **ShardingSphere-Sidecar**：Service Mesh 分片（规划中）

### ShardingSphere-JDBC 使用

**Maven 依赖**：
```xml
<dependency>
    <groupId>org.apache.shardingsphere</groupId>
    <artifactId>shardingsphere-jdbc-core</artifactId>
    <version>5.3.0</version>
</dependency>
```

**配置示例**（YAML）：
```yaml
spring:
  shardingsphere:
    datasource:
      names: ds0,ds1
      ds0:
        type: com.zaxxer.hikari.HikariDataSource
        jdbc-url: jdbc:mysql://localhost:3306/db0
      ds1:
        type: com.zaxxer.hikari.HikariDataSource
        jdbc-url: jdbc:mysql://localhost:3306/db1

    rules:
      sharding:
        tables:
          t_user:
            actual-data-nodes: ds$->{0..1}.t_user_$->{0..3}
            # 分库策略
            database-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: database-inline
            # 分表策略
            table-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: table-inline

        sharding-algorithms:
          database-inline:
            type: INLINE
            props:
              algorithm-expression: ds$->{user_id % 2}
          table-inline:
            type: INLINE
            props:
              algorithm-expression: t_user_$->{user_id % 4}
```

**Java 代码**：
```java
// 直接使用 JPA/MyBatis，无需修改业务代码
@Autowired
private UserRepository userRepository;

// ShardingSphere 自动路由到正确的库表
User user = userRepository.findById(123L);
```

### ShardingSphere 核心功能

**1. 数据分片**
- 支持多种分片算法（取模、范围、哈希、自定义）
- 支持分库分表、读写分离
- 支持强制路由（Hint）

**2. 分布式事务**
- XA 事务（强一致性）
- Seata（最终一致性）
- BASE 柔性事务

**3. 读写分离**
```yaml
rules:
  readwrite-splitting:
    data-sources:
      ds:
        write-data-source-name: master
        read-data-source-names: slave0,slave1
        load-balancer-name: round-robin
```

**4. 数据加密**
```yaml
rules:
  encrypt:
    tables:
      t_user:
        columns:
          phone:
            cipher-column: phone_cipher
            encryptor-name: phone-encryptor
```

### 优点

- **无代理，高性能**：直连数据库，无额外网络开销
- **功能丰富**：分片、读写分离、加密、影子库
- **生态好**：支持 MyBatis、JPA、Spring Boot
- **社区活跃**：Apache 顶级项目，持续迭代

### 缺点

- **客户端升级成本高**：需要修改所有应用
- **多语言支持差**：主要支持 Java

---

## MyCAT ⭐⭐⭐⭐

### 简介

MyCAT 是开源的数据库分片中间件，模拟 MySQL 协议，应用无需改动代码。

**架构**：
```
Application
    ↓ MySQL 协议
MyCAT (8066端口)
    ↓
┌────────┬────────┬────────┐
│  DB 0  │  DB 1  │  DB 2  │
└────────┴────────┴────────┘
```

### 配置示例

**server.xml**（用户配置）：
```xml
<user name="mycat">
    <property name="password">123456</property>
    <property name="schemas">testdb</property>
</user>
```

**schema.xml**（分片规则）：
```xml
<schema name="testdb" checkSQLschema="false">
    <table name="t_user" dataNode="dn0,dn1,dn2,dn3" rule="mod-long"/>
</schema>

<dataNode name="dn0" dataHost="localhost1" database="db0"/>
<dataNode name="dn1" dataHost="localhost1" database="db1"/>

<dataHost name="localhost1" maxCon="1000" minCon="10" ...>
    <writeHost host="hostM1" url="localhost:3306" user="root" password="123456">
        <readHost host="hostS1" url="localhost:3307" .../>
    </writeHost>
</dataHost>
```

**rule.xml**（分片算法）：
```xml
<tableRule name="mod-long">
    <rule>
        <columns>user_id</columns>
        <algorithm>mod-long</algorithm>
    </rule>
</tableRule>

<function name="mod-long" class="io.mycat.route.function.PartitionByMod">
    <property name="count">4</property>
</function>
```

### 使用方式

```java
// 应用连接 MyCAT，像使用单库一样
DataSource ds = new DruidDataSource();
ds.setUrl("jdbc:mysql://localhost:8066/testdb");
ds.setUsername("mycat");
ds.setPassword("123456");

// 业务代码不变
Connection conn = ds.getConnection();
PreparedStatement ps = conn.prepareStatement("SELECT * FROM t_user WHERE user_id = ?");
ps.setLong(1, 123);
ResultSet rs = ps.executeQuery();
```

### 优点

- **应用零改动**：支持所有语言，只需修改连接地址
- **成熟稳定**：社区使用广泛
- **支持分布式 JOIN**：有限支持跨分片 JOIN

### 缺点

- **单点风险**：MyCAT 本身可能成为瓶颈（需做高可用）
- **性能损耗**：多一层代理，延迟增加
- **复杂 SQL 支持有限**：如子查询、窗口函数
- **社区不活跃**：近年更新缓慢

---

## ShardingSphere vs MyCAT ⭐⭐⭐⭐⭐

### 对比总结

| 对比项 | ShardingSphere-JDBC | ShardingSphere-Proxy | MyCAT |
|-------|--------------------|--------------------|-------|
| **架构** | 客户端 | 代理 | 代理 |
| **性能** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **多语言** | ❌ (Java) | ✅ | ✅ |
| **运维复杂度** | 高 | 低 | 低 |
| **功能丰富度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **社区活跃度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **分布式事务** | ✅ (XA/Seata) | ✅ (XA/Seata) | ❌ |
| **推荐度** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |

### 选型建议

**选择 ShardingSphere-JDBC**：
- Java 项目
- 追求性能
- 不介意升级应用

**选择 ShardingSphere-Proxy**：
- 多语言项目
- 追求运维简单
- 可接受少许性能损耗

**选择 MyCAT**：
- 老项目，不想大改
- 社区方案成熟
- 功能需求简单

---

## 常见问题 ⭐⭐⭐⭐

### Q1: 如何处理跨分片 JOIN？

**方案1**：数据冗余（推荐）
```java
// order 表冗余 user_name
// 避免 JOIN user 表
```

**方案2**：应用层 JOIN
```java
List<User> users = userDao.selectByIds(userIds);
List<Order> orders = orderDao.selectByUserIds(userIds);
// 应用层合并
```

**方案3**：全局表
```yaml
# 小表在每个分片都存一份
rules:
  sharding:
    broadcast-tables: t_config,t_dict
```

### Q2: 如何强制路由到指定分片？

**ShardingSphere Hint**：
```java
// 强制路由到 ds0
HintManager.getInstance().setDatabaseShardingValue("ds0");
userRepository.findById(123L);
HintManager.clear();
```

### Q3: 如何平滑扩容？

**双写方案**：
```
1. 新库开始同时写入（双写）
2. 数据迁移工具同步历史数据
3. 校验数据一致性
4. 切换读流量到新库
5. 停止双写，下线旧库
```

### Q4: 如何监控分片性能？

**ShardingSphere**：
- 内置 Metrics，支持 Prometheus
- 慢 SQL 日志
- 分片路由信息

**MyCAT**：
- 管理端口（9066）查看统计信息
- show @@datasource
- show @@connection

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: 客户端分片和代理分片的区别？**
- 客户端：嵌入应用，性能高，运维复杂
- 代理：独立服务，运维简单，性能稍低

**Q2: ShardingSphere 和 MyCAT 如何选择？**
- Java 项目优先 ShardingSphere-JDBC
- 多语言或运维简单优先 ShardingSphere-Proxy
- 老项目迁移成本低选 MyCAT

**Q3: 如何保证分片中间件的高可用？**
- 客户端分片：天然高可用（应用多实例）
- 代理分片：部署多个 Proxy，前置 LVS/Nginx

**Q4: 分片后如何执行分布式事务？**
- XA 事务（强一致性，性能差）
- Seata（最终一致性，推荐）
- 业务补偿（人工兜底）

**Q5: 如何选择分片键？**
- 数据均匀分布
- 查询条件包含分片键
- 业务相关性强

---

## 参考资料

1. **ShardingSphere 官网**：[https://shardingsphere.apache.org/](https://shardingsphere.apache.org/)
2. **MyCAT 官网**：[http://www.mycat.org.cn/](http://www.mycat.org.cn/)
3. **书籍推荐**：《ShardingSphere 核心原理精讲》
