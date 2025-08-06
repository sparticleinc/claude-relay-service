#!/bin/bash
set -e

# ===================================================================
# Claude Relay Service 快速灾难恢复脚本
# 用于在服务被封后快速在新服务器上重建服务
# ===================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置（需要根据实际情况修改）
DEFAULT_KEY_PATH="$HOME/.ssh/id_ed25519"
DEFAULT_BACKUP_DIR="$HOME/Documents/claude-relay-backup/data-backups"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}Claude Relay Service 快速灾难恢复工具${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# 收集必要信息
read -p "请输入新服务器的 IP 地址: " NEW_IP
read -p "请输入 SSH 密钥路径 [默认: $DEFAULT_KEY_PATH]: " KEY_PATH
KEY_PATH=${KEY_PATH:-$DEFAULT_KEY_PATH}

# 检查 SSH 密钥
if [ ! -f "$KEY_PATH" ]; then
    echo -e "${RED}错误: SSH 密钥文件不存在: $KEY_PATH${NC}"
    exit 1
fi

# 列出可用的备份
echo -e "\n${YELLOW}可用的备份文件:${NC}"
BACKUP_DIR=${DEFAULT_BACKUP_DIR}
if [ ! -d "$BACKUP_DIR" ]; then
    read -p "备份目录不存在，请输入备份文件所在目录: " BACKUP_DIR
fi

cd "$BACKUP_DIR" 2>/dev/null || { echo -e "${RED}备份目录不存在${NC}"; exit 1; }

backups=($(ls -t claude-relay-backup-*.tar.gz 2>/dev/null))
if [ ${#backups[@]} -eq 0 ]; then
    echo -e "${RED}没有找到备份文件${NC}"
    exit 1
fi

for i in "${!backups[@]}"; do
    size=$(du -h "${backups[$i]}" | cut -f1)
    echo "  $((i+1)). ${backups[$i]} ($size)"
done

read -p "请选择要恢复的备份文件编号 (1-${#backups[@]}): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
    echo -e "${RED}无效的选择${NC}"
    exit 1
fi

BACKUP_FILE="${backups[$((choice-1))]}"
echo -e "${GREEN}已选择: $BACKUP_FILE${NC}"

# 新域名配置（可选）
read -p "是否需要配置新域名？(y/n): " NEED_DOMAIN
if [[ $NEED_DOMAIN =~ ^[Yy]$ ]]; then
    read -p "请输入新域名（例如: relay.example.com）: " NEW_DOMAIN
fi

echo -e "\n${YELLOW}准备开始恢复，请确认以下信息:${NC}"
echo "  服务器 IP: $NEW_IP"
echo "  SSH 密钥: $KEY_PATH"
echo "  备份文件: $BACKUP_FILE"
[ ! -z "$NEW_DOMAIN" ] && echo "  新域名: $NEW_DOMAIN"
echo ""
read -p "确认开始恢复？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "取消恢复"
    exit 0
fi

# ===================================================================
# 第一步：测试 SSH 连接
# ===================================================================
echo -e "\n${YELLOW}[1/7] 测试 SSH 连接...${NC}"
if ! ssh -i "$KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no ubuntu@$NEW_IP "echo '连接成功'" > /dev/null 2>&1; then
    echo -e "${RED}无法连接到服务器，请检查:${NC}"
    echo "  1. IP 地址是否正确"
    echo "  2. SSH 密钥是否正确"
    echo "  3. 服务器安全组是否开放 22 端口"
    exit 1
fi
echo -e "${GREEN}✓ SSH 连接成功${NC}"

# ===================================================================
# 第二步：安装 Docker 环境
# ===================================================================
echo -e "\n${YELLOW}[2/7] 安装 Docker 环境...${NC}"
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$NEW_IP << 'ENDSSH'
    set -e
    
    # 检查是否已安装 Docker
    if command -v docker &> /dev/null; then
        echo "Docker 已安装，跳过安装步骤"
    else
        echo "安装 Docker..."
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y ca-certificates curl gnupg > /dev/null 2>&1
        curl -fsSL https://get.docker.com | sudo sh > /dev/null 2>&1
        sudo usermod -aG docker $USER
    fi
    
    # 安装 Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "安装 Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    # 创建部署目录
    mkdir -p ~/claude-relay-deployment
    cd ~/claude-relay-deployment
    mkdir -p logs data redis_data
    
    echo "Docker 环境准备完成"
ENDSSH
echo -e "${GREEN}✓ Docker 环境安装完成${NC}"

# ===================================================================
# 第三步：上传备份文件
# ===================================================================
echo -e "\n${YELLOW}[3/7] 上传备份文件...${NC}"
echo "文件大小: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$BACKUP_DIR/$BACKUP_FILE" ubuntu@$NEW_IP:/tmp/ > /dev/null 2>&1
echo -e "${GREEN}✓ 备份文件上传完成${NC}"

# ===================================================================
# 第四步：恢复数据
# ===================================================================
echo -e "\n${YELLOW}[4/7] 恢复备份数据...${NC}"
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$NEW_IP << 'ENDSSH'
    set -e
    cd ~/claude-relay-deployment
    
    # 解压备份
    echo "解压备份文件..."
    sudo tar xzf /tmp/claude-relay-backup-*.tar.gz -C /tmp/
    BACKUP_DIR=$(ls /tmp/ | grep claude-relay-backup | grep -v tar.gz | head -1)
    
    # 恢复数据
    echo "恢复数据文件..."
    sudo cp -rp /tmp/$BACKUP_DIR/redis_data/* ./redis_data/ 2>/dev/null || true
    sudo cp -rp /tmp/$BACKUP_DIR/logs/* ./logs/ 2>/dev/null || true
    sudo cp -rp /tmp/$BACKUP_DIR/data/* ./data/ 2>/dev/null || true
    sudo cp /tmp/$BACKUP_DIR/.env ./ 2>/dev/null || true
    sudo cp /tmp/$BACKUP_DIR/docker-compose.yml ./ 2>/dev/null || true
    
    # 设置权限
    sudo chown -R $(id -u):$(id -g) .
    sudo chmod -R 755 logs data
    sudo chmod 600 .env
    
    # 清理临时文件
    sudo rm -rf /tmp/$BACKUP_DIR /tmp/claude-relay-backup-*.tar.gz
    
    echo "数据恢复完成"
ENDSSH
echo -e "${GREEN}✓ 数据恢复完成${NC}"

# ===================================================================
# 第五步：启动服务
# ===================================================================
echo -e "\n${YELLOW}[5/7] 启动 Docker 服务...${NC}"
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$NEW_IP << 'ENDSSH'
    set -e
    cd ~/claude-relay-deployment
    
    # 需要重新登录以应用 docker 组权限，这里使用 sudo
    echo "拉取 Docker 镜像..."
    sudo docker-compose pull > /dev/null 2>&1
    
    echo "启动服务..."
    sudo docker-compose up -d > /dev/null 2>&1
    
    # 等待服务启动
    sleep 10
    
    # 检查服务状态
    if sudo docker-compose ps | grep -q "Up"; then
        echo "服务启动成功"
    else
        echo "警告: 服务可能未正常启动"
        sudo docker-compose logs --tail=20
    fi
ENDSSH
echo -e "${GREEN}✓ 服务启动完成${NC}"

# ===================================================================
# 第六步：配置域名和 HTTPS（可选）
# ===================================================================
if [ ! -z "$NEW_DOMAIN" ]; then
    echo -e "\n${YELLOW}[6/7] 配置域名和 HTTPS...${NC}"
    
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$NEW_IP << ENDSSH
        set -e
        
        # 安装 Caddy
        if ! command -v caddy &> /dev/null; then
            echo "安装 Caddy..."
            sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https > /dev/null 2>&1
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y caddy > /dev/null 2>&1
        fi
        
        # 配置 Caddy
        echo "配置 Caddy..."
        sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
$NEW_DOMAIN {
    reverse_proxy localhost:3000
    
    header {
        X-Real-IP {remote_host}
        X-Forwarded-For {remote_host}
        X-Forwarded-Proto {scheme}
    }
    
    encode gzip
    
    log {
        output file /var/log/caddy/access.log
        format console
    }
}
EOF
        
        # 创建日志目录
        sudo mkdir -p /var/log/caddy
        
        # 重启 Caddy
        sudo systemctl restart caddy
        
        echo "Caddy 配置完成"
ENDSSH
    
    echo -e "${GREEN}✓ 域名和 HTTPS 配置完成${NC}"
    echo -e "${YELLOW}请确保域名 DNS 已指向 IP: $NEW_IP${NC}"
else
    echo -e "\n${YELLOW}[6/7] 跳过域名配置${NC}"
fi

# ===================================================================
# 第七步：验证服务
# ===================================================================
echo -e "\n${YELLOW}[7/7] 验证服务状态...${NC}"

# 测试健康检查
echo -n "检查服务健康状态... "
HEALTH_RESPONSE=$(ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@$NEW_IP "curl -s http://localhost:3000/health" 2>/dev/null)
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo -e "${GREEN}✓${NC}"
    VERSION=$(echo "$HEALTH_RESPONSE" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
    echo -e "  服务版本: ${GREEN}$VERSION${NC}"
else
    echo -e "${RED}✗${NC}"
    echo -e "${RED}  服务可能未正常运行${NC}"
fi

# ===================================================================
# 完成
# ===================================================================
echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}🎉 恢复完成！${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${BLUE}访问地址:${NC}"
echo -e "  HTTP:  ${GREEN}http://$NEW_IP:3000${NC}"
if [ ! -z "$NEW_DOMAIN" ]; then
    echo -e "  HTTPS: ${GREEN}https://$NEW_DOMAIN${NC}"
fi
echo -e "  管理界面: ${GREEN}http://$NEW_IP:3000/web${NC}"
echo ""
echo -e "${BLUE}下一步操作:${NC}"
echo "  1. 访问管理界面，使用原管理员账号登录"
echo "  2. 添加新的 Claude 账号（如果原账号被封）"
echo "  3. 测试 API 调用是否正常"
echo "  4. 更新客户端配置中的服务地址"
if [ -z "$NEW_DOMAIN" ]; then
    echo "  5. 配置域名和 HTTPS（推荐）"
fi
echo ""
echo -e "${YELLOW}提示: 查看服务日志${NC}"
echo "  ssh -i $KEY_PATH ubuntu@$NEW_IP 'cd ~/claude-relay-deployment && sudo docker-compose logs -f'"
echo ""
echo -e "${YELLOW}重要: 请立即创建新的备份计划！${NC}"