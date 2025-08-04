# 步骤3：私有Docker镜像管理

完成Fork设置后，现在需要构建Docker镜像并推送到私有仓库。

## 🎯 为什么使用私有仓库？

- ✅ **版本管理**：保留历史版本，支持快速回滚
- ✅ **安全控制**：私有镜像避免代码和配置泄露
- ✅ **稳定可靠**：不依赖第三方，完全自主控制
- ✅ **CI/CD集成**：方便自动化构建和部署

## 📦 方案一：使用Docker Hub私有仓库

### 1. 创建私有仓库

1. 登录 [Docker Hub](https://hub.docker.com)
2. 点击 "Create Repository"
3. 选择 "Private" 仓库类型
4. 命名为 `claude-relay-service`

### 2. 配置自动构建

创建 `.github/workflows/docker-build.yml`:

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
    paths-ignore:
      - 'docs/**'
      - '*.md'
  workflow_dispatch:
    inputs:
      version:
        description: 'Version tag (e.g., v1.0.0)'
        required: false
        default: 'latest'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3
      
    - name: Login to Docker Hub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}
    
    - name: Generate tags
      id: tags
      run: |
        TAGS="${{ secrets.DOCKER_USERNAME }}/claude-relay-service:latest"
        if [[ "${{ github.event_name }}" == "workflow_dispatch" && "${{ github.event.inputs.version }}" != "latest" ]]; then
          TAGS="${TAGS},${{ secrets.DOCKER_USERNAME }}/claude-relay-service:${{ github.event.inputs.version }}"
        fi
        if [[ "${{ github.ref }}" == "refs/heads/main" ]]; then
          TAGS="${TAGS},${{ secrets.DOCKER_USERNAME }}/claude-relay-service:main-$(date +%Y%m%d-%H%M%S)"
        fi
        echo "tags=$TAGS" >> $GITHUB_OUTPUT
    
    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.tags.outputs.tags }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        
    - name: Update deployment
      if: github.ref == 'refs/heads/main'
      run: |
        echo "New image pushed: ${{ steps.tags.outputs.tags }}"
        # 这里可以添加触发部署的逻辑
```

### 3. 配置GitHub Secrets

在你的Fork仓库设置中添加：
- `DOCKER_USERNAME`: Docker Hub用户名
- `DOCKER_PASSWORD`: Docker Hub访问令牌（不是密码）

获取Docker Hub访问令牌：
1. 登录Docker Hub
2. Account Settings → Security → New Access Token
3. 给令牌命名并保存

## 🚀 方案二：使用AWS ECR（推荐AWS用户）

### 1. 创建ECR仓库

```bash
# 创建仓库
aws ecr create-repository \
  --repository-name claude-relay-service \
  --image-scanning-configuration scanOnPush=true \
  --region us-west-2

# 获取仓库URI
aws ecr describe-repositories \
  --repository-names claude-relay-service \
  --query 'repositories[0].repositoryUri' \
  --output text
```

### 2. 配置生命周期策略

创建 `ecr-lifecycle-policy.json`:
```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

应用策略：
```bash
aws ecr put-lifecycle-policy \
  --repository-name claude-relay-service \
  --lifecycle-policy-text file://ecr-lifecycle-policy.json
```

### 3. GitHub Actions配置（ECR版本）

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  AWS_REGION: us-west-2
  ECR_REPOSITORY: claude-relay-service

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}
    
    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v2
      
    - name: Build and push
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
        IMAGE_TAG: ${{ github.sha }}
      run: |
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPOSITORY:latest
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
```

## 📋 部署配置更新

### 使用Docker Hub镜像

```yaml
# docker-compose.yml
version: '3.8'
services:
  app:
    image: ${DOCKER_USERNAME}/claude-relay-service:${VERSION:-latest}
    restart: unless-stopped
    # ... 其他配置
```

### 使用ECR镜像

```yaml
# docker-compose.yml
version: '3.8'
services:
  app:
    image: ${ECR_REGISTRY}/claude-relay-service:${VERSION:-latest}
    restart: unless-stopped
    # ... 其他配置
```

部署前登录ECR：
```bash
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $ECR_REGISTRY
```

## 🔄 版本管理策略

### 推荐的标签策略

```bash
# 主要版本
docker tag local-image:latest $REGISTRY/claude-relay-service:v1.0.0
docker tag local-image:latest $REGISTRY/claude-relay-service:v1.0
docker tag local-image:latest $REGISTRY/claude-relay-service:v1
docker tag local-image:latest $REGISTRY/claude-relay-service:latest

# 开发版本
docker tag local-image:latest $REGISTRY/claude-relay-service:dev-$(date +%Y%m%d)

# 特性分支
docker tag local-image:latest $REGISTRY/claude-relay-service:feature-oauth-improvement
```

### 版本回滚

```bash
# 快速回滚到上一个版本
docker-compose down
export VERSION=v1.0.0  # 指定要回滚的版本
docker-compose up -d
```

## 🛡️ 安全最佳实践

### 1. 镜像扫描

```bash
# Docker Hub自动扫描
# 在仓库设置中启用 "Vulnerability Scanning"

# ECR扫描
aws ecr start-image-scan \
  --repository-name claude-relay-service \
  --image-id imageTag=latest

# 查看扫描结果
aws ecr describe-image-scan-findings \
  --repository-name claude-relay-service \
  --image-id imageTag=latest
```

### 2. 多阶段构建优化

更新 `Dockerfile` 减小镜像体积：
```dockerfile
# 构建阶段
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# 运行阶段
FROM node:18-alpine
RUN apk add --no-cache dumb-init
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/app.js"]
```

### 3. 敏感信息处理

永远不要在镜像中包含：
- `.env` 文件
- 私钥或证书
- 硬编码的密码

使用构建参数传递必要信息：
```bash
docker build --build-arg VERSION=$(git describe --tags) -t myimage .
```

## 🚀 自动部署集成

### 部署脚本示例

创建 `deploy.sh`:
```bash
#!/bin/bash
set -e

REGISTRY="${1:-docker.io}"
USERNAME="${2:-your-username}"
VERSION="${3:-latest}"

echo "Deploying Claude Relay Service version: $VERSION"

# 登录到仓库
if [[ "$REGISTRY" == *"amazonaws.com"* ]]; then
  aws ecr get-login-password | docker login --username AWS --password-stdin $REGISTRY
else
  docker login $REGISTRY
fi

# 更新镜像
docker-compose pull

# 重启服务
docker-compose down
docker-compose up -d

# 清理旧镜像
docker image prune -f

echo "Deployment completed!"
```

## 📊 监控和告警

### 监控镜像更新

```bash
# 检查最新镜像
docker pull $REGISTRY/claude-relay-service:latest
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}" | grep claude-relay

# 比较本地和远程镜像
LOCAL_DIGEST=$(docker inspect --format='{{.RepoDigests}}' $IMAGE:latest)
REMOTE_DIGEST=$(docker manifest inspect $IMAGE:latest | jq -r '.config.digest')
```

## 🎯 总结

本项目已配置使用Docker Hub账号：`gptbasesparticle`

主要步骤：
1. 克隆Fork的仓库
2. 使用提供的脚本构建镜像
3. 推送到私有仓库
4. 在EC2上拉取部署

## ➡️ 下一步

镜像准备好后，请继续阅读[步骤4：部署指南](deployment-guide.md)进行实际部署。