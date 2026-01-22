# 分布式事务

> 分库分表后，单机事务的 ACID 特性无法保证，需要分布式事务方案。理解 CAP/BASE 理论和常见方案是面试重点。

## 理论基础 ⭐⭐⭐⭐⭐

### CAP 理论

分布式系统无法同时满足 CAP，最多满足其中两个：

- **C (Consistency)**：一致性，所有节点看到的数据一致
- **A (Availability)**：可用性，系统保证服务可用
- **P (Partition Tolerance)**：分区容错性，网络分区时系统继续工作

**权衡**：
```
CP: 牺牲可用性，保证一致性（如 Zookeeper）
AP: 牺牲一致性，保证可用性（如 Cassandra）
CA: 不考虑分区，单机系统（如传统 RDBMS）
```

### BASE 理论

放弃强一致性，追求最终一致性：

- **BA (Basically Available)**：基本可用
- **S (Soft State)**：软状态，允许中间状态
- **E (Eventually Consistent)**：最终一致性

---

## 方案对比 ⭐⭐⭐⭐⭐

| 方案 | 一致性 | 性能 | 实现复杂度 | 适用场景 |
|------|--------|------|-----------|---------|
| **2PC/XA** | 强一致 | 差 | 低 | 金融核心业务 |
| **TCC** | 最终一致 | 好 | 高 | 电商订单、扣款 |
| **SAGA** | 最终一致 | 好 | 中 | 长流程业务 |
| **可靠消息** | 最终一致 | 好 | 中 | 异步业务 |

---

## 2PC / XA 事务 ⭐⭐⭐⭐⭐

### 两阶段提交（2PC）

**流程**：
```
阶段1：准备阶段 (Prepare)
协调者 → 所有参与者：准备提交
参与者 → 协调者：准备完成 (Yes/No)

阶段2：提交阶段 (Commit)
如果所有参与者都 Yes:
    协调者 → 所有参与者：提交
如果有一个参与者 No:
    协调者 → 所有参与者：回滚
```

**示例**：
```java
// 使用 Atomikos 实现 XA 事务
@Transactional
public void transfer(Long fromUserId, Long toUserId, BigDecimal amount) {
    // 操作分片 1
    userDao.deduct(fromUserId, amount);
    // 操作分片 2
    userDao.add(toUserId, amount);
    // 两个操作要么都成功，要么都失败
}
```

### 2PC 的问题

**问题1：同步阻塞**
- 参与者在准备阶段锁定资源，等待协调者指令
- 性能差，吞吐量低

**问题2：单点故障**
- 协调者宕机，参与者一直阻塞

**问题3：数据不一致**
- 提交阶段网络分区，部分参与者未收到 Commit
- 导致数据不一致

### 3PC（三阶段提交）

在 2PC 基础上增加 **CanCommit** 阶段和**超时机制**：

```
阶段1：CanCommit（询问）
阶段2：PreCommit（准备）
阶段3：DoCommit（提交）
```

**改进**：
- 降低阻塞时间
- 超时自动提交，减少阻塞

**仍存在的问题**：
- 复杂度高
- 网络分区时仍可能不一致

---

## TCC 方案 ⭐⭐⭐⭐⭐

### 原理

TCC 将事务分为三个阶段：
- **Try**：尝试执行，预留资源
- **Confirm**：确认执行，提交资源
- **Cancel**：取消执行，释放资源

### 示例：转账业务

```java
// Try 阶段：冻结金额
public void tryTransfer(Long fromUserId, Long toUserId, BigDecimal amount) {
    // 账户 A 冻结 100 元
    accountDao.freeze(fromUserId, amount);
    // 账户 B 预增加 100 元（冻结状态）
    accountDao.prePlus(toUserId, amount);
}

// Confirm 阶段：扣款并解冻
public void confirmTransfer(Long fromUserId, Long toUserId, BigDecimal amount) {
    // 账户 A 扣除冻结的 100 元
    accountDao.deductFrozen(fromUserId, amount);
    // 账户 B 确认增加 100 元
    accountDao.confirmPlus(toUserId, amount);
}

// Cancel 阶段：解冻
public void cancelTransfer(Long fromUserId, Long toUserId, BigDecimal amount) {
    // 账户 A 解冻 100 元
    accountDao.unfreeze(fromUserId, amount);
    // 账户 B 取消预增加
    accountDao.cancelPlus(toUserId, amount);
}
```

### TCC 特点

**优点**：
- 不长期锁定资源，性能好
- 业务灵活，可自定义补偿逻辑

**缺点**：
- **侵入性强**：需要实现 Try/Confirm/Cancel 三个接口
- **幂等性**：Confirm 和 Cancel 可能重复调用，需保证幂等
- **空回滚**：Try 未执行，Cancel 被调用，需处理

### TCC 框架

- **Seata**：阿里开源，支持 TCC、AT、XA
- **ByteTCC**：独立 TCC 框架
- **Hmily**：高性能 TCC 框架

---

## SAGA 方案 ⭐⭐⭐⭐

### 原理

将长事务拆分为多个本地短事务，每个事务都有对应的**补偿事务**。

**模式**：
- **正向服务**：T1, T2, T3, ...
- **补偿服务**：C1, C2, C3, ...

**流程**：
```
成功：T1 → T2 → T3 → 完成
失败：T1 → T2 → T3 失败 → C2 → C1 → 回滚完成
```

### 示例：订单流程

