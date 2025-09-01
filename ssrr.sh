# === One-shot：SSPanel 后端 WebAPI 对接（固定你的参数）===
set -Eeuo pipefail

# 你的对接参数（如需改动，按需修改下面四行）
WEBAPI_URL="https://lse112233.icu"
WEBAPI_TOKEN="${WEBAPI_TOKEN:-NimaQu}"
NODE_ID="1104"
MODE="modwebapi"   # modwebapi / glzjinmod

# 镜像固定为“仓库+标签”分离，避免双冒号
IMAGE="baiyuetribe/sspanel"
TAG="backend"
CONTAINER="ssrmu"
ENV_DIR="/opt/sspanel-backend"
ENV_FILE="${ENV_DIR}/.env"

echo "== 1/6 写入环境配置 ${ENV_FILE}"
mkdir -p "${ENV_DIR}" "${ENV_DIR}/logs"
cat > "${ENV_FILE}" <<EOF
# sspanel backend env
MODE=${MODE}
NODE_ID=${NODE_ID}
IMAGE=${IMAGE}
TAG=${TAG}
# WebAPI
WEBAPI_URL=${WEBAPI_URL}
WEBAPI_TOKEN=${WEBAPI_TOKEN}
# DB(留空即可)
MYSQL_HOST=
MYSQL_DB=
MYSQL_USER=
MYSQL_PASS=
EOF
chmod 600 "${ENV_FILE}"

echo "== 2/6 安装并修复 Docker（含 daemon.json）"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | bash
fi
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'JSON'
{
  "default-runtime": "runc",
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
JSON
systemctl daemon-reload || true
systemctl enable --now docker
systemctl restart docker

echo "== 3/6 拉镜像并重建容器"
docker rm -f "${CONTAINER}" 2>/dev/null || true
docker pull "${IMAGE}:${TAG}"

docker run -d \
  --name="${CONTAINER}" \
  --network=host \
  --restart=always \
  --ulimit nofile=1048576:1048576 \
  --security-opt seccomp=unconfined \
  --cgroupns=host \
  -e NODE_ID="${NODE_ID}" \
  -e API_INTERFACE="${MODE}" \
  -e WEBAPI_URL="${WEBAPI_URL}" \
  -e WEBAPI_TOKEN="${WEBAPI_TOKEN}" \
  --log-opt max-size=50m --log-opt max-file=3 \
  "${IMAGE}:${TAG}"

echo "== 4/6（可选）补齐容器内 CIDR 前缀，消除 WARNING"
docker exec -i "${CONTAINER}" sh -lc '
set -e
f=$(grep -R -l "\"forbidden_ip\"" /root /usr /etc /opt /app 2>/dev/null | head -n1 || true)
[ -z "$f" ] && f=$(find / -maxdepth 3 -type f -name "user-config.json" 2>/dev/null | head -n1 || true)
[ -z "$f" ] && { echo "未找到 user-config.json，跳过"; exit 0; }
python3 - <<PY "$f"
import json, sys
p=sys.argv[1]
with open(p,"r",encoding="utf-8") as fh: d=json.load(fh)
chg=False
def fix(lst):
    global chg
    if not isinstance(lst, list): return lst
    out=[]
    for x in lst:
        if isinstance(x,str):
            s=x.strip()
            if s and "/" not in s:
                s += "/128" if ":" in s else "/32"
                chg=True
            out.append(s)
        else: out.append(x)
    return out
for k in ("forbidden_ip","forbidden_ip6","white_list","block_list","allow_list"):
    if k in d: d[k]=fix(d[k])
if chg:
    with open(p,"w",encoding="utf-8") as fh: json.dump(d,fh,ensure_ascii=False,indent=2)
    print("patched:", p)
else:
    print("no change:", p)
PY
' || true
docker restart "${CONTAINER}" >/dev/null

echo "== 5/6 系统调优（一次性，已设置过可忽略错误）"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y chrony >/dev/null 2>&1 || true
systemctl enable --now chronyd >/dev/null 2>&1 || true
cat >/etc/sysctl.d/99-sspanel.conf <<'SYS'
fs.file-max=1048576
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=262144
net.ipv4.ip_local_port_range=10000 65000
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_keepalive_time=600
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
SYS
sysctl --system >/dev/null 2>&1 || true
systemctl set-property docker.service LimitNOFILE=1048576 >/dev/null 2>&1 || true

echo "== 6/6 运行状态与关键日志（看到 start server at port 即对接成功）"
docker ps --filter "name=${CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
docker logs --tail=80 "${CONTAINER}"
