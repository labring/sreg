#!/bin/bash
#
# sreg-storage.sh - 对象存储镜像包管理工具（配置文件版本）
#
# 功能：
#   save: 保存镜像到本地、打包并上传到对象存储
#   load: 从对象存储下载或使用本地tar包，解压并同步到目标registry
#
# 使用方式：
#   ./sreg-storage.sh save --config=/path/to/config.yaml
#   ./sreg-storage.sh load --config=/path/to/config.yaml
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查依赖
check_dependencies() {
    local deps=("sreg" "tar" "gzip" "python3")
    if [[ "$1" == "load" ]] || [[ -n "$RCLONE_REMOTE" ]]; then
        deps+=("rclone")
    fi

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "缺少依赖命令: $cmd"
            if [[ "$cmd" == "sreg" ]]; then
                echo "请先构建并安装 sreg:"
                echo "  cd /path/to/sreg && go build -o sreg ."
                echo "  sudo mv sreg /usr/local/bin/"
            elif [[ "$cmd" == "python3" ]]; then
                echo "请安装 Python 3"
                echo "  macOS:   brew install python3"
                echo "  Linux:   sudo apt-get install python3 / yum install python3"
            elif [[ "$cmd" == "rclone" ]]; then
                echo "请安装 rclone:"
                echo "  macOS:   brew install rclone"
                echo "  Linux:   curl https://rclone.org/install.sh | sudo bash"
            fi
            exit 1
        fi
    done

    # 检查 PyYAML
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_error "缺少 Python 模块: PyYAML"
        echo "请安装: pip3 install pyyaml"
        exit 1
    fi
}

# 解析 YAML 配置文件
parse_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "配置文件不存在: $config_file"
        exit 1
    fi

    # 使用 Python 解析 YAML
    python3 <<EOF
import yaml
import sys
import json

try:
    with open('$config_file', 'r') as f:
        config = yaml.safe_load(f)

    # 导出配置为环境变量格式
    if 'rclone' in config:
        print(f"export RCLONE_REMOTE='{config['rclone'].get('remote', '')}'")

    if 'tmp_dir' in config:
        print(f"export TMP_DIR='{config['tmp_dir']}'")

    if 'save' in config:
        save_config = config['save']
        if 'path' in save_config:
            print(f"export RCLONE_PATH='{save_config['path']}'")
        if 'images' in save_config:
            images = save_config['images']
            if isinstance(images, list):
                print(f"export IMAGES='{json.dumps(images)}'")

    if 'load' in config:
        load_config = config['load']
        if 'source' in load_config:
            source = load_config['source']
            if 'remote' in source:
                print(f"export SOURCE_REMOTE='{source['remote']}'")
            if 'local' in source:
                print(f"export SOURCE_LOCAL='{source['local']}'")
        if 'extract_dir' in load_config:
            print(f"export EXTRACT_DIR='{load_config['extract_dir']}'")
        if 'local_registry' in load_config:
            local_reg = load_config['local_registry']
            if 'port' in local_reg:
                print(f"export LOCAL_REGISTRY_PORT='{local_reg['port']}'")
        if 'dest_registry' in load_config:
            dest_reg = load_config['dest_registry']
            if 'url' in dest_reg:
                print(f"export DEST_REGISTRY='{dest_reg['url']}'")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# 加载配置
load_config() {
    local config_file="$1"

    log_info "加载配置文件: $config_file"

    # 解析配置并导出为环境变量
    eval "$(parse_config "$config_file")"

    # 设置默认值
    TMP_DIR="${TMP_DIR:-/tmp/sreg-storage}"
    LOCAL_REGISTRY_PORT="${LOCAL_REGISTRY_PORT:-15001}"

    # 验证必选配置
    if [[ -z "$RCLONE_REMOTE" ]]; then
        log_error "配置文件缺少必选项: rclone.remote"
        exit 1
    fi
}

# 配置 rclone（通过环境变量）
setup_rclone_config() {
    local remote="$1"

    # 检查是否通过环境变量配置了此 remote
    local config_type="RCLONE_CONFIG_${remote^^}_TYPE"

    if [[ -n "${!config_type}" ]]; then
        log_info "使用环境变量配置 rclone remote: $remote"
        return 0
    fi

    # 检查 remote 是否已存在
    if ! rclone listremotes 2>/dev/null | grep -q "^${remote}:$"; then
        log_error "rclone remote \"$remote\" 不存在"
        echo ""
        echo "请使用环境变量配置："
        echo "  export RCLONE_CONFIG_${remote^^}_TYPE=s3"
        echo "  export RCLONE_CONFIG_${remote^^}_ENDPOINT=https://s3.amazonaws.com"
        echo "  export RCLONE_CONFIG_${remote^^}_ACCESS_KEY_ID=your-key"
        echo "  export RCLONE_CONFIG_${remote^^}_SECRET_ACCESS_KEY=your-secret"
        exit 1
    fi

    log_info "使用已配置的 rclone remote: $remote"
}

