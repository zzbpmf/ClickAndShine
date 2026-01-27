#!/usr/bin/env bash
# Sub-Store Auto Deploy Script (Dev/Fixed)
# Version: 3.3
# Fixes: Crontab crash on empty list, obsolete version warning

set -euo pipefail

# --- 配置 ---
readonly SERVICE_NAME="sub-store"
readonly PORT="3001"
readonly DATA_DIR="/opt/sub-store"
readonly WORK_DIR=$(pwd)

# --- 颜色 ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

install_docker_environment() {
    log_info "检查 Docker 环境..."

    if command -v docker &>/dev/null; then
        log_info "Docker 已安装，跳过安装步骤。"
    else
        log_info "未检测到 Docker，开始安装..."
        if ! curl -fsSL https://get.docker.com | bash; then
            log_error "Docker 自动安装失败。"
            log_warn "如使用 Ubuntu 20.04，请手动执行: apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
            exit 1
        fi
    fi

    systemctl enable docker &>/dev/null || true
    systemctl start docker &>/dev/null || true

    # 兼容性修复
    if ! command -v docker-compose &>/dev/null; then
        if docker compose version &>/dev/null; then
            echo 'docker compose "$@"' > /usr/bin/docker-compose
            chmod +x /usr/bin/docker-compose
        fi
    fi
}

get_public_ip() {
    local ips=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ident.me")
    for service in "${ips[@]}"; do
        local ip
        if ip=$(curl -sS --connect-timeout 5 "$service"); then
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$ip"
                return
            fi
        fi
    done
    ip route get 8.8.8.8 | awk '{print $7; exit}'
}

deploy_substore() {
    local public_ip=$(get_public_ip)
    
    # 16位密钥
    local secret_key=$(openssl rand -hex 8)

    log_info "准备部署目录: $DATA_DIR"
    mkdir -p "$DATA_DIR"

    log_info "清理旧服务..."
    docker-compose -p "$SERVICE_NAME" down 2>/dev/null || true
    docker rm -f "$SERVICE_NAME" 2>/dev/null || true

    log_info "生成配置文件..."
    # 移除了 obsolete 的 version 字段
    cat > docker-compose.yml << EOF
services:
  sub-store:
    image: xream/sub-store:latest
    container_name: ${SERVICE_NAME}
    restart: always
    environment:
      - SUB_STORE_BACKEND_UPLOAD_CRON=55 23 * * *
      - SUB_STORE_FRONTEND_BACKEND_PATH=/$secret_key
      - TZ=Asia/Shanghai
    ports:
      - "${PORT}:3001"
    volumes:
      - ${DATA_DIR}:/opt/app/data
EOF

    log_info "拉取镜像并启动..."
    docker-compose pull
    docker-compose up -d

    log_info "清理无用镜像..."
    docker image prune -f >/dev/null 2>&1

    # --- 关键修复: Crontab 设置 ---
    local current_script_dir=$(pwd)
    local update_cmd="0 4 * * * cd $current_script_dir && docker-compose pull && docker-compose up -d && docker image prune -f"
    
    if command -v crontab &>/dev/null; then
        # 增加 || true 防止因没有现有任务而报错退出
        (crontab -l 2>/dev/null || true; echo "$update_cmd") | grep -v "sub-store" | sort -u | crontab -
        log_info "已添加每日自动更新任务 (04:00 AM)"
    fi

    # 输出结果
    echo -e "\n${GREEN}==========================================${NC}"
    echo -e "   ✅ Sub-Store 部署成功"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "   面板地址: http://${public_ip}:${PORT}"
    echo -e "   后端地址: http://${public_ip}:${PORT}/${secret_key}"
    echo -e "   后端密钥: ${YELLOW}${secret_key}${NC} (16位)"
    echo -e "${GREEN}==========================================${NC}\n"
}

main() {
    check_root
    install_docker_environment
    deploy_substore
}

trap 'log_error "脚本执行出错，请检查上方日志"; exit 1' ERR

main
