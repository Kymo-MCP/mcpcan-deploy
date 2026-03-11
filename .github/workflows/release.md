# Release Notes
**Range**: `origin/main` ... `HEAD`

## 🚀 Features
- **[Architecture Adaptation]**: Explicitly specified `linux/arm64` platform tags for all core services in `docker-compose-arm64.yml`, ensuring stable deployment on ARM-based hosts ([d45af27]).

## 🔧 Chore / Release
- **[Version Update]**: Completed global version update from `v1.12-dev` to `v1.12`. Affected files include `VERSION`, `Helm Chart.yaml`, `values.yaml`, and related `README` documentation ([0acc381]).
- **[Image Sync]**: Batched updates of image version references in Helm and Docker Compose configurations, ensuring all applications point to the latest image versions ([5e73473]).
