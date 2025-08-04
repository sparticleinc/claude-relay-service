#!/bin/bash
# 自动构建和推送Docker镜像的脚本

set -euo pipefail

# 配置
DOCKER_USERNAME="gptbasesparticle"
IMAGE_NAME="${DOCKER_USERNAME}/claude-relay-service"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否已登录Docker Hub
check_docker_login() {
    if ! docker info 2>/dev/null | grep -q "Username: ${DOCKER_USERNAME}"; then
        print_warning "未登录Docker Hub，请先登录"
        echo "请使用以下命令登录："
        echo "docker login -u ${DOCKER_USERNAME}"
        exit 1
    fi
}

# 主函数
main() {
    # 获取版本参数
    VERSION="${1:-latest}"
    
    print_message "开始构建和推送Docker镜像"
    print_message "镜像名称: ${IMAGE_NAME}"
    print_message "版本标签: ${VERSION}"
    
    # 检查Docker登录状态
    check_docker_login
    
    # 确保在项目根目录
    if [ ! -f "package.json" ] || [ ! -f "Dockerfile" ]; then
        print_error "请在claude-relay-service项目根目录运行此脚本"
        exit 1
    fi
    
    # 获取git commit hash作为额外标签
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    print_message "Git commit: ${GIT_COMMIT}"
    
    # 构建镜像
    print_message "开始构建Docker镜像..."
    if docker build -t "${IMAGE_NAME}:${VERSION}" -t "${IMAGE_NAME}:${GIT_COMMIT}" .; then
        print_message "Docker镜像构建成功"
    else
        print_error "Docker镜像构建失败"
        exit 1
    fi
    
    # 如果版本不是latest，也打上latest标签
    if [ "$VERSION" != "latest" ]; then
        docker tag "${IMAGE_NAME}:${VERSION}" "${IMAGE_NAME}:latest"
        print_message "已添加latest标签"
    fi
    
    # 推送镜像
    print_message "开始推送镜像到Docker Hub..."
    
    # 推送所有标签
    for TAG in "${VERSION}" "${GIT_COMMIT}" "latest"; do
        print_message "推送标签: ${TAG}"
        if docker push "${IMAGE_NAME}:${TAG}"; then
            print_message "标签 ${TAG} 推送成功"
        else
            print_error "标签 ${TAG} 推送失败"
            exit 1
        fi
    done
    
    print_message "所有镜像推送完成！"
    echo ""
    echo "可以使用以下命令拉取镜像："
    echo "  docker pull ${IMAGE_NAME}:${VERSION}"
    echo "  docker pull ${IMAGE_NAME}:${GIT_COMMIT}"
    echo "  docker pull ${IMAGE_NAME}:latest"
}

# 显示使用说明
usage() {
    echo "使用方法: $0 [VERSION]"
    echo ""
    echo "参数:"
    echo "  VERSION    版本标签（默认: latest）"
    echo ""
    echo "示例:"
    echo "  $0          # 构建并推送latest版本"
    echo "  $0 v1.0.0   # 构建并推送v1.0.0版本"
}

# 检查参数
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

# 运行主函数
main "$@"