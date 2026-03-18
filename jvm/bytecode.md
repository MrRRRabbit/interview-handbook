# 字节码与执行引擎

## 核心概念

Java 程序编译后生成 Class 文件（字节码），由 JVM 的执行引擎解释或编译执行。理解字节码有助于深入理解 Java 语言特性的底层实现。

## Class 文件结构

### 整体结构

```
ClassFile {
    u4             magic;                 // 魔数：0xCAFEBABE
    u2             minor_version;         // 次版本号
    u2             major_version;         // 主版本号（52=JDK 8, 61=JDK 17）
    u2             constant_pool_count;   // 常量池大小
    cp_info        constant_pool[];       // 常量池
    u2             access_flags;          // 访问标志
    u2             this_class;            // 类索引
    u2             super_class;           // 父类索引
    u2             interfaces_count;      // 接口数量
    u2             interfaces[];          // 接口索引
    u2             fields_count;          // 字段数量
    field_info     fields[];              // 字段表
    u2             methods_count;         // 方法数量
    method_info    methods[];             // 方法表
    u2             attributes_count;      // 属性数量
    attribute_info attributes[];          // 属性表
}
```

### 常量池

常量池是 Class 文件的资源仓库，包含两大类常量：

- **字面量**：文本字符串、final 常量值
- **符号引用**：类/接口全限定名、字段名和描述符、方法名和描述符

### 查看字节码

```bash
# 使用 javap 反编译
javap -v -p MyClass.class

# 查看特定方法
javap -c MyClass.class
```

## 字节码指令

### 操作数栈与局部变量表

```
方法执行时的栈帧：

局部变量表（Local Variables）：
┌──────┬──────┬──────┬──────┐
│ this │ arg1 │ arg2 │ var1 │  ← 按 slot 存储
└──────┴──────┴──────┴──────┘
  [0]    [1]    [2]    [3]

操作数栈（Operand Stack）：
┌──────┐
│  b   │  ← 栈顶
├──────┤
│  a   │
└──────┘
```

### 常用指令分类

#### 加载和存储指令

```
iload_0     // 将局部变量表 slot 0 的 int 值压入操作数栈
istore_1    // 将操作数栈顶 int 值存入局部变量表 slot 1
aload_0     // 加载引用类型（this）
bipush 100  // 将常量 100 压入栈
ldc "hello" // 将字符串常量压入栈
```

#### 算术指令

```
iadd        // int 加法
isub        // int 减法
imul        // int 乘法
idiv        // int 除法
iinc 1, 1   // 局部变量表 slot 1 自增 1
```

#### 方法调用指令

```
invokevirtual   // 调用实例方法（虚方法，支持多态）
invokeinterface // 调用接口方法
invokespecial   // 调用构造器、私有方法、super 方法
invokestatic    // 调用静态方法
invokedynamic   // 动态调用（Lambda、方法引用）
```

### 实例分析

```java
public int add(int a, int b) {
    return a + b;
}
```

对应字节码：

```
0: iload_1     // 将参数 a（slot 1）压入栈
1: iload_2     // 将参数 b（slot 2）压入栈
2: iadd        // 弹出两个值相加，结果压入栈
3: ireturn     // 返回栈顶 int 值
```

### i++ 与 ++i 的字节码区别

```java
int i = 0;
int a = i++;   // a = 0, i = 1
int b = ++i;   // b = 2, i = 2
```

```
// i++：先压栈再自增
iload_1         // 将 i 的值压入操作数栈（值为 0）
iinc 1, 1       // 局部变量表中 i 自增（i 变为 1）
istore_2        // 将栈顶值（0）存入 a

// ++i：先自增再压栈
iinc 1, 1       // 局部变量表中 i 自增（i 变为 2）
iload_1         // 将 i 的值压入操作数栈（值为 2）
istore_3        // 将栈顶值（2）存入 b
```

## 执行引擎

### 解释执行

- 逐条读取字节码指令并执行
- 启动速度快，执行速度慢
- 所有 Java 代码都可以解释执行

### JIT 编译（Just-In-Time）⭐⭐⭐⭐

将热点字节码编译为本地机器码，提升执行效率。

#### 热点代码检测

- **方法调用计数器**：统计方法被调用的次数
- **回边计数器**：统计循环体执行的次数
- 达到阈值后触发 JIT 编译

```bash
-XX:CompileThreshold=10000   # 方法调用计数器阈值（默认 C1: 1500, C2: 10000）
```

