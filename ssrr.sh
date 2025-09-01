#!/usr/bin/env bash
# ============================================================================
# sspanel 后端对接一键脚本（企业级优化版 / High-Concurrency Ready / AUTO）
# 特色：
#  - 一次性自动对接（可非交互），支持从环境变量或 .env 注入参数
#  - 自清洁：自动去除 CRLF / UTF-8 BOM，避免 “unexpected end of file”
#  - 彻底修复镜像名/标签双拼（统一使用安全 IMAGE_REF），避免 invalid reference format
#  - 预检与修复：Docker/内核/cgroup 检测，daemon.json 安全修复
#  - 高并发优化：ulimit/limits、sysctl（含可选 BBR）、日志轮转、拉取重试
#  - 运行稳健：可选兼容参数（seccomp/cgroupns），自动补齐 IP 列表 CIDR（/32、/128）
# 适用：CentOS7 / Debian / Ubuntu
# ============================================================================
set -Eeuo pipefail

# ---- 自清洁：去掉 Windows CRLF 和 UTF-8 BOM，修复后自我重启 ----
if grep -q $'\r' "$0" 2>/dev/null || [ "$(head -c3 "$0" | od -An -t x1 | tr -d ' \n')" = "efbbbf" ]; then
  sed -i 's/\r$//' "$0" 2>/dev/null || true
  sed -i '1s/^\xEF\xBB\xBF//' "$0" 2>/dev/null || true
  tail -c1 "$0" | read -r _ || printf '\n' >> "$0"
  echo "[self-heal] 已清理 CRLF/BOM，重新执行脚本..."
  exec bash "$0" "$@"
fi

# ---- 自动对接 & 参数来源（不在脚本内硬编码你的信息） ------------------------
# NON_INTERACTIVE=1：若在执行时提供了所需环境变量（见下），脚本将自动部署；
# 若变量缺失，将自动回退到交互式提示（不会把你填的值打印出来）。
NON_INTERACTIVE=${NON_INTERACTIVE:-1}
# 支持在运行时通过环境变量传入（示例）：
# MODE=modwebapi WEBAPI_URL="https://你的域名" WEBAPI_TOKEN="你的token" NODE_ID=123 \
#   ./sspanel_backend.sh

# ---- 全局配置（可按需调整） -------------------------------------------------
APP_NAME="sspanel-backend"
CONTAINER_NAME="ssrmu"
# 仓库与标签分离，避免双冒号
IMAGE_NAME="baiyuetribe/sspanel"
IMAGE_TAG="backend"
DATA_DIR="/opt/${APP_NAME}"
ENV_FILE="${DATA_DIR}/.env"
LOG_DIR="${DATA_DIR}/logs"
# 兼容性增强：遇到容器创建期的 cgroup/seccomp 报错时可开启以下参数
DOCKER_EXTRA_OPTS=(
  --security-opt seccomp=unconfined
  --cgroupns=host
  # 若仍失败，可临时解锁（验证后建议恢复）：
  # --security-opt apparmor=unconfined
  # --privileged
)
# 资源限制（高并发建议放开），按需调整
ULIMIT_NOFILE="1048576:1048576"
MEM_LIMIT=""          # 例："2g"  留空表示不限制
CPU_LIMIT=""          # 例："2"   留空表示不限制

# ---- 颜色/通用 --------------------------------------------------------------
cecho(){ local c="$1"; shift; echo -e "\033[${c}m$*\033[0m"; }
blue(){ cecho "34;01" "$@"; }
green(){ cecho "32;01" "$@"; }
yellow(){ cecho "33;01" "$@"; }
red(){ cecho "31;01" "$@"; }
trap 'rc=$?; red "[ERROR] 第$LINENO行失败，退出码=$rc"; exit $rc' ERR
need_root(){ [[ $EUID -eq 0 ]] || { red "请用 root 运行（sudo -i）"; exit 1; }; }
confirm(){ read -rp "$1 [y/N]: " r; [[ "${r:-N}" =~ ^[Yy]$ ]]; }

