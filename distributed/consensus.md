# 分布式一致性算法 ⭐⭐⭐⭐⭐ 重点

## 1. Paxos 算法

### 1.1 Paxos 核心概念
- **角色划分**
  - Proposer（提议者）：提出提案
  - Acceptor（接受者）：投票决定是否接受提案
  - Learner（学习者）：学习被选定的提案
- **提案结构**
  - 提案编号（Proposal ID）：全局唯一且递增
  - 提案值（Value）：实际要达成一致的值

### 1.2 Basic Paxos 流程

**阶段一：Prepare 阶段**
- Proposer 选择提案编号 n，向多数派 Acceptor 发送 Prepare(n)
- Acceptor 收到 Prepare(n)：
  - 如果 n 大于已承诺的编号，则承诺不再接受编号小于 n 的提案
  - 返回已接受的最大编号提案（如果有）

**阶段二：Accept 阶段**
- Proposer 收到多数派响应后，发送 Accept(n, v)
  - v 为收到的最大编号提案的值，若无则为自己的值
- Acceptor 收到 Accept(n, v)：
  - 如果 n 不小于已承诺的编号，则接受该提案

### 1.3 Paxos 详细案例分析

#### 案例1：正常情况
```
节点：P1(Proposer), A1, A2, A3(Acceptor)
提案编号生成规则：轮次 * 10 + 节点ID

场景：P1 想要提交值 "X"

阶段1 - Prepare:
P1 -> A1, A2, A3: Prepare(11)
A1: 第一次收到，承诺 minProposal=11，回复 OK(null)
A2: 第一次收到，承诺 minProposal=11，回复 OK(null)
A3: 第一次收到，承诺 minProposal=11，回复 OK(null)

阶段2 - Accept:
P1 收到 3 个 OK，发送 Accept(11, "X")
A1: 11 >= 11，接受 (11, "X")，回复 Accepted
A2: 11 >= 11，接受 (11, "X")，回复 Accepted
A3: 11 >= 11，接受 (11, "X")，回复 Accepted

结果：值 "X" 被选定
```

#### 案例2：提案冲突
```
场景：P1 和 P2 同时提交不同值

时间线：
T1: P1 发送 Prepare(11) 给 A1, A2
T2: P2 发送 Prepare(22) 给 A2, A3
T3: A1 回复 P1: OK(null)
T4: A2 先收到 P1，回复 OK(null)，再收到 P2，更新承诺为22，回复 OK(null)
T5: A3 回复 P2: OK(null)
T6: P1 收到 A1 的回复（只有1个多数派不足），P2 收到 A2, A3 的回复
T7: P2 发送 Accept(22, "Y")，A2, A3 接受
T8: P1 发送 Accept(11, "X")，A1 接受，A2 拒绝（承诺了22）

分析：
- P1 只获得 A1 的接受（少数派）
- P2 获得 A2, A3 的接受（多数派）
- 最终 "Y" 被选定
```

#### 案例3：旧提案的值被继承
```
场景：P1 的 Accept 部分成功后崩溃，P2 接续

T1: P1 发送 Prepare(11)，全部响应 OK(null)
T2: P1 发送 Accept(11, "X")，仅 A1 成功接受后 P1 崩溃
T3: P2 发送 Prepare(22)
    A1: 回复 OK(11, "X")  // 返回已接受的提案
    A2: 回复 OK(null)
    A3: 回复 OK(null)
T4: P2 发现有已接受的提案 (11, "X")
    P2 必须使用 "X" 作为提案值（而非自己的值）
T5: P2 发送 Accept(22, "X")
    A1, A2, A3 全部接受

结果：虽然 P1 崩溃，但 "X" 最终仍被选定
关键：Paxos 保证了已被多数派接受的值不会丢失
```

### 1.4 Multi-Paxos
- Basic Paxos 每次决策需要两轮通信
- Multi-Paxos 优化：
  - 选举一个 Leader
  - Leader 可以跳过 Prepare 阶段
  - 减少通信轮次，提高效率

