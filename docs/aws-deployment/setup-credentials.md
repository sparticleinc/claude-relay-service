# 步骤1：凭据配置指南

这是部署的第一步，请先完成凭据配置再进行后续步骤。

## ⚠️ 安全提醒

**绝对不要将凭据提交到Git仓库！** 本指南介绍如何安全地管理部署所需的各种凭据。

## 🔐 凭据管理最佳实践

### 1. 本地开发环境

创建 `.secrets` 文件（已在 .gitignore 中）：
```bash
# 复制模板
cp .secrets.example .secrets

# 设置严格权限
chmod 600 .secrets

# 编辑并填入实际凭据
nano .secrets
```

### 2. GitHub Actions配置

在你的Fork仓库中设置Secrets：

1. 进入仓库设置：Settings → Secrets and variables → Actions
2. 添加以下Secrets：
   - `DOCKER_USERNAME`: Docker Hub用户名
   - `DOCKER_PASSWORD`: Docker Hub访问令牌
   - `AWS_ACCESS_KEY_ID`: AWS访问密钥（如使用ECR）
   - `AWS_SECRET_ACCESS_KEY`: AWS密钥

### 3. EC2服务器配置

使用AWS Systems Manager Parameter Store：
```bash
# 存储敏感配置
aws ssm put-parameter \
  --name "/claude-relay/docker-token" \
  --value "your-docker-token" \
  --type "SecureString"

# 在脚本中读取
DOCKER_TOKEN=$(aws ssm get-parameter --name "/claude-relay/docker-token" --with-decryption --query 'Parameter.Value' --output text)
```

## 📝 凭据获取指南

### Docker Hub访问令牌

1. 登录 [Docker Hub](https://hub.docker.com)
2. 点击右上角用户名 → Account Settings
3. Security → New Access Token
4. 设置权限：Read, Write, Delete
5. 保存生成的令牌

### GitHub Personal Access Token

1. 登录 GitHub
2. Settings → Developer settings → Personal access tokens → Tokens (classic)
3. Generate new token
4. 选择权限：repo, workflow
5. 保存令牌

## 🛡️ 安全建议

1. **定期轮换**：每90天更新一次凭据
2. **最小权限**：只授予必要的权限
3. **环境隔离**：开发和生产使用不同凭据
4. **审计日志**：启用访问日志记录
5. **加密存储**：使用密钥管理服务

## 🚀 自动化部署脚本

创建安全的部署脚本 `deploy-with-credentials.sh`：
```bash
#!/bin/bash
set -euo pipefail

# 加载凭据（确保.secrets文件存在且有正确权限）
if [ -f .secrets ]; then
    source .secrets
else
    echo "错误：.secrets 文件不存在"
    echo "请复制 .secrets.example 并填入实际凭据"
    exit 1
fi

# 验证必要的凭据
if [ -z "${DOCKER_USERNAME:-}" ] || [ -z "${DOCKER_TOKEN:-}" ]; then
    echo "错误：缺少必要的Docker凭据"
    exit 1
fi

# Docker登录
echo "$DOCKER_TOKEN" | docker login -u "$DOCKER_USERNAME" --password-stdin

# 构建和推送镜像
IMAGE_NAME="${DOCKER_USERNAME}/claude-relay-service"
VERSION="${1:-latest}"

echo "构建镜像：$IMAGE_NAME:$VERSION"
docker build -t "$IMAGE_NAME:$VERSION" .
docker push "$IMAGE_NAME:$VERSION"

# 清理登录信息
docker logout

echo "部署完成！"
```

## 🔍 凭据泄露应急响应

如果凭据意外泄露：

1. **立即撤销**：
   - Docker Hub：删除并重新创建访问令牌
   - GitHub：撤销并重新生成令牌
   - AWS：使用IAM禁用访问密钥

2. **审查日志**：
   - 检查是否有未授权访问
   - 审查最近的API调用

3. **更新凭据**：
   - 生成新凭据
   - 更新所有使用位置
   - 通知团队成员

4. **加强安全**：
   - 启用2FA
   - 实施IP白名单
   - 增加监控告警

## 📋 检查清单

部署前确认：
- [ ] `.secrets` 文件已创建且权限为600
- [ ] 所有凭据已正确填写
- [ ] `.gitignore` 包含 `.secrets`
- [ ] GitHub Secrets已配置
- [ ] 没有在代码中硬编码凭据
- [ ] 定期轮换计划已制定

记住：安全是持续的过程，而不是一次性的任务。

## ➡️ 下一步

完成凭据配置后，请继续阅读[步骤2：Fork仓库同步策略](fork-sync-strategy.md)。