# ---- 检测系统/Docker --------------------------------------------------------
detect_os(){ if [[ -f /etc/os-release ]]; then . /etc/os-release; OS_ID=$ID; OS_VER=$VERSION_ID; else OS_ID=unknown; OS_VER=""; fi; yellow "检测到系统：${OS_ID} ${OS_VER}"; }
need_pkg(){ command -v "$1" >/dev/null 2>&1 || { yellow "安装 $1 ..."; case "$OS_ID" in ubuntu|debian) apt-get update -y && apt-get install -y "$1" ;; centos|rhel) yum install -y "$1" ;; *) red "未知系统，无法安装 $1"; exit 1 ;; esac; }; }

install_docker(){
  if command -v docker >/dev/null 2>&1; then green "Docker 已安装"; systemctl enable --now docker || true; return; fi
  yellow "安装 Docker ..."; curl -fsSL https://get.docker.com | bash
  systemctl enable --now docker
  green "Docker 安装完成"
}

# ---- Docker daemon.json 安全修复（不注册保留名 runc） ----------------------
fix_daemon_json(){
  local f=/etc/docker/daemon.json; mkdir -p /etc/docker
  if [[ ! -s "$f" ]]; then
    cat >"$f" <<'EOF'
{
  "default-runtime": "runc",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {"max-size": "50m", "max-file": "3"}
}
EOF
  else
    grep -q 'default-runtime' "$f" || sed -i '1s|^{|{"default-runtime":"runc",|' "$f"
    grep -q 'native.cgroupdriver' "$f" || sed -i '1s|^{|{"exec-opts":["native.cgroupdriver=systemd"],|' "$f"
    grep -q 'log-driver' "$f" || sed -i '1s|^{|{"log-driver":"json-file",|' "$f"
    grep -q 'log-opts' "$f" || sed -i '1s|^{|{"log-opts":{"max-size":"50m","max-file":"3"},|' "$f"
    sed -i '/"runtimes"/,+10{/"runc"/d}' "$f" || true
  fi
  systemctl daemon-reload || true
  systemctl restart docker
}

# ---- 性能优化（高并发推荐，安全默认） -------------------------------------
apply_sysctl(){
  cp -a /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%F-%H%M%S) 2>/dev/null || true
  cat >/etc/sysctl.d/99-${APP_NAME}.conf <<'EOF'
# --- sspanel backend tuning ---
fs.file-max=1048576
net.core.somaxconn=65535
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_syn_backlog=262144
net.ipv4.ip_local_port_range=10000 65000
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_syncookies=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null 2>&1 || sysctl -p || true
}

apply_limits(){
  cat >/etc/security/limits.d/99-${APP_NAME}.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  systemctl set-property docker.service LimitNOFILE=1048576 >/dev/null 2>&1 || true
}

show_cgroup(){ local t; t=$(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo unknown); yellow "cgroup 文件系统: $t (cgroup2fs 表示 v2)"; }

# ---- .env 读写/镜像引用 -----------------------------------------------------
ensure_dirs(){ mkdir -p "$DATA_DIR" "$LOG_DIR"; }
load_env(){ [[ -f "$ENV_FILE" ]] && . "$ENV_FILE" || true; }
_split_image_to_vars(){ local img="$1"; local -n _repo=$2; local -n _tag=$3; _repo="$img"; _tag=""; [[ "$img" == *:* ]] && { _repo="${img%%:*}"; _tag="${img##*:}"; }; }
write_env(){
  local _repo _tag; _split_image_to_vars "$IMAGE_NAME" _repo _tag; [[ -n "${IMAGE_TAG:-}" ]] && _tag="$IMAGE_TAG"
  cat >"$ENV_FILE" <<EOF
# sspanel backend env
MODE=${MODE}
NODE_ID=${NODE_ID}
IMAGE=${_repo}
TAG=${_tag}
# WebAPI
WEBAPI_URL=${WEBAPI_URL:-}
WEBAPI_TOKEN=${WEBAPI_TOKEN:-}
# DB
MYSQL_HOST=${MYSQL_HOST:-}
MYSQL_DB=${MYSQL_DB:-}
MYSQL_USER=${MYSQL_USER:-}
MYSQL_PASS=${MYSQL_PASS:-}
EOF
  chmod 600 "$ENV_FILE"; green "配置已写入：${ENV_FILE}"
}
build_image_ref(){
  local _IMAGE="${IMAGE:-${IMAGE_NAME:-}}"; local _TAG="${TAG:-${IMAGE_TAG:-}}"
  [[ -z "$_IMAGE" ]] && _IMAGE="$IMAGE_NAME"
  if [[ "$_IMAGE" == *:* ]]; then IMAGE_REF="$_IMAGE"; else IMAGE_REF="${_IMAGE}${_TAG:+:${_TAG}}"; fi
}