```
Multi-Paxos 优化流程：

1. Leader 选举（只做一次）
   - 执行完整的 Prepare 阶段
   - 成为 Leader 后拥有稳定的提案编号

2. 正常阶段（跳过 Prepare）
   Client -> Leader: 请求
   Leader -> Acceptors: Accept(n, v)
   Acceptors -> Leader: Accepted
   Leader -> Client: 成功

3. Leader 失效时
   - 检测到 Leader 心跳超时
   - 重新执行 Leader 选举
   - 新 Leader 继续服务
```

### 1.5 Paxos 变种
| 变种 | 特点 | 应用 |
|------|------|------|
| Basic Paxos | 单值共识，两阶段 | 理论基础 |
| Multi-Paxos | Leader优化，连续共识 | Chubby |
| Fast Paxos | 减少延迟，乐观路径 | 低延迟场景 |
| Flexible Paxos | 灵活的 Quorum | 优化读性能 |
| EPaxos | 无Leader，乱序执行 | 地理分布 |

## 2. Raft 算法 ⭐⭐⭐⭐⭐

### 2.1 Raft 核心概念
- **角色**
  - Leader（领导者）：处理所有客户端请求
  - Follower（跟随者）：被动接收请求
  - Candidate（候选人）：用于选举 Leader
- **任期（Term）**
  - 逻辑时钟，单调递增
  - 每个任期最多一个 Leader
  - 选举超时触发新任期

### 2.2 Leader 选举详细流程

```
状态转换图：

                 超时，开始选举
    ┌──────────────────────────────────────┐
    │                                      │
    ▼          收到多数票                   │
┌─────────┐  ───────────────>  ┌─────────┐ │
│ Follower│                    │  Leader │ │
└─────────┘  <───────────────  └─────────┘ │
    │          发现更高任期                 │
    │                                      │
    │ 选举超时                              │
    ▼                                      │
┌─────────┐  选举超时或更高任期             │
│Candidate│  ──────────────────────────────┘
└─────────┘
```

**选举超时机制**：
```
选举超时设计要点：

1. 随机化超时
   - 范围：150ms ~ 300ms
   - 避免多个节点同时发起选举
   - 减少选票分裂

2. 心跳间隔
   - 通常 50ms ~ 100ms
   - 必须小于选举超时
   - 公式：broadcastTime << electionTimeout << MTBF

3. 超时处理
   Follower:
     if (lastHeartbeat + electionTimeout < now) {
         becomeCandidate();
         startElection();
     }
```

**投票规则**：
```java
/**
 * Raft 投票逻辑
 */
public class RaftVoting {
    private int currentTerm;
    private Integer votedFor;  // 当前任期投票给谁
    private List<LogEntry> log;

    public VoteResponse handleVoteRequest(VoteRequest request) {
        // 规则1：拒绝旧任期的请求
        if (request.term < currentTerm) {
            return new VoteResponse(currentTerm, false);
        }

        // 规则2：更新任期
        if (request.term > currentTerm) {
            currentTerm = request.term;
            votedFor = null;  // 新任期重置投票
        }

        // 规则3：检查是否已投票
        if (votedFor != null && votedFor != request.candidateId) {
            return new VoteResponse(currentTerm, false);
        }

        // 规则4：检查日志是否足够新（关键！）
        if (!isLogUpToDate(request.lastLogIndex, request.lastLogTerm)) {
            return new VoteResponse(currentTerm, false);
        }

        // 授予投票
        votedFor = request.candidateId;
        return new VoteResponse(currentTerm, true);
    }

    /**
     * 日志比较规则：
     * 1. 先比较最后日志的任期，任期大的更新
     * 2. 任期相同比较日志长度，长的更新
     */
    private boolean isLogUpToDate(int lastLogIndex, int lastLogTerm) {
        int myLastTerm = log.isEmpty() ? 0 : log.get(log.size() - 1).term;
        int myLastIndex = log.size();

        if (lastLogTerm != myLastTerm) {
            return lastLogTerm > myLastTerm;
        }
        return lastLogIndex >= myLastIndex;
    }
}
```

