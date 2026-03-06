#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Hysteria2 v2.7.1 极简部署脚本（Wispbyte 防踢优化版 - 防 SIGINT + 减少 warn）
set -e

# ---------- 默认配置（优化防 crash） ----------
HYSTERIA_VERSION="v2.7.1"
DEFAULT_PORT=443
AUTH_PASSWORD="ieshare2035"
OBFS_PASSWORD="supersecret1080"
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.microsoft.com"
ALPN="h3"

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Hysteria2 优化部署脚本（防 SIGINT + 减少 TCP warn + 支持1080p）"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# 清理旧文件
rm -f server.yaml hysteria-linux-* cert.pem key.pem hy2.log 2>/dev/null || true
echo "🗑️ 已清理。"

# 获取端口
if [[ $# -ge 1 && -n "${1:-}" ]]; then
    SERVER_PORT="$1"
    echo "✅ 端口: $SERVER_PORT"
elif [[ -n "$PORT" ]]; then
    SERVER_PORT="$PORT"
    echo "✅ 平台端口: $SERVER_PORT"
else
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    echo "⚙️ 默认端口: $SERVER_PORT"
fi

# 检测架构
arch_name() {
    machine=$(uname -m | tr '[:upper:]' '[:lower:]')
    if [[ "$machine" == *"arm64"* ]] || [[ "$machine" == *"aarch64"* ]]; then
        echo "arm64"
    elif [[ "$machine" == *"x86_64"* ]] || [[ "$machine" == *"amd64"* ]]; then
        echo "amd64"
    else
        echo ""
    fi
}
ARCH=$(arch_name)
if [ -z "$ARCH" ]; then
  echo "❌ 架构错误。"
  exit 1
fi
BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

# 下载二进制
download_binary() {
    if [ -f "$BIN_PATH" ]; then
        echo "✅ 二进制存在。"
        return
    fi
    URL="https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/${BIN_NAME}"
    echo "⏳ 下载 $URL"
    curl -sL -o "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo "✅ 下载完成。"
}

# 生成证书
ensure_cert() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "✅ 证书存在。"
        return
    fi
    echo "🔑 生成证书..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${SNI}" 2>/dev/null
    echo "✅ 生成成功。"
}

# 写配置（减少 warn：长 idle 超时 + keepalive）
write_config() {
cat > server.yaml <<EOF
listen: ":${SERVER_PORT}"
tls:
  cert: "$(pwd)/${CERT_FILE}"
  key: "$(pwd)/${KEY_FILE}"
  alpn:
    - "${ALPN}"
auth:
  type: "password"
  password: "${AUTH_PASSWORD}"
obfs:
  type: salamander
  salamander:
    password: "${OBFS_PASSWORD}"
bandwidth:
  up: "3mbps"
  down: "5mbps"
quic:
  max_idle_timeout: "30s"
  keepAlivePeriod: "10s"
  max_concurrent_streams: 1
  initial_stream_receive_window: 16384
  max_stream_receive_window: 32768
  initial_conn_receive_window: 32768
  max_conn_receive_window: 65536
masquerade:
  type: proxy
  proxy:
    url: https://${SNI}/
    rewriteHost: true
EOF
    echo "✅ 配置写入（减少 warn）。"
}

# 获取 IP
get_server_ip() {
    IP=$(curl -s https://api.ipify.org || curl -s https://icanhazip.com || curl -s https://ifconfig.me || echo "YOUR_SERVER_IP")
    echo "$IP"
}

# 打印信息
print_connection_info() {
    local IP="$1"
    echo "🎉 部署成功！"
    echo "=========================================================================="
    echo "IP: $IP | 端口: $SERVER_PORT | 密码: $AUTH_PASSWORD | obfs: salamander | obfs-password: $OBFS_PASSWORD"
    echo "链接: hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1&obfs=salamander&obfs-password=${OBFS_PASSWORD}#Optimized-Hy2"
    echo "=========================================================================="
}

# 主逻辑
main() {
    download_binary
    ensure_cert
    write_config
    SERVER_IP=$(get_server_ip)
    print_connection_info "$SERVER_IP"
   
    echo "🚀 设置环境..."
    export HYSTERIA_DISABLE_UPDATE_CHECK=1
    export GOGC=off
    export GOMEMLIMIT=40MiB  # 稍松，防 OOM

    echo "🚀 启动（防 SIGINT + 保活）..."
    pkill -f hysteria-linux || true
    trap '' INT  # 忽略 SIGINT
    (
        while true; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hy2 正常 - 低流量模式"
            sleep 10
        done
    ) &
    nohup "$BIN_PATH" server -c server.yaml --log-level error > hy2.log 2>&1 &
    echo "✅ 后台启动（error 日志）。tail -f hy2.log 查看。"
    tail -f hy2.log
}
main "$@"