# 清理临时目录
cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        log_info "清理临时目录: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
}

# save 子命令
cmd_save() {
    local config_file="$1"

    check_dependencies "save"
    load_config "$config_file"
    setup_rclone_config "$RCLONE_REMOTE"

    if [[ -z "$IMAGES" ]]; then
        log_error "配置文件缺少必选项: save.images"
        exit 1
    fi

    # 解析镜像列表
    local images=($(echo "$IMAGES" | python3 -c "import sys, json; print(' '.join(json.load(sys.stdin)))"))

    local timestamp=$(date +%Y%m%d%H%M%S)
    local registry_dir="$TMP_DIR/registry-$timestamp"
    local tar_file="registry-$timestamp.tar.gz"
    local tar_path="$TMP_DIR/$tar_file"

    log_info "开始保存镜像..."
    log_info "镜像列表: ${images[*]}"

    # 1. 保存镜像到本地目录
    log_info "步骤1/4: 保存镜像到本地目录..."
    mkdir -p "$registry_dir"

    local image_list=""
    for img in "${images[@]}"; do
        if [[ -z "$image_list" ]]; then
            image_list="$img"
        else
            image_list="$image_list,$img"
        fi
    done

    if ! sreg save --registry-dir="$registry_dir" --images="$image_list"; then
        log_error "保存镜像失败"
        cleanup
        exit 1
    fi

    # 2. 打包成 tar.gz
    log_info "步骤2/4: 打包镜像目录..."
    cd "$registry_dir"
    if ! tar czf "$tar_path" .; then
        log_error "打包失败"
        cleanup
        exit 1
    fi
    cd - > /dev/null

    local tar_size=$(du -h "$tar_path" | cut -f1)
    log_info "打包完成: $tar_path (大小: $tar_size)"

    # 3. 上传到对象存储
    log_info "步骤3/4: 上传到对象存储..."

    # 构建远程路径
    local remote_path="${RCLONE_REMOTE}:"
    if [[ -n "$RCLONE_PATH" ]]; then
        remote_path="${RCLONE_REMOTE}:${RCLONE_PATH}/$tar_file"
    else
        remote_path="${RCLONE_REMOTE}:$tar_file"
    fi

    if ! rclone copy "$tar_path" "$remote_path" --progress; then
        log_error "上传到对象存储失败"
        cleanup
        exit 1
    fi

    # 4. 输出结果
    log_info "步骤4/4: 完成"
    echo ""
    echo "=========================================="
    log_info "镜像包已成功上传到对象存储"
    echo "------------------------------------------"
    echo "  远程路径: $remote_path"
    echo "  本地路径: $tar_path"
    echo "  文件大小: $tar_size"
    echo "  镜像数量: ${#images[@]}"
    echo "=========================================="
    echo ""

    # 清理registry目录，保留tar文件
    rm -rf "$registry_dir"
}

