# 步骤4：AWS EC2部署指南

这是最后一步，将服务部署到AWS EC2上。

## 🎯 方案特点

- **单EC2实例**：适合10-50人内部使用
- **Docker部署**：使用私有镜像仓库
- **成本优化**：t3.medium约$30/月
- **维护简单**：一台服务器搞定

## 📋 快速部署步骤

### 1. 创建EC2实例

在AWS控制台：
1. 选择区域：**美西（us-west-2）或美东（us-east-1）**
2. 启动实例：
   - AMI：**Amazon Linux 2023**
   - 实例类型：**t3.medium**（2核4G）
   - 存储：**30GB GP3 SSD**
   - 安全组规则：
     - SSH (22)：你的办公室IP
     - HTTP (80)：你的办公室网段
     - HTTPS (443)：你的办公室网段

### 2. 初始设置（SSH登录后）

```bash
# 安装Docker和Docker Compose
sudo yum update -y
sudo yum install -y docker git
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# 安装Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 重新登录使docker组生效
exit
# 重新SSH登录
```

### 3. 构建并推送到私有仓库

```bash
# 克隆你Fork的仓库
cd ~
git clone https://github.com/qq98982/claude-relay-service.git
cd claude-relay-service

# 使用自动构建脚本
./docs/aws-deployment/scripts/build-and-push.sh v1.0.0

# 或手动构建
docker build -t gptbasesparticle/claude-relay-service:latest .
docker login -u gptbasesparticle
docker push gptbasesparticle/claude-relay-service:latest
```

### 4. 部署服务

```bash
# 创建部署目录
mkdir -p ~/claude-relay-deployment
cd ~/claude-relay-deployment

# 创建环境配置
cat > .env << 'EOF'
# 必填项
JWT_SECRET=your-random-secret-at-least-32-characters-long
ENCRYPTION_KEY=exactly-32-character-encryption-

# 管理员账号
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your-secure-password-here

# Redis（使用Docker内部网络）
REDIS_HOST=redis
REDIS_PORT=6379
EOF

# 创建docker-compose.yml（使用私有镜像）
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  app:
    image: gptbasesparticle/claude-relay-service:latest
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - REDIS_HOST=redis
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - ./redis_data:/data
    command: redis-server --appendonly yes
EOF

# 启动服务
docker-compose up -d

# 查看日志确认启动成功
docker-compose logs -f
```

### 5. 访问服务

1. 访问：`http://你的EC2公网IP:3000/web`
2. 使用设置的管理员账号登录
3. 添加Claude账户（需要OAuth授权）
4. 创建API Key分配给用户

## 🔄 日常维护

### 同步上游更新

```bash
# 1. 在本地开发环境
cd ~/claude-relay-service
git remote add upstream https://github.com/Wei-Shaw/claude-relay-service.git
git fetch upstream
git merge upstream/main

# 2. 构建并推送新镜像
./docs/aws-deployment/scripts/build-and-push.sh

# 3. 在EC2服务器上更新
ssh ec2-user@your-server-ip
./deploy-to-ec2.sh update
```

### 使用部署脚本

```bash
# 复制部署脚本到服务器
scp docs/aws-deployment/scripts/deploy-to-ec2.sh ec2-user@your-server-ip:~/

# 在服务器上使用
./deploy-to-ec2.sh update    # 更新服务
./deploy-to-ec2.sh backup    # 备份数据
./deploy-to-ec2.sh status    # 查看状态
./deploy-to-ec2.sh logs      # 查看日志
```

### 查看日志

```bash
# 实时日志
docker-compose logs -f

# 查看最近100行
docker-compose logs --tail=100
```

### 备份数据

```bash
# 创建备份脚本
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="$HOME/backups"
mkdir -p $BACKUP_DIR
cd ~/claude-relay-service
tar -czf $BACKUP_DIR/claude-backup-$(date +%Y%m%d-%H%M%S).tar.gz .env data/ logs/ redis_data/
# 保留最近7天的备份
find $BACKUP_DIR -name "claude-backup-*.tar.gz" -mtime +7 -delete
EOF

chmod +x backup.sh

# 添加定时任务（每天凌晨2点备份）
(crontab -l 2>/dev/null; echo "0 2 * * * $HOME/claude-relay-service/backup.sh") | crontab -
```

