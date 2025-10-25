#!/bin/bash

# Rocket.Chat Tencent Cloud One-Click Deployment Script
# This script automatically deploys Rocket.Chat on Tencent Cloud servers

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
    
    if [[ $OS == *"Ubuntu"* ]] || [[ $OS == *"Debian"* ]]; then
        apt install -y curl wget gnupg apt-transport-https ca-certificates
    elif [[ $OS == *"CentOS"* ]] || [[ $OS == *"Red Hat"* ]]; then
        yum install -y curl wget gnupg
    fi
}

# Install Docker
install_docker() {
    log "Installing Docker..."
    
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | bash -s docker
        systemctl start docker
        systemctl enable docker
    else
        log "Docker is already installed"
    fi
    
    if ! command -v docker-compose &> /dev/null; then
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

# Create docker-compose.yml
create_docker_compose() {
    log "Creating docker-compose.yml..."
    
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
EOF
}

# Start services
start_services() {
    log "Starting Rocket.Chat services..."
    docker-compose up -d
    
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
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo "=================================================="
    echo "           Rocket.Chat Deployment Complete        "
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
    log "Starting Rocket.Chat one-click deployment for Tencent Cloud..."
    
    check_root
    detect_os
    update_system
    install_dependencies
    install_docker
    create_deployment_dir
    create_docker_compose
    start_services
    show_post_deployment_info
    
    log "Deployment completed successfully!"
}

# Execute main function
main