#!/bin/bash
set -e

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载环境变量文件
ENV_FILE="$SCRIPT_DIR/.env.local"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# 日志文件（在项目目录的 logs 子目录）
mkdir -p logs
LOG_FILE="$SCRIPT_DIR/logs/auto-update.log"
LOCK_FILE="/tmp/claude-relay-update.lock"

# 创建日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查锁文件，避免重复运行
if [ -f "$LOCK_FILE" ]; then
    log "更新脚本已在运行，退出"
    exit 0
fi

# 创建锁文件
touch "$LOCK_FILE"

# 清理函数
cleanup() {
    rm -f "$LOCK_FILE"
}

# 设置退出时清理
trap cleanup EXIT

log "===== 开始自动更新检查 ====="

# 检查环境变量是否加载
if [ -f "$ENV_FILE" ]; then
    log "已加载环境变量文件: $ENV_FILE"
else
    log "警告：未找到环境变量文件: $ENV_FILE"
fi

# 验证必需的环境变量
if [ -n "$DOCKER_HUB_USERNAME" ] && [ -n "$DOCKER_HUB_TOKEN" ]; then
    log "Docker Hub 认证信息已配置"
else
    log "警告：Docker Hub 认证信息未配置"
fi

# 设置 git 配置以避免交互提示
export GIT_MERGE_AUTOEDIT=no

# 1. 获取上游更新
log "获取上游更新..."
git fetch upstream --quiet

# 检查是否有新的提交
UPDATES=$(git rev-list main..upstream/main --count)
if [ "$UPDATES" -eq 0 ]; then
    log "没有新的更新，退出"
    exit 0
fi

log "发现 $UPDATES 个新提交"

# 显示更新内容
log "更新内容："
git log --oneline main..upstream/main | head -5 >> "$LOG_FILE"

# 2. 检查并处理VERSION文件冲突
log "检查VERSION文件冲突..."
if [ -f "VERSION" ] && git diff --name-only main upstream/main | grep -q "VERSION"; then
    log "检测到VERSION文件存在冲突，优先使用上游版本"
    # 强制使用上游的VERSION文件
    git checkout upstream/main -- VERSION
    git add VERSION
    git commit -m "chore: sync VERSION file with upstream [skip ci]" --no-edit
    log "已采用上游VERSION文件: $(cat VERSION)"
fi

# 3. 合并更新
log "合并上游更新..."
# 使用 --no-ff 确保创建合并提交，--no-edit 使用默认消息
# 使用 -X theirs 策略，在有冲突时优先使用上游版本
git merge upstream/main -X theirs -m "auto: 同步上游版本更新" --no-edit --no-ff

# 4. 获取版本号
VERSION=$(cat VERSION)
log "当前版本: $VERSION"

# 5. 构建镜像
log "构建 Docker 镜像..."
podman build -t gptbasesparticle/claude-relay-service:v$VERSION -t gptbasesparticle/claude-relay-service:latest . >> "$LOG_FILE" 2>&1

# 6. 推送到 Docker Hub
log "推送镜像到 Docker Hub..."
# 确保已登录
if ! podman login --get-login docker.io >/dev/null 2>&1; then
    # 检查环境变量
    if [ -z "$DOCKER_HUB_TOKEN" ] || [ -z "$DOCKER_HUB_USERNAME" ]; then
        log "错误：未设置 DOCKER_HUB_TOKEN 或 DOCKER_HUB_USERNAME 环境变量"
        log "请设置环境变量后重试："
        log "  export DOCKER_HUB_USERNAME=your-username"
        log "  export DOCKER_HUB_TOKEN=your-token"
        exit 1
    fi
    
    log "使用环境变量登录 Docker Hub..."
    echo "$DOCKER_HUB_TOKEN" | podman login docker.io -u "$DOCKER_HUB_USERNAME" --password-stdin >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        log "错误：Docker Hub 登录失败"
        exit 1
    fi
fi

podman push gptbasesparticle/claude-relay-service:v$VERSION >> "$LOG_FILE" 2>&1
podman push gptbasesparticle/claude-relay-service:latest >> "$LOG_FILE" 2>&1

# 7. 部署到服务器
log "部署到服务器..."
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no ubuntu@cc-relay.gbase.ai << 'EOF' >> "$LOG_FILE" 2>&1
    cd ~/claude-relay-deployment
    sudo docker-compose pull
    sudo docker-compose down
    sudo docker-compose up -d
    sudo docker-compose ps
EOF

# 8. 验证部署
log "验证部署..."
sleep 15
DEPLOYED_VERSION=$(curl -s https://cc-relay.gbase.ai/health | jq -r '.version')
if [ "$DEPLOYED_VERSION" == "$VERSION" ]; then
    log "✅ 部署成功！当前运行版本: $DEPLOYED_VERSION"
else
    log "❌ 部署可能失败！期望版本: $VERSION, 实际版本: $DEPLOYED_VERSION"
    exit 1
fi

# 9. 推送到公司仓库
log "推送到公司仓库..."
git push origin main >> "$LOG_FILE" 2>&1

log "✨ 更新完成！"
log "===== 更新结束 ====="
log ""