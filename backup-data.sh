#!/bin/bash
set -e

# 配置
REMOTE_HOST="ubuntu@cc-relay.gbase.ai"
REMOTE_DIR="/home/ubuntu/claude-relay-deployment"
LOCAL_BACKUP_DIR="$HOME/Documents/claude-relay-backup/data-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="claude-relay-backup-$DATE"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔄 开始备份 Claude Relay Service 数据...${NC}"

# 创建本地备份目录
mkdir -p "$LOCAL_BACKUP_DIR"

# 在远程服务器上创建备份
echo -e "\n${YELLOW}📦 在服务器上创建数据备份...${NC}"
ssh -i ~/.ssh/id_ed25519 $REMOTE_HOST << EOF
    cd $REMOTE_DIR
    # 创建临时备份目录
    mkdir -p /tmp/$BACKUP_NAME
    
    # 复制数据（保持权限）
    sudo cp -rp redis_data /tmp/$BACKUP_NAME/
    sudo cp -rp logs /tmp/$BACKUP_NAME/
    sudo cp -rp data /tmp/$BACKUP_NAME/
    sudo cp -p .env /tmp/$BACKUP_NAME/
    sudo cp -p docker-compose.yml /tmp/$BACKUP_NAME/
    
    # 创建压缩包
    cd /tmp
    sudo tar czf $BACKUP_NAME.tar.gz $BACKUP_NAME
    sudo chown ubuntu:ubuntu $BACKUP_NAME.tar.gz
    
    # 清理临时目录
    sudo rm -rf /tmp/$BACKUP_NAME
EOF

# 下载备份到本地
echo -e "\n${YELLOW}📥 下载备份到本地...${NC}"
scp -i ~/.ssh/id_ed25519 $REMOTE_HOST:/tmp/$BACKUP_NAME.tar.gz "$LOCAL_BACKUP_DIR/"

# 清理远程临时文件
echo -e "\n${YELLOW}🧹 清理远程临时文件...${NC}"
ssh -i ~/.ssh/id_ed25519 $REMOTE_HOST "rm -f /tmp/$BACKUP_NAME.tar.gz"

# 显示备份信息
echo -e "\n${GREEN}✅ 备份完成！${NC}"
echo -e "备份文件: ${GREEN}$LOCAL_BACKUP_DIR/$BACKUP_NAME.tar.gz${NC}"
echo -e "备份大小: $(du -h "$LOCAL_BACKUP_DIR/$BACKUP_NAME.tar.gz" | cut -f1)"

# 保留最近7个备份
echo -e "\n${YELLOW}🗑️  清理旧备份（保留最近7个）...${NC}"
cd "$LOCAL_BACKUP_DIR"
ls -t claude-relay-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo -e "\n${YELLOW}📋 当前备份列表：${NC}"
ls -lh claude-relay-backup-*.tar.gz 2>/dev/null || echo "没有找到备份文件"