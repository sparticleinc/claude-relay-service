# .env.local 使用说明

## 概述

`.env.local` 文件用于存储本地敏感配置信息，不会被提交到版本控制系统。

## 使用场景

### 1. 自动更新脚本 (auto-update-service.sh)

自动更新脚本需要 Docker Hub 认证信息来推送镜像。

**配置步骤：**

1. 复制示例文件：
```bash
cp .env.local.example .env.local
```

2. 编辑 `.env.local` 文件，设置你的 Docker Hub 认证信息：
```bash
# Docker Hub 认证信息
DOCKER_HUB_USERNAME=your-dockerhub-username
DOCKER_HUB_TOKEN=your-dockerhub-access-token
```

3. 获取 Docker Hub Access Token：
   - 登录 [Docker Hub](https://hub.docker.com/)
   - 进入 Account Settings → Security
   - 点击 "New Access Token"
   - 设置权限为 "Read, Write, Delete"
   - 复制生成的 token

### 2. 定时任务配置 (setup-cron.sh)

`setup-cron.sh` 脚本会自动配置 crontab，在执行自动更新前加载 `.env.local`：

```bash
# 设置定时任务
./setup-cron.sh

# crontab 会添加类似这样的任务：
22 10 * * * source /path/to/.env.local && /path/to/auto-update-service.sh
```

### 3. 手动执行脚本

手动执行自动更新脚本时，脚本会自动加载 `.env.local`：

```bash
# 直接执行即可，无需手动 source
./auto-update-service.sh
```

## 文件优先级

1. `.env.local` - 最高优先级，本地配置
2. 环境变量 - 系统环境变量
3. `.env` - 默认配置

## 安全注意事项

- **永远不要** 将 `.env.local` 提交到版本控制
- 定期更新 Docker Hub Access Token
- 确保文件权限正确：`chmod 600 .env.local`

## 故障排除

### 环境变量未加载

检查日志文件：
```bash
tail -f logs/auto-update.log
```

日志中应该显示：
```
[2024-01-01 10:22:00] 已加载环境变量文件: /path/to/.env.local
[2024-01-01 10:22:00] Docker Hub 认证信息已配置
```

### Docker Hub 登录失败

1. 验证 token 是否有效
2. 检查 token 权限是否正确
3. 确认用户名拼写正确

### 调试模式

可以在脚本开头添加调试输出：
```bash
# 编辑 auto-update-service.sh
set -ex  # 添加 -x 显示执行的命令
```