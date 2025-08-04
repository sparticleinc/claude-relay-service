#!/bin/bash
# EC2部署脚本 - 用于在EC2服务器上更新Claude Relay Service

set -euo pipefail

# 配置
DOCKER_USERNAME="gptbasesparticle"
IMAGE_NAME="${DOCKER_USERNAME}/claude-relay-service"
DEPLOYMENT_DIR="$HOME/claude-relay-deployment"

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查部署目录
check_deployment() {
    if [ ! -d "$DEPLOYMENT_DIR" ]; then
        print_error "部署目录不存在: $DEPLOYMENT_DIR"
        print_error "请先完成初始部署"
        exit 1
    fi
    
    if [ ! -f "$DEPLOYMENT_DIR/docker-compose.yml" ]; then
        print_error "docker-compose.yml 文件不存在"
        exit 1
    fi
    
    if [ ! -f "$DEPLOYMENT_DIR/.env" ]; then
        print_error ".env 配置文件不存在"
        exit 1
    fi
}

# 备份当前数据
backup_data() {
    print_message "备份当前数据..."
    
    BACKUP_DIR="$HOME/backups"
    mkdir -p "$BACKUP_DIR"
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/claude-relay-backup-${TIMESTAMP}.tar.gz"
    
    cd "$DEPLOYMENT_DIR"
    tar -czf "$BACKUP_FILE" .env data/ logs/ redis_data/ 2>/dev/null || true
    
    print_message "备份完成: $BACKUP_FILE"
    
    # 清理旧备份（保留最近7个）
    ls -t "$BACKUP_DIR"/claude-relay-backup-*.tar.gz | tail -n +8 | xargs -r rm
}

# 更新服务
update_service() {
    VERSION="${1:-latest}"
    
    print_message "准备更新到版本: $VERSION"
    
    cd "$DEPLOYMENT_DIR"
    
    # 拉取新镜像
    print_message "拉取最新镜像..."
    if ! docker-compose pull; then
        print_error "拉取镜像失败"
        exit 1
    fi
    
    # 停止当前服务
    print_message "停止当前服务..."
    docker-compose down
    
    # 启动新版本
    print_message "启动新版本..."
    if ! docker-compose up -d; then
        print_error "启动服务失败"
        print_warning "尝试回滚..."
        docker-compose up -d
        exit 1
    fi
    
    # 等待服务启动
    print_message "等待服务启动..."
    sleep 10
    
    # 健康检查
    print_message "执行健康检查..."
    if curl -f -s http://localhost:3000/health > /dev/null; then
        print_message "服务健康检查通过"
    else
        print_error "服务健康检查失败"
        print_warning "查看日志以了解详情: docker-compose logs"
        exit 1
    fi
    
    # 清理旧镜像
    print_message "清理旧镜像..."
    docker image prune -f
    
    print_message "服务更新成功！"
}

# 查看服务状态
check_status() {
    cd "$DEPLOYMENT_DIR"
    
    print_message "服务状态:"
    docker-compose ps
    
    echo ""
    print_message "最近日志:"
    docker-compose logs --tail=20
}

# 主函数
main() {
    case "${1:-update}" in
        update)
            check_deployment
            backup_data
            update_service "${2:-latest}"
            ;;
        backup)
            check_deployment
            backup_data
            ;;
        status)
            check_deployment
            check_status
            ;;
        logs)
            check_deployment
            cd "$DEPLOYMENT_DIR"
            docker-compose logs -f "${@:2}"
            ;;
        *)
            usage
            ;;
    esac
}

# 使用说明
usage() {
    echo "Claude Relay Service EC2部署脚本"
    echo ""
    echo "使用方法: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "命令:"
    echo "  update [VERSION]  更新服务（默认: latest）"
    echo "  backup           仅备份数据"
    echo "  status           查看服务状态"
    echo "  logs [SERVICE]   查看日志"
    echo ""
    echo "示例:"
    echo "  $0 update        # 更新到最新版本"
    echo "  $0 update v1.0.0 # 更新到指定版本"
    echo "  $0 backup        # 备份当前数据"
    echo "  $0 status        # 查看状态"
    echo "  $0 logs app      # 查看app服务日志"
}

# 运行主函数
main "$@"