**选举过程示例**：
```
集群：S1, S2, S3, S4, S5（S1 是 Leader，Term=1）

T1: S1 宕机
T2: S3 选举超时（150ms），发起选举
    S3: Term++ (变为2), 给自己投票, 变成 Candidate
    S3 -> S2, S4, S5: RequestVote(term=2, lastLogIndex=5, lastLogTerm=1)

T3: 投票响应
    S2: 检查日志，投票给 S3
    S4: 检查日志，投票给 S3
    S5: 检查日志，投票给 S3

T4: S3 收到 3 票（加自己共4票），超过多数派
    S3 成为 Leader (Term=2)
    S3 立即发送心跳

T5: S2, S4, S5 收到心跳，重置选举超时
    S1 恢复，收到更高 Term 的心跳，变成 Follower
```

### 2.3 日志复制详细流程

**日志结构**：
```
┌─────────────────────────────────────────────────┐
│                     日志条目                      │
├───────┬───────┬──────────────────┬──────────────┤
│ Index │ Term  │     Command      │    State     │
├───────┼───────┼──────────────────┼──────────────┤
│   1   │   1   │   x ← 3          │  committed   │
│   2   │   1   │   y ← 1          │  committed   │
│   3   │   1   │   x ← 2          │  committed   │
│   4   │   2   │   y ← 9          │  committed   │
│   5   │   3   │   x ← 1          │  uncommitted │
└───────┴───────┴──────────────────┴──────────────┘
```

**复制流程详解**：
```java
/**
 * Leader 处理客户端请求
 */
public class RaftLeader {
    private List<LogEntry> log;
    private int commitIndex;
    private Map<Integer, Integer> nextIndex;   // 每个Follower的下一条日志索引
    private Map<Integer, Integer> matchIndex;  // 每个Follower已复制的最高索引

    public void handleClientRequest(Command command) {
        // 1. 追加到本地日志
        LogEntry entry = new LogEntry(log.size() + 1, currentTerm, command);
        log.add(entry);

        // 2. 并行发送给所有 Follower
        for (int followerId : followers) {
            sendAppendEntries(followerId);
        }
    }

    private void sendAppendEntries(int followerId) {
        int prevLogIndex = nextIndex.get(followerId) - 1;
        int prevLogTerm = prevLogIndex > 0 ? log.get(prevLogIndex - 1).term : 0;

        // 发送从 nextIndex 开始的所有日志
        List<LogEntry> entries = log.subList(
            nextIndex.get(followerId) - 1,
            log.size()
        );

        AppendEntriesRequest request = new AppendEntriesRequest(
            currentTerm,
            leaderId,
            prevLogIndex,
            prevLogTerm,
            entries,
            commitIndex
        );

        // 异步发送
        sendAsync(followerId, request, response -> {
            handleAppendEntriesResponse(followerId, response);
        });
    }

    private void handleAppendEntriesResponse(int followerId, AppendEntriesResponse response) {
        if (response.success) {
            // 更新 matchIndex 和 nextIndex
            matchIndex.put(followerId, matchIndex.get(followerId) + response.entriesCount);
            nextIndex.put(followerId, matchIndex.get(followerId) + 1);

            // 尝试提交
            tryCommit();
        } else {
            // 日志不一致，回退 nextIndex
            nextIndex.put(followerId, nextIndex.get(followerId) - 1);
            // 重试
            sendAppendEntries(followerId);
        }
    }

    private void tryCommit() {
        // 找到大多数节点都复制的最大索引
        for (int n = log.size(); n > commitIndex; n--) {
            // 统计已复制到索引 n 的节点数
            int count = 1; // 包括自己
            for (int matchIdx : matchIndex.values()) {
                if (matchIdx >= n) count++;
            }

            // 多数派已复制，且是当前任期的日志
            if (count > (clusterSize / 2) && log.get(n - 1).term == currentTerm) {
                commitIndex = n;
                applyToStateMachine(commitIndex);
                break;
            }
        }
    }
}
```

