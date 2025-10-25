# Linux服务器一键部署Rocket.Chat指南

## 1. 概述

本文档详细介绍如何在Linux服务器上通过一键脚本快速部署Rocket.Chat。我们将提供多种一键部署方案，包括使用Snap、Docker和官方安装脚本等方式。

## 2. 系统要求

### 2.1 操作系统支持
- Ubuntu 18.04/20.04/22.04 LTS
- CentOS 7/8
- Debian 9/10/11
- RHEL 7/8

### 2.2 硬件要求
- CPU: 至少2核
- 内存: 至少4GB（推荐8GB以上）
- 存储: 至少20GB可用空间
- 网络: 公网IP或可访问的内网IP

### 2.3 软件依赖
- Docker 18.06+（如果使用Docker方式）
- Snapd（如果使用Snap方式）
- curl或wget工具

## 3. 一键部署方案

### 3.1 使用Snap一键部署（推荐）

Snap是Ubuntu官方推荐的部署方式，具有自动更新和依赖管理的优势。

#### 3.1.1 安装Snapd
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install snapd -y

# CentOS/RHEL
sudo yum install epel-release -y
sudo yum install snapd -y

# 启动snapd服务
sudo systemctl enable --now snapd.socket
```

#### 3.1.2 安装Rocket.Chat
```bash
# 安装Rocket.Chat
sudo snap install rocketchat-server

# 检查服务状态
sudo systemctl status snap.rocketchat-server.rocketchat-server

# 查看服务日志
sudo journalctl -u snap.rocketchat-server.rocketchat-server
```

#### 3.1.3 访问Rocket.Chat
安装完成后，可以通过以下URL访问：
```
http://your-server-ip:3000
```

### 3.2 使用Docker一键部署

Docker方式提供了更好的环境隔离和部署灵活性。

#### 3.2.1 安装Docker和Docker Compose
```bash
# 安装Docker
curl -fsSL https://get.docker.com | bash -s docker

# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

#### 3.2.2 创建一键部署脚本
```bash
# 创建部署脚本
cat > deploy-rocketchat.sh << 'EOF'
#!/bin/bash

# 创建部署目录
mkdir -p /opt/rocketchat
cd /opt/rocketchat

# 创建docker-compose.yml文件
cat > docker-compose.yml << 'DOCKEREOF'
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
      traefik.http.routers.rocketchat.rule: "Host(\`localhost\`)"
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
DOCKEREOF

# 启动服务
docker-compose up -d

echo "Rocket.Chat部署完成！"
echo "请通过 http://your-server-ip:3000 访问"
echo "初始管理员账户将在首次访问时创建"
EOF

# 添加执行权限
chmod +x deploy-rocketchat.sh

# 执行部署脚本
./deploy-rocketchat.sh
```

### 3.3 使用官方一键安装脚本

Rocket.Chat官方提供了一键安装脚本，适用于多种Linux发行版。

#### 3.3.1 下载并执行安装脚本
```bash
# 下载安装脚本
curl -L https://raw.githubusercontent.com/RocketChat/Rocket.Chat/master/scripts/install.sh -O

# 添加执行权限
chmod +x install.sh

# 执行安装
sudo ./install.sh
```

### 3.4 自定义一键部署脚本

创建一个完整的自动化部署脚本：

```bash
# 创建一键部署脚本
cat > rocket-deploy.sh << 'EOF'
#!/bin/bash

# Rocket.Chat一键部署脚本
# 支持Ubuntu/Debian/CentOS/RHEL系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# 检查系统类型
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "无法检测操作系统类型"
        exit 1
    fi
    
    log "检测到操作系统: $OS $VER"
}

# 安装必要依赖
install_dependencies() {
    log "安装必要依赖..."
    
    if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
        apt update
        apt install -y curl wget gnupg apt-transport-https ca-certificates
    elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
        yum install -y curl wget gnupg
    else
        error "不支持的操作系统: $OS"
        exit 1
    fi
}

# 安装Docker
install_docker() {
    log "安装Docker..."
    
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl start docker
        systemctl enable docker
    else
        log "Docker已安装"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        log "Docker Compose已安装"
    fi
}

# 创建部署目录
create_deployment_dir() {
    log "创建部署目录..."
    mkdir -p /opt/rocketchat
    cd /opt/rocketchat
}

# 创建docker-compose文件
create_docker_compose() {
    log "创建docker-compose配置文件..."
    
    cat > docker-compose.yml << 'DOCKEREOF'
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
      traefik.http.routers.rocketchat.rule: "Host(\`localhost\`)"
      traefik.http.routers.rocketchat.tls: "true"
      traefik.http.routers.rocketchat.entrypoints: "https"
      traefik.http.routers.rocketchat.tls.certresolver: "le"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

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
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  mongodb_data:
    driver: local
DOCKEREOF
}

# 启动服务
start_services() {
    log "启动Rocket.Chat服务..."
    docker-compose up -d
    
    log "等待服务启动..."
    sleep 30
    
    if docker-compose ps | grep -q "running"; then
        log "Rocket.Chat部署成功！"
        log "请通过 http://$(hostname -I | awk '{print $1}'):3000 访问"
        log "首次访问需要创建管理员账户"
    else
        error "服务启动失败，请检查日志"
        docker-compose logs
        exit 1
    fi
}

# 主函数
main() {
    log "开始Rocket.Chat一键部署..."
    
    check_os
    install_dependencies
    install_docker
    create_deployment_dir
    create_docker_compose
    start_services
    
    log "部署完成！"
}

# 执行主函数
main
EOF

# 添加执行权限
chmod +x rocket-deploy.sh

# 执行部署
./rocket-deploy.sh
```

## 4. 部署后配置

### 4.1 访问Rocket.Chat
部署完成后，通过浏览器访问：
```
http://your-server-ip:3000
```

### 4.2 初始配置
1. 注册管理员账户
2. 配置组织信息
3. 设置站点URL
4. 配置邮件服务器（可选）

### 4.3 配置反向代理（推荐）
```bash
# 安装Nginx
sudo apt install nginx -y  # Ubuntu/Debian
# 或
sudo yum install nginx -y   # CentOS/RHEL

# 创建Nginx配置
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

# 启用配置
sudo ln -s /etc/nginx/sites-available/rocketchat /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## 5. 管理命令

### 5.1 服务管理
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

### 5.2 数据备份
```bash
# 备份MongoDB数据
docker-compose exec mongodb mongodump --out /bitnami/mongodb/backup

# 复制备份到本地
docker cp rocketchat_mongodb_1:/bitnami/mongodb/backup ./backup
```

## 6. 故障排除

### 6.1 常见问题
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

### 6.2 性能优化
```bash
# 增加swap空间
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 7. 安全建议

### 7.1 防火墙配置
```bash
# Ubuntu/Debian (UFW)
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 3000
sudo ufw enable

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload
```

### 7.2 SSL证书配置
```bash
# 安装Certbot
sudo apt install certbot python3-certbot-nginx -y

# 获取SSL证书
sudo certbot --nginx -d your-domain.com
```

通过以上一键部署方案，您可以快速在Linux服务器上部署Rocket.Chat，并根据需要进行进一步的配置和优化。