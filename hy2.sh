#!/usr/bin/env bash
# Hysteria2 一键部署 + 保活 + 自动重启脚本（Wispbyte 优化版）
# 使用：chmod +x hy2.sh && ./hy2.sh 12721

set -e

# ==================== 配置 ====================
PORT=${1:-12721}                       # 你的新端口
PASSWORD="123456"
OBFS_PASS="123456"
SNI="www.microsoft.com"
ALPN="h3"

echo "================================================================"
echo "Hysteria2 部署 + 保活脚本（Wispbyte 优化） - 端口 $PORT"
echo "================================================================"

# 清理
rm -f server.yaml hysteria-linux-* cert.pem key.pem hy2.log 2>/dev/null || true
pkill -f hysteria-linux 2>/dev/null || true

# 下载（amd64/arm64 自适应）
ARCH=$(uname -m | grep -q "aarch64\|arm64" && echo "arm64" || echo "amd64")
BIN="hysteria-linux-$ARCH"
curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/download/app/v2.7.1/$BIN"
chmod +x "$BIN"

# 生成证书
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout key.pem -out cert.pem -subj "/CN=$SNI" 2>/dev/null

# 生成 server.yaml
cat > server.yaml <<EOF
listen: ":$PORT"
tls:
  cert: "$(pwd)/cert.pem"
  key: "$(pwd)/key.pem"
  alpn:
    - "$ALPN"
auth:
  type: "password"
  password: "$PASSWORD"
obfs:
  type: salamander
  salamander:
    password: "$OBFS_PASS"
bandwidth:
  up: "3mbps"
  down: "5mbps"
quic:
  max_idle_timeout: "60s"
  keepAlivePeriod: "20s"
  max_concurrent_streams: 1
masquerade:
  type: proxy
  proxy:
    url: https://$SNI/
    rewriteHost: true
EOF

# 输出节点链接
IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "YOUR_IP")
echo ""
echo "节点链接："
echo "hysteria2://${PASSWORD}@${IP}:${PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1&obfs=salamander&obfs-password=${OBFS_PASS}#Hy2-12721"
echo ""

# ==================== 守护模式 ====================
echo "启动守护模式：每10秒保活，进程退出立即重启"

# 忽略 SIGINT（防平台误发中断）
trap '' INT

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动 Hysteria2..."

    # 前台运行 hysteria（必须前台！不能加 &）
    env HYSTERIA_DISABLE_UPDATE_CHECK=1 GOGC=off GOMEMLIMIT=40MiB \
        ./$BIN server -c server.yaml --log-level error

    # 如果进程退出（被杀或异常），立即重启
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 进程退出 (code $?)，等待 5 秒后重启..."
    sleep 5

    # 保活输出（在循环里每10秒输出一次）
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hy2 运行中 - 低流量模式"
    sleep 5  # 总间隔约10秒
done
