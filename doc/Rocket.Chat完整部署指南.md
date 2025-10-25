# Rocket.Chat完整部署指南

## 1. 概述

本文档详细介绍如何使用我们新创建的完整部署脚本，在Ubuntu系统上快速部署Rocket.Chat。该部署方案专为2GB内存的服务器优化，支持10个左右用户的初期使用场景，并启用了所有必需的功能：

- 用户自行注册
- 私聊/群聊
- 文件分享
- 消息编辑
- Web登录等基本功能

## 2. 系统要求

### 2.1 硬件要求
- **CPU**: 至少1核
- **内存**: 2GB RAM（最低要求）
- **存储**: 至少10GB可用空间
- **网络**: 公网IP或可访问的内网IP

### 2.2 操作系统支持
- Ubuntu 18.04/20.04/22.04 LTS（推荐）

## 3. 部署脚本说明

我们提供了一个专门优化的部署脚本，能够自动完成以下任务：

1. 检查系统环境和权限
2. 安装Docker和Docker Compose
3. 针对2GB内存环境优化系统配置
4. 创建资源受限的容器配置
5. 启用所有必需功能
6. 启动Rocket.Chat服务
7. 提供详细的部署后信息

## 4. 使用方法

### 4.1 下载并执行脚本

```bash
# 进入项目根目录
cd /path/to/rocket.chat

# 添加执行权限
chmod +x scripts/complete-rocketchat-deploy.sh

# 执行部署（需要root权限）
sudo ./scripts/complete-rocketchat-deploy.sh
```

或者，您也可以直接使用npm脚本：

```bash
cd /path/to/rocket.chat
sudo npm run deploy:complete
```

### 4.2 脚本执行过程

脚本执行过程中会自动完成以下步骤：

1. **环境检查**: 验证操作系统类型和root权限
2. **系统更新**: 更新系统软件包
3. **依赖安装**: 安装必要的系统依赖
4. **Docker安装**: 安装并配置Docker和Docker Compose
5. **系统优化**: 
   - 如果内存不足2GB，自动添加1GB交换空间
   - 配置内核参数优化内存使用
6. **配置创建**: 生成针对2GB内存优化的docker-compose.yml文件，并启用所有必需功能
7. **服务启动**: 启动Rocket.Chat和MongoDB服务
8. **完成提示**: 显示访问信息和管理命令

## 5. 优化措施

### 5.1 内存优化

- **Rocket.Chat容器**: 限制内存使用为1GB
- **MongoDB容器**: 限制内存使用为512MB
- **MongoDB配置**: 将WiredTiger缓存限制为256MB
- **Node.js配置**: 将Node.js堆大小限制为1024MB

### 5.2 系统优化

- **交换空间**: 如果物理内存不足2GB，自动添加1GB交换空间
- **内核参数**: 调整内存管理参数以适应低内存环境
- **日志管理**: 限制容器日志大小，防止磁盘空间耗尽

### 5.3 CPU优化

- **Rocket.Chat容器**: 限制CPU使用为0.5个核心
- **MongoDB容器**: 限制CPU使用为0.3个核心

## 6. 启用的功能

### 6.1 用户功能
- **自行注册**: 用户可以自行创建账户
- **好友添加**: 用户可以添加其他用户为好友
- **个人资料**: 用户可以编辑个人资料和头像

### 6.2 消息功能
- **私聊**: 用户之间可以进行一对一私聊
- **群聊**: 用户可以创建和加入群组聊天
- **消息编辑**: 用户可以编辑已发送的消息
- **消息删除**: 用户可以删除自己的消息
- **消息历史**: 保存聊天历史记录

### 6.3 文件分享
- **文件上传**: 用户可以上传文件到聊天中
- **文件下载**: 用户可以下载聊天中的文件
- **图片预览**: 支持图片文件的预览功能

### 6.4 Web登录
- **Web界面**: 完整的Web聊天界面
- **多浏览器支持**: 支持主流浏览器
- **响应式设计**: 支持桌面和移动设备

## 7. 访问Rocket.Chat

部署完成后，您可以通过以下方式访问Rocket.Chat：

- **直接访问**: http://your-server-ip:3000
- **推荐访问**: 配置域名后通过 http://your-domain.com 访问

首次访问时，系统会引导您完成管理员账户创建和基本设置。

## 8. 日常管理命令

```bash
# 进入部署目录
cd /opt/rocketchat

# 查看服务状态
docker-compose ps

# 查看实时日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重启服务
docker-compose restart

# 更新到最新版本
docker-compose pull
docker-compose up -d
```

## 9. 备份和恢复

```bash
# 进入部署目录
cd /opt/rocketchat

# 备份MongoDB数据
docker-compose exec mongodb mongodump --out /data/db/backup

# 恢复MongoDB数据
docker-compose exec mongodb mongorestore /data/db/backup
```

## 10. 性能建议

### 10.1 用户数量建议
该配置适合初期使用，建议用户数量不超过：
- **活跃用户**: 10-20人
- **并发用户**: 5-10人

### 10.2 功能使用建议
为保证系统稳定性，建议：
1. 避免上传大量大文件（单文件建议不超过100MB）
2. 定期清理不需要的频道和消息
3. 避免安装过多的应用程序

### 10.3 监控命令
```bash
# 查看系统内存使用情况
free -h

# 查看磁盘使用情况
df -h

# 查看Docker容器资源使用
docker stats
```

## 11. 故障排除

### 11.1 常见问题

1. **服务启动缓慢**:
   - 2GB内存环境下首次启动可能需要3-4分钟
   - 请耐心等待，不要重复执行启动命令

2. **内存不足**:
   ```bash
   # 检查内存使用情况
   free -h
   
   # 检查交换空间
   swapon --show
   ```

3. **端口被占用**:
   ```bash
   # 检查3000端口占用情况
   netstat -tlnp | grep 3000
   ```

4. **服务无法启动**:
   ```bash
   # 查看详细日志
   cd /opt/rocketchat
   docker-compose logs
   ```

### 11.2 性能优化

如果需要进一步优化性能，可以考虑：

1. **升级硬件**: 增加内存到4GB或以上
2. **使用SSD存储**: 提高磁盘I/O性能
3. **配置反向代理**: 使用Nginx作为反向代理
4. **启用SSL**: 配置HTTPS以提高安全性

## 12. 安全建议

1. **配置防火墙**:
   ```bash
   # Ubuntu/Debian (UFW)
   sudo ufw allow 22
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw enable
   ```

2. **配置SSL证书**（推荐）:
   ```bash
   # 安装Certbot
   sudo apt install certbot python3-certbot-nginx -y
   
   # 获取SSL证书
   sudo certbot --nginx -d your-domain.com
   ```

3. **定期更新**:
   ```bash
   # 更新Rocket.Chat
   cd /opt/rocketchat
   docker-compose pull
   docker-compose up -d
   ```

通过以上优化方案，您可以在仅有2GB内存的Ubuntu服务器上成功部署和运行Rocket.Chat，为小型团队提供完整的即时通讯服务。