**日志一致性检查**：
```
AppendEntries 一致性检查：

Follower 收到 AppendEntries(prevLogIndex=5, prevLogTerm=2, entries=[...])

情况1：日志匹配
Follower 日志: [..., (5,2)]
检查：log[5].term == 2 ✓
结果：接受新日志

情况2：日志缺失
Follower 日志: [..., (3,1)]
检查：log[5] 不存在
结果：拒绝，Leader 回退 nextIndex

情况3：日志冲突
Follower 日志: [..., (5,1)]  // 注意 term 是 1
检查：log[5].term == 2 ✗
结果：删除索引5及之后的日志，拒绝并等待 Leader 回退
```

**日志修复过程**：
```
场景：Follower 日志落后

Leader 日志:  [1:1] [2:1] [3:2] [4:2] [5:3]
Follower 日志: [1:1] [2:1]

修复过程：
1. Leader 发送 AppendEntries(prevLogIndex=5, prevLogTerm=3, entries=[])
   Follower: 没有 index=5，拒绝

2. Leader 发送 AppendEntries(prevLogIndex=4, prevLogTerm=2, entries=[5:3])
   Follower: 没有 index=4，拒绝

3. Leader 发送 AppendEntries(prevLogIndex=3, prevLogTerm=2, entries=[4:2, 5:3])
   Follower: 没有 index=3，拒绝

4. Leader 发送 AppendEntries(prevLogIndex=2, prevLogTerm=1, entries=[3:2, 4:2, 5:3])
   Follower: log[2].term == 1 ✓，接受
   Follower 追加日志 [3:2] [4:2] [5:3]

最终 Follower 日志: [1:1] [2:1] [3:2] [4:2] [5:3]
```

### 2.4 安全性保证
- 选举安全性：每个任期最多一个 Leader
- Leader 只追加日志：Leader 不会覆盖或删除日志
- 日志匹配性：相同索引和任期的日志项一定相同
- Leader 完整性：已提交的日志一定在未来的 Leader 中
- 状态机安全性：节点应用相同日志到状态机后状态一致

### 2.5 成员变更

**单节点变更**：
```
推荐方式：一次只添加或移除一个节点

原理：保证新旧配置的多数派有重叠

示例：3节点 -> 4节点 -> 5节点
[A, B, C]
    ↓ 添加 D
[A, B, C, D]  // 3节点多数派=2, 4节点多数派=3, 有重叠
    ↓ 添加 E
[A, B, C, D, E]  // 4节点多数派=3, 5节点多数派=3, 有重叠

流程：
1. Leader 收到配置变更请求
2. 追加配置变更日志 C_new
3. 复制到多数派
4. 提交后新配置生效
```

**联合共识（Joint Consensus）**：
```
用于同时变更多个节点

阶段1：过渡配置 C_old,new
- 需要同时获得新旧配置的多数派同意
- 防止两个 Leader 同时存在

阶段2：新配置 C_new
- C_old,new 提交后切换到 C_new
- C_new 提交后变更完成
```

### 2.6 Raft vs Paxos
| 特性 | Raft | Paxos |
|------|------|-------|
| 可理解性 | 易于理解 | 复杂难懂 |
| Leader | 强 Leader | 无 Leader / 弱 Leader |
| 日志 | 日志必须连续 | 日志可以有空洞 |
| 工程实现 | 容易 | 困难 |
| 成员变更 | 联合共识或单节点变更 | 复杂 |

## 3. ZooKeeper ZAB 协议

### 3.1 ZAB 协议概述
- ZooKeeper Atomic Broadcast
- 专为 ZooKeeper 设计的一致性协议
- 基于 Paxos 改进，但有本质区别

### 3.2 ZAB vs Paxos/Raft
| 特性 | ZAB | Paxos | Raft |
|------|-----|-------|------|
| 设计目标 | 主备复制 | 通用共识 | 日志复制 |
| Leader | 必须有 | 可选 | 必须有 |
| 日志顺序 | 严格 FIFO | 可乱序 | 严格顺序 |
| 崩溃恢复 | 原生支持 | 需额外设计 | 原生支持 |

### 3.3 ZAB 核心机制

