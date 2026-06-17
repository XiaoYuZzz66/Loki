#!/bin/bash
# ============================================================
# 日志中心 - 183 服务器专用部署脚本
#
# 在 192.168.1.183 上执行，自动完成 Fluent Bit 容器的配置和启动。
# 采集 /usr/projectData/api/ 和 /usr/projectData/admin/ 下的 blm-* 日志。
#
# 用法：
#   bash deploy-183.sh --loki-host <IP> --hostname <name> --env <pre|prod>
#
# 示例：
#   bash deploy-183.sh --loki-host 192.168.1.185 --hostname server-b --env pre
# ============================================================

set -euo pipefail

# ---- 参数默认值 ----
LOKI_HOST=""
HOSTNAME_VAL=""
ENV_VAL="pre"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOY_DIR="/work/log-center-fluent-bit"
FB_IMAGE="fluent/fluent-bit:3.0.7"
LOG_BASE="/usr/projectData"

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- 参数解析 ----
usage() {
    echo "用法: $0 --loki-host <IP> --hostname <name> [--env <pre|prod>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --loki-host)  LOKI_HOST="$2";    shift 2 ;;
        --hostname)   HOSTNAME_VAL="$2"; shift 2 ;;
        --env)        ENV_VAL="$2";      shift 2 ;;
        -h|--help)    usage ;;
        *)            log_error "未知参数: $1"; usage ;;
    esac
done

if [[ -z "$LOKI_HOST" || -z "$HOSTNAME_VAL" ]]; then
    log_error "缺少必要参数"
    usage
fi

# ---- 前置检查 ----
if ! command -v docker &>/dev/null; then
    log_error "未检测到 docker，请先安装 Docker"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    log_error "docker 服务未运行或无权限，请确认 docker daemon 已启动"
    exit 1
fi

# ---- Step 1: 准备部署目录 ----
log_info "准备部署目录: $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# ---- Step 2: 从模板生成配置文件 ----
log_info "从模板生成 Fluent Bit 配置..."

TEMPLATE="$REPO_DIR/fluent-bit/fluent-bit-183.conf.template"
if [[ ! -f "$TEMPLATE" ]]; then
    log_error "模板文件不存在: $TEMPLATE"
    log_error "请确保已将 log-center 目录复制到本机"
    exit 1
fi

sed "s|__LOKI_HOST__|${LOKI_HOST}|g" "$TEMPLATE" > "$DEPLOY_DIR/fluent-bit.conf"
log_info "配置已生成: $DEPLOY_DIR/fluent-bit.conf (Loki Host: $LOKI_HOST)"

# ---- Step 3: 复制 parsers 和 lua 脚本 ----
log_info "复制 parsers.conf 和 map_app_labels_183.lua..."
cp "$REPO_DIR/fluent-bit/parsers.conf"           "$DEPLOY_DIR/parsers.conf"
cp "$REPO_DIR/fluent-bit/map_app_labels_183.lua" "$DEPLOY_DIR/map_app_labels_183.lua"

# ---- Step 4: 检查日志路径是否存在 ----
if [[ ! -d "$LOG_BASE" ]]; then
    log_warn "日志根目录不存在: $LOG_BASE"
    log_warn "Fluent Bit 启动后不会报错，但在目录创建前不会采集任何日志"
fi

# ---- Step 5: 停止并删除旧容器（如有）----
CONTAINER_NAME="log-center-fluent-bit"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "发现旧容器 $CONTAINER_NAME，停止并删除..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

# ---- Step 6: 启动 Fluent Bit 容器 ----
log_info "启动 Fluent Bit 容器..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart=always \
    --net=host \
    -e GAOBAO_HOST="$HOSTNAME_VAL" \
    -e GAOBAO_ENV="$ENV_VAL" \
    -v "$DEPLOY_DIR/fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro" \
    -v "$DEPLOY_DIR/parsers.conf:/fluent-bit/etc/parsers.conf:ro" \
    -v "$DEPLOY_DIR/map_app_labels_183.lua:/fluent-bit/etc/map_app_labels_183.lua:ro" \
    -v "${LOG_BASE}:${LOG_BASE}:ro" \
    --memory=512m \
    --memory-swap=512m \
    "$FB_IMAGE"

log_info "容器已启动，等待 5 秒后检查状态..."
sleep 5

# ---- Step 7: 验证 ----
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "容器启动失败！请查看日志："
    log_error "  docker logs $CONTAINER_NAME"
    exit 1
fi

log_info "检查 Loki 连通性..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${LOKI_HOST}:3100/ready" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    log_info "Loki 连通成功 (HTTP $HTTP_CODE)"
elif [[ "$HTTP_CODE" == "503" ]]; then
    log_warn "Loki 响应 503（正在启动中），连通正常，稍后可重试"
elif [[ "$HTTP_CODE" == "000" ]]; then
    log_error "无法连接 Loki ($LOKI_HOST:3100)，请检查："
    log_error "  1. 防火墙是否放行 3100/tcp"
    log_error "  2. 服务器 A 的 Loki 是否正在运行"
    log_error "  3. IP 地址是否正确"
    exit 1
else
    log_warn "Loki 响应非预期状态码: HTTP $HTTP_CODE"
fi

# ---- 完成 ----
echo ""
log_info "============================================"
log_info "部署完成！"
log_info "  主机标识 : $HOSTNAME_VAL"
log_info "  环境     : $ENV_VAL"
log_info "  Loki     : $LOKI_HOST:3100"
log_info "  容器名   : $CONTAINER_NAME"
log_info "  日志路径 : ${LOG_BASE}/api/*/data/logs/*/*.log"
log_info "             ${LOG_BASE}/admin/*/data/logs/*/*.log"
log_info "             ${LOG_BASE}/admin/data/layer-activity/logs/*/*.log"
log_info "============================================"
log_info ""
log_info "常用命令："
log_info "  查看状态 : docker ps | grep $CONTAINER_NAME"
log_info "  查看日志 : docker logs -f $CONTAINER_NAME"
log_info "  查看指标 : curl http://localhost:2020/api/v1/metrics"
log_info "  重启容器 : docker restart $CONTAINER_NAME"
