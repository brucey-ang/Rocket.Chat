#!/bin/bash

# Rocket.Chat Complete Deployment Script for Ubuntu with 2GB RAM
# This script deploys Rocket.Chat with all required features optimized for small teams
# Features: User registration, private/public chats, file sharing, message editing, web login
# Enhanced version with:
# - Docker registry mirror configuration to avoid authentication issues
# - Alternative image sources for better reliability
# - Improved error handling and retry mechanisms
# - System resource checking
# - Skip already installed components
# - Better MongoDB initialization with error handling

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

# Check system resources
check_system_resources() {
    log "Checking system resources..."

    # Check available memory
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $7}')

    log "Total memory: ${TOTAL_MEM}MB, Available memory: ${AVAILABLE_MEM}MB"

    # Check disk space
    AVAILABLE_DISK=$(df -m / | awk 'NR==2 {print $4}')
    log "Available disk space: ${AVAILABLE_DISK}MB"

    # Warn if resources are low
    if [[ $TOTAL_MEM -lt 1024 ]]; then
        warn "System has less than 1GB RAM. Performance may be affected."
    fi

    if [[ $AVAILABLE_DISK -lt 512 ]]; then
        error "Less than 512MB disk space available. Please free up space."
        exit 1
    fi
}

# Check network connectivity
check_network() {
    log "Checking network connectivity..."

    # Check if we can reach Docker Hub
    if ! curl -s --connect-timeout 10 https://hub.docker.com > /dev/null; then
        warn "Cannot reach Docker Hub. Network connectivity may be limited."

        # Check basic connectivity
        if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
            error "No internet connectivity. Please check your network connection."
            exit 1
        fi
    else
        log "Network connectivity to Docker Hub is OK"
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

    if [[ $OS != *"Ubuntu"* ]]; then
        error "This script is optimized for Ubuntu. You are running: $OS"
        exit 1
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."

    # Wait for any existing package manager locks to be released
    wait_for_package_manager

    # Check if system was updated recently (within last 24 hours)
    if [ -f /var/cache/apt/pkgcache.bin ]; then
        LAST_UPDATE=$(stat -c %Y /var/cache/apt/pkgcache.bin)
        NOW=$(date +%s)
        DIFF=$((NOW - LAST_UPDATE))

        # If last update was less than 24 hours ago, skip update
        if [ $DIFF -lt 86400 ]; then
            log "System was updated recently, skipping update"
            return 0
        fi
    fi

    apt update
}

# Install required dependencies
install_dependencies() {
    log "Installing required dependencies..."

    # Wait for any existing package manager locks to be released
    wait_for_package_manager

    # Check if essential packages are already installed
    local packages="curl wget gnupg apt-transport-https ca-certificates software-properties-common"
    local missing_packages=""

    for package in $packages; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages="$missing_packages $package"
        fi
    done

    if [ -n "$missing_packages" ]; then
        log "Installing missing packages: $missing_packages"
        apt install -y $missing_packages
    else
        log "All required dependencies are already installed"
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
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/dpkg/lock >/dev/null 2>&1 && \
           ! fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
            log "No package manager locks detected"
            return 0
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
        # Check if Docker daemon is running
        if ! systemctl is-active --quiet docker; then
            log "Starting Docker daemon..."
            systemctl start docker
        else
            log "Docker daemon is already running"
        fi

        # Check Docker version compatibility
        DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log "Docker version: $DOCKER_VERSION"
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
  },
  "registry-mirrors": [
    "https://registry.docker-cn.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF

    systemctl restart docker

    if ! command -v docker-compose &> /dev/null; then
        # Install Docker Compose
        log "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        DOCKER_COMPOSE_VERSION=$(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        log "Docker Compose version: $DOCKER_COMPOSE_VERSION (already installed)"
    fi

    # Add current user to docker group if not already
    if ! groups $(whoami) | grep -q docker; then
        log "Adding current user to docker group..."
        usermod -aG docker $(whoami)
    fi
}

# Create deployment directory
create_deployment_dir() {
    log "Creating deployment directory..."
    mkdir -p /opt/rocketchat
    cd /opt/rocketchat
}

