# 腾讯云服务器部署Rocket.Chat指南

## 1. 概述

本文档详细介绍了如何在腾讯云服务器上部署Rocket.Chat聊天平台。Rocket.Chat是一个开源的团队通信平台，提供了丰富的功能，包括实时聊天、文件共享、视频通话等。

## 2. 系统要求

### 2.1 硬件要求

根据用户数量选择合适的配置：

**小型部署（≤ 500并发用户）：**
- CPU: 2核
- 内存: 4GB
- 存储: 20GB

**中型部署（≥ 500并发用户）：**
- CPU: 4核
- 内存: 8-12GB
- 存储: 20GB

**大型部署（≥ 5000并发用户）：**
- CPU: 16核
- 内存: 12GB
- 存储: 40GB

### 2.2 操作系统要求

推荐使用以下操作系统：
- Ubuntu 20.04/22.04 LTS
- CentOS 7/8
- Debian 10/11

### 2.3 软件依赖

- Docker 20.10或更高版本
- Docker Compose 1.29或更高版本
- Node.js 14.x（如果从源码编译）
- MongoDB 4.2或更高版本

## 3. 腾讯云服务器准备

### 3.1 创建云服务器实例

1. 登录腾讯云控制台
2. 选择"云服务器CVM"
3. 点击"新建"创建实例
4. 选择合适的配置：
   - 地域：选择离用户较近的地域
   - 实例类型：根据用户规模选择
   - 镜像：选择Ubuntu 20.04 LTS
   - 存储：至少20GB SSD云硬盘
   - 网络：配置公网IP和安全组规则

### 3.2 配置安全组

确保以下端口开放：
- 22：SSH连接
- 80：HTTP访问
- 443：HTTPS访问
- 3000：Rocket.Chat默认端口（如果直接访问）

### 3.3 连接服务器

使用SSH工具连接到服务器：
```bash
ssh root@your-server-ip
```

## 4. 安装Docker和Docker Compose

### 4.1 更新系统包
```bash
apt update && apt upgrade -y
```

### 4.2 安装Docker
```bash
# 安装必要工具
apt install apt-transport-https ca-certificates curl gnupg lsb-release -y

# 添加Docker官方GPG密钥
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# 添加Docker仓库
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装Docker
apt update
apt install docker-ce docker-ce-cli containerd.io -y

# 启动并启用Docker服务
systemctl start docker
systemctl enable docker
```

### 4.3 安装Docker Compose
```bash
# 下载Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加执行权限
chmod +x /usr/local/bin/docker-compose

# 创建软链接
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

## 5. 部署Rocket.Chat

### 5.1 创建部署目录
```bash
mkdir /opt/rocketchat
cd /opt/rocketchat
```

### 5.2 创建docker-compose.yml文件
```bash
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
    labels:
      traefik.enable: "true"
      traefik.http.routers.rocketchat.rule: "Host(`your-domain.com`)"
      traefik.http.routers.rocketchat.tls: "true"
      traefik.http.routers.rocketchat.entrypoints: "https"
      traefik.http.routers.rocketchat.tls.certresolver: "le"

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
docker-compose up -d
```

### 5.4 检查服务状态
```bash
docker-compose ps
```

等待几分钟让服务完全启动，然后可以通过浏览器访问 `http://your-server-ip:3000`。

## 6. 配置反向代理和SSL证书

### 6.1 安装Nginx
```bash
apt install nginx -y
```

### 6.2 配置Nginx反向代理
创建Nginx配置文件：
```bash
cat > /etc/nginx/sites-available/rocketchat << 'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name your-domain.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
}
EOF
```

### 6.3 启用配置
```bash
ln -s /etc/nginx/sites-available/rocketchat /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx
```

### 6.4 配置SSL证书（可选但推荐）
使用Let's Encrypt免费SSL证书：

1. 安装Certbot：
```bash
apt install certbot python3-certbot-nginx -y
```

2. 获取SSL证书：
```bash
certbot --nginx -d your-domain.com
```

按照提示完成证书申请和自动配置。

## 7. 初始配置

### 7.1 访问Rocket.Chat
在浏览器中访问 `http://your-server-ip:3000` 或 `https://your-domain.com`（如果配置了SSL）。

### 7.2 完成安装向导
1. 选择语言
2. 创建管理员账户：
   - 名称：admin
   - 用户名：admin
   - 电子邮件：admin@your-domain.com
   - 密码：设置强密码
3. 配置组织信息
4. 完成安装

## 8. 高级配置

### 8.1 环境变量配置
可以通过修改docker-compose.yml文件中的环境变量来配置Rocket.Chat：

```yaml
environment:
  MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0"
  MONGO_OPLOG_URL: "mongodb://mongodb:27017/local?replicaSet=rs0"
  ROOT_URL: "https://your-domain.com"
  PORT: 3000
  ADMIN_PASS: "your-admin-password"
  ADMIN_EMAIL: "admin@your-domain.com"
  OVERWRITE_SETTING_Show_Setup_Wizard: "completed"
```

### 8.2 文件上传配置
推荐使用对象存储服务（如腾讯云COS）来存储文件：

1. 在腾讯云控制台创建COS存储桶
2. 获取访问密钥
3. 在Rocket.Chat管理面板中配置文件上传设置

## 9. 日常维护

### 9.1 查看日志
```bash
docker-compose logs -f
```

### 9.2 更新Rocket.Chat
```bash
cd /opt/rocketchat
docker-compose pull
docker-compose up -d
```

### 9.3 备份数据
```bash
# 备份MongoDB数据
docker-compose exec mongodb mongodump --out /bitnami/mongodb/backup

# 复制备份到安全位置
docker cp rocketchat_mongodb_1:/bitnami/mongodb/backup ./backup
```

## 10. 故障排除

### 10.1 服务无法启动
1. 检查Docker服务状态：`systemctl status docker`
2. 检查容器日志：`docker-compose logs`
3. 确认端口未被占用：`netstat -tlnp | grep 3000`

### 10.2 数据库连接问题
1. 检查MongoDB容器状态：`docker-compose ps`
2. 确认MongoDB连接URL配置正确
3. 检查MongoDB日志：`docker-compose logs mongodb`

### 10.3 网络连接问题
1. 检查安全组规则
2. 确认防火墙设置
3. 测试端口连通性：`telnet your-server-ip 3000`

## 11. 性能优化建议

### 11.1 系统优化
1. 增加文件描述符限制
2. 调整内核参数
3. 启用swap空间（如果内存不足）

### 11.2 Rocket.Chat优化
1. 根据用户数量调整实例规格
2. 启用缓存机制
3. 配置适当的日志级别

## 12. 安全建议

### 12.1 访问安全
1. 使用强密码策略
2. 启用双因素认证
3. 限制管理员访问

### 12.2 网络安全
1. 使用SSL/TLS加密
2. 配置防火墙规则
3. 定期更新系统和软件

通过遵循本指南，您可以在腾讯云服务器上成功部署和运行Rocket.Chat，为您的团队提供安全、高效的通信平台。