# JVM 类加载机制

## 核心概念

类加载机制是 JVM 将 Class 文件加载到内存，并对其进行校验、解析和初始化，最终形成可被 JVM 直接使用的 Java 类型的过程。

## 类的生命周期

```
加载 → 验证 → 准备 → 解析 → 初始化 → 使用 → 卸载
       ├─────────────────┤
              连接阶段
```

### 1. 加载（Loading）

- 通过类的全限定名获取二进制字节流
- 将字节流代表的静态存储结构转化为方法区的运行时数据结构
- 在堆中生成该类的 `Class` 对象，作为方法区数据的访问入口

**字节流来源**：
- 本地文件系统（.class 文件）
- JAR/WAR 包
- 网络（Applet）
- 动态代理（运行时生成）
- JSP 文件生成

### 2. 验证（Verification）

确保 Class 文件的字节流符合 JVM 规范，不会危害 JVM 安全。

- **文件格式验证**：魔数 `0xCAFEBABE`、版本号、常量池
- **元数据验证**：语义分析，如是否有父类、是否继承了 final 类
- **字节码验证**：数据流和控制流分析，确保语义合法
- **符号引用验证**：确保解析阶段能正确执行

### 3. 准备（Preparation）

为类的**静态变量**分配内存并设置**零值**。

```java
public static int value = 123;
// 准备阶段：value = 0（零值）
// 初始化阶段：value = 123（赋值）

public static final int CONSTANT = 123;
// 准备阶段：CONSTANT = 123（编译期常量，直接赋值）
```

### 4. 解析（Resolution）

将常量池中的**符号引用**替换为**直接引用**。

- **符号引用**：用一组符号描述引用的目标（如全限定类名）
- **直接引用**：直接指向目标的指针、偏移量等

### 5. 初始化（Initialization）⭐

执行类构造器 `<clinit>()` 方法，真正执行类中定义的 Java 代码。

#### 触发初始化的场景（有且仅有）

1. `new`、`getstatic`、`putstatic`、`invokestatic` 指令
2. 反射调用（`Class.forName()`）
3. 初始化子类时，父类未初始化
4. JVM 启动时的主类
5. `MethodHandle` 解析结果为相关方法

#### 不会触发初始化的场景

```java
// 1. 通过子类引用父类的静态字段 → 只初始化父类
class Parent {
    static int value = 10;
}
class Child extends Parent {}
System.out.println(Child.value); // 不会初始化 Child

// 2. 通过数组定义引用类 → 不会初始化该类
Parent[] arr = new Parent[10];

// 3. 引用常量 → 编译期已放入常量池，不会初始化定义类
System.out.println(Parent.CONSTANT);
```

## 类加载器

### 类加载器层次

```
┌─────────────────────────────────┐
│  Bootstrap ClassLoader          │ ← C++ 实现，加载 rt.jar
│  （启动类加载器）                │    JAVA_HOME/lib
├─────────────────────────────────┤
│  Extension ClassLoader          │ ← Java 实现
│  （扩展类加载器）                │    JAVA_HOME/lib/ext
│  JDK 9+: Platform ClassLoader  │
├─────────────────────────────────┤
│  Application ClassLoader        │ ← Java 实现
│  （应用程序类加载器）             │    classpath 下的类
├─────────────────────────────────┤
│  Custom ClassLoader             │ ← 用户自定义
│  （自定义类加载器）               │
└─────────────────────────────────┘
```

### 双亲委派模型（Parents Delegation Model）⭐⭐⭐⭐⭐

#### 工作原理

```
                  加载请求
                     │
          ┌──────────▼──────────┐
          │ Custom ClassLoader   │─── 能加载？──▶ 加载
          └──────────┬──────────┘      ↑ NO
                     │ 委派给父加载器    │
          ┌──────────▼──────────┐      │
          │ App ClassLoader      │─── 能加载？──┘
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────┐
          │ Ext ClassLoader      │─── 能加载？
          └──────────┬──────────┘      ↑ NO
                     │                 │
          ┌──────────▼──────────┐      │
          │ Bootstrap ClassLoader│─── 能加载？──┘
          └─────────────────────┘
```