# ---- 自动“消音”：容器内补齐 CIDR 前缀 --------------------------------------
container_post_patch(){
  yellow "执行容器内 CIDR 补齐（/32,/128）..."
  docker exec -i "${CONTAINER_NAME}" sh -lc '
set -e
f=$(grep -R -l "\"forbidden_ip\"" /root /usr /etc /opt /app 2>/dev/null | head -n1 || true)
[ -z "$f" ] && f=$(find / -maxdepth 3 -type f -name "user-config.json" 2>/dev/null | head -n1 || true)
[ -z "$f" ] && { echo "未找到配置文件，跳过补齐"; exit 0; }
python3 - "$f" <<'PY'
import json, sys
p=sys.argv[1]
with open(p, 'r', encoding='utf-8') as fh:
    d=json.load(fh)
chg=False
keys=["forbidden_ip","forbidden_ip6","white_list","block_list","allow_list"]
def fix(lst):
    global chg
    if not isinstance(lst, list): return lst
    out=[]
    for x in lst:
        if isinstance(x, str):
            s=x.strip()
            if s and '/' not in s:
                s += '/128' if ':' in s else '/32'
                chg=True
            out.append(s)
        else:
            out.append(x)
    return out
for k in keys:
    if k in d: d[k]=fix(d[k])
if chg:
    with open(p,'w',encoding='utf-8') as fh:
        json.dump(d, fh, ensure_ascii=False, indent=2)
    print('patched:', p)
else:
    print('no change:', p)
PY
' || true
}

# ---- 交互配置 & 非交互（从环境变量） ----------------------------------------
configure(){
  blue "选择对接模式：\n  1) WebAPI 对接（推荐）\n  2) 数据库对接"; read -rp "请输入数字(1/2，默认1): " v; v=${v:-1}
  if [[ "$v" == "1" ]]; then
    MODE="modwebapi"; blue "请输入前端网站 URL（示例：https://example.com 或 http://1.2.3.4）"; read -rp "WEBAPI_URL: " WEBAPI_URL
    [[ -z "${WEBAPI_URL}" ]] && { red "WEBAPI_URL 不能为空"; exit 1; }
    read -rp "WEBAPI_TOKEN(默认 NimaQu，直接回车为默认): " WEBAPI_TOKEN; WEBAPI_TOKEN=${WEBAPI_TOKEN:-NimaQu}
  else
    MODE="glzjinmod"; blue "请输入前端数据库信息："; read -rp "MYSQL_HOST: " MYSQL_HOST; read -rp "MYSQL_DB: " MYSQL_DB; read -rp "MYSQL_USER: " MYSQL_USER; read -rp "MYSQL_PASS: " MYSQL_PASS
    [[ -z "${MYSQL_HOST}${MYSQL_DB}${MYSQL_USER}${MYSQL_PASS}" ]] && { red "数据库信息不完整"; exit 1; }
  fi
  read -rp "节点 ID (例如 3): " NODE_ID; [[ -n "${NODE_ID}" && "${NODE_ID}" =~ ^[0-9]+$ ]] || { red "节点 ID 必须为数字"; exit 1; }
  write_env
}

