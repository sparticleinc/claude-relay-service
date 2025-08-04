# 步骤2：Fork仓库同步策略

完成凭据配置后，接下来需要Fork项目并设置同步机制。

## 🎯 核心原则

- **不修改原代码**：通过环境变量配置
- **定期同步更新**：获取bug修复和新功能
- **使用Docker镜像**：避免代码冲突

## 📋 初始设置

### 1. Fork仓库

在GitHub上Fork原仓库：
```
https://github.com/Wei-Shaw/claude-relay-service
```

### 2. 克隆到本地

```bash
# 克隆你的Fork仓库
git clone https://github.com/YOUR_USERNAME/claude-relay-service.git
cd claude-relay-service

# 添加上游仓库
git remote add upstream https://github.com/Wei-Shaw/claude-relay-service.git

# 验证远程仓库
git remote -v
# 应该看到：
# origin    https://github.com/YOUR_USERNAME/claude-relay-service.git (fetch)
# origin    https://github.com/YOUR_USERNAME/claude-relay-service.git (push)
# upstream  https://github.com/Wei-Shaw/claude-relay-service.git (fetch)
# upstream  https://github.com/Wei-Shaw/claude-relay-service.git (push)
```


## 🔄 同步策略

### 手动同步流程

```bash
# 1. 获取上游更新
git checkout main
git fetch upstream

# 2. 查看有哪些更新
git log --oneline main..upstream/main

# 3. 合并更新
git merge upstream/main

# 4. 推送到你的Fork
git push origin main

# 5. 构建新镜像
./docs/aws-deployment/scripts/build-and-push.sh

# 6. 部署到服务器
ssh ec2-user@your-server
./deploy-to-ec2.sh update
```

### 自动同步设置

使用GitHub Actions自动同步（推荐）：

创建 `.github/workflows/sync-upstream.yml`:

```yaml
name: Sync Upstream

on:
  schedule:
    # 每天UTC时间1点执行（北京时间9点）
    - cron: '0 1 * * *'
  workflow_dispatch:  # 允许手动触发

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      with:
        token: ${{ secrets.GITHUB_TOKEN }}
        fetch-depth: 0

    - name: Add upstream
      run: |
        git remote add upstream https://github.com/Wei-Shaw/claude-relay-service.git
        git fetch upstream

    - name: Sync upstream changes
      run: |
        git checkout main
        git merge upstream/main --no-edit
        
    - name: Push changes
      run: |
        git push origin main
        
    - name: Create Pull Request for conflicts
      if: failure()
      uses: peter-evans/create-pull-request@v5
      with:
        title: 'Sync: Merge conflicts with upstream'
        body: |
          自动同步发现冲突，请手动解决。
          
          上游仓库: https://github.com/Wei-Shaw/claude-relay-service
        branch: sync-upstream-conflicts
```

## 🛠️ 最佳实践

### 1. 使用环境变量

所有配置通过 `.env` 文件管理，不修改代码：

```bash
# .env 文件示例
JWT_SECRET=your-company-secret
ADMIN_USERNAME=company_admin
ADMIN_PASSWORD=secure-password
```

### 2. 文档和脚本管理

将公司特定的文档和脚本放在 `docs/` 目录：
- 部署文档
- 自动化脚本
- 内部使用指南

这些内容不会与上游冲突。

## 📊 Docker镜像版本管理

```bash
# 基于上游版本打标签
docker build -t gptbasesparticle/claude-relay-service:v1.0.0 .
docker build -t gptbasesparticle/claude-relay-service:latest .

# 推送到私有仓库
docker push gptbasesparticle/claude-relay-service:v1.0.0
docker push gptbasesparticle/claude-relay-service:latest
```

## ⚠️ 注意事项

### 永远不要做的事

1. ❌ 不要直接在main分支修改源代码
2. ❌ 不要删除或修改上游的文件
3. ❌ 不要更改核心业务逻辑
4. ❌ 不要提交敏感信息到仓库

### 推荐做法

1. ✅ 通过环境变量配置
2. ✅ 使用配置文件覆盖
3. ✅ 保持与上游的兼容性
4. ✅ 定期同步更新
5. ✅ 记录所有定制化内容

## 🔍 冲突解决

当同步时遇到冲突（通常是 package-lock.json）：

```bash
# 1. 使用上游版本
git checkout --theirs package-lock.json

# 2. 重新安装依赖
npm install

# 3. 提交
git add .
git commit -m "Resolve conflicts with upstream"
```

## 📝 总结

- 每周检查一次上游更新
- 使用Docker镜像避免代码冲突
- 通过环境变量配置，不改代码
- 自动化同步和部署流程

## ➡️ 下一步

完成Fork设置后，请继续阅读[步骤3：私有镜像管理](private-registry-guide.md)。