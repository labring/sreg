# sreg - Sealos 镜像仓库工具

sreg 是一个专注于 Sealos 镜像仓库管理的工具，它的目标是提供一个不依赖于 buildah 的解决方案，以便更灵活地管理镜像，并为 Sealos 部署提供支持。

## 安装

您可以通过以下步骤来安装 sreg：

1. 下载适用于您的操作系统的最新版本 sreg 发布包：[sreg](https://github.com/labring/sreg/releases)

2. 解压下载的发布包：
   ```sh
   tar -xzf sreg_0.1.1_linux_amd64.tar.gz
   ```

3. 将解压后的可执行文件移动到您的 PATH 中，以使其可以全局访问：
   ```sh
   sudo mv sreg /usr/local/bin/
   ```

## 使用方法

### 保存镜像到本地文件
```sh
sreg save --registry-dir=/tmp/registry1 my-context
```

### 启动文件系统镜像仓库服务
```sh
sreg serve filesystem --port=5000
```

### 启动内存中的镜像仓库服务
```sh
sreg serve inmem --port=5000
```

### 同步镜像到不同仓库
```sh
sreg sync source-image dst
```

### 复制镜像到不同仓库
```sh
sreg copy source-image dst
```

## 构建自己的版本

如果您希望构建自己的 sreg 版本，您可以使用 [goreleaser](https://goreleaser.com/) 进行构建。使用以下命令进行构建：

```sh
goreleaser build --snapshot --timeout=1h --rm-dist
```

## 为什么选择 sreg？

sreg 的开发旨在满足在 Sealos 部署中无需依赖 buildah 的镜像仓库需求，提供了更灵活和安全的镜像管理方式。无论您需要更严格的镜像安全性还是更受控的镜像分发，sreg 都是理想的选择。