**ZXID 设计**：
```
ZXID（事务ID）= 64位
┌─────────────────────┬─────────────────────┐
│     Epoch (32位)     │    Counter (32位)    │
└─────────────────────┴─────────────────────┘

Epoch：纪元/时代，每次新 Leader 选举 +1
Counter：事务计数器，每次事务 +1，新纪元重置为 0

示例：
ZXID = 0x0000000100000005
Epoch = 1, Counter = 5

比较规则：
1. 先比较 Epoch
2. Epoch 相同再比较 Counter
```

**消息广播流程**：
```
类似两阶段提交，但改进了阻塞问题

1. 客户端请求
   Client -> Leader: write(key, value)

2. Leader 生成提案
   ZXID++
   创建 Proposal(ZXID, data)

3. 广播提案（第一阶段）
   Leader -> Followers: Proposal
   Followers: 写入磁盘日志，返回 ACK

4. 广播提交（第二阶段）
   Leader 收到多数派 ACK 后
   Leader -> Followers: Commit(ZXID)
   Followers: 应用到内存数据树

5. 响应客户端
   Leader -> Client: 成功

关键点：
- 只需要多数派确认，不会阻塞
- FIFO 顺序保证：Leader 与每个 Follower 之间的消息严格有序
```

### 3.4 崩溃恢复详解

**Leader 选举**：
```
选举算法：Fast Leader Election

选举信息：
- myid: 节点ID
- ZXID: 最大事务ID
- epoch: 选举轮次

投票规则：
1. 优先选择 ZXID 最大的节点
2. ZXID 相同选择 myid 最大的

选举过程：
T1: Leader 崩溃，所有节点进入 LOOKING 状态
T2: 每个节点先投票给自己
    S1: (myid=1, ZXID=0x0100000005)
    S2: (myid=2, ZXID=0x0100000007)
    S3: (myid=3, ZXID=0x0100000006)

T3: 交换投票信息，更新投票
    S1 收到 S2 的投票，S2 的 ZXID 更大，改投 S2
    S3 收到 S2 的投票，S2 的 ZXID 更大，改投 S2

T4: S2 获得多数票，成为新 Leader
```

**数据同步阶段**：
```
新 Leader 选举完成后，需要与 Follower 同步数据

1. Leader 确定同步起点
   Leader 获取所有 Follower 的 ZXID

2. 同步策略选择
   根据 Follower 的 ZXID 与 Leader 的关系选择策略：

   ┌─────────────────────────────────────────────────┐
   │ DIFF 同步（差异同步）                             │
   │ 条件：minCommittedLog <= follower.ZXID <= maxLog │
   │ 动作：发送差异日志                                │
   └─────────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────┐
   │ TRUNC 同步（回滚同步）                           │
   │ 条件：follower.ZXID > maxLog                    │
   │ 动作：Follower 回滚到 maxLog                     │
   │ 场景：旧 Leader 的未提交事务                     │
   └─────────────────────────────────────────────────┘

   ┌─────────────────────────────────────────────────┐
   │ SNAP 同步（快照同步）                            │
   │ 条件：follower.ZXID < minCommittedLog           │
   │ 动作：发送完整快照                               │
   │ 场景：Follower 落后太多                          │
   └─────────────────────────────────────────────────┘

3. 同步完成确认
   Follower -> Leader: ACK
   多数派 ACK 后进入广播模式
```

**已提交事务的保证**：
```
ZAB 保证：已提交的事务不会丢失

场景分析：
1. Leader L1 提交了事务 T1, T2
2. L1 崩溃，T3 未提交（只发给了部分节点）
3. 新 Leader L2 被选举

情况 A：L2 有 T3
- L2 的 ZXID 更大，所以被选为 Leader
- T3 会被继续提交

情况 B：L2 没有 T3
- L2 有更大的 epoch，但 counter 较小
- 有 T3 的 Follower 回滚 T3（TRUNC 同步）
- T3 丢弃（符合预期，因为 T3 未被提交）
```

