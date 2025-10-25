#!/bin/bash

# Rocket.Chat 2GB Memory Optimized Deployment Script
# This script deploys Rocket.Chat in monolith mode optimized for servers with only 2GB RAM

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "Cannot detect operating system"
        exit 1
    fi

    info "Detected OS: $OS $VER"

    if [[ $OS != *"Ubuntu"* && $OS != *"Debian"* ]]; then
        warn "This script is optimized for Ubuntu/Debian. You may encounter issues on other systems."
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."

    # Wait for any existing package manager locks to be released
    wait_for_package_manager

    if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
        apt update
    elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
        yum update -y
    else
        error "Unsupported operating system"
        exit 1
    fi
}

# Install required dependencies
install_dependencies() {
    log "Installing required dependencies..."

    # Wait for any existing package manager locks to be released
    wait_for_package_manager

    if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
        apt install -y curl wget gnupg apt-transport-https ca-certificates
    elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
        yum install -y curl wget gnupg
    fi
}

# Wait for package manager locks to be released
wait_for_package_manager() {
    local max_wait=300  # Maximum wait time in seconds (5 minutes)
    local wait_time=0
    local check_interval=10  # Check every 10 seconds

    log "Checking for package manager locks..."

    while [[ $wait_time -lt $max_wait ]]; do
        # Check for apt locks (Debian/Ubuntu)
        if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
            if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
               ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
               ! fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
                log "No package manager locks detected"
                return 0
            fi
        # Check for yum locks (CentOS/RHEL)
        elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
            if [[ ! -f /var/run/yum.pid ]] || ! kill -0 $(cat /var/run/yum.pid) 2>/dev/null; then
                log "No package manager locks detected"
                return 0
            fi
        fi

        log "Package manager lock detected, waiting ${check_interval}s... (${wait_time}s elapsed)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    error "Package manager lock timeout exceeded (${max_wait}s)"
    error "Please stop any ongoing package updates and try again"
    exit 1
}

# Install Docker with optimizations for low memory
install_docker() {
    log "Installing Docker..."

    if ! command -v docker &> /dev/null; then
        # Use convenience script for Docker installation
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl start docker
        systemctl enable docker
    else
        log "Docker is already installed"
    fi

    # Configure Docker daemon for low memory environments
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

    systemctl restart docker

    if ! command -v docker-compose &> /dev/null; then
        # Install Docker Compose
        curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        log "Docker Compose is already installed"
    fi
}

# Create deployment directory
create_deployment_dir() {
    log "Creating deployment directory..."
    mkdir -p /opt/rocketchat
    cd /opt/rocketchat
}

# Create optimized docker-compose.yml for 2GB RAM
create_docker_compose() {
    log "Creating optimized docker-compose.yml for 2GB RAM..."

    # Create MongoDB initialization script
    cat > mongo-init.js << 'EOF'
var status = rs.status();
if (status.ok === 0) {
  print('===== Initializing MongoDB Replica Set =====');
  rs.initiate({
    _id: 'rs0',
    members: [
      { _id: 0, host: 'mongodb:27017' }  // 使用服务名称而不是 localhost
    ]
  });

  // Wait for replica set initialization
  var attempts = 0;
  var maxAttempts = 30;
  while (attempts < maxAttempts) {
    try {
      var status = rs.status();
      if (status.ok === 1 && status.members && status.members.length > 0 && status.members[0].stateStr === 'PRIMARY') {
        print('===== Replica set initialized successfully =====');
        break;
      }
    } catch (err) {
      print('Replica set not ready yet, retrying... (' + (attempts + 1) + '/' + maxAttempts + ')');
    }
    sleep(2000);
    attempts++;
  }

  if (attempts >= maxAttempts) {
    print('===== Failed to initialize replica set =====');
    quit(1);
  }

  print('===== Creating rocketchat database =====');
  db = db.getSiblingDB('rocketchat');
  db.createUser({
    user: 'rocketchat',
    pwd: 'rocketchat',
    roles: [
      { role: 'readWrite', db: 'rocketchat' },
      { role: 'readWrite', db: 'local' }
    ]
  });

  print('===== MongoDB initialization completed =====');
} else {
  print('===== MongoDB Replica Set already initialized =====');
}
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  rocketchat:
    image: rocketchat/rocket.chat:latest
    restart: always
    environment:
      MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0"
      MONGO_OPLOG_URL: "mongodb://mongodb:27017/local?replicaSet=rs0"
      ROOT_URL: "http://localhost:3000"
      PORT: 3000
      TRANSPORTER: "monolith"
      MOLECULER_LOG_LEVEL: "warn"
      NODE_OPTIONS: "--max-old-space-size=1024"
      OVERWRITE_SETTING_Show_Setup_Wizard: "completed"
    depends_on:
      - mongodb
    ports:
      - "3000:3000"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    # Resource limits for low memory environments
    mem_limit: 1024m
    mem_reservation: 512m
    # CPU limits
    cpus: 0.5

  mongodb:
    image: mongo:6.0
    restart: always
    volumes:
      - mongodb_data:/data/db
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    command: [--replSet, rs0, --oplogSize, "128", --wiredTigerCacheSizeGB, "0.25"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    # Resource limits for low memory environments
    mem_limit: 512m
    mem_reservation: 256m
    # CPU limits
    cpus: 0.3

volumes:
  mongodb_data:
    driver: local
EOF
}

# Optimize system for low memory
optimize_system() {
    log "Optimizing system for low memory..."

    # Add swap space if less than 2GB
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $TOTAL_MEM -lt 2 ]]; then
        if ! swapon --show | grep -q swapfile; then
            log "Adding 1GB swap space..."
            fallocate -l 1G /swapfile
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        else
            log "Swap file already exists"
        fi
    fi

    # Configure kernel parameters for better memory management
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
    sysctl -p
}

