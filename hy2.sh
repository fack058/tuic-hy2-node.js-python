#!/usr/bin/env bash
# Hysteria2 一键部署 + 保活 + 每3分钟强制重启脚本
# 保存为 hy2.sh 后：chmod +x hy2.sh && ./hy2.sh 12616

set -e

# ==================== 配置 ====================
PORT=${1:-12616}                       # 默认端口，可命令行指定
PASSWORD="ieshare2035"                 # 认证密码
OBFS_PASS="supersecret1080"            # salamander 混淆密码
SNI="www.microsoft.com"                # 伪装域名

# ==============================================

echo "================================================================"
echo "开始部署 Hysteria2 (端口 $PORT)"
echo "================================================================"

# 清理旧文件和进程
rm -f server.yaml hysteria-linux-* cert.pem key.pem hy2.log 2>/dev/null || true
pkill -f hysteria-linux 2>/dev/null || true

# 下载最新 hysteria (amd64/arm64 自适应)
ARCH=$(uname -m | grep -q "aarch64\|arm64" && echo "arm64" || echo "amd64")
BIN="hysteria-linux-$ARCH"
curl -L -o "$BIN" "https://github.com/apernet/hysteria/releases/download/app/v2.7.1/$BIN"
chmod +x "$BIN"

# 生成自签证书
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout key.pem -out cert.pem -subj "/CN=$SNI" 2>/dev/null

# 生成 server.yaml
cat > server.yaml <<EOF
listen: ":$PORT"
tls:
  cert: "$(pwd)/cert.pem"
  key: "$(pwd)/key.pem"
  alpn:
    - "h3"
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
echo "hysteria2://${PASSWORD}@${IP}:${PORT}?sni=${SNI}&alpn=h3&insecure=1&obfs=salamander&obfs-password=${OBFS_PASS}#Hy2-12616"
echo ""

# ==================== 守护循环 ====================
echo "启动守护模式：每10秒保活，每180秒强制重启"

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动 Hysteria2..."

    # 启动 hysteria
    env HYSTERIA_DISABLE_UPDATE_CHECK=1 GOGC=off GOMEMLIMIT=40MiB \
        ./$BIN server -c server.yaml --log-level error &
    PID=$!

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PID: $PID"

    # 保活 + 定时重启循环
    for ((i=0; i<180; i+=10)); do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hy2 运行中 - 低流量模式"
        sleep 10

        # 检查进程是否还活着
        if ! kill -0 $PID 2>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 进程已退出，立即重启..."
            break
        fi
    done

    # 强制杀掉旧进程
    kill $PID 2>/dev/null || true
    pkill -f "$BIN" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 强制重启完成"
done
