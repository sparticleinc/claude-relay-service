# 灾难恢复完整指南 - 从零重建服务

本文档提供详细的步骤说明，用于在原服务被封禁后，快速在新环境重建 Claude Relay Service。

## 前置准备

### 必需资源清单
- [ ] 数据备份文件（`claude-relay-backup-*.tar.gz`）
- [ ] AWS 账号（或其他云服务商账号）
- [ ] Docker Hub 账号（用于拉取镜像）
- [ ] 新域名（如果原域名不可用）
- [ ] SSH 密钥对（本地已有 `~/.ssh/id_ed25519`）
- [ ] 新的 Claude 账号（用于获取 OAuth token）

### 时间预估
- 整个恢复过程约需 1-2 小时
- 服务器创建和配置：30 分钟
- 数据恢复：15 分钟
- Claude 账号配置：15 分钟
- 测试验证：15 分钟

## 第一部分：AWS EC2 新实例创建

### 1.1 登录 AWS 控制台
```
1. 访问 https://console.aws.amazon.com
2. 选择区域（建议选择东京 ap-northeast-1）
3. 进入 EC2 服务
```

### 1.2 创建新的 EC2 实例

#### 步骤 1：启动实例
```
EC2 Dashboard → Instances → Launch instances
```

#### 步骤 2：配置实例
```
名称和标签:
  Name: claude-relay-new

选择 AMI:
  Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
  架构: 64-bit (x86)

实例类型:
  t3.small (2 vCPU, 2 GiB Memory)
  
密钥对:
  选择现有密钥对或创建新密钥对
  如果创建新的，下载 .pem 文件并保存
  
网络设置:
  VPC: 默认 VPC
  子网: 无偏好
  自动分配公有 IP: 启用
  
安全组:
  创建新的安全组
  名称: claude-relay-sg
  描述: Security group for Claude Relay Service
  
  入站规则:
    - SSH (22): 来源 My IP
    - HTTP (80): 来源 Anywhere (0.0.0.0/0)
    - HTTPS (443): 来源 Anywhere (0.0.0.0/0)
    - Custom TCP (3000): 来源 Anywhere (0.0.0.0/0)

存储:
  20 GiB gp3
  加密: 默认
  删除终止: 是
```

#### 步骤 3：启动实例
```
点击 "Launch instance"
等待实例状态变为 "Running"
记录新的公网 IP 地址（例如: 54.xxx.xxx.xxx）
```

### 1.3 配置 SSH 访问

如果使用新密钥对：
```bash
# 设置密钥权限
chmod 400 ~/Downloads/new-key.pem

# 移动到 .ssh 目录
mv ~/Downloads/new-key.pem ~/.ssh/

# 首次连接
ssh -i ~/.ssh/new-key.pem ubuntu@54.xxx.xxx.xxx
```

如果使用现有密钥：
```bash
# 直接连接
ssh -i ~/.ssh/id_ed25519 ubuntu@54.xxx.xxx.xxx
```

## 第二部分：服务器环境配置

### 2.1 更新系统并安装 Docker

SSH 连接到新服务器后执行：

```bash
# 更新系统包
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y curl wget git jq

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 添加当前用户到 docker 组
sudo usermod -aG docker $USER

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 验证安装
docker --version
docker-compose --version

# 重新登录以应用组权限
exit
```

重新 SSH 连接：
```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@54.xxx.xxx.xxx
```

### 2.2 创建部署目录结构

```bash
# 创建部署目录
mkdir -p ~/claude-relay-deployment
cd ~/claude-relay-deployment

# 创建必要的子目录
mkdir -p logs data redis_data
```

## 第三部分：恢复备份数据

### 3.1 上传备份文件

在本地机器执行：
```bash
# 找到最新的备份文件
cd ~/Documents/claude-relay-backup/data-backups/
ls -lh claude-relay-backup-*.tar.gz

# 上传备份文件到新服务器
scp -i ~/.ssh/id_ed25519 claude-relay-backup-20250805_142530.tar.gz ubuntu@54.xxx.xxx.xxx:/tmp/
```

