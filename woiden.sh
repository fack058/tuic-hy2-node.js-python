#!/usr/bin/env bash
# Hysteria2 一键部署 + Systemd 后台运行 + 极致安全防封版 (Woiden IPv6)
# 使用：chmod +x hy2.sh && ./hy2.sh

set -e

# ==================== 基础配置 ====================
PORT=${1:-12616}
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "错误：端口必须是 1-65535 之间的数字"
    exit 1
fi

# 极致安全：自动生成 24 位高强度随机密码，防止 GFW 主动探测
PASSWORD=$(openssl rand -hex 12)
OBFS_PASS=$(openssl rand -hex 12)

# 更换为大陆连通性更好、白名单权重极高的苹果云服务域名
SNI="gateway.icloud.com"
ALPN="h3"

echo "================================================================"
echo "Hysteria2 极致安全版部署 - 端口 $PORT"
echo "正在生成高强度加密凭证..."
echo "================================================================"

# 清理旧文件和进程
rm -f server.yaml hysteria-linux-* cert.pem key.pem hy2.log 2>/dev/null || true
pkill -f hysteria-linux 2>/dev/null || true

# 下载主程序
ARCH=$(uname -m | grep -q "aarch64\|arm64" && echo "arm64" || echo "amd64")
BIN="hysteria-linux-$ARCH"
curl -L -o "$BIN" "https://ghfast.top/https://github.com/apernet/hysteria/releases/download/app/v2.7.1/$BIN" || { echo "下载失败"; exit 1; }
chmod +x "$BIN"

# 生成自签名证书
openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout key.pem -out cert.pem -subj "/CN=$SNI" 2>/dev/null

# 生成高安全级 server.yaml
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
  up: "20mbps"
  down: "20mbps"
quic:
  max_idle_timeout: "60s"
  keepAlivePeriod: "20s"
  max_concurrent_streams: 1
masquerade:
  type: proxy
  proxy:
    url: https://www.apple.com/
    rewriteHost: true
EOF

# 获取 IP 并处理纯 IPv6 的方括号问题
IP=$(curl -6 -s ifconfig.co || curl -s ifconfig.me || echo "YOUR_IP")
if [[ "$IP" == *":"* ]]; then
    URL_IP="[$IP]"
else
    URL_IP="$IP"
fi

echo ""
echo "✅ 你的专属超高安全节点链接（请妥善保存，密码已随机化）："
echo "----------------------------------------------------------------"
echo "hysteria2://${PASSWORD}@${URL_IP}:${PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1&obfs=salamander&obfs-password=${OBFS_PASS}#Hy2-Safe"
echo "----------------------------------------------------------------"
echo ""

# ==================== 注册为系统服务 ====================
echo "正在配置 Systemd 服务，实现后台运行与开机自启..."

cat > /etc/systemd/system/hy2.service <<EOF
[Unit]
Description=Hysteria2 Secure Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$(pwd)
Environment="HYSTERIA_DISABLE_UPDATE_CHECK=1"
Environment="GOGC=off"
Environment="GOMEMLIMIT=40MiB"
ExecStart=$(pwd)/$BIN server -c $(pwd)/server.yaml --log-level error
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 重新加载配置并启动服务
systemctl daemon-reload
systemctl enable hy2
systemctl restart hy2

echo "🎉 极致安全版部署彻底完成！服务已在后台隐蔽运行。"
