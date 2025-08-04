# AWS部署指南

为公司内部使用Claude Relay Service提供简单实用的AWS部署方案。

## 🚀 快速开始

本方案专注于简单实用，使用单EC2实例 + Docker部署，适合10-50人内部使用。

## 📋 阅读顺序

请按照以下顺序阅读文档：

### 第一步：准备工作
1. [**凭据配置**](setup-credentials.md) - 首先配置好GitHub和Docker Hub凭据

### 第二步：代码准备
2. [**Fork仓库同步**](fork-sync-strategy.md) - Fork项目并设置同步机制
3. [**私有镜像管理**](private-registry-guide.md) - 了解如何使用Docker Hub私有仓库

### 第三步：部署实施
4. [**部署指南**](deployment-guide.md) - 按步骤在EC2上部署服务

### 辅助工具
- [`scripts/build-and-push.sh`](scripts/build-and-push.sh) - 构建并推送Docker镜像
- [`scripts/deploy-to-ec2.sh`](scripts/deploy-to-ec2.sh) - EC2服务器部署脚本

## 🎯 方案特点

- **简单易用**：30分钟完成部署
- **成本优化**：单EC2实例，月成本约$30
- **安全可靠**：使用私有Docker仓库
- **易于维护**：提供自动化脚本

## 📊 架构概览

```
公司内部用户 → VPN/内网 → EC2实例(Docker) → Claude API
                              ↓
                         Redis(本地容器)
```

## 🔧 技术栈

- **服务器**：AWS EC2 (t3.medium)
- **容器**：Docker + Docker Compose
- **镜像仓库**：Docker Hub私有仓库
- **数据存储**：Redis容器
- **反向代理**：Nginx/Caddy（可选）

## 💡 部署流程概览

整个部署流程分为4个阶段：

**阶段1：准备凭据** → **阶段2：Fork和配置仓库** → **阶段3：构建Docker镜像** → **阶段4：部署到EC2**

具体步骤：
1. 配置GitHub和Docker Hub访问凭据
2. Fork原项目到自己的GitHub账号
3. 构建Docker镜像并推送到私有仓库
4. 在AWS EC2上部署服务
5. 设置日常维护流程

## 🛡️ 安全建议

- 限制EC2安全组只允许公司IP访问
- 使用HTTPS（Caddy自动配置）
- 定期备份数据
- 使用强密码和密钥

## 📞 开始部署

**第一步**：从[凭据配置](setup-credentials.md)开始，按照文档顺序逐步完成部署。

预计总时间：30-45分钟

---

**注意**：本方案已针对公司内部使用优化，避免了不必要的复杂性。如需更复杂的架构（如ECS、负载均衡等），请参考AWS官方文档。