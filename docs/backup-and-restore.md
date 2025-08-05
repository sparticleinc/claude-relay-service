# 数据备份与恢复指南

## 数据存储说明

Claude Relay Service 的数据存储在服务器的文件系统中，而不是 Docker 容器内部。所有数据通过 Docker volumes 挂载到宿主机，确保数据持久化。

### 数据目录结构

数据存储在服务器的 `~/claude-relay-deployment/` 目录下：

```
~/claude-relay-deployment/
├── redis_data/      # Redis 持久化数据（约 30MB）
│   └── appendonly.aof  # Redis AOF 持久化文件
├── logs/            # 应用日志文件（约 2-3MB）
│   ├── claude-relay-2025-08-05.log
│   └── ...
├── data/            # 应用数据文件（约 500KB）
├── .env             # 环境配置文件
└── docker-compose.yml  # Docker 部署配置
```

### 数据内容说明

- **redis_data**: 包含所有核心业务数据
  - API Keys 和使用统计
  - Claude/Gemini 账户信息（OAuth tokens 已加密）
  - 管理员账户和会话信息
  - 系统配置和状态缓存

- **logs**: 应用运行日志
  - 按日期分割的日志文件
  - 包含请求记录、错误信息、系统事件

- **data**: 其他应用数据
  - 临时文件和缓存数据

## 备份操作

### 手动备份

1. 运行备份脚本：
   ```bash
   ./backup-data.sh
   ```

2. 备份过程：
   - 在服务器上创建数据快照
   - 打包成 tar.gz 压缩文件
   - 下载到本地 `~/Documents/claude-relay-backup/data-backups/` 目录
   - 自动保留最近 7 个备份

3. 备份文件命名格式：
   ```
   claude-relay-backup-20250805_142530.tar.gz
   ```

### 自动定期备份

设置 crontab 实现自动备份：

```bash
# 编辑 crontab
crontab -e

# 添加定期备份任务（每天凌晨 2 点）
0 2 * * * /path/to/claude-relay-service/backup-data.sh >> /path/to/backup.log 2>&1
```

### 备份策略建议

- **频率**: 每日备份（根据业务重要性调整）
- **保留期**: 本地保留 7 天，重要版本长期保存
- **异地备份**: 定期将备份文件同步到云存储（如 S3、Google Drive）

## 恢复操作

### 恢复步骤

1. 运行恢复脚本：
   ```bash
   ./restore-data.sh
   ```

2. 选择要恢复的备份：
   ```
   可用的备份文件：
     1. claude-relay-backup-20250805_142530.tar.gz (32M) - 20250805_142530
     2. claude-relay-backup-20250804_021500.tar.gz (31M) - 20250804_021500
   
   请选择要恢复的备份文件编号 (1-2): 1
   ```

3. 确认恢复操作（输入 `yes`）

4. 恢复过程：
   - 停止当前服务
   - 备份当前数据（添加 .bak 后缀）
   - 恢复选定的备份数据
   - 重启服务
   - 验证服务状态

### 注意事项

⚠️ **警告**：
- 恢复操作会覆盖当前所有数据
- 恢复前会自动备份当前数据，但建议先手动备份
- 恢复后需要验证服务是否正常运行

## 灾难恢复

### 完整服务迁移

如需迁移到新服务器：

1. 在新服务器上部署基础环境：
   ```bash
   # 安装 Docker 和 Docker Compose
   # 创建部署目录
   mkdir ~/claude-relay-deployment
   cd ~/claude-relay-deployment
   ```

2. 复制部署配置：
   ```bash
   # 复制 docker-compose.yml 和 .env 文件到新服务器
   ```

3. 恢复数据：
   ```bash
   # 上传备份文件并解压
   tar xzf claude-relay-backup-YYYYMMDD_HHMMSS.tar.gz
   ```

4. 启动服务：
   ```bash
   docker-compose up -d
   ```

### 部分数据恢复

如只需恢复特定数据：

```bash
# 解压备份文件
tar xzf claude-relay-backup-YYYYMMDD_HHMMSS.tar.gz

# 只恢复 Redis 数据
sudo cp -rp claude-relay-backup-YYYYMMDD_HHMMSS/redis_data/* ~/claude-relay-deployment/redis_data/

# 重启 Redis 服务
docker-compose restart redis
```

## 监控和维护

### 数据增长监控

定期检查数据目录大小：

```bash
ssh ubuntu@cc-relay.gbase.ai "du -sh ~/claude-relay-deployment/*"
```

### 日志清理

日志文件会持续增长，建议定期清理：

```bash
# 保留最近 30 天的日志
find ~/claude-relay-deployment/logs -name "*.log" -mtime +30 -delete
```

### 备份验证

定期验证备份的完整性：

```bash
# 测试解压备份文件
tar tzf backup-file.tar.gz > /dev/null && echo "备份文件完整"
```

## 安全建议

1. **备份加密**: 对敏感备份文件进行加密
   ```bash
   # 加密备份
   gpg -c backup-file.tar.gz
   
   # 解密备份
   gpg -d backup-file.tar.gz.gpg > backup-file.tar.gz
   ```

2. **访问控制**: 限制备份文件的访问权限
   ```bash
   chmod 600 backup-file.tar.gz
   ```

3. **传输安全**: 使用 SSH/SCP 进行安全传输

4. **定期测试**: 定期进行恢复演练，确保备份可用

## 故障排查

### 备份失败

- 检查 SSH 连接和密钥配置
- 确认服务器磁盘空间充足
- 查看备份脚本的错误日志

### 恢复失败

- 确认备份文件完整性
- 检查服务器权限设置
- 查看 Docker 服务状态
- 检查防火墙和网络配置

### 服务无法启动

恢复后如果服务无法启动：

```bash
# 查看容器日志
docker-compose logs -f

# 检查 Redis 数据完整性
docker-compose exec redis redis-cli ping

# 验证环境配置
docker-compose config
```

## 相关脚本

- `backup-data.sh`: 数据备份脚本
- `restore-data.sh`: 数据恢复脚本
- `auto-update-service.sh`: 自动更新脚本（包含服务重启）

所有脚本都位于项目根目录，具有执行权限。