#!/bin/bash

# 获取当前脚本的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/auto-update-service.sh"
ENV_FILE="$SCRIPT_DIR/.env.local"

echo "设置自动更新任务..."
echo ""

# 检查环境变量文件是否存在
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  警告：未找到 .env.local 文件"
    echo "请创建 .env.local 文件并设置以下变量："
    echo "  DOCKER_HUB_USERNAME=your-username"
    echo "  DOCKER_HUB_TOKEN=your-token"
    echo ""
fi

echo "将添加以下 crontab 任务："
echo "22 10 * * * source $ENV_FILE && $SCRIPT_PATH"
echo ""
echo "这将在每天早上 10:22 运行自动更新检查"
echo ""

# 获取现有的 crontab（如果有）
crontab -l > /tmp/current_cron 2>/dev/null || true

# 检查是否已经存在该任务
if grep -q "auto-update-service.sh" /tmp/current_cron; then
    echo "⚠️  自动更新任务已存在，跳过添加"
    cat /tmp/current_cron | grep "auto-update-service.sh"
else
    # 添加新任务（包含环境变量）
    echo "22 10 * * * source $ENV_FILE && $SCRIPT_PATH" >> /tmp/current_cron
    
    # 安装新的 crontab
    crontab /tmp/current_cron
    
    echo "✅ 自动更新任务已添加"
fi

# 清理临时文件
rm -f /tmp/current_cron

echo ""
echo "查看当前 crontab 任务："
crontab -l | grep -E "(auto-update-service|claude)" || echo "没有找到相关任务"

echo ""
echo "其他有用的命令："
echo "  查看所有 crontab: crontab -l"
echo "  编辑 crontab:     crontab -e"
echo "  删除所有 crontab: crontab -r"
echo "  查看更新日志:     tail -f logs/auto-update.log"