# Start services
start_services() {
    log "Starting Rocket.Chat services..."
    docker-compose up -d

    log "Waiting for MongoDB to start (this may take 1-2 minutes)..."
    sleep 120

    log "Initializing MongoDB replica set..."
    # 等待 MongoDB 完全启动后再初始化副本集
    for i in {1..30}; do
        if docker-compose exec mongodb mongo --eval "print(\"MongoDB is ready\")" &>/dev/null; then
            log "MongoDB is ready, initializing replica set..."
            break
        fi
        log "Waiting for MongoDB to be ready... (${i}/30)"
        sleep 10
    done

    # 初始化副本集
    docker-compose exec mongodb mongo --eval "
        rs.initiate({
            _id: 'rs0',
            members: [
                { _id: 0, host: 'mongodb:27017' }
            ]
        });
    "

    log "Waiting for MongoDB replica set initialization (this may take 2-3 minutes)..."
    sleep 180

    if docker-compose ps | grep -q "running"; then
        log "Rocket.Chat deployment successful!"
        SERVER_IP=$(hostname -I | awk '{print $1}')
        log "You can access Rocket.Chat at: http://$SERVER_IP:3000"
        log "The first access will prompt you to create an admin account."
    else
        error "Service startup failed. Please check the logs:"
        docker-compose logs
        exit 1
    fi
}

# Display post-deployment information
show_post_deployment_info() {
    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo "=================================================="
    echo "    Rocket.Chat Deployment Complete (2GB RAM)     "
    echo "=================================================="
    echo ""
    echo "Access Information:"
    echo "  URL: http://$SERVER_IP:3000"
    echo ""
    echo "Management Commands:"
    echo "  Check status: docker-compose ps"
    echo "  View logs:    docker-compose logs -f"
    echo "  Stop:         docker-compose down"
    echo "  Restart:      docker-compose restart"
    echo "  Update:       docker-compose pull && docker-compose up -d"
    echo ""
    echo "Memory Optimization Notes:"
    echo "  - MongoDB cache limited to 256MB"
    echo "  - Rocket.Chat memory limited to 1GB"
    echo "  - Swap space added if needed"
    echo ""
    echo "Next Steps:"
    echo "  1. Open http://$SERVER_IP:3000 in your browser"
    echo "  2. Create your admin account"
    echo "  3. Configure your organization settings"
    echo ""
    echo "For security, consider:"
    echo "  1. Setting up a domain with SSL certificate"
    echo "  2. Configuring firewall rules"
    echo "  3. Changing the default port if needed"
    echo ""
    echo "=================================================="
}

# Main deployment function
main() {
    log "Starting Rocket.Chat deployment optimized for 2GB RAM..."

    check_root
    detect_os
    update_system
    install_dependencies
    install_docker
    create_deployment_dir
    create_docker_compose
    optimize_system
    start_services
    show_post_deployment_info

    log "Deployment completed successfully!"
}

# Execute main function
main
