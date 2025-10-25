# 针对您服务器的 Rocket.Chat 部署脚本

## 服务器信息
- 公网IP: 123.206.104.25
- 用户名: root
- 密码: lhkp-bdt05f64 (请在首次登录后立即更改)

## 部署前安全建议

### 1. 立即更改密码
首次登录后，请立即更改root密码：
```bash
passwd
```

### 2. 创建非root用户(推荐)
```bash
adduser rocket
usermod -aG sudo rocket
```

### 3. 配置SSH安全设置
编辑SSH配置文件：
```bash
nano /etc/ssh/sshd_config
```

修改以下设置：
```
Port 22  # 可以更改为其他端口以增加安全性
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
```

重启SSH服务：
```bash
systemctl restart sshd
```

## 部署步骤

### 1. 连接到服务器
```bash
ssh root@123.206.104.25
```

### 2. 更新系统
```bash
apt update && apt upgrade -y
```

### 3. 安装必要工具
```bash
apt install apt-transport-https ca-certificates curl gnupg lsb-release -y
```

### 4. 安装Docker
```bash
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

### 5. 安装Docker Compose
```bash
# 下载Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 添加执行权限
chmod +x /usr/local/bin/docker-compose

# 创建软链接
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
```

### 6. 创建Rocket.Chat部署目录
```bash
mkdir -p /opt/rocketchat
cd /opt/rocketchat
```

### 7. 创建docker-compose.yml文件
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
      ROOT_URL: "http://123.206.104.25:3000"
      PORT: 3000
    depends_on:
      - mongodb
    ports:
      - "3000:3000"
    labels:
      traefik.enable: "true"
      traefik.http.routers.rocketchat.rule: "Host(`123.206.104.25`)"
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

### 8. 启动服务
```bash
docker-compose up -d
```

### 9. 检查服务状态
```bash
docker-compose ps
```

### 10. 查看日志
```bash
docker-compose logs -f
```

## 访问Rocket.Chat

服务启动后，您可以通过以下URL访问Rocket.Chat：
```
http://123.206.104.25:3000
```

## 后续配置建议

### 1. 配置防火墙
```bash
ufw allow 22
ufw allow 3000
ufw enable
```

### 2. 配置SSL证书(推荐)
安装Certbot：
```bash
apt install certbot python3-certbot-nginx -y
```

获取SSL证书：
```bash
certbot --nginx -d your-domain.com
```

### 3. 配置Nginx反向代理
安装Nginx：
```bash
apt install nginx -y
```

创建Nginx配置：
```bash
cat > /etc/nginx/sites-available/rocketchat << 'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name 123.206.104.25;
    
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

启用配置：
```bash
ln -s /etc/nginx/sites-available/rocketchat /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx
```

## 管理命令

### 查看运行状态
```bash
docker-compose ps
```

### 查看日志
```bash
docker-compose logs -f
```

### 停止服务
```bash
docker-compose down
```

### 更新服务
```bash
docker-compose pull
docker-compose up -d
```

### 备份数据
```bash
docker-compose exec mongodb mongodump --out /bitnami/mongodb/backup
```

## 故障排除

### 1. 服务无法启动
检查Docker服务：
```bash
systemctl status docker
```

查看容器日志：
```bash
docker-compose logs
```

### 2. 端口被占用
检查端口占用情况：
```bash
netstat -tlnp | grep 3000
```

### 3. 内存不足
检查内存使用情况：
```bash
free -h
```

如有必要，添加swap空间：
```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## 安全建议

1. 定期更新系统和Docker镜像
2. 使用强密码策略
3. 配置防火墙规则
4. 启用SSL/TLS加密
5. 定期备份重要数据
6. 限制root用户直接访问
7. 使用SSH密钥认证而非密码认证

通过按照以上步骤操作，您应该能够成功在您的腾讯云服务器上部署Rocket.Chat。