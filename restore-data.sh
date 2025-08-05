#!/bin/bash
set -e

# 配置
REMOTE_HOST="ubuntu@cc-relay.gbase.ai"
REMOTE_DIR="/home/ubuntu/claude-relay-deployment"
LOCAL_BACKUP_DIR="$HOME/Documents/claude-relay-backup/data-backups"

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🔄 Claude Relay Service 数据恢复工具${NC}"

# 列出可用的备份
echo -e "\n${YELLOW}📋 可用的备份文件：${NC}"
cd "$LOCAL_BACKUP_DIR" 2>/dev/null || { echo -e "${RED}备份目录不存在${NC}"; exit 1; }

backups=($(ls -t claude-relay-backup-*.tar.gz 2>/dev/null))
if [ ${#backups[@]} -eq 0 ]; then
    echo -e "${RED}没有找到备份文件${NC}"
    exit 1
fi

for i in "${!backups[@]}"; do
    size=$(du -h "${backups[$i]}" | cut -f1)
    date=$(echo "${backups[$i]}" | grep -oE '[0-9]{8}_[0-9]{6}')
    echo "  $((i+1)). ${backups[$i]} ($size) - $date"
done

# 选择备份文件
echo ""
read -p "请选择要恢复的备份文件编号 (1-${#backups[@]}): " choice

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
    echo -e "${RED}无效的选择${NC}"
    exit 1
fi

BACKUP_FILE="${backups[$((choice-1))]}"
echo -e "\n${YELLOW}已选择: $BACKUP_FILE${NC}"

# 确认恢复
echo -e "\n${RED}⚠️  警告：恢复操作将覆盖当前的所有数据！${NC}"
read -p "确定要继续吗？(yes/no) " confirm
if [ "$confirm" != "yes" ]; then
    echo "取消恢复"
    exit 0
fi

# 上传备份文件到服务器
echo -e "\n${YELLOW}📤 上传备份文件到服务器...${NC}"
scp -i ~/.ssh/id_ed25519 "$LOCAL_BACKUP_DIR/$BACKUP_FILE" $REMOTE_HOST:/tmp/

# 在服务器上执行恢复
echo -e "\n${YELLOW}🔧 执行数据恢复...${NC}"
ssh -i ~/.ssh/id_ed25519 $REMOTE_HOST << EOF
    cd $REMOTE_DIR
    
    # 停止服务
    echo "停止服务..."
    sudo docker-compose down
    
    # 备份当前数据（以防万一）
    echo "备份当前数据..."
    sudo mv redis_data redis_data.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    sudo mv logs logs.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    sudo mv data data.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 解压恢复数据
    echo "解压备份数据..."
    cd /tmp
    sudo tar xzf $BACKUP_FILE
    BACKUP_DIR=\$(tar tzf $BACKUP_FILE | head -1 | cut -d/ -f1)
    
    # 恢复数据
    echo "恢复数据..."
    cd $REMOTE_DIR
    sudo mv /tmp/\$BACKUP_DIR/redis_data ./
    sudo mv /tmp/\$BACKUP_DIR/logs ./
    sudo mv /tmp/\$BACKUP_DIR/data ./
    
    # 恢复配置文件（如果需要）
    # sudo cp /tmp/\$BACKUP_DIR/.env ./
    # sudo cp /tmp/\$BACKUP_DIR/docker-compose.yml ./
    
    # 清理临时文件
    sudo rm -rf /tmp/\$BACKUP_DIR /tmp/$BACKUP_FILE
    
    # 启动服务
    echo "启动服务..."
    sudo docker-compose up -d
    
    # 检查服务状态
    sleep 5
    sudo docker-compose ps
EOF

# 验证恢复
echo -e "\n${YELLOW}✅ 验证服务状态...${NC}"
sleep 10
curl -s https://cc-relay.gbase.ai/health | jq '.' || echo -e "${RED}服务可能未正常启动${NC}"

echo -e "\n${GREEN}✨ 数据恢复完成！${NC}"
echo -e "请访问 ${GREEN}https://cc-relay.gbase.ai/web${NC} 检查服务是否正常"