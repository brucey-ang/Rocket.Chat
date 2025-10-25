# Rocket.Chat单体部署配置参数说明

## 1. 概述

Rocket.Chat支持单体部署模式，所有服务运行在单一进程中。这种部署方式适合小型团队和开发测试环境。本文档详细说明了在单体部署时需要配置的参数。

## 2. 基本环境变量配置

### 2.1 数据库配置
```bash
# MongoDB连接URL
MONGO_URL=mongodb://localhost:27017/rocketchat

# MongoDB Oplog连接URL（用于实时数据同步）
MONGO_OPLOG_URL=mongodb://localhost:27017/local
```

### 2.2 网络配置
```bash
# 服务器根URL
ROOT_URL=http://localhost:3000

# 服务器监听端口
PORT=3000

# 实例IP地址
INSTANCE_IP=127.0.0.1
```

## 3. 微服务相关配置

### 3.1 传输器配置
在单体部署中，通常使用`monolith`传输器：
```bash
TRANSPORTER=monolith
```

### 3.2 网络代理配置
```bash
# 命名空间
MS_NAMESPACE=

# 缓存类型
CACHE=Memory

# 序列化器
SERIALIZER=EJSON

# 负载均衡策略
BALANCE_STRATEGY=RoundRobin

# 是否优先使用本地服务
BALANCE_PREFER_LOCAL=true
```

## 4. 日志和监控配置

### 4.1 日志级别
```bash
# Moleculer日志级别
MOLECULER_LOG_LEVEL=warn

# 可选值: fatal, error, warn, info, debug, trace
```

### 4.2 指标监控
```bash
# 是否启用指标收集
MS_METRICS=false

# 指标服务端口
MS_METRICS_PORT=9458
```

## 5. 重试和超时配置

### 5.1 请求超时
```bash
# 请求超时时间（秒）
REQUEST_TIMEOUT=60
```

### 5.2 重试策略
```bash
# 是否启用重试
RETRY_ENABLED=false

# 重试次数
RETRY_RETRIES=5

# 初始延迟（毫秒）
RETRY_DELAY=100

# 最大延迟（毫秒）
RETRY_MAX_DELAY=1000

# 重试因子
RETRY_FACTOR=2
```

## 6. 心跳和连接配置

### 6.1 心跳设置
```bash
# 心跳间隔（秒）
HEARTBEAT_INTERVAL=10

# 心跳超时（秒）
HEARTBEAT_TIMEOUT=30
```

### 6.2 批量处理
```bash
# 是否启用批量处理
BULKHEAD_ENABLED=false

# 并发数
BULKHEAD_CONCURRENCY=10

# 最大队列大小
BULKHEAD_MAX_QUEUE_SIZE=10000
```

## 7. 多实例配置

### 7.1 实例状态
```bash
# 多实例ping间隔（秒）
MULTIPLE_INSTANCES_PING_INTERVAL=10

# 实例过期时间（秒）
MULTIPLE_INSTANCES_EXPIRE=30
```

## 8. 许可证和企业功能

### 8.1 企业许可证
```bash
# 企业版许可证
ROCKETCHAT_LICENSE=
```

## 9. 启动命令

### 9.1 开发环境启动
```bash
# 基本启动命令
yarn dev

# 单体部署启动（默认）
yarn dev
```

### 9.2 生产环境启动
```bash
# 构建应用
meteor build --server-only --directory /path/to/build

# 运行构建后的应用
node main.js
```

## 10. Docker部署配置

### 10.1 Docker环境变量
在Docker部署中，可以通过环境变量配置：
```yaml
environment:
  - MONGO_URL=mongodb://mongo:27017/rocketchat
  - MONGO_OPLOG_URL=mongodb://mongo:27017/local
  - ROOT_URL=http://localhost:3000
  - PORT=3000
```

## 11. 高级配置选项

### 11.1 性能调优
```bash
# Node.js内存限制
NODE_OPTIONS=--max-old-space-size=4096

# 跳过未处理的Promise拒绝
EXIT_UNHANDLEDPROMISEREJECTION=true
```

### 11.2 调试配置
```bash
# 启用调试模式
meteor run --inspect

# 启用调试模式并暂停
meteor run --inspect-brk
```

## 12. 安全配置

### 12.1 环境变量覆盖设置
```bash
# 覆盖特定设置
OVERWRITE_SETTING_<Setting_Id>=value
```

例如：
```bash
OVERWRITE_SETTING_Log_Level=2
```

## 13. 常见问题和解决方案

### 13.1 数据库连接问题
确保MongoDB服务正在运行，并且连接URL正确配置。

### 13.2 端口冲突
修改PORT环境变量以使用不同的端口。

### 13.3 内存不足
增加Node.js内存限制：
```bash
NODE_OPTIONS=--max-old-space-size=8192
```

## 14. 最佳实践

1. **生产环境**：始终配置MONGO_OPLOG_URL以获得最佳性能
2. **安全性**：不要在环境变量中存储敏感信息
3. **监控**：启用指标收集以监控系统性能
4. **备份**：定期备份MongoDB数据库
5. **日志**：适当配置日志级别以平衡信息量和性能

通过正确配置这些参数，您可以成功部署和运行Rocket.Chat单体实例。