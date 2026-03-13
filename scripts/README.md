# scripts 使用说明

`scripts/` 目录用于构建并运行 `sreg-storage.sh` 镜像，完成镜像包的对象存储备份与恢复。

## 目录说明

- `Dockerfile.sreg-storage`: 构建 `sreg-storage.sh` 运行镜像
- `sreg-storage.sh`: 保存和加载镜像包的主脚本
- `job-save.example.yaml`: Kubernetes 单次保存任务示例
- `job-load.example.yaml`: Kubernetes 单次加载任务示例

## 1. 构建镜像

在仓库根目录执行：

```bash
docker build -f scripts/Dockerfile.sreg-storage -t your-registry/sreg-storage:latest .
docker push your-registry/sreg-storage:latest
```

如果需要固定版本，建议改为显式 tag：

```bash
docker build -f scripts/Dockerfile.sreg-storage -t your-registry/sreg-storage:v1.0.0 .
docker push your-registry/sreg-storage:v1.0.0
```

## 2. 创建一次性 Job

这两个示例都是 `kind: Job`，天然就是单次启动执行，不会周期性重复。

如果希望任务完成若干天后由集群自动清理，可以设置：

```yaml
spec:
  ttlSecondsAfterFinished: 604800
```

计算方式：

- `1` 天 = `86400`
- `3` 天 = `259200`
- `7` 天 = `604800`
- `30` 天 = `2592000`

前提条件：

- Kubernetes 需要开启 TTL-after-finished 控制器
- 集群版本通常需要 `batch/v1 Job + ttlSecondsAfterFinished` 支持

示例默认启用了主机网络：

```yaml
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
```

适用场景：

- 任务需要直接访问宿主机可见的 registry 或对象存储地址
- 临时本地 registry 需要通过宿主机网络暴露
- 集群 CNI 网络到目标地址存在限制

## 3. 保存镜像到对象存储

参考示例文件 [job-save.example.yaml](/Users/huaijiahui/go/src/github.com/bxy4543/sreg/scripts/job-save.example.yaml)。

执行：

```bash
kubectl apply -f scripts/job-save.example.yaml
kubectl get job sreg-storage-save
kubectl logs -l job-name=sreg-storage-save -f
```

示例包含以下内容：

- 一个单次执行的 `Job`
- 一个 `ConfigMap`，挂载 `config.yaml`
- `ttlSecondsAfterFinished`，用于任务完成后延迟删除
- `hostNetwork: true`，用于使用宿主机网络访问外部服务

注意：

- 示例 YAML 为可直接应用的静态文件，`access_key_id` 和 `secret_access_key` 需要按实际环境手动替换
- 如果你希望密钥来自 `Secret`，建议在发布流程中使用 Helm、Kustomize 或 CI 模板渲染后再生成最终 YAML

`save` 配置关注点：

- `rclone.remote`: remote 名称
- `rclone.config`: 运行时创建 remote 所需配置
- `save.path`: 对象存储 bucket/目录
- `save.images`: 要打包保存的镜像列表

## 4. 从对象存储加载镜像

参考示例文件 [job-load.example.yaml](/Users/huaijiahui/go/src/github.com/bxy4543/sreg/scripts/job-load.example.yaml)。

执行：

```bash
kubectl apply -f scripts/job-load.example.yaml
kubectl get job sreg-storage-load
kubectl logs -l job-name=sreg-storage-load -f
```

`load` 配置关注点：

- `load.source.remote`: 对象存储中的 tar.gz 完整路径
- `load.extract_dir`: 解压目录
- `load.local_registry.port`: 临时 registry 监听端口
- `load.dest_registry.url`: 要同步到的目标 registry

## 5. 配置约束

`rclone.config` 建议直接写在 `config.yaml` 中，由脚本在运行时执行 `rclone config create`。

例如：

```yaml
rclone:
  remote: "myremote"
  config:
    # 顶层写法也兼容，脚本会自动按运行参数处理
    no_check_certificate: true
    s3-no-check-bucket: true
    type: "s3"
    provider: "Other"
    endpoint: "https://objectstorage.example.com"
    access_key_id: "admin"
    secret_access_key: "secret"
    override:
      no_check_certificate: true
      s3-no-check-bucket: true
```

推荐将运行时开关放在 `override` 或 `global` 下；如果直接写在 `rclone.config` 顶层，当前脚本也会兼容处理。

如果对象存储使用自签名证书，需确认：

- 服务端证书域名与访问域名一致
- 证书链完整
- 或显式允许跳过证书校验

如果对象存储不支持 bucket 存在性探测，需同时启用：

- `s3-no-check-bucket: true`

## 6. 清理与排查

查看任务：

```bash
kubectl get jobs
kubectl get pods -l job-name=sreg-storage-save
kubectl get pods -l job-name=sreg-storage-load
```

查看日志：

```bash
kubectl logs -l job-name=sreg-storage-save -f
kubectl logs -l job-name=sreg-storage-load -f
```

手动删除：

```bash
kubectl delete -f scripts/job-save.example.yaml
kubectl delete -f scripts/job-load.example.yaml
```