### 3.5 ZAB 四种状态
```
状态转换：

          启动/选举失败
              ↓
┌────────────────────────┐
│       LOOKING          │ ←─┬── 失去 Leader
│    (选举中)             │   │
└────────────────────────┘   │
        │ 选举成功           │
        ↓                    │
┌────────────────────────┐   │
│      DISCOVERY         │   │
│    (发现阶段)           │   │
└────────────────────────┘   │
        │ 确定 epoch         │
        ↓                    │
┌────────────────────────┐   │
│    SYNCHRONIZATION     │   │
│     (同步阶段)          │   │
└────────────────────────┘   │
        │ 同步完成           │
        ↓                    │
┌────────────────────────┐   │
│      BROADCAST         │ ──┘
│     (广播阶段)          │
└────────────────────────┘
```

### 3.6 ZooKeeper 节点类型
- **Leading**：领导者状态，处理写请求
- **Following**：跟随者状态，参与投票
- **Observing**：观察者状态，不参与投票，只同步数据

```
Observer 的作用：
1. 扩展读能力（不影响写性能）
2. 跨数据中心部署（不增加投票延迟）
3. 不参与选举（不增加选举复杂度）
```

## 4. Raft 状态机伪代码

```java
/**
 * Raft 状态机完整实现
 */
public class RaftServer {
    // 持久化状态（需要落盘）
    private int currentTerm = 0;
    private Integer votedFor = null;
    private List<LogEntry> log = new ArrayList<>();

    // 易失状态
    private int commitIndex = 0;
    private int lastApplied = 0;
    private ServerState state = ServerState.FOLLOWER;

    // Leader 专用状态
    private Map<Integer, Integer> nextIndex;
    private Map<Integer, Integer> matchIndex;

    // 时间相关
    private long lastHeartbeat = System.currentTimeMillis();
    private long electionTimeout = randomTimeout(150, 300);

    /**
     * 主循环
     */
    public void run() {
        while (true) {
            switch (state) {
                case FOLLOWER:
                    runFollower();
                    break;
                case CANDIDATE:
                    runCandidate();
                    break;
                case LEADER:
                    runLeader();
                    break;
            }
        }
    }

    /**
     * Follower 逻辑
     */
    private void runFollower() {
        while (state == ServerState.FOLLOWER) {
            if (System.currentTimeMillis() - lastHeartbeat > electionTimeout) {
                // 选举超时，转为 Candidate
                state = ServerState.CANDIDATE;
                return;
            }
            // 处理 RPC 请求
            processIncomingMessages();
            sleep(10);
        }
    }

    /**
     * Candidate 逻辑
     */
    private void runCandidate() {
        currentTerm++;
        votedFor = myId;
        int votesReceived = 1;  // 投给自己

        // 发送投票请求
        for (int peer : peers) {
            VoteRequest request = new VoteRequest(
                currentTerm, myId,
                getLastLogIndex(), getLastLogTerm()
            );
            sendAsync(peer, request);
        }

        long electionStart = System.currentTimeMillis();
        long thisElectionTimeout = randomTimeout(150, 300);

        while (state == ServerState.CANDIDATE) {
            // 处理投票响应
            VoteResponse response = pollVoteResponse();
            if (response != null) {
                if (response.term > currentTerm) {
                    // 发现更高任期，转为 Follower
                    currentTerm = response.term;
                    state = ServerState.FOLLOWER;
                    votedFor = null;
                    return;
                }
                if (response.voteGranted) {
                    votesReceived++;
                    if (votesReceived > peers.size() / 2) {
                        // 获得多数票，成为 Leader
                        state = ServerState.LEADER;
                        initLeaderState();
                        return;
                    }
                }
            }

            // 选举超时，重新选举
            if (System.currentTimeMillis() - electionStart > thisElectionTimeout) {
                return;  // 重新进入 runCandidate()
            }

            processIncomingMessages();
            sleep(10);
        }
    }

    /**
     * Leader 逻辑
     */
    private void runLeader() {
        // 立即发送心跳
        broadcastHeartbeat();
        long lastHeartbeatTime = System.currentTimeMillis();

        while (state == ServerState.LEADER) {
            // 定期发送心跳
            if (System.currentTimeMillis() - lastHeartbeatTime > HEARTBEAT_INTERVAL) {
                broadcastHeartbeat();
                lastHeartbeatTime = System.currentTimeMillis();
            }

            // 处理客户端请求
            ClientRequest request = pollClientRequest();
            if (request != null) {
                handleClientRequest(request);
            }

            // 处理 AppendEntries 响应
            processAppendEntriesResponses();

            // 处理其他 RPC
            processIncomingMessages();

            sleep(10);
        }
    }

    /**
     * 处理 AppendEntries RPC
     */
    public AppendEntriesResponse handleAppendEntries(AppendEntriesRequest request) {
        // 1. 任期检查
        if (request.term < currentTerm) {
            return new AppendEntriesResponse(currentTerm, false);
        }

        // 2. 更新任期，转为 Follower
        if (request.term > currentTerm) {
            currentTerm = request.term;
            votedFor = null;
        }
        state = ServerState.FOLLOWER;
        lastHeartbeat = System.currentTimeMillis();

        // 3. 日志一致性检查
        if (request.prevLogIndex > 0) {
            if (request.prevLogIndex > log.size()) {
                return new AppendEntriesResponse(currentTerm, false);
            }
            if (log.get(request.prevLogIndex - 1).term != request.prevLogTerm) {
                // 删除冲突的日志
                log = log.subList(0, request.prevLogIndex - 1);
                return new AppendEntriesResponse(currentTerm, false);
            }
        }

        // 4. 追加新日志
        int insertIndex = request.prevLogIndex;
        for (LogEntry entry : request.entries) {
            insertIndex++;
            if (insertIndex <= log.size()) {
                if (log.get(insertIndex - 1).term != entry.term) {
                    log = log.subList(0, insertIndex - 1);
                    log.add(entry);
                }
            } else {
                log.add(entry);
            }
        }

        // 5. 更新 commitIndex
        if (request.leaderCommit > commitIndex) {
            commitIndex = Math.min(request.leaderCommit, log.size());
            applyLogs();
        }

        return new AppendEntriesResponse(currentTerm, true);
    }

    /**
     * 应用已提交的日志到状态机
     */
    private void applyLogs() {
        while (lastApplied < commitIndex) {
            lastApplied++;
            LogEntry entry = log.get(lastApplied - 1);
            stateMachine.apply(entry.command);
        }
    }
}
```

