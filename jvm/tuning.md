# JVM 调优实战

## 核心概念

JVM 调优的目标是在满足应用性能需求的前提下，合理分配和管理内存资源。调优不是盲目调参数，而是基于监控数据和问题分析的系统性工程。

## JVM 参数配置

### 内存相关参数

```bash
# 堆内存
-Xms4g                          # 堆初始大小（建议与 -Xmx 相同，避免动态扩缩容）
-Xmx4g                          # 堆最大大小
-Xmn2g                          # 新生代大小
-XX:NewRatio=2                   # 老年代:新生代 = 2:1
-XX:SurvivorRatio=8              # Eden:S0:S1 = 8:1:1

# 栈内存
-Xss512k                        # 每个线程栈大小

# 元空间
-XX:MetaspaceSize=256m           # 元空间初始大小
-XX:MaxMetaspaceSize=512m        # 元空间最大大小

# 直接内存
-XX:MaxDirectMemorySize=1g       # 最大直接内存
```

### GC 相关参数

```bash
# 选择收集器
-XX:+UseG1GC                     # 使用 G1（JDK 9+ 默认）
-XX:+UseZGC                      # 使用 ZGC（JDK 15+）
-XX:+UseParallelGC               # 使用 Parallel（JDK 8 默认）

# G1 参数
-XX:MaxGCPauseMillis=200         # 目标停顿时间（ms）
-XX:G1HeapRegionSize=4m          # Region 大小
-XX:InitiatingHeapOccupancyPercent=45  # 触发并发标记的堆占用率
-XX:G1MixedGCCountTarget=8      # 混合回收次数目标

# GC 日志（JDK 9+）
-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=100m
```

### 生产环境推荐配置

```bash
# 4C8G 服务器，普通 Web 应用（JDK 17 + G1）
java \
  -Xms4g -Xmx4g \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -XX:MetaspaceSize=256m \
  -XX:MaxMetaspaceSize=512m \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/var/log/app/heapdump.hprof \
  -Xlog:gc*:file=/var/log/app/gc.log:time,uptime,level,tags:filecount=5,filesize=100m \
  -jar app.jar
```

## 监控与诊断工具

### JDK 自带工具

| 工具 | 用途 | 常用命令 |
|------|------|---------|
| jps | 查看 Java 进程 | `jps -lv` |
| jstat | GC 统计信息 | `jstat -gc <pid> 1000` |
| jmap | 内存映射 | `jmap -heap <pid>` |
| jstack | 线程快照 | `jstack <pid>` |
| jcmd | 综合诊断 | `jcmd <pid> VM.flags` |
| jinfo | JVM 参数 | `jinfo -flags <pid>` |

### jstat — GC 监控

```bash
# 每秒输出一次 GC 统计，共输出 10 次
jstat -gc <pid> 1000 10

# 输出说明
# S0C/S1C: Survivor 0/1 容量
# S0U/S1U: Survivor 0/1 已用
# EC/EU:   Eden 容量/已用
# OC/OU:   Old 容量/已用
# MC/MU:   Metaspace 容量/已用
# YGC/YGCT: Young GC 次数/总时间
# FGC/FGCT: Full GC 次数/总时间

# 查看 GC 原因
jstat -gccause <pid> 1000
```

### jmap — 堆分析

```bash
# 查看堆内存概况
jmap -heap <pid>

# 查看对象统计（按实例数排序）
jmap -histo <pid> | head -20

# 生成堆转储文件
jmap -dump:format=b,file=heap.hprof <pid>

# 只转储存活对象（会触发 Full GC）
jmap -dump:live,format=b,file=heap_live.hprof <pid>
```

### jstack — 线程分析

```bash
# 输出线程快照
jstack <pid>

# 检测死锁
jstack -l <pid>
```

线程状态说明：

```
NEW          → 新建
RUNNABLE     → 运行中（包含 Ready 和 Running）
BLOCKED      → 阻塞（等待锁）
WAITING      → 等待（wait/join/park）
TIMED_WAITING → 超时等待（sleep/wait(timeout)）
TERMINATED   → 终止
```

### Arthas — 在线诊断神器

```bash
# 启动 Arthas
java -jar arthas-boot.jar

# 常用命令
dashboard           # 实时仪表盘（线程、内存、GC）
thread              # 查看所有线程
thread -n 3         # 最忙的 3 个线程
thread -b            # 找出阻塞其他线程的线程
jvm                  # JVM 信息
heapdump /tmp/dump.hprof  # 堆转储
sc *.MyClass         # 搜索类
watch com.example.MyService myMethod returnObj  # 观察方法返回值
trace com.example.MyService myMethod            # 方法耗时追踪
profiler start       # 启动火焰图采集
profiler stop --format html --file /tmp/profiler.html  # 生成火焰图
```

## 故障排查实战

### 场景一：CPU 飙高排查

```bash
# 1. 找到 CPU 最高的 Java 进程
top

# 2. 找到进程中 CPU 最高的线程
top -H -p <pid>

# 3. 将线程 ID 转为十六进制
printf "%x\n" <tid>

# 4. 在 jstack 输出中搜索该线程
jstack <pid> | grep -A 30 "nid=0x<hex_tid>"

# 5. 分析线程栈，定位问题代码
```

