#!/usr/bin/env bash
# sspanel 后端对接一键脚本（安全版）
# 作者：为你重构（保留原功能，增强健壮性）
# 系统：CentOS7 / Debian / Ubuntu
# 功能：安装/启动/停止/重启/卸载、日志、WebAPI/DB 对接
set -Eeuo pipefail

APP_NAME="sspanel-backend"
CONTAINER_NAME="ssrmu"
IMAGE_NAME="baiyuetribe/sspanel:backend"
IMAGE_TAG="latest"   # 建议你改成固定 tag，如 2025-08-xx
DATA_DIR="/opt/${APP_NAME}"
ENV_FILE="${DATA_DIR}/.env"
LOG_DIR="${DATA_DIR}/logs"

# ========== 颜色 ==========
cecho(){ local c="$1"; shift; echo -e "\033[${c}m$*\033[0m"; }
blue(){ cecho "34;01" "$@"; }
green(){ cecho "32;01" "$@"; }
yellow(){ cecho "33;01" "$@"; }
red(){ cecho "31;01" "$@"; }

# ========== 断言 ==========
need_root(){
  if [[ $EUID -ne 0 ]]; then
    red "请使用 root 运行：sudo -i 后再执行。"
    exit 1
  fi
}

confirm(){ read -rp "$1 [y/N]: " r; [[ "${r:-N}" =~ ^[Yy]$ ]]; }

# ========== 系统&Docker ==========
detect_os(){
  if [[ -f /etc/os-release ]]; then . /etc/os-release; OS_ID=$ID; OS_VER=$VERSION_ID; else OS_ID="unknown"; OS_VER=""; fi
  yellow "检测到系统：${OS_ID} ${OS_VER}"
}

install_docker(){
  if command -v docker >/dev/null 2>&1; then
    green "Docker 已安装。"
    systemctl enable --now docker || true
    return
  fi
  yellow "正在安装 Docker ..."
  case "$OS_ID" in
    centos|rhel)
      # CentOS 7 EOL，优先尝试官方脚本；失败可手动换源
      curl -fsSL https://get.docker.com | bash || { red "自动安装失败，请手动安装 docker-ce"; exit 1; }
      ;;
    debian|ubuntu)
      curl -fsSL https://get.docker.com | bash || { red "自动安装失败，请手动安装 docker-ce"; exit 1; }
      ;;
    *)
      red "未识别的系统：${OS_ID}，请手动安装 Docker 后重试。"
      exit 1
      ;;
  esac
  systemctl enable --now docker
  green "Docker 安装完成。"
}

# ========== 读取/写入配置 ==========
ensure_dirs(){
  mkdir -p "$DATA_DIR" "$LOG_DIR"
}

write_env(){
  cat > "$ENV_FILE" <<EOF
# sspanel backend env
MODE=${MODE}               # modwebapi / glzjinmod
NODE_ID=${NODE_ID}
IMAGE=${IMAGE_NAME}
TAG=${IMAGE_TAG}
# WebAPI
WEBAPI_URL=${WEBAPI_URL:-}
WEBAPI_TOKEN=${WEBAPI_TOKEN:-}
# DB
MYSQL_HOST=${MYSQL_HOST:-}
MYSQL_DB=${MYSQL_DB:-}
MYSQL_USER=${MYSQL_USER:-}
MYSQL_PASS=${MYSQL_PASS:-}
EOF
  chmod 600 "$ENV_FILE"
  green "配置已写入：${ENV_FILE}"
}

load_env(){
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
}

# ========== 交互对接 ==========
configure(){
  blue "选择对接模式："
  echo "  1) WebAPI 对接（推荐）"
  echo "  2) 数据库对接"
  read -rp "请输入数字(1/2，默认1): " v
  v=${v:-1}
  if [[ "$v" == "1" ]]; then
    MODE="modwebapi"
    blue "请输入前端网站 URL（示例：https://example.com 或 http://1.2.3.4）"
    read -rp "WEBAPI_URL: " WEBAPI_URL
    [[ -z "${WEBAPI_URL}" ]] && { red "WEBAPI_URL 不能为空"; exit 1; }
    read -rp "WEBAPI_TOKEN(默认 NimaQu，直接回车为默认): " WEBAPI_TOKEN
    WEBAPI_TOKEN=${WEBAPI_TOKEN:-NimaQu}
  elif [[ "$v" == "2" ]]; then
    MODE="glzjinmod"
    blue "请输入前端数据库信息："
    read -rp "MYSQL_HOST(例如 127.0.0.1): " MYSQL_HOST
    read -rp "MYSQL_DB(例如 sspanel): " MYSQL_DB
    read -rp "MYSQL_USER(例如 root): " MYSQL_USER
    read -rp "MYSQL_PASS(数据库密码): " MYSQL_PASS
    [[ -z "${MYSQL_HOST}${MYSQL_DB}${MYSQL_USER}${MYSQL_PASS}" ]] && { red "数据库信息不完整"; exit 1; }
  else
    red "输入无效"; exit 1
  fi
  read -rp "节点 ID (例如 3): " NODE_ID
  [[ -z "${NODE_ID}" ]] && { red "节点 ID 不能为空"; exit 1; }
  write_env
}