### 3.2 恢复数据

在新服务器上执行：
```bash
cd ~/claude-relay-deployment

# 解压备份
sudo tar xzf /tmp/claude-relay-backup-*.tar.gz -C /tmp/
BACKUP_DIR=$(ls /tmp/ | grep claude-relay-backup | grep -v tar.gz)

# 恢复各个目录
sudo cp -rp /tmp/$BACKUP_DIR/redis_data/* ./redis_data/
sudo cp -rp /tmp/$BACKUP_DIR/logs/* ./logs/
sudo cp -rp /tmp/$BACKUP_DIR/data/* ./data/
sudo cp /tmp/$BACKUP_DIR/.env ./
sudo cp /tmp/$BACKUP_DIR/docker-compose.yml ./

# 设置正确的权限
sudo chown -R $(id -u):$(id -g) .
sudo chmod -R 755 logs data
sudo chmod 600 .env

# 清理临时文件
sudo rm -rf /tmp/$BACKUP_DIR /tmp/claude-relay-backup-*.tar.gz
```

### 3.3 更新配置文件

编辑 `.env` 文件，确保配置正确：
```bash
nano .env
```

检查并更新以下配置：
```env
# 保持原有的密钥不变（重要！）
JWT_SECRET=原有的JWT密钥
ENCRYPTION_KEY=原有的32字符加密密钥

# Redis 配置
REDIS_HOST=redis
REDIS_PORT=6379

# 其他配置保持不变
```

## 第四部分：启动基础服务

### 4.1 启动 Docker 服务

```bash
cd ~/claude-relay-deployment

# 拉取镜像
sudo docker-compose pull

# 启动服务
sudo docker-compose up -d

# 检查服务状态
sudo docker-compose ps

# 查看日志
sudo docker-compose logs -f --tail=100
```

### 4.2 验证服务运行

```bash
# 测试健康检查端点
curl http://localhost:3000/health

# 应该返回类似：
# {
#   "status": "healthy",
#   "version": "1.1.89",
#   ...
# }
```

## 第五部分：域名配置

### 5.1 配置新域名（如果需要）

如果原域名不可用，需要配置新域名：

1. 在域名注册商处添加 A 记录：
```
类型: A
名称: cc-relay 或 @
值: 54.xxx.xxx.xxx (新服务器 IP)
TTL: 300
```

2. 等待 DNS 生效（通常 5-30 分钟）：
```bash
# 测试 DNS 解析
nslookup your-new-domain.com
ping your-new-domain.com
```

### 5.2 安装和配置 Caddy

```bash
# 安装 Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy

# 配置 Caddy
sudo nano /etc/caddy/Caddyfile
```

Caddyfile 内容：
```
your-new-domain.com {
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
```

重启 Caddy：
```bash
sudo systemctl restart caddy
sudo systemctl status caddy
```

### 5.3 验证 HTTPS 访问

```bash
# 测试 HTTPS
curl https://your-new-domain.com/health

# 访问 Web 界面
echo "Web 界面: https://your-new-domain.com/web"
```

## 第六部分：添加新的 Claude 账号

由于原账号可能被封，需要添加新的 Claude 账号。

### 6.1 登录管理界面

1. 访问 `https://your-new-domain.com/web`
2. 使用原管理员账号登录（密码从备份中恢复）

### 6.2 准备新的 Claude 账号

1. 注册新的 Claude 账号：
   - 访问 https://claude.ai
   - 使用新邮箱注册
   - 完成邮箱验证

2. 升级到 Pro 账号（如需要）：
   - 访问账号设置
   - 选择升级到 Pro

### 6.3 添加 OAuth 账号

在管理界面操作：

#### 步骤 1：生成授权 URL
```
1. 点击 "Claude 账户管理"
2. 点击 "添加账户"
3. 填写基本信息：
   - 账户名称: claude-new-1
   - 描述: 新的 Claude Pro 账号
   - 是否启用: 是
   
4. 代理设置（如果需要）：
   - 代理类型: SOCKS5 或 HTTP
   - 代理地址: proxy.example.com
   - 代理端口: 1080
   - 用户名/密码: （如果需要）
   
5. 点击 "生成授权 URL"
```