#### 编译器类型

| 编译器 | 特点 | 编译速度 | 代码质量 |
|-------|------|---------|---------|
| C1（Client Compiler） | 简单优化 | 快 | 一般 |
| C2（Server Compiler） | 深度优化 | 慢 | 高 |
| Graal | 新一代编译器 | 中 | 高 |

#### 分层编译（Tiered Compilation）

JDK 8+ 默认开启，结合 C1 和 C2：

```
解释执行 → C1 编译（快速优化） → C2 编译（深度优化）
  Level 0      Level 1-3              Level 4
```

### JIT 优化技术

#### 1. 方法内联（Inlining）

```java
// 优化前
public int add(int a, int b) { return a + b; }
public int calculate() { return add(1, 2); }

// 内联后（消除方法调用开销）
public int calculate() { return 1 + 2; }
```

#### 2. 逃逸分析（Escape Analysis）⭐⭐⭐⭐

分析对象的作用域，判断对象是否"逃逸"出方法或线程。

```java
// 未逃逸 - 对象只在方法内使用
public int test() {
    Point p = new Point(1, 2);
    return p.x + p.y;
}
```

基于逃逸分析的优化：

- **栈上分配**：未逃逸的对象直接在栈上分配，方法结束自动回收
- **标量替换**：将对象拆解为基本类型变量

```java
// 标量替换前
Point p = new Point(1, 2);
return p.x + p.y;

// 标量替换后（不创建对象）
int x = 1;
int y = 2;
return x + y;
```

- **锁消除**：未逃逸的对象上的同步操作可以消除

```java
// 锁消除前
public void test() {
    Object lock = new Object(); // 未逃逸
    synchronized (lock) { ... }
}
// 锁消除后：移除 synchronized
```

```bash
-XX:+DoEscapeAnalysis        # 开启逃逸分析（默认开启）
-XX:+EliminateAllocations    # 开启标量替换（默认开启）
-XX:+EliminateLocks          # 开启锁消除（默认开启）
```

## 方法调用

### 静态分派（编译期确定）

```java
// 重载：编译期根据引用类型确定调用哪个方法
public void print(Object obj) { ... }      // 方法 1
public void print(String str) { ... }      // 方法 2

Object s = "hello";
print(s);   // 调用方法 1（编译期看引用类型 Object）
```

### 动态分派（运行期确定）

```java
// 重写：运行期根据实际类型确定调用哪个方法
class Parent {
    void show() { System.out.println("Parent"); }
}
class Child extends Parent {
    @Override
    void show() { System.out.println("Child"); }
}

Parent obj = new Child();
obj.show();  // 输出 "Child"（invokevirtual 指令，查虚方法表）
```

#### 虚方法表（vtable）

```
Parent vtable:           Child vtable:
┌──────────┬─────────┐  ┌──────────┬─────────┐
│ toString │ Object   │  │ toString │ Object   │
│ show     │ Parent   │  │ show     │ Child  ← │ 重写
└──────────┴─────────┘  └──────────┴─────────┘
```

- 每个类有一个虚方法表
- 重写的方法指向子类实现
- 未重写的方法指向父类实现
- 类加载的连接阶段初始化虚方法表

## 面试要点

### 高频问题

1. **JIT 编译器的作用？**
   - 将热点代码编译为本地机器码，提升执行效率

2. **什么是逃逸分析？有什么优化？**
   - 分析对象是否逃逸出方法/线程
   - 栈上分配、标量替换、锁消除

3. **方法调用的分派机制？**
   - 静态分派：重载，编译期确定
   - 动态分派：重写，运行期确定（虚方法表）

4. **invokedynamic 指令的作用？**
   - 支持动态类型语言
   - Lambda 表达式的底层实现

5. **i++ 是线程安全的吗？**
   - 不是，i++ 包含读取、自增、写回三个步骤，不是原子操作

### 常见陷阱

- 解释执行不等于慢，JIT 编译不等于快（编译本身有开销）
- 逃逸分析不保证一定触发栈上分配（受 JVM 实现和参数影响）
- `final` 方法不一定被内联，短方法更容易被内联

## 参考资料

- 《深入理解 Java 虚拟机》第 6、8 章 - 周志明
- [JVM Specification: The class File Format](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-4.html)
- [Understanding JIT Compilation](https://docs.oracle.com/en/java/javase/17/vm/java-hotspot-virtual-machine-performance-enhancements.html)