# ========== 运行容器 ==========
docker_run(){
  load_env
  [[ -z "${MODE:-}" ]] && { red "未检测到配置，请先执行 安装/配置"; exit 1; }

  # 统一可见的 --env
  ENV_ARGS=(
    -e NODE_ID="${NODE_ID}"
    -e API_INTERFACE="${MODE}"
  )

  if [[ "$MODE" == "modwebapi" ]]; then
    ENV_ARGS+=(-e WEBAPI_URL="${WEBAPI_URL}" -e WEBAPI_TOKEN="${WEBAPI_TOKEN}")
  else
    ENV_ARGS+=(
      -e MYSQL_HOST="${MYSQL_HOST}"
      -e MYSQL_USER="${MYSQL_USER}"
      -e MYSQL_DB="${MYSQL_DB}"
      -e MYSQL_PASS="${MYSQL_PASS}"
    )
  fi

  # 你可改为 bridge 并自行 -p 映射；保留 host 以兼容原习惯
  NET_ARG="--network=host"

  # 打标签，便于识别
  LABELS=(--label "app=${APP_NAME}" --label "mode=${MODE}")

  # 拉镜像（指定 tag）
  docker pull "${IMAGE_NAME}:${IMAGE_TAG}"

  # 若已存在同名容器则替换
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    yellow "检测到旧容器，先移除..."
    docker rm -f "${CONTAINER_NAME}" || true
  fi

  docker run -d \
    --name "${CONTAINER_NAME}" \
    "${ENV_ARGS[@]}" \
    ${NET_ARG} \
    --restart=always \
    --log-opt max-size=50m --log-opt max-file=3 \
    "${LABELS[@]}" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

  green "容器已启动：${CONTAINER_NAME}"
}

cmd_install(){
  ensure_dirs
  configure
  docker_run
  green "安装/部署完成。"
}

cmd_start(){ docker start "${CONTAINER_NAME}" && green "已启动"; }
cmd_stop(){ docker stop "${CONTAINER_NAME}" && green "已停止"; }
cmd_restart(){ docker restart "${CONTAINER_NAME}" && green "已重启"; }
cmd_status(){ docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || true; }
cmd_logs(){ docker logs -n 200 -f "${CONTAINER_NAME}"; }

cmd_uninstall(){
  yellow "将卸载容器 ${CONTAINER_NAME}（不删除 ${DATA_DIR} 配置）"
  if confirm "确认卸载容器？"; then
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    green "容器已卸载。"
  fi
  if confirm "同时删除配置与数据目录 ${DATA_DIR} ？（不可恢复）"; then
    rm -rf "${DATA_DIR}"
    green "已删除 ${DATA_DIR}"
  fi
}

menu(){
  clear
  blue "=========== sspanel 后端对接 - 安全版 ==========="
  echo "1) 安装/配置并部署"
  echo "2) 启动"
  echo "3) 停止"
  echo "4) 重启"
  echo "5) 查看状态"
  echo "6) 查看日志"
  echo "7) 卸载（可选保留配置）"
  echo "0) 退出"
  read -rp "请选择: " n
  case "${n:-0}" in
    1) need_root; detect_os; install_docker; cmd_install ;;
    2) need_root; cmd_start ;;
    3) need_root; cmd_stop ;;
    4) need_root; cmd_restart ;;
    5) cmd_status ;;
    6) cmd_logs ;;
    7) need_root; cmd_uninstall ;;
    0) exit 0 ;;
    *) red "无效选择"; sleep 1; menu ;;
  esac
}

menu
