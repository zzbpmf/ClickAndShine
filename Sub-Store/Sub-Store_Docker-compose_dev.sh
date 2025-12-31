#!/usr/bin/env bash

# Sub-Store Auto Deploy Script - Professional Version (Fixed & Optimized)
# Version: 3.1
# Fixes: Fixed syntax errors, adjusted key length to 8 chars

set -euo pipefail

# --- 配置常量 ---
readonly SERVICE_NAME="sub-store"
readonly SERVICE_PORT="3001"
readonly DATA_DIR="/opt/sub-store"
readonly CONFIG_DIR="/etc/sub-store"
readonly LOG_DIR="/var/log/sub-store"
readonly COMPOSE_FILE="$CONFIG_DIR/docker-compose.yml"
readonly ENV_FILE="$CONFIG_DIR/.env"

# --- 颜色定义 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. 检查环境 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本 (sudo -i)"
        exit 1
    fi
}

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" =~ (debian|ubuntu|centos|rhel|fedora|rocky|almalinux) ]]; then
            log_success "系统检测通过: $PRETTY_NAME"
        else
            log_warn "未测试的系统: $PRETTY_NAME，尝试继续..."
        fi
    else
        log_error "无法识别操作系统"
        exit 1
    fi
}

# --- 2. 安装 Docker ---
install_docker() {
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then
        log_success "Docker 及 Compose 已安装"
        return
    fi

    log_info "正在安装 Docker..."
    if ! curl -fsSL https://get.docker.com | bash; then
        log_error "Docker 安装失败"
        exit 1
    fi
    log_success "Docker 安装完成"
}

# --- 3. 获取 IP ---
get_public_ip() {
    local ips=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ident.me")
    for service in "${ips[@]}"; do
        local ip
        ip=$(curl -sS --connect-timeout 5 "$service")
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return
        fi
    done
    # 获取失败则尝试获取本机局域网IP
    ip route get 8.8.8.8 | awk '{print $7; exit}'
}

# --- 4. 生成 16位 短密钥 ---
generate_secret_key() {
   
    openssl rand -hex 8
}

# --- 5. 核心部署逻辑 ---
deploy_service() {
    local public_ip=$(get_public_ip)
    local secret_key=$(generate_secret_key)

    log_info "准备部署环境..."
    mkdir -p "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR"

    # 清理旧容器
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
    docker rm -f sub-store 2>/dev/null || true

    # 创建 .env
    log_info "生成配置文件..."
    cat > "$ENV_FILE" << EOF
SUB_STORE_PORT=$SERVICE_PORT
SUB_STORE_SECRET_KEY=$secret_key
SUB_STORE_DATA_DIR=$DATA_DIR
SUB_STORE_LOG_DIR=$LOG_DIR
# 每天自动上传时间 (Cron)
SUB_STORE_BACKEND_UPLOAD_CRON=55 23 * * *
EOF

    # 创建 docker-compose.yml
    cat > "$COMPOSE_FILE" << EOF
services:
  sub-store:
    image: xream/sub-store:latest
    container_name: ${SERVICE_NAME}
    restart: unless-stopped
    environment:
      - SUB_STORE_BACKEND_UPLOAD_CRON=\${SUB_STORE_BACKEND_UPLOAD_CRON}
      - SUB_STORE_FRONTEND_BACKEND_PATH=/$secret_key
      - TZ=Asia/Shanghai
    ports:
      - "\${SUB_STORE_PORT}:3001"
    volumes:
      - \${SUB_STORE_DATA_DIR}:/opt/app/data
      - \${SUB_STORE_LOG_DIR}:/opt/app/logs
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

    log_info "启动服务..."
    if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
        log_success "容器启动成功"
    else
        log_error "容器启动失败"
        exit 1
    fi
    
    # 清理垃圾镜像
    docker image prune -f >/dev/null 2>&1

    # --- 设置自动更新 (每周日凌晨3点) ---
    local update_script="/usr/local/bin/sub-store-update.sh"
    cat > "$update_script" << EOF
#!/bin/bash
cd $CONFIG_DIR
docker compose pull
docker compose up -d
docker image prune -f
EOF
    chmod +x "$update_script"
    
    # 写入 Crontab
    (crontab -l 2>/dev/null | grep -v "sub-store-update"; echo "0 3 * * 0 $update_script") | crontab -
    log_success "自动更新已设置 (每周日 03:00)"

    # --- 写入卸载脚本 ---
    local uninstall_script="/usr/local/bin/sub-store-uninstall.sh"
    cat > "$uninstall_script" << EOF
#!/bin/bash
read -p "确定要卸载 Sub-Store 并删除所有数据吗? [y/N] " -n 1 -r
echo
if [[ \$REPLY =~ ^[Yy]$ ]]; then
    docker compose -f $COMPOSE_FILE down
    rm -rf $DATA_DIR $CONFIG_DIR $LOG_DIR
    rm /usr/local/bin/sub-store-update.sh
    rm /usr/local/bin/sub-store-uninstall.sh
    (crontab -l | grep -v "sub-store-update") | crontab -
    echo "卸载完成。"
fi
EOF
    chmod +x "$uninstall_script"

    # --- 结束输出 ---
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "   🎉 Sub-Store 部署成功 (专业版) "
    echo -e "${GREEN}==========================================${NC}"
    echo -e "   面板地址: http://${public_ip}:${SERVICE_PORT}"
    echo -e "   后端地址: http://${public_ip}:${SERVICE_PORT}/${secret_key}"
    echo -e "   后台密钥: ${YELLOW}${secret_key}${NC} (8位)"
    echo -e "------------------------------------------"
    echo -e "   配置文件: $CONFIG_DIR"
    echo -e "   数据目录: $DATA_DIR"
    echo -e "   卸载命令: sub-store-uninstall.sh"
    echo -e "${GREEN}==========================================${NC}\n"
}

main() {
    check_root
    check_os
    install_docker
    deploy_service
}

main