## 🛡️ 安全建议

### 1. 限制访问来源

编辑安全组，只允许公司IP访问：
- 获取公司出口IP：`curl ifconfig.me`
- 在AWS安全组中设置入站规则只允许该IP

### 2. 启用HTTPS（推荐）

使用Caddy自动配置HTTPS：
```bash
# 安装Caddy
sudo yum install -y yum-plugin-copr
sudo yum copr enable @caddy/caddy -y
sudo yum install -y caddy

# 配置Caddy
sudo tee /etc/caddy/Caddyfile << EOF
your-domain.com {
    reverse_proxy localhost:3000
}
EOF

# 启动Caddy
sudo systemctl enable --now caddy
```

### 3. 使用弹性IP

分配弹性IP避免重启后IP变化：
```bash
# 在AWS控制台分配弹性IP
# 关联到你的EC2实例
```

## 💰 成本优化

### 使用预留实例

- 1年期预留实例：节省约40%
- 3年期预留实例：节省约60%

### 实例类型选择

| 用户数 | 推荐实例 | 月成本 |
|--------|----------|--------|
| 1-10人 | t3.small | ~$15 |
| 10-50人 | t3.medium | ~$30 |
| 50-100人 | t3.large | ~$60 |

## 🐳 使用私有镜像的优势

### 为什么使用私有仓库？

1. **版本控制**：可以保留多个版本，方便回滚
2. **安全性**：私有仓库更安全，避免敏感配置泄露
3. **稳定性**：不依赖第三方镜像，避免被删除或篡改
4. **定制化**：可以在Dockerfile中添加自己的配置

### 镜像版本管理

```bash
# 使用语义化版本
docker build -t gptbasesparticle/claude-relay-service:v1.0.0 .
docker tag gptbasesparticle/claude-relay-service:v1.0.0 gptbasesparticle/claude-relay-service:latest

# 推送多个标签
docker push gptbasesparticle/claude-relay-service:v1.0.0
docker push gptbasesparticle/claude-relay-service:latest
```

## 🚨 故障排查

### 服务无法访问

```bash
# 1. 检查Docker服务
docker-compose ps

# 2. 检查端口
sudo netstat -tlnp | grep 3000

# 3. 重启服务
docker-compose restart
```

### Claude账户连接问题

1. 检查账户OAuth token是否过期
2. 确认服务器能访问claude.ai
3. 查看日志：`docker-compose logs app | grep ERROR`

### 性能问题

```bash
# 查看资源使用
docker stats

# 清理Docker资源
docker system prune -a
```

## 📝 最佳实践总结

### DO ✅
- 定期备份数据（每日自动）
- 及时同步上游更新（每周检查）
- 限制访问IP范围
- 使用HTTPS加密传输
- 监控磁盘空间

### DON'T ❌
- 不要修改原项目代码
- 不要暴露服务到公网
- 不要忘记设置强密码
- 不要跳过备份
- 不要忽视安全更新

## 🔧 进阶优化（可选）

### 使用CloudWatch监控

```bash
# 安装CloudWatch代理
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
sudo rpm -U ./amazon-cloudwatch-agent.rpm

# 配置基础监控
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard
```

### 配置自动化部署

在你的Fork仓库创建 `.github/workflows/deploy.yml`：
```yaml
name: Deploy to EC2

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - name: Deploy via SSH
      uses: appleboy/ssh-action@v0.1.5
      with:
        host: ${{ secrets.EC2_HOST }}
        username: ec2-user
        key: ${{ secrets.EC2_SSH_KEY }}
        script: |
          cd ~/claude-relay-service
          git pull
          docker-compose pull
          docker-compose up -d
```

## 🎯 总结

这个简化方案专注于：
- **简单**：一台EC2搞定一切
- **实用**：满足公司内部使用需求
- **经济**：成本可控，按需扩展
- **可靠**：易于维护和故障恢复

## 🎉 恭喜！

遵循这个指南，你已经完成了Claude Relay Service的部署。

### 后续维护

- 每周检查上游更新
- 定期备份数据
- 监控服务状态
- 使用提供的脚本简化操作

### 需要帮助？

如有问题，请查看故障排查部分或返回[主页](README.md)查看其他文档。