常见原因：
- 死循环
- 频繁 GC（GC 线程占用 CPU）
- 正则表达式回溯
- 加密/序列化等计算密集型操作

### 场景二：内存泄漏排查

```bash
# 1. 观察堆内存增长趋势
jstat -gc <pid> 5000

# 2. 对比两次堆转储，找出增长的对象
jmap -dump:format=b,file=dump1.hprof <pid>
# 等待一段时间
jmap -dump:format=b,file=dump2.hprof <pid>

# 3. 使用 MAT（Memory Analyzer Tool）分析
# - 打开 dump 文件
# - 查看 Leak Suspects Report
# - 分析 Dominator Tree
# - 查看 GC Roots 到泄漏对象的引用链
```

常见内存泄漏原因：
- 集合类持有对象引用未释放
- 静态集合不断增长
- 连接/流未关闭
- ThreadLocal 未 remove
- 内部类持有外部类引用
- 监听器/回调未注销

### 场景三：频繁 Full GC

```bash
# 1. 查看 GC 日志，确认 Full GC 频率和耗时
# 2. 分析 GC 原因
jstat -gccause <pid> 1000

# 3. 根据原因采取措施
```

常见原因和解决方案：

| 原因 | 分析方法 | 解决方案 |
|------|---------|---------|
| 老年代空间不足 | jstat -gc 观察 OU 持续增长 | 增大堆内存或排查内存泄漏 |
| 元空间不足 | MC/MU 接近上限 | 增大 MaxMetaspaceSize |
| 大对象直接进入老年代 | 分析堆转储中大对象 | 调整 PretenureSizeThreshold |
| 晋升失败 | GC 日志显示 Promotion Failed | 增大 Survivor 或老年代 |
| System.gc() 调用 | GC 日志显示 System.gc() | 添加 -XX:+DisableExplicitGC |

### 场景四：死锁排查

```bash
# 方法一：jstack 检测
jstack -l <pid>
# 输出中搜索 "Found one Java-level deadlock"

# 方法二：Arthas
thread -b

# 方法三：JConsole / JVisualVM
# 图形界面中的"检测死锁"按钮
```

## GC 调优方法论

### 调优目标

根据应用类型确定优先级：

| 应用类型 | 优先指标 | 推荐收集器 |
|---------|---------|-----------|
| Web 服务 | 低延迟 | G1 / ZGC |
| 批处理 | 高吞吐 | Parallel |
| 交易系统 | 超低延迟 | ZGC |
| 微服务 | 均衡 | G1 |

### 调优步骤

```
1. 确定目标
   ├── 停顿时间目标（如 < 200ms）
   ├── 吞吐量目标（如 > 95%）
   └── 堆内存限制

2. 收集数据
   ├── 开启 GC 日志
   ├── 监控 JVM 指标
   └── 压测获取基准数据

3. 分析问题
   ├── GC 频率是否过高
   ├── GC 停顿时间是否过长
   ├── 堆内存使用趋势
   └── 是否存在内存泄漏

4. 调整参数
   ├── 调整堆大小
   ├── 调整分代比例
   ├── 调整 GC 参数
   └── 更换收集器

5. 验证效果
   ├── 对比调优前后 GC 指标
   ├── 压测验证
   └── 灰度发布观察
```

### 调优原则

1. **不要过早优化**：先保证功能正确，再考虑性能
2. **基于数据调优**：不要凭直觉调参数，用 GC 日志和监控数据说话
3. **每次只改一个参数**：方便对比效果
4. **Xms = Xmx**：避免堆大小动态调整带来的开销
5. **关注 Full GC**：Full GC 频率和耗时是关键指标

## 面试要点

### 高频问题

1. **生产环境 JVM 参数怎么配？**
   - Xms=Xmx，避免动态扩缩容
   - 开启 GC 日志和 OOM 堆转储
   - 根据应用类型选择收集器

2. **线上 CPU 100% 怎么排查？**
   - top → top -Hp → printf hex → jstack grep

3. **内存泄漏怎么排查？**
   - jstat 观察趋势 → jmap 堆转储 → MAT 分析

4. **频繁 Full GC 怎么处理？**
   - 先看 GC 日志确认原因
   - 老年代不足、元空间不足、大对象、晋升失败

5. **Arthas 用过吗？常用哪些命令？**
   - dashboard、thread、trace、watch、heapdump

### 常见陷阱

- 不要盲目增大堆内存，可能导致 GC 停顿时间更长
- `-XX:+DisableExplicitGC` 可能导致 NIO 直接内存无法及时回收
- 生产环境不要随意使用 `jmap -dump:live`，会触发 Full GC

## 参考资料

- 《深入理解 Java 虚拟机》第 4、5 章 - 周志明
- 《Java Performance: The Definitive Guide》 - Scott Oaks
- [Arthas 官方文档](https://arthas.aliyun.com/doc/)
- [GC Tuning Guide](https://docs.oracle.com/en/java/javase/17/gctuning/)