1. 收到类加载请求时，先委派给父加载器
2. 父加载器无法加载时，子加载器才尝试加载
3. 从顶层 Bootstrap 开始往下尝试

#### 源码实现

```java
protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
    synchronized (getClassLoadingLock(name)) {
        // 1. 检查是否已加载
        Class<?> c = findLoadedClass(name);
        if (c == null) {
            try {
                // 2. 委派给父加载器
                if (parent != null) {
                    c = parent.loadClass(name, false);
                } else {
                    c = findBootstrapClassOrNull(name);
                }
            } catch (ClassNotFoundException e) {
                // 父加载器无法加载
            }
            if (c == null) {
                // 3. 自己加载
                c = findClass(name);
            }
        }
        return c;
    }
}
```

#### 双亲委派的意义

1. **避免类的重复加载**：父加载器加载过的类不会再加载
2. **保证核心类安全**：即使自定义了 `java.lang.String`，也会被 Bootstrap 加载器优先加载，保证使用的是 JDK 的核心类

### 打破双亲委派

#### 1. SPI 机制（Service Provider Interface）

```
Bootstrap ClassLoader 加载了 JDBC 接口（rt.jar）
但实现类（mysql-connector.jar）在 classpath 下
需要 App ClassLoader 加载

解决方案：线程上下文类加载器（Thread Context ClassLoader）
```

```java
// ServiceLoader 使用线程上下文类加载器加载 SPI 实现
ServiceLoader<Driver> drivers = ServiceLoader.load(Driver.class);
```

#### 2. Tomcat 类加载器

```
      Bootstrap
          │
      Extension
          │
      Application
          │
    ┌─────┴──────┐
  Common       Catalina
    │
 ┌──┴──┐
WebApp1 WebApp2    ← 每个 Web 应用独立的类加载器
```

- 每个 Web 应用使用独立的 `WebAppClassLoader`
- **先自己加载**，再委派给父加载器（打破双亲委派）
- 实现不同 Web 应用的**类隔离**

#### 3. OSGi 模块化

- 网状类加载结构
- 每个 Bundle 有自己的类加载器
- 可以精确控制类的可见性

#### 4. 热部署

```java
// 自定义类加载器实现热部署
public class HotSwapClassLoader extends ClassLoader {
    @Override
    public Class<?> findClass(String name) throws ClassNotFoundException {
        byte[] classData = loadClassData(name); // 重新读取 class 文件
        return defineClass(name, classData, 0, classData.length);
    }
}
// 每次热部署创建新的类加载器实例
```

## 面试要点

### 高频问题

1. **类加载的过程是什么？**
   - 加载 → 验证 → 准备 → 解析 → 初始化

2. **什么是双亲委派模型？为什么需要？**
   - 向上委派，向下加载
   - 保证类的唯一性和核心类安全

3. **如何打破双亲委派？**
   - 重写 `loadClass()` 方法
   - 线程上下文类加载器（SPI）
   - Tomcat 的 WebAppClassLoader

4. **类的初始化时机？**
   - new、getstatic、putstatic、invokestatic
   - 反射、子类初始化触发父类、主类、MethodHandle

5. **两个类相等的条件？**
   - 同一个 Class 文件 + 同一个类加载器
   - 不同类加载器加载的同一个 Class 文件，产生的类不相等

### 常见陷阱

- `Class.forName()` 会触发初始化，`ClassLoader.loadClass()` 不会
- 准备阶段赋零值，初始化阶段才赋真正的值（static final 编译期常量除外）
- Bootstrap ClassLoader 在 Java 中返回 `null`，因为它由 C++ 实现

## 参考资料

- 《深入理解 Java 虚拟机》第 7 章 - 周志明
- [JVM Specification: Loading, Linking, and Initializing](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-5.html)
