read -p "请输入面板地址："  URL
echo -----------------------------
echo "面板地址为"$URL
echo -----------------------------
echo
read -p "请输入节点ID："  ID
echo -----------------------------
echo "节点ID为"$ID
echo -----------------------------
echo
read -p "请输入面板密钥："  KEY
echo -----------------------------
echo "面板密钥为"$KEY
echo -----------------------------
echo
read -p "请输入监听端口："  port
echo -----------------------------
echo "监听端口为"$port
echo -----------------------------
echo
read -p "回车确定对接....."
tag="SSR_NOED_$port"
docker run -d --name=$tag -e NODE_ID=$ID -e API_INTERFACE=modwebapi -e WEBAPI_URL=$URL -e SPEEDTEST=0 -e WEBAPI_TOKEN=$KEY --log-opt max-size=1000m --log-opt max-file=3 -p $port:$port/tcp -p $port:$port/udp --restart=always origined/ssr:latest
