# sreg - Sealos Registry Tool

sreg is a tool focused on managing Sealos registry. Its goal is to provide a solution that doesn't rely on buildah, allowing for more flexible image management and support for Sealos deployments.

## Installation

You can install sreg by following these steps:

1. Download the latest version of the sreg release package for your operating system: [sreg](https://github.com/labring/sreg/releases)

2. Extract the downloaded release package:
   ```sh
   tar -xzf sreg_0.1.1_linux_amd64.tar.gz
   ```

3. Move the extracted executable to your PATH for global access:
   ```sh
   sudo mv sreg /usr/local/bin/
   ```

## Usage

### Save an Image to a Local File
```sh
sreg save --registry-dir=/tmp/registry1 my-context
```

### Start a Filesystem Image Repository Service
```sh
sreg serve filesystem --port=5000
```

### Start an In-Memory Image Repository Service
```sh
sreg serve inmem --port=5000
```

### Sync an Image to a Different Repository
```sh
sreg sync source-image dst
```

### Copy an Image to a Different Repository
```sh
sreg copy source-image dst
```

## Building Your Own Version

If you wish to build your own version of sreg, you can use [goreleaser](https://goreleaser.com/) for building. Use the following command to build:

```sh
goreleaser build --snapshot --timeout=1h --rm-dist
```

## Why Choose sreg?

sreg's development aims to meet the need for image repository management in Sealos deployments without relying on buildah. It offers a more flexible and secure image management approach. Whether you require stricter image security or more controlled image distribution, sreg is an ideal choice.