# load 子命令
cmd_load() {
    local config_file="$1"

    check_dependencies "load"
    load_config "$config_file"

    # 验证必选配置
    if [[ -z "$DEST_REGISTRY" ]]; then
        log_error "配置文件缺少必选项: load.dest_registry.url"
        exit 1
    fi

    if [[ -z "$EXTRACT_DIR" ]]; then
        log_error "配置文件缺少必选项: load.extract_dir"
        exit 1
    fi

    local tar_path=""
    local source_info=""

    # 1. 获取 tar 包
    if [[ -n "$SOURCE_REMOTE" ]]; then
        # 从对象存储下载
        log_info "步骤1/5: 从对象存储下载镜像包..."

        setup_rclone_config "$RCLONE_REMOTE"

        local filename=$(basename "$SOURCE_REMOTE")
        tar_path="$TMP_DIR/$filename"
        source_info="$SOURCE_REMOTE"

        if ! rclone copy "$SOURCE_REMOTE" "$tar_path" --progress; then
            log_error "从对象存储下载失败"
            cleanup
            exit 1
        fi

        local tar_size=$(du -h "$tar_path" | cut -f1)
        log_info "下载完成: $tar_path (大小: $tar_size)"
    elif [[ -n "$SOURCE_LOCAL" ]]; then
        # 使用本地文件
        log_info "步骤1/5: 使用本地镜像包..."
        if [[ ! -f "$SOURCE_LOCAL" ]]; then
            log_error "文件不存在: $SOURCE_LOCAL"
            exit 1
        fi
        tar_path="$SOURCE_LOCAL"
        source_info="$SOURCE_LOCAL"
        local tar_size=$(du -h "$tar_path" | cut -f1)
        log_info "本地文件: $tar_path (大小: $tar_size)"
    else
        log_error "配置文件缺少源文件配置: load.source.remote 或 load.source.local"
        exit 1
    fi

    # 2. 解压tar包
    log_info "步骤2/5: 解压镜像包..."
    mkdir -p "$EXTRACT_DIR"
    if ! tar xzf "$tar_path" -C "$EXTRACT_DIR"; then
        log_error "解压失败"
        cleanup
        exit 1
    fi
    log_info "解压完成: $EXTRACT_DIR"

    # 3. 启动临时本地 registry 服务
    log_info "步骤3/5: 启动临时本地 registry 服务 (端口: $LOCAL_REGISTRY_PORT)..."
    local pid_file="$TMP_DIR/registry.pid"
    local log_file="$TMP_DIR/registry.log"
    mkdir -p $TMP_DIR

    echo "sreg serve filesystem \"$EXTRACT_DIR\" --port=\"$LOCAL_REGISTRY_PORT\" > \"$log_file\" 2>&1 &"

    sreg serve filesystem "$EXTRACT_DIR" --port="$LOCAL_REGISTRY_PORT" > "$log_file" 2>&1 &
    local registry_pid=$!
    echo $registry_pid > "$pid_file"

    # 等待服务启动
    sleep 3
    if ! kill -0 $registry_pid 2>/dev/null; then
        log_error "registry 服务启动失败"
        cat "$log_file"
        cleanup
        exit 1
    fi
    log_info "临时 registry 服务已启动 (PID: $registry_pid, 端口: $LOCAL_REGISTRY_PORT)"

    # 4. 同步到目标 registry
    log_info "步骤4/5: 同步镜像到 $DEST_REGISTRY..."
    local source_registry="localhost:$LOCAL_REGISTRY_PORT"

    if ! sreg sync -a "$source_registry" "$DEST_REGISTRY"; then
        log_warn "同步过程中出现错误（可能是部分镜像已存在）"
    fi

    # 5. 清理并完成
    log_info "步骤5/5: 清理临时文件..."
    if [[ -n "$SOURCE_REMOTE" ]]; then
        rm -f "$tar_path"
    fi

    # 停止临时 registry 服务
    if kill $registry_pid 2>/dev/null; then
        wait $registry_pid 2>/dev/null || true
    fi
    rm -f "$pid_file" "$log_file"

    echo ""
    echo "=========================================="
    log_info "镜像同步完成"
    echo "------------------------------------------"
    echo "  源地址: $source_info"
    echo "  目标: $DEST_REGISTRY"
    echo "=========================================="
    echo ""

    cleanup
}

# 主函数
main() {
    if [[ $# -eq 0 ]]; then
        echo "sreg-storage.sh - 对象存储镜像包管理工具（配置文件版本）"
        echo ""
        echo "用法:"
        echo "  $0 save --config=<配置文件路径>"
        echo "  $0 load --config=<配置文件路径>"
        echo ""
        echo "示例:"
        echo "  $0 save --config=config.yaml"
        echo "  $0 load --config=config.yaml"
        echo ""
        echo "配置文件格式 (YAML):"
        echo "  rclone:"
        echo "    remote: \"myremote\""
        echo "  save:"
        echo "    path: \"my-bucket/backups\""
        echo "    images:"
        echo "      - \"nginx:latest\""
        echo "      - \"redis:7-alpine\""
        echo "  load:"
        echo "    source:"
        echo "      remote: \":myremote:bucket/registry.tar.gz\""
        echo "    extract_dir: \"/tmp/extracted\""
        echo "    local_registry:"
        echo "      port: 15000"
        echo "    dest_registry:"
        echo "      url: \"localhost:5000\""
        echo ""
        echo "请参考 config.yaml 获取完整配置示例"
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        save)
            local config_file=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --config=*)
                        config_file="${1#*=}"
                        shift
                        ;;
                    *)
                        log_error "未知参数: $1"
                        exit 1
                        ;;
                esac
            done

            if [[ -z "$config_file" ]]; then
                log_error "缺少必选参数: --config"
                exit 1
            fi

            cmd_save "$config_file"
            ;;
        load)
            local config_file=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --config=*)
                        config_file="${1#*=}"
                        shift
                        ;;
                    *)
                        log_error "未知参数: $1"
                        exit 1
                        ;;
                esac
            done

            if [[ -z "$config_file" ]]; then
                log_error "缺少必选参数: --config"
                exit 1
            fi

            cmd_load "$config_file"
            ;;
        *)
            log_error "未知命令: $command"
            echo "可用命令: save, load"
            exit 1
            ;;
    esac
}

main "$@"