preconfigure(){
  # 从环境变量读取；若缺失则回退到交互式，不在日志中打印值
  MODE="${MODE:-modwebapi}"
  if [[ "$MODE" == "modwebapi" ]]; then
    if [[ -z "${WEBAPI_URL:-}" || -z "${WEBAPI_TOKEN:-}" || -z "${NODE_ID:-}" ]]; then
      yellow "未检测到完整的环境变量，进入交互式配置..."; configure; return
    fi
  else
    if [[ -z "${MYSQL_HOST:-}" || -z "${MYSQL_DB:-}" || -z "${MYSQL_USER:-}" || -z "${MYSQL_PASS:-}" || -z "${NODE_ID:-}" ]]; then
      yellow "未检测到完整的数据库参数，进入交互式配置..."; configure; return
    fi
  fi
  write_env
}

# ---- 生成空白 .env 模板（不含敏感值） -------------------------------------
cmd_init_env_template(){
  ensure_dirs
  if [[ -f "$ENV_FILE" ]]; then
    if ! confirm "${ENV_FILE} 已存在，是否覆盖？"; then return; fi
  fi
  cat >"$ENV_FILE" <<EOF
# sspanel backend env (template)
MODE=modwebapi               # modwebapi / glzjinmod
NODE_ID=
IMAGE=${IMAGE_NAME}
TAG=${IMAGE_TAG}
# WebAPI
WEBAPI_URL=
WEBAPI_TOKEN=
# DB
MYSQL_HOST=
MYSQL_DB=
MYSQL_USER=
MYSQL_PASS=
EOF
  chmod 600 "$ENV_FILE"
  green "已生成模板：$ENV_FILE （请填入你的真实值）"
}

# ---- 容器生命周期 -----------------------------------------------------------
docker_pull_retry(){ local n=0; until docker pull "$1"; do n=$((n+1)); [[ $n -ge 3 ]] && { red "拉取镜像失败：$1"; return 1; }; yellow "拉取失败，重试($n/3)..."; sleep 2; done; }

compose_run_args(){
  RUN_ARGS=(
    --name "${CONTAINER_NAME}"
    --network=host
    --restart=always
    --ulimit "nofile=${ULIMIT_NOFILE}"
    --log-opt max-size=50m --log-opt max-file=3
  )
  [[ -n "$MEM_LIMIT" ]] && RUN_ARGS+=(--memory "$MEM_LIMIT")
  [[ -n "$CPU_LIMIT" ]] && RUN_ARGS+=(--cpus "$CPU_LIMIT")
  RUN_ARGS+=("${DOCKER_EXTRA_OPTS[@]}")
}

docker_run(){
  load_env; [[ -z "${MODE:-}" ]] && { red "未检测到配置，请先执行 安装/配置"; exit 1; }
  build_image_ref; yellow "Using image: ${IMAGE_REF}"; docker_pull_retry "${IMAGE_REF}"
  ENV_ARGS=(-e NODE_ID="${NODE_ID}" -e API_INTERFACE="${MODE}")
  if [[ "$MODE" == "modwebapi" ]]; then ENV_ARGS+=(-e WEBAPI_URL="${WEBAPI_URL}" -e WEBAPI_TOKEN="${WEBAPI_TOKEN}"); else ENV_ARGS+=(-e MYSQL_HOST="${MYSQL_HOST}" -e MYSQL_USER="${MYSQL_USER}" -e MYSQL_DB="${MYSQL_DB}" -e MYSQL_PASS="${MYSQL_PASS}"); fi
  LABELS=(--label "app=${APP_NAME}" --label "mode=${MODE}")
  compose_run_args
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then yellow "检测到旧容器，先移除..."; docker rm -f "${CONTAINER_NAME}" || true; fi
  docker run -d "${RUN_ARGS[@]}" "${LABELS[@]}" "${ENV_ARGS[@]}" "${IMAGE_REF}"
  green "容器已启动：${CONTAINER_NAME}"
  container_post_patch || true
}