#### 步骤 2：完成 OAuth 授权
```
1. 复制生成的授权 URL
2. 在浏览器中打开该 URL（建议使用隐私模式）
3. 使用新的 Claude 账号登录
4. 点击 "Allow" 授权
5. 页面会显示 Authorization Code
6. 复制整个 code（很长的字符串）
```

#### 步骤 3：交换 Token
```
1. 回到管理界面
2. 粘贴 Authorization Code
3. 点击 "交换 Token"
4. 等待成功提示
5. 账户状态应显示 "活跃"
```

### 6.4 测试新账号

```bash
# 使用 API Key 测试
curl -X POST https://your-new-domain.com/api/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: cr_your_api_key" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-3-opus-20240229",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 100
  }'
```

## 第七部分：配置监控和自动化

### 7.1 设置自动重启

```bash
# 确保 docker-compose.yml 中有 restart 策略
cd ~/claude-relay-deployment
grep restart docker-compose.yml
# 应该看到: restart: unless-stopped
```

### 7.2 配置系统监控

创建监控脚本：
```bash
cat > ~/check-service.sh << 'EOF'
#!/bin/bash
HEALTH_URL="https://your-new-domain.com/health"
WEBHOOK_URL="your-slack-webhook-url"  # 可选

# 检查服务健康
if ! curl -sf $HEALTH_URL > /dev/null; then
    echo "Service is down at $(date)" >> ~/service-monitor.log
    # 尝试重启
    cd ~/claude-relay-deployment
    sudo docker-compose restart
    
    # 发送通知（可选）
    # curl -X POST $WEBHOOK_URL -d '{"text":"Claude Relay Service is down and restarting"}'
fi
EOF

chmod +x ~/check-service.sh

# 添加到 crontab（每5分钟检查一次）
(crontab -l 2>/dev/null; echo "*/5 * * * * ~/check-service.sh") | crontab -
```

### 7.3 设置日志轮转

```bash
sudo nano /etc/logrotate.d/claude-relay
```

内容：
```
/home/ubuntu/claude-relay-deployment/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 ubuntu ubuntu
    sharedscripts
    postrotate
        docker-compose -f /home/ubuntu/claude-relay-deployment/docker-compose.yml restart app
    endscript
}
```

## 第八部分：安全加固

### 8.1 配置防火墙

```bash
# 安装 ufw
sudo apt install -y ufw

# 配置规则
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https

# 启用防火墙
sudo ufw --force enable
sudo ufw status
```

### 8.2 配置 fail2ban

```bash
# 安装 fail2ban
sudo apt install -y fail2ban

# 配置 SSH 保护
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# 找到 [sshd] 部分，确保启用：
# enabled = true
# maxretry = 3
# bantime = 3600

sudo systemctl restart fail2ban
```

### 8.3 定期安全更新

```bash
# 启用自动安全更新
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
# 选择 "Yes" 启用自动更新
```

## 第九部分：验证和测试

### 9.1 功能测试清单

- [ ] Web 管理界面可访问
- [ ] 管理员可正常登录
- [ ] API Key 列表正常显示
- [ ] Claude 账户列表正常显示
- [ ] 可以创建新的 API Key
- [ ] API 调用测试成功
- [ ] 流式响应正常工作
- [ ] 使用统计正常记录
- [ ] 日志正常记录

### 9.2 性能测试

```bash
# 简单的并发测试
for i in {1..10}; do
  curl -X POST https://your-new-domain.com/api/v1/messages \
    -H "x-api-key: cr_your_api_key" \
    -H "Content-Type: application/json" \
    -d '{"model":"claude-3-haiku-20240307","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' &
done
wait
```

### 9.3 备份验证

```bash
# 执行一次备份测试
cd ~/Documents/claude-relay-backup
./backup-data.sh

# 确认备份文件创建成功
ls -lh data-backups/
```