## 5. 面试要点总结

### 5.1 算法对比
| 特性 | Paxos | Raft | ZAB |
|------|-------|------|-----|
| 复杂度 | 高 | 中 | 中 |
| Leader | 可选 | 必须 | 必须 |
| 日志顺序 | 可空洞 | 连续 | 连续FIFO |
| 主要应用 | Chubby | etcd, Consul | ZooKeeper |
| 成员变更 | 复杂 | 联合共识 | 动态配置 |

### 5.2 关键记忆点
```
Paxos：
- 两阶段：Prepare + Accept
- 提案编号全局唯一递增
- 多数派保证已接受值不丢失

Raft：
- 三角色：Leader, Follower, Candidate
- 日志比较：先比任期，再比长度
- 只提交当前任期的日志（安全性保证）

ZAB：
- ZXID = Epoch + Counter
- 三种同步：DIFF, TRUNC, SNAP
- FIFO 顺序保证
```

## 6. 常见面试题

### 6.1 Paxos 相关

**Q1：Basic Paxos 为什么需要两阶段？**
```
答：
Prepare 阶段的目的：
1. 获取提案编号的承诺（阻止旧提案）
2. 发现已被接受的提案（保证安全性）

Accept 阶段的目的：
1. 提交最终的值
2. 使用 Prepare 阶段发现的值（或自己的值）

单阶段无法保证：
- 可能覆盖已被多数派接受的值
- 导致一致性被破坏
```

**Q2：Paxos 可能出现活锁吗？如何解决？**
```
答：可能出现活锁。

活锁场景：
1. P1 发送 Prepare(1)，获得承诺
2. P2 发送 Prepare(2)，获得承诺，P1 的提案被拒绝
3. P1 发送 Prepare(3)，获得承诺，P2 的提案被拒绝
... 无限循环

解决方案：
1. Multi-Paxos：选举一个稳定的 Leader
2. 随机退避：失败后随机等待一段时间
3. 指数退避：逐渐增加等待时间
```

### 6.2 Raft 相关