```java
// 正向服务
createOrder();     // T1: 创建订单
deductStock();     // T2: 扣减库存
deductBalance();   // T3: 扣减余额

// 如果 T3 失败，执行补偿
compensateStock();    // C2: 恢复库存
compensateOrder();    // C1: 取消订单
```

### SAGA vs TCC

| 特性 | TCC | SAGA |
|------|-----|------|
| **资源锁定** | Try 阶段锁定 | 不锁定 |
| **一致性** | 最终一致 | 最终一致 |
| **性能** | 好 | 更好 |
| **实现复杂度** | 高 | 中 |
| **适用场景** | 短事务 | 长流程事务 |

### SAGA 实现

- **Seata SAGA**：状态机模式
- **Apache Camel Saga**：基于 Camel 路由
- **Eventuate Tram Saga**：事件驱动

---

## 可靠消息最终一致性 ⭐⭐⭐⭐⭐

### 原理

通过消息队列保证事务最终一致性。

**本地消息表方案**：
```
1. 事务开始
2. 执行业务逻辑（如扣减库存）
3. 插入本地消息表（同一事务）
4. 提交事务
5. 定时任务扫描消息表，发送 MQ
6. 消费者消费消息，执行下游业务
7. 消费成功后，更新消息状态为已消费
```

### 示例：订单支付

```java
@Transactional
public void payOrder(Long orderId) {
    // 1. 更新订单状态为已支付
    orderDao.updateStatus(orderId, "PAID");

    // 2. 插入消息表（同一事务）
    Message msg = new Message();
    msg.setTopic("order-paid");
    msg.setContent("{\"orderId\":" + orderId + "}");
    messageDao.insert(msg);

    // 3. 提交事务
}

// 定时任务：扫描消息表，发送 MQ
@Scheduled(fixedDelay = 1000)
public void sendMessage() {
    List<Message> messages = messageDao.selectUnsent();
    for (Message msg : messages) {
        mqProducer.send(msg.getTopic(), msg.getContent());
        messageDao.updateStatus(msg.getId(), "SENT");
    }
}

// 消费者：处理下游业务（如增加积分）
@RabbitListener(queues = "order-paid")
public void handleOrderPaid(String message) {
    Long orderId = parseOrderId(message);
    // 增加用户积分
    pointService.addPoints(orderId);
}
```

### RocketMQ 事务消息

RocketMQ 原生支持事务消息：

```java
// 发送事务消息
TransactionSendResult result = producer.sendMessageInTransaction(msg, null);

// 执行本地事务
@Override
public LocalTransactionState executeLocalTransaction(Message msg, Object arg) {
    try {
        // 执行本地事务
        orderService.payOrder(orderId);
        return LocalTransactionState.COMMIT_MESSAGE;
    } catch (Exception e) {
        return LocalTransactionState.ROLLBACK_MESSAGE;
    }
}

// 回查本地事务状态
@Override
public LocalTransactionState checkLocalTransaction(MessageExt msg) {
    // 查询订单状态，返回事务状态
    Order order = orderDao.selectById(orderId);
    if (order.getStatus().equals("PAID")) {
        return LocalTransactionState.COMMIT_MESSAGE;
    }
    return LocalTransactionState.ROLLBACK_MESSAGE;
}
```

---

## 方案选型 ⭐⭐⭐⭐⭐

### 决策树

```
是否需要强一致性？
├─ 是 → XA 事务（2PC/3PC）
└─ 否 → 最终一致性
        ├─ 业务逻辑复杂，需要精细控制？
        │   └─ 是 → TCC
        ├─ 长流程业务？
        │   └─ 是 → SAGA
        └─ 异步业务，可容忍短暂延迟？
            └─ 是 → 可靠消息
```

### 实际建议

**金融核心业务**：XA 事务
**电商订单/扣款**：TCC
**长流程（如旅游预订）**：SAGA
**积分、通知等异步业务**：可靠消息

---

## 面试要点 ⭐⭐⭐⭐⭐

**Q1: CAP 和 BASE 理论是什么？**
- CAP：一致性、可用性、分区容错性，最多满足两个
- BASE：基本可用、软状态、最终一致性

**Q2: 2PC 的缺点是什么？**
- 同步阻塞，性能差
- 单点故障
- 可能数据不一致

**Q3: TCC 的三个阶段是什么？**
- Try：尝试执行，预留资源
- Confirm：确认执行
- Cancel：取消执行，释放资源

**Q4: TCC 需要注意什么？**
- 幂等性：Confirm/Cancel 可能重复调用
- 空回滚：Try 未执行，Cancel 被调用
- 悬挂：Cancel 先于 Try 执行

**Q5: SAGA 和 TCC 的区别？**
- TCC 在 Try 阶段锁定资源，SAGA 不锁定
- SAGA 适合长流程，TCC 适合短事务
- SAGA 实现相对简单

**Q6: 可靠消息方案如何保证消息不丢失？**
- 本地消息表：业务和消息插入在同一事务
- 定时任务扫描未发送消息
- 消费者幂等处理

**Q7: 分布式事务方案如何选择？**
- 强一致性 → XA
- 短事务、精细控制 → TCC
- 长流程 → SAGA
- 异步业务 → 可靠消息

**Q8: Seata 支持哪些模式？**
- AT 模式：自动补偿（推荐）
- TCC 模式：手动补偿
- SAGA 模式：长事务
- XA 模式：强一致性

---

## 参考资料

1. **Seata 官网**：[https://seata.io/](https://seata.io/)
2. **论文**：《Life beyond Distributed Transactions》
3. **书籍推荐**：《数据密集型应用系统设计》