## 故障排查

### 问题 1：Docker 服务无法启动
```bash
# 检查 Docker 状态
sudo systemctl status docker

# 查看 Docker 日志
sudo journalctl -u docker -n 100

# 重启 Docker
sudo systemctl restart docker
```

### 问题 2：Redis 数据损坏
```bash
# 停止服务
cd ~/claude-relay-deployment
sudo docker-compose down

# 检查 Redis AOF 文件
sudo docker run --rm -v $(pwd)/redis_data:/data redis:7-alpine redis-check-aof --fix /data/appendonly.aof

# 重启服务
sudo docker-compose up -d
```

### 问题 3：Claude API 调用失败
```bash
# 检查账户状态
curl https://your-new-domain.com/admin/claude-accounts \
  -H "Authorization: Bearer your-admin-token"

# 查看详细日志
sudo docker-compose logs -f app | grep ERROR

# 手动刷新 token
curl -X POST https://your-new-domain.com/admin/claude-accounts/refresh/account-id \
  -H "Authorization: Bearer your-admin-token"
```

### 问题 4：域名无法访问
```bash
# 检查 DNS 解析
nslookup your-new-domain.com
dig your-new-domain.com

# 检查 Caddy 状态
sudo systemctl status caddy
sudo journalctl -u caddy -n 100

# 检查证书
sudo caddy list-certs
```

## 快速恢复脚本

为了加快恢复速度，可以使用以下一键脚本：

```bash
#!/bin/bash
# quick-recovery.sh

# 配置变量
NEW_IP="54.xxx.xxx.xxx"
BACKUP_FILE="claude-relay-backup-20250805_142530.tar.gz"
DOMAIN="your-new-domain.com"

echo "开始快速恢复 Claude Relay Service..."

# 1. 连接到服务器并安装 Docker
ssh -i ~/.ssh/id_ed25519 ubuntu@$NEW_IP << 'ENDSSH'
  # 更新系统
  sudo apt update && sudo apt upgrade -y
  
  # 安装 Docker
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  
  # 安装 Docker Compose
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  
  # 创建目录
  mkdir -p ~/claude-relay-deployment
  cd ~/claude-relay-deployment
  mkdir -p logs data redis_data
ENDSSH

# 2. 上传备份
scp -i ~/.ssh/id_ed25519 ~/Documents/claude-relay-backup/data-backups/$BACKUP_FILE ubuntu@$NEW_IP:/tmp/

# 3. 恢复数据并启动服务
ssh -i ~/.ssh/id_ed25519 ubuntu@$NEW_IP << 'ENDSSH'
  cd ~/claude-relay-deployment
  
  # 解压备份
  sudo tar xzf /tmp/claude-relay-backup-*.tar.gz -C /tmp/
  BACKUP_DIR=$(ls /tmp/ | grep claude-relay-backup | grep -v tar.gz)
  
  # 恢复数据
  sudo cp -rp /tmp/$BACKUP_DIR/* ./
  sudo chown -R $(id -u):$(id -g) .
  
  # 启动服务
  sudo docker-compose up -d
  
  # 清理
  sudo rm -rf /tmp/$BACKUP_DIR /tmp/*.tar.gz
ENDSSH

echo "恢复完成！"
echo "请访问: http://$NEW_IP:3000/web"
echo "下一步：配置域名和 HTTPS"
```

## 恢复后的维护建议

1. **定期备份**：每天自动备份数据
2. **监控告警**：设置服务监控和告警
3. **账号轮换**：准备多个 Claude 账号备用
4. **文档更新**：记录新的服务器信息
5. **应急预案**：准备备用服务器和域名

## 联系支持

如遇到问题，可以：
1. 查看项目 Wiki：https://github.com/your-repo/wiki
2. 提交 Issue：https://github.com/your-repo/issues
3. 查看日志：`docker-compose logs -f`

---

**最后更新**: 2025-08-05
**适用版本**: Claude Relay Service v1.1.89+