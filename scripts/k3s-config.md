要在一个新的 K3s 环境中同时实现**日志大小限制**、**镜像自动垃圾回收 (GC)** 和**磁盘资源驱逐**，你需要配置 Kubelet 的启动参数。在 K3s 中，最推荐的方式是通过修改配置文件 `/etc/rancher/k3s/config.yaml` 来实现。

以下是完整的配置方案和步骤：

### 1. 配置文件修改方案

请编辑 K3s 的配置文件（如果文件不存在则新建）：

```bash
sudo vim /etc/rancher/k3s/config.yaml
```

将以下内容填入文件。重点在于 `kubelet-arg` 部分，它将参数透传给 Kubelet：

```yaml
# /etc/rancher/k3s/config.yaml

kubelet-arg:
  # ----------------------------------------------------
  # 1. 容器日志限制 (Log Rotation)
  # ----------------------------------------------------
  # 单个日志文件最大 50MiB
  - "container-log-max-size=50Mi"
  # 每个容器最多保留 2 个文件 (1个当前写，1个历史)
  # 总量 = 50Mi * 2 = 100MiB
  - "container-log-max-files=2"

  # ----------------------------------------------------
  # 2. 镜像垃圾回收 (Image Garbage Collection)
  # ----------------------------------------------------
  # 磁盘使用率达到 85% 时，开始删除未使用的镜像
  - "image-gc-high-threshold=85"
  # 删除镜像直到磁盘使用率降到 80% 为止
  - "image-gc-low-threshold=80"
  
  # ----------------------------------------------------
  # 3. 磁盘压力驱逐 (Eviction Policies)
  # ----------------------------------------------------
  # 定义硬性驱逐阈值。如果满足以下任一条件，Kubelet 会立即杀掉 Pod 以释放空间：
  # nodefs.available<10%: 节点文件系统（/var/lib/kubelet）可用空间少于 10%
  # nodefs.inodesFree<5%: 节点 inode 可用少于 5%
  # imagefs.available<15%: 容器运行时文件系统（/var/lib/rancher/k3s/agent/containerd）可用空间少于 15%
  - "eviction-hard=nodefs.available<10%,nodefs.inodesFree<5%,imagefs.available<15%"
  # 设置驱逐信号的最短监测时间（防止瞬间抖动触发驱逐）
  - "eviction-pressure-transition-period=1m"
```

---

### 2. 配置项详细解读

#### A. 限制日志 100MB (`container-log-*`)
Kubelet 自带日志轮转功能。
*   **计算公式**：`max-size` * `max-files` = 最大占用量。
*   **配置**：我们设置每个文件 `50Mi`，保留 `2` 个文件。
*   **效果**：当 `0.log` 写满 50MB 后，会重命名为 `1.log`，并创建新的 `0.log`。如果 `1.log` 之前已经存在，它会被删除。这确保了该容器产生的日志永远不会超过 100MB。

#### B. 自动清理镜像 (`image-gc-*`)
这是 Kubernetes 的镜像垃圾回收机制。
*   **High Threshold (85%)**: 当磁盘使用量超过这个线时，GC 机制启动。
*   **Low Threshold (80%)**: GC 会按照“最近最少使用 (LRU)”的算法删除未使用的镜像，直到磁盘使用率降回这个线以下。
*   **注意**：这只会删除**当前没有容器在运行**的镜像（Unused Images）。

#### C. 磁盘资源驱逐 (`eviction-hard`)
这是最后的防线。如果 GC 清理了镜像后磁盘还是很满，或者磁盘被日志/EmptyDir 填满了：
*   **行为**：Kubelet 会将该节点标记为 `DiskPressure`，禁止新 Pod 调度上来。同时，它会开始**杀死 (Evict)** 节点上正在运行的 Pod，优先杀死资源占用大且非核心的 Pod，直到磁盘空间满足阈值。
*   **nodefs**: 宿主机的主要文件系统。
*   **imagefs**: K3s 存放镜像和容器读写层的文件系统（在 K3s 中通常和 nodefs 是同一个，除非你单独挂载了分区）。

---

### 3. 应用配置

配置完成后，必须重启 K3s 服务才能生效：

**如果是 Master (Server) 节点：**
```bash
sudo systemctl restart k3s
```

**如果是 Worker (Agent) 节点：**
```bash
sudo systemctl restart k3s-agent
```

---

### 4. 验证配置是否生效

重启完成后，你可以通过查看节点详情来验证参数是否成功注入。

执行以下命令：
```bash
kubectl describe node <你的节点名称> | grep -i -E "Limit|Pressure" -A 10
```

或者检查 Kubelet 进程参数：
```bash
ps -ef | grep kubelet
```
你应该能在进程参数中看到 `container-log-max-size=50Mi` 等字样。

### 补充说明
对于日志限制，**该配置只对新创建的容器或重启后的容器生效**。已经正在运行且已经产生了大文件的容器，可能需要重启 Pod 才能应用新的轮转策略。