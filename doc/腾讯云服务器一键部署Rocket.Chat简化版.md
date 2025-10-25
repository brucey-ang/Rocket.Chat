# 腾讯云服务器一键部署Rocket.Chat简化版指南

## 1. 概述

本文档提供了一个极度简化的Rocket.Chat部署方案，专为腾讯云服务器设计。通过本指南，您可以在几分钟内完成Rocket.Chat的部署，无需复杂的配置步骤。

## 2. 系统要求

### 2.1 腾讯云服务器配置
- **推荐配置**：2核CPU + 4GB内存 + 20GB存储（适用于小型团队）
- **操作系统**：Ubuntu 20.04 LTS（推荐）

### 2.2 网络要求
- 公网IP地址
- 开放端口：80, 443, 3000

## 3. 一键部署脚本

我们提供了一个完全自动化的部署脚本，只需执行一条命令即可完成所有部署工作。

### 3.1 连接服务器
```bash
ssh root@your-server-ip
```

### 3.2 执行一键部署命令
```bash
# 如果您已经克隆了Rocket.Chat仓库，可以直接执行本地脚本
bash /path/to/rocket.chat/scripts/tencent-cloud-deploy.sh

# 或者下载并执行我们为您定制的一键部署脚本
curl -L https://raw.githubusercontent.com/RocketChat/Rocket.Chat/master/scripts/tencent-cloud-deploy.sh -o deploy.sh && bash deploy.sh

# 或者使用我们最新创建的完整部署脚本（推荐）
curl -L https://raw.githubusercontent.com/RocketChat/Rocket.Chat/master/scripts/complete-rocketchat-deploy.sh -o deploy.sh && bash deploy.sh
```

或者，如果您更喜欢手动执行每个步骤：

## 4. 使用本地一键部署脚本

我们为您创建了两个专门的一键部署脚本：

### 4.1 腾讯云专用部署脚本
该脚本专为腾讯云服务器优化，会自动完成以下部署步骤：

1. 检查系统环境
2. 安装Docker和Docker Compose
3. 创建必要的配置文件
4. 启动Rocket.Chat服务

只需执行以下命令即可：

```bash
cd /path/to/rocket.chat
bash scripts/tencent-cloud-deploy.sh
```

### 4.2 完整部署脚本（推荐）
我们还创建了一个更完整的部署脚本，它可以处理更多情况，包括自动检测和安装缺失的组件：

```bash
curl -L https://raw.githubusercontent.com/RocketChat/Rocket.Chat/master/scripts/complete-rocketchat-deploy.sh -o deploy.sh && bash deploy.sh
```

这个脚本会自动：
1. 检查并安装Docker（如果未安装）
2. 检查并安装Docker Compose（如果未安装）
3. 下载正确的docker-compose.yml文件
4. 启动所有必要的服务
5. 提供详细的部署后信息

脚本执行过程中，您会看到详细的进度信息。部署完成后，您将获得访问地址和管理命令。

## 5. 极简手动部署方案

如果您希望完全手动控制部署过程，这里是一个最简化的Docker Compose部署方案：

### 5.1 安装Docker和Docker Compose
```bash
# 一键安装Docker
curl -fsSL https://get.docker.com | bash -s docker

# 启动Docker服务
systemctl start docker
systemctl enable docker

# 安装Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

### 5.2 创建最简化的docker-compose.yml
```bash
# 创建部署目录
mkdir -p /opt/rocketchat
cd /opt/rocketchat

# 创建docker-compose.yml文件
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  rocketchat:
    image: registry.rocket.chat/rocketchat/rocket.chat:latest
    restart: always
    environment:
      MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0"
      MONGO_OPLOG_URL: "mongodb://mongodb:27017/local?replicaSet=rs0"
      ROOT_URL: "http://localhost:3000"
      PORT: 3000
    depends_on:
      - mongodb
    ports:
      - "3000:3000"

  mongodb:
    image: docker.io/bitnami/mongodb:6.0
    restart: always
    volumes:
      - mongodb_data:/bitnami/mongodb
    environment:
      MONGODB_REPLICA_SET_MODE: primary
      MONGODB_REPLICA_SET_NAME: rs0
      MONGODB_PORT_NUMBER: 27017
      MONGODB_INITIAL_PRIMARY_HOST: mongodb
      MONGODB_INITIAL_PRIMARY_PORT_NUMBER: 27017
      MONGODB_ADVERTISED_HOSTNAME: mongodb
      MONGODB_ENABLE_JOURNAL: true
      ALLOW_EMPTY_PASSWORD: yes

volumes:
  mongodb_data:
    driver: local
EOF
```

### 5.3 启动服务
```bash
# 启动Rocket.Chat服务
docker-compose up -d

# 等待服务启动（约1-2分钟）
sleep 120

# 检查服务状态
docker-compose ps
```

## 6. 访问Rocket.Chat

部署完成后，您可以通过以下方式访问Rocket.Chat：

- **直接访问**：http://your-server-ip:3000
- **推荐访问**：配置域名后通过 http://your-domain.com 访问

## 7. 初始配置

首次访问时，系统会引导您完成以下设置：

1. 创建管理员账户
2. 配置组织信息
3. 设置站点URL（如果使用域名）

## 8. 日常管理命令

```bash
# 查看服务状态
docker-compose ps

# 查看日志
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
# 备份数据
docker-compose exec mongodb mongodump --out /bitnami/mongodb/backup

# 恢复数据
docker-compose exec mongodb mongorestore /bitnami/mongodb/backup
```

## 10. 安全建议

1. **配置防火墙**：
   ```bash
   ufw allow 22
   ufw allow 80
   ufw allow 443
   ufw enable
   ```

2. **配置SSL证书**（推荐）：
   ```bash
   # 安装Certbot
   apt install certbot python3-certbot-nginx -y
   
   # 获取SSL证书
   certbot certonly --standalone -d your-domain.com
   ```

3. **定期更新**：
   ```bash
   # 更新Rocket.Chat
   docker-compose pull
   docker-compose up -d
   ```

## 11. 故障排除

### 11.1 常见问题
1. **端口被占用**：
   ```bash
   netstat -tlnp | grep 3000
   ```

2. **服务无法启动**：
   ```bash
   docker-compose logs
   ```

3. **内存不足**：
   ```bash
   free -h
   ```

### 11.2 性能优化
```bash
# 增加swap空间（如果内存不足）
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

通过以上简化步骤，您可以在腾讯云服务器上快速部署Rocket.Chat，为您的团队提供安全、高效的通信平台。