**Q3：Raft 如何保证已提交的日志不会丢失？**
```
答：通过选举限制和提交规则保证。

选举限制：
- 投票时检查日志是否足够新
- 只有日志最完整的节点才能当选 Leader
- 保证新 Leader 一定有所有已提交的日志

提交规则：
- 只有复制到多数派才能提交
- 只提交当前任期的日志
- 通过提交新日志间接提交旧日志
```

**Q4：为什么 Raft 只提交当前任期的日志？**
```
答：为了避免已提交日志被覆盖。

反例场景（如果允许提交旧任期日志）：
T1: S1(Leader) 复制日志 [2:2] 到 S2，然后崩溃
T2: S5(Leader, term=3) 复制 [3:3] 到 S3,S4
T3: S1(Leader, term=4) 复制 [2:2] 到 S3（达到多数派）
    如果此时提交 [2:2]...
T4: S5(Leader, term=5) 被选举（因为 S3,S4,S5 可以投票）
    S5 会用 [3:3] 覆盖已提交的 [2:2]，违反安全性！

正确做法：
- S1 在 term=4 时追加新日志 [4:4]
- [4:4] 复制到多数派后提交
- [2:2] 和 [4:4] 一起被提交
```

**Q5：Raft 选举过程中如何避免选票分裂？**
```
答：使用随机化选举超时。

机制：
1. 选举超时在 [150ms, 300ms] 随机选择
2. 不同节点超时时间不同
3. 先超时的节点先发起选举
4. 大概率在其他节点超时前获得多数票

效果：
- 减少多个 Candidate 同时竞争
- 加快选举收敛
- 实践中很少出现多轮选举
```

### 6.3 ZAB 相关

**Q6：ZAB 的 ZXID 设计有什么好处？**
```
答：
1. Epoch 区分不同 Leader
   - 新 Leader 一定有更大的 Epoch
   - 旧 Leader 的消息可以被识别并拒绝

2. Counter 区分同一 Leader 的事务
   - 保证事务的 FIFO 顺序
   - 便于快速定位缺失的事务

3. 简化比较逻辑
   - 单次 64 位比较即可确定顺序
   - 高 32 位是 Epoch，低 32 位是 Counter

4. 便于恢复
   - 通过 ZXID 确定同步策略
   - DIFF/TRUNC/SNAP 三种模式
```

**Q7：ZAB 崩溃恢复时如何处理未提交的事务？**
```
答：根据新 Leader 的状态决定。

场景：旧 Leader 崩溃前发送了 Proposal 但未 Commit

情况1：新 Leader 有该 Proposal
- 新 Leader 的 ZXID 包含该事务
- 说明至少有一个 Follower 收到了
- 同步阶段会将其传播给其他节点
- 最终该事务会被提交

情况2：新 Leader 没有该 Proposal
- 新 Leader 可能来自未收到 Proposal 的少数派
- 这时该事务的 ZXID 比新 Leader 的最大 ZXID 大
- 有该事务的 Follower 会通过 TRUNC 同步回滚
- 该事务被丢弃（这是正确的，因为未提交）
```

### 6.4 综合比较

**Q8：什么场景选择 Raft？什么场景选择 ZAB？**
```
答：
选择 Raft：
1. 需要通用的日志复制（如 etcd, Consul）
2. 希望实现简单，容易理解
3. 需要成员变更功能

选择 ZAB：
1. 需要 ZooKeeper 的语义（临时节点、Watch）
2. 需要严格的 FIFO 顺序保证
3. 已有 ZooKeeper 部署
```

**Q9：这些算法的性能瓶颈在哪里？**
```
答：
1. 网络延迟
   - 写操作需要多数派确认
   - 跨数据中心延迟影响大

2. 磁盘 IO
   - 日志需要持久化
   - 快照创建影响性能

3. Leader 瓶颈
   - 所有写操作经过 Leader
   - Leader 故障导致短暂不可用

4. 序列化开销
   - 日志条目需要序列化
   - 状态机快照序列化

优化方向：
- Pipeline：批量处理请求
- 并行日志复制
- 读操作优化（ReadIndex、LeaseRead）
- 快照压缩
```