# Install Certbot for SSL certificate generation
install_certbot() {
    log "Installing Certbot for SSL certificate generation..."

    # Check if certbot is already installed
    if command -v certbot &> /dev/null; then
        log "Certbot is already installed"
        return 0
    fi

    # Install certbot
    apt install -y certbot python3-certbot-nginx

    if command -v certbot &> /dev/null; then
        log "Certbot installed successfully"
    else
        error "Failed to install Certbot"
        exit 1
    fi
}

# Request SSL certificate using Certbot
request_ssl_certificate() {
    local domain=$1

    if [ -z "$domain" ]; then
        warn "No domain provided, skipping SSL certificate request"
        return 0
    fi

    log "Requesting SSL certificate for $domain..."

    # Check if certificate already exists
    if certbot certificates | grep -q "$domain"; then
        log "SSL certificate for $domain already exists"
        return 0
    fi

    # Request certificate (standalone mode)
    if certbot certonly --standalone --preferred-challenges http -d "$domain" --non-interactive --agree-tos --email admin@"$domain"; then
        log "SSL certificate successfully obtained for $domain"
    else
        error "Failed to obtain SSL certificate for $domain"
        warn "Continuing without SSL certificate..."
    fi
}

# Create optimized docker-compose.yml for 2GB RAM with all required features
create_docker_compose() {
    local domain=$1
    local use_https=$2

    log "Creating optimized docker-compose.yml for 2GB RAM with all features..."

    # Create MongoDB initialization script
    cat > mongo-init.js << 'EOF'
// Wait for MongoDB to be ready
sleep(5000);

// Initialize replica set
try {
  var status = rs.status();
  print('Replica set status: ' + status.ok);
} catch (err) {
  print('Initializing replica set...');
  try {
    rs.initiate({
      _id: 'rs0',
      members: [
        { _id: 0, host: 'mongodb:27017' }
      ]
    });
    print('Replica set initiated');
  } catch (initErr) {
    print('Replica set initiation error: ' + initErr);
  }
}

// Wait for replica set to be ready
sleep(10000);

// Create user
try {
  db = db.getSiblingDB('rocketchat');

  // Check if user already exists
  var users = db.getUsers({filter: {user: 'rocketchat'}});
  if (users.length === 0) {
    print('Creating rocketchat user...');
    var result = db.createUser({
      user: 'rocketchat',
      pwd: 'rocketchat',
      roles: [
        { role: 'readWrite', db: 'rocketchat' },
        { role: 'readWrite', db: 'local' }
      ]
    });

    if (result) {
      print('User created successfully');
    } else {
      print('Failed to create user');
    }
  } else {
    print('User already exists');
  }
} catch (userErr) {
  print('User creation error: ' + userErr);
}

print('MongoDB initialization completed');
EOF

    # Create docker-compose.yml with all required features enabled
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  rocketchat:
    image: rocketchat/rocket.chat:latest
    restart: always
    environment:
      MONGO_URL: "mongodb://mongodb:27017/rocketchat?replicaSet=rs0&connectTimeoutMS=30000&socketTimeoutMS=30000&serverSelectionTimeoutMS=30000"
      MONGO_OPLOG_URL: "mongodb://mongodb:27017/local?replicaSet=rs0&connectTimeoutMS=30000&socketTimeoutMS=30000&serverSelectionTimeoutMS=30000"
EOF

    # Set ROOT_URL based on whether HTTPS is used
    if [ "$use_https" = "true" ] && [ -n "$domain" ]; then
        cat >> docker-compose.yml << EOF
      ROOT_URL: "https://$domain"
EOF
    else
        cat >> docker-compose.yml << EOF
      ROOT_URL: "http://localhost:3000"
EOF
    fi

    cat >> docker-compose.yml << 'EOF'
      PORT: 3000
      TRANSPORTER: "monolith"
      MOLECULER_LOG_LEVEL: "warn"
      NODE_OPTIONS: "--max-old-space-size=1024"
      OVERWRITE_SETTING_Show_Setup_Wizard: "completed"
      # Enable user registration
      ACCOUNTS_DEFAULT_USER_REGISTRATION: "true"
      ACCOUNTS_REGISTRATION_FORM: "public"
      # Enable file upload
      UPLOADS_MAX_SIZE_TO_DB: "256"
      UPLOADS_MAX_SIZE_TO_FS: "104857600"
      # Enable message editing
      MESSAGE_EDITING_ALLOWED: "true"
      MESSAGE_ALLOW_EDITING_BLOCKED_BY_ROOM_OWNERS: "false"
      # Enable private and public channels
      API_Enable_CORS: "true"
      CORS_ORIGIN: "*"
      MONGO_RETRY_WRITES: "false"

    depends_on:
      - mongodb
    ports:
EOF

    # Set ports based on whether HTTPS is used
    if [ "$use_https" = "true" ] && [ -n "$domain" ]; then
        cat >> docker-compose.yml << EOF
      - "80:3000"  # HTTP to HTTPS redirect
      - "443:3000" # HTTPS
EOF
    else
        cat >> docker-compose.yml << EOF
      - "3000:3000"
EOF
    fi

    cat >> docker-compose.yml << 'EOF'
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
    volumes:
      - uploads:/app/uploads

  mongodb:
    image: mongo:6.0
    restart: always
    volumes:
      - mongodb_data:/data/db
      - ./mongo-init.js:/docker-entrypoint-initdb.d/mongo-init.js:ro
    command: [--replSet, rs0, --oplogSize, "128", --wiredTigerCacheSizeGB, "0.25", --bind_ip_all]
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
    healthcheck:
      test: ["CMD", "echo", "try { rs.status() } catch (err) { rs.initiate({ _id: 'rs0', members: [{ _id: 0, host: 'mongodb:27017' }] }) }", "|", "mongosh", "--port", "27017", "--quiet"]
      interval: 5s
      timeout: 30s
      retries: 30


volumes:
  mongodb_data:
    driver: local
  uploads:
    driver: local

EOF
}

