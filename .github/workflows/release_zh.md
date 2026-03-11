# 版本发布说明 (Release Notes)
**统计范围**: `origin/main` ... `HEAD`

## 🚀 新功能 (Features)
- **[架构适配]**: 在 `docker-compose-arm64.yml` 中为所有核心服务强制指定 `linux/arm64` 平台标识，确保在 ARM 架构主机上的部署稳定性 ([d45af27])。

## 🔧 常规维护与发布 (Chore / Release)
- **[版本更新]**: 完成从 `v1.12-dev` 正式切换到 `v1.12` 的全局版本号更新。影响范围涵盖 `VERSION` 文件、`Helm Chart.yaml`、`values.yaml` 以及相关 `README` 说明文档 ([0acc381])。
- **[镜像同步]**: 批量更新 Helm 和 Docker Compose 配置中的镜像版本引用，确保所有应用指向最新的镜像版本标识 ([5e73473])。
