#!/bin/bash
# ============================================================
# 日志中心 - 远程机器配置更新脚本
#
# 用于在远程机器上更新 Fluent Bit 配置（模板、parsers、lua 脚本），
# 并重启容器使新配置生效。
#
# 用法：
#   bash upgrade-remote.sh
#   bash upgrade-remote.sh --hostname <new-name> --env <new-env>
#
# 说明：
# - 不带参数时，仅更新配置文件（parsers.conf、map_app_labels.lua、
#   fluent-bit.conf 从模板重新生成），保留原有 hostname/env 不变。
# - 带参数时，同时更新 hostname 和 env。
# ============================================================

set -euo pipefail

# ---- 参数默认值（从现有容器读取）----
NEW_HOSTNAME=""
NEW_ENV=""
DEPLOY_DIR="/work/log-center-fluent-bit"
CONTAINER_NAME="log-center-fluent-bit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- 参数解析 ----
while [[ $# -gt 0 ]]; do
    case $1 in
        --hostname) NEW_HOSTNAME="$2"; shift 2 ;;
        --env)      NEW_ENV="$2";      shift 2 ;;
        -h|--help)
            echo "用法: $0 [--hostname <name>] [--env <pre|prod>]"
            exit 0 ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

# ---- 前置检查 ----
if [[ ! -d "$DEPLOY_DIR" ]]; then
    log_error "部署目录不存在: $DEPLOY_DIR"
    log_error "请先执行 deploy-remote.sh 完成初始部署"
    exit 1
fi

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "容器 $CONTAINER_NAME 不存在，请先执行 deploy-remote.sh"
    exit 1
fi

# ---- 读取当前配置（如果未传入新参数）----
if [[ -z "$NEW_HOSTNAME" ]]; then
    NEW_HOSTNAME=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
        | grep "^GAOBAO_HOST=" | cut -d= -f2)
    if [[ -z "$NEW_HOSTNAME" ]]; then
        log_error "无法读取当前 GAOBAO_HOST，请通过 --hostname 参数指定"
        exit 1
    fi
fi

if [[ -z "$NEW_ENV" ]]; then
    NEW_ENV=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
        | grep "^GAOBAO_ENV=" | cut -d= -f2)
    if [[ -z "$NEW_ENV" ]]; then
        log_error "无法读取当前 GAOBAO_ENV，请通过 --env 参数指定"
        exit 1
    fi
fi

# 从当前 fluent-bit.conf 中提取 Loki Host
LOKI_HOST=$(grep -E "^\s+Host\s+" "$DEPLOY_DIR/fluent-bit.conf" 2>/dev/null | awk '{print $2}' | head -1)
if [[ -z "$LOKI_HOST" ]]; then
    log_error "无法从 $DEPLOY_DIR/fluent-bit.conf 中读取 Loki Host"
    exit 1
fi

log_info "当前配置: hostname=$NEW_HOSTNAME, env=$NEW_ENV, loki_host=$LOKI_HOST"

# ---- Step 1: 更新配置文件 ----
log_info "更新 Fluent Bit 配置..."

TEMPLATE="$REPO_DIR/fluent-bit/fluent-bit-remote.conf.template"
if [[ -f "$TEMPLATE" ]]; then
    sed "s|__LOKI_HOST__|${LOKI_HOST}|g" "$TEMPLATE" > "$DEPLOY_DIR/fluent-bit.conf"
    log_info "fluent-bit.conf 已从模板重新生成"
else
    log_warn "模板文件不存在，跳过 fluent-bit.conf 更新"
fi

if [[ -f "$REPO_DIR/fluent-bit/parsers.conf" ]]; then
    cp "$REPO_DIR/fluent-bit/parsers.conf" "$DEPLOY_DIR/parsers.conf"
    log_info "parsers.conf 已更新"
fi

if [[ -f "$REPO_DIR/fluent-bit/map_app_labels.lua" ]]; then
    cp "$REPO_DIR/fluent-bit/map_app_labels.lua" "$DEPLOY_DIR/map_app_labels.lua"
    log_info "map_app_labels.lua 已更新"
fi

# ---- Step 2: 重启容器（如果 hostname/env 有变化）----
CURRENT_HOST=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
    | grep "^GAOBAO_HOST=" | cut -d= -f2)
CURRENT_ENV=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null \
    | grep "^GAOBAO_ENV=" | cut -d= -f2)

NEED_RECREATE=false
if [[ "$CURRENT_HOST" != "$NEW_HOSTNAME" || "$CURRENT_ENV" != "$NEW_ENV" ]]; then
    log_info "检测到 hostname 或 env 变化，需要重建容器..."
    NEED_RECREATE=true
fi

if [[ "$NEED_RECREATE" == "true" ]]; then
    log_info "重建容器以应用新的环境变量..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=always \
        --net=host \
        -e GAOBAO_HOST="$NEW_HOSTNAME" \
        -e GAOBAO_ENV="$NEW_ENV" \
        -v "$DEPLOY_DIR/fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro" \
        -v "$DEPLOY_DIR/parsers.conf:/fluent-bit/etc/parsers.conf:ro" \
        -v "$DEPLOY_DIR/map_app_labels.lua:/fluent-bit/etc/map_app_labels.lua:ro" \
        -v "/work/projectData/gaobao:/work/projectData/gaobao:ro" \
        --memory=256m \
        --memory-swap=256m \
        "fluent/fluent-bit:3.0.7"
else
    log_info "hostname/env 无变化，仅重启容器以加载新配置..."
    docker restart "$CONTAINER_NAME"
fi

sleep 3

# ---- Step 3: 验证 ----
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "============================================"
    log_info "更新完成！"
    log_info "  主机标识 : $NEW_HOSTNAME"
    log_info "  环境     : $NEW_ENV"
    log_info "  Loki     : $LOKI_HOST:3100"
    log_info "============================================"
else
    log_error "容器启动失败！请查看日志："
    log_error "  docker logs $CONTAINER_NAME"
    exit 1
fi