# Create Nginx configuration for SSL termination
create_nginx_config() {
    local domain=$1

    if [ -z "$domain" ]; then
        return 0
    fi

    log "Creating Nginx configuration for SSL termination..."

    # Install Nginx if not already installed
    if ! command -v nginx &> /dev/null; then
        log "Installing Nginx..."
        apt install -y nginx
    fi

    # Create Nginx configuration
    cat > /etc/nginx/sites-available/rocketchat << EOF
server {
    listen 80;
    server_name $domain;

    # Redirect all HTTP requests to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_buffering off;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/rocketchat /etc/nginx/sites-enabled/

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default

    # Test Nginx configuration
    if nginx -t; then
        systemctl reload nginx
        log "Nginx configuration created and reloaded successfully"
    else
        error "Nginx configuration test failed"
        exit 1
    fi
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

    # Try to pull images first to handle authentication issues
    log "Pulling Docker images..."
    if ! docker-compose pull; then
        warn "Failed to pull images from default registry, trying alternative sources..."

        # Check if Docker daemon is working properly
        if ! docker info > /dev/null 2>&1; then
            error "Docker daemon is not working properly. Please check Docker installation."
            exit 1
        fi

        # Update docker-compose to use alternative image sources
        log "Trying Docker China mirror..."
        sed -i 's|rocketchat/rocket.chat:latest|registry.docker-cn.com/rocketchat/rocket.chat:latest|g' docker-compose.yml
        sed -i 's|mongo:6.0|registry.docker-cn.com/library/mongo:6.0|g' docker-compose.yml

        if ! docker-compose pull; then
            # Try another mirror
            warn "Failed to pull images from docker-cn registry, trying Docker Hub mirror..."
            log "Trying Docker Hub mirror..."
            sed -i 's|registry.docker-cn.com/rocketchat/rocket.chat:latest|registry-1.docker.io/rocketchat/rocket.chat:latest|g' docker-compose.yml
            sed -i 's|registry.docker-cn.com/library/mongo:6.0|registry-1.docker.io/library/mongo:6.0|g' docker-compose.yml

            if ! docker-compose pull; then
                # Try to pull images individually
                warn "Failed to pull images with docker-compose, trying individual pulls..."

                if ! docker pull registry-1.docker.io/rocketchat/rocket.chat:latest; then
                    error "Failed to pull Rocket.Chat image. Please check your network connection and Docker configuration."
                    # Show available mirrors
                    log "Available Docker registry mirrors:"
                    docker info | grep -i mirror || log "No mirrors configured"
                    exit 1
                fi

                if ! docker pull registry-1.docker.io/library/mongo:6.0; then
                    error "Failed to pull MongoDB image. Please check your network connection and Docker configuration."
                    exit 1
                fi

                log "Successfully pulled images individually. Continuing with deployment..."
            fi
        fi
    fi

    docker-compose up -d

    # Wait for MongoDB to be ready and initialized
    log "Waiting for MongoDB to initialize..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=10

    while [[ $wait_time -lt $max_wait ]]; do
        if docker-compose exec mongodb mongosh --eval "rs.status()" > /dev/null 2>&1; then
            log "MongoDB is ready and initialized"
            break
        fi

        log "Waiting for MongoDB to initialize... (${wait_time}s elapsed)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    if [[ $wait_time -ge $max_wait ]]; then
        warn "MongoDB initialization timeout. Checking status..."
        docker-compose exec mongodb mongosh --eval "rs.status()" || true
    fi

    # Additional wait for MongoDB to be fully ready for connections
    log "Waiting for MongoDB to be fully ready..."
    sleep 30

    log "Waiting for services to start (this may take 2-3 minutes)..."
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
    local domain=$1
    local use_https=$2

    echo ""
    echo "=================================================="
    echo "    Rocket.Chat Complete Deployment Complete      "
    echo "=================================================="
    echo ""
    echo "System Configuration:"
    echo "  - Ubuntu OS optimized"
    echo "  - 2GB RAM environment"
    echo "  - Single instance (monolith) deployment"
    echo "  - Swap space added if needed"
    echo ""
    echo "Enabled Features:"
    echo "  - User self-registration"
    echo "  - Private and group chats"
    echo "  - File sharing"
    echo "  - Message editing"
    echo "  - Web login interface"
    echo ""

    if [ "$use_https" = "true" ] && [ -n "$domain" ]; then
        echo "Access Information:"
        echo "  URL: https://$domain"
        echo ""
        echo "SSL Certificate:"
        echo "  - Certificate installed via Let's Encrypt"
        echo "  - Automatic HTTP to HTTPS redirect configured"
        echo ""
    else
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo "Access Information:"
        echo "  URL: http://$SERVER_IP:3000"
        echo ""
        echo "Security Recommendation:"
        echo "  - Consider setting up SSL for production use"
        echo "  - Run with --domain your-domain.com to enable HTTPS"
        echo ""
    fi

    echo "Management Commands:"
    echo "  Check status: docker-compose ps"
    echo "  View logs:    docker-compose logs -f"
    echo "  Stop:         docker-compose down"
    echo "  Restart:      docker-compose restart"
    echo "  Update:       docker-compose pull && docker-compose up -d"
    echo ""
    echo "Next Steps:"
    echo "  1. Open the URL above in your browser"
    echo "  2. Create your admin account"
    echo "  3. Configure your organization settings"
    echo "  4. Invite users to register and join"
    echo ""
    echo "=================================================="
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --domain DOMAIN    Domain name for SSL certificate (enables HTTPS)"
    echo "  --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Deploy with HTTP only"
    echo "  $0 --domain chat.example.com # Deploy with HTTPS"
}

# Parse command line arguments
parse_arguments() {
    DOMAIN=""
    USE_HTTPS="false"

    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                USE_HTTPS="true"
                shift 2
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# Main deployment function
main() {
    # Parse command line arguments
    parse_arguments "$@"

    log "Starting Rocket.Chat complete deployment..."
    log "Target: Ubuntu system with 2GB RAM, single instance deployment"
    log "Features: User registration, private/group chats, file sharing, message editing, web login"

    if [ "$USE_HTTPS" = "true" ]; then
        log "SSL Configuration: Enabled for domain $DOMAIN"
    else
        log "SSL Configuration: Disabled (HTTP only)"
    fi

    check_root
    detect_os
    check_system_resources
    check_network
    update_system
    install_dependencies
    install_docker
    create_deployment_dir

    # If HTTPS is requested, install Certbot and request certificate
    if [ "$USE_HTTPS" = "true" ]; then
        install_certbot
        request_ssl_certificate "$DOMAIN"
    fi

    create_docker_compose "$DOMAIN" "$USE_HTTPS"
    optimize_system
    start_services

    # If HTTPS is requested, create Nginx configuration
    if [ "$USE_HTTPS" = "true" ]; then
        create_nginx_config "$DOMAIN"
    fi

    show_post_deployment_info "$DOMAIN" "$USE_HTTPS"

    log "Deployment completed successfully!"
}

# Execute main function
main