docker_start(){ docker start "${CONTAINER_NAME}" && green "已启动" || red "容器不存在"; }
docker_stop(){ docker stop "${CONTAINER_NAME}" && green "已停止" || true; }
docker_restart(){ docker restart "${CONTAINER_NAME}" && green "已重启" || red "容器不存在"; }
docker_status(){ docker ps -a --filter "name=^${CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || true; }
docker_logs(){ docker logs -n 200 -f "${CONTAINER_NAME}"; }

# ---- 一键快速对接（读取现有 /opt/sspanel-backend/.env，直接部署） ---------
cmd_quick(){
  ensure_dirs; need_pkg curl; install_docker; fix_daemon_json
  [[ -s "${ENV_FILE}" ]] || { red "未找到 ${ENV_FILE}，请先执行安装/配置或手动写入 .env"; exit 1; }
  set -a; . "${ENV_FILE}"; set +a   # 只加载，不回显私参
  build_image_ref; yellow "Using image: ${IMAGE_REF}"
  docker_pull_retry "${IMAGE_REF}"
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
  ENV_ARGS=(-e NODE_ID="${NODE_ID}" -e API_INTERFACE="${MODE:-modwebapi}")
  if [[ "${MODE:-modwebapi}" == "modwebapi" ]]; then
    ENV_ARGS+=( -e WEBAPI_URL="${WEBAPI_URL}" -e WEBAPI_TOKEN="${WEBAPI_TOKEN}" )
  else
    ENV_ARGS+=( -e MYSQL_HOST="${MYSQL_HOST}" -e MYSQL_USER="${MYSQL_USER}" -e MYSQL_DB="${MYSQL_DB}" -e MYSQL_PASS="${MYSQL_PASS}" )
  fi
  LABELS=(--label "app=${APP_NAME}" --label "mode=${MODE:-modwebapi}")
  compose_run_args
  docker run -d "${RUN_ARGS[@]}" "${LABELS[@]}" "${ENV_ARGS[@]}" "${IMAGE_REF}"
  green "容器已启动：${CONTAINER_NAME}"
  container_post_patch || true
  docker_status
  echo "------ last 120 log lines ------"
  docker logs --tail=120 "${CONTAINER_NAME}"
}

docker_upgrade(){ load_env; build_image_ref; yellow "升级镜像 ${IMAGE_REF} ..."; docker_pull_retry "${IMAGE_REF}"; docker_stop || true; docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true; docker_run }

cmd_install(){ ensure_dirs; apply_limits; apply_sysctl; fix_daemon_json; show_cgroup; if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then preconfigure; else configure; fi; docker_run; green "安装/部署完成"; }
cmd_uninstall(){ yellow "将卸载容器 ${CONTAINER_NAME}（不删除 ${DATA_DIR} 配置）"; if confirm "确认卸载容器？"; then docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true; green "容器已卸载"; fi; if confirm "同时删除配置与数据目录 ${DATA_DIR}？（不可恢复）"; then rm -rf "${DATA_DIR}"; green "已删除 ${DATA_DIR}"; fi }

menu(){
  clear; blue "=========== sspanel 后端对接 - 企业级优化版 ==========="; cat <<'M'
1) 安装/配置并部署（含系统与 Docker 调优 + 自动消音）
2) 启动
3) 停止
4) 重启
5) 查看状态
6) 查看日志
7) 升级镜像并重建
8) 卸载（可选保留配置）
9) 快速对接（读取现有 .env 直接部署）
10) 生成 .env 模板（空白示例）
0) 退出
M
  read -rp "请选择: " n
  case "${n:-0}" in
    1) need_root; detect_os; need_pkg curl; install_docker; fix_daemon_json; cmd_install ;;
    2) need_root; docker_start ;;
    3) need_root; docker_stop ;;
    4) need_root; docker_restart ;;
    5) docker_status ;;
    6) docker_logs ;;
    7) need_root; docker_upgrade ;;
    8) need_root; cmd_uninstall ;;
    9) need_root; cmd_quick ;;
    10) need_root; cmd_init_env_template ;;
    0) exit 0 ;;
    *) red "无效选择"; sleep 1; menu ;;
  esac
}

# ---- 启动入口：非交互模式优先走 quick（若有 .env），否则 install -----------
if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
  need_root; detect_os; need_pkg curl; install_docker; fix_daemon_json
  if [[ -s "$ENV_FILE" ]]; then
    cmd_quick; exit 0
  else
    cmd_install; exit 0
  fi
else
  menu
fi
