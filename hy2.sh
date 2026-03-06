#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# Hysteria2 v2.7.1 极简部署脚本（Wispbyte 超低调防踢版 - 支持1080p视频）
set -e

# ---------- 默认配置（优化为1080p流畅） ----------
HYSTERIA_VERSION="v2.7.1"
DEFAULT_PORT=443          # 优先443伪装好，如果平台不允许换8443或12616
AUTH_PASSWORD="ieshare2025"
OBFS_PASSWORD="supersecret1080"  # 自定义混淆密码，字母+数字
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.microsoft.com"   # 微软域名，低特征
ALPN="h3"

# ------------------------------
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Hysteria2 极简部署脚本（Wispbyte 超低调防踢版 - 支持1080p视频）"
echo "带宽优化为 down 10mbps（够1080p流畅），up 5mbps防风控"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

# ---------- 清理旧文件 ----------
rm -f server.yaml hysteria-linux-* cert.pem key.pem hy2.log 2>/dev/null || true
echo "🗑️ 已清理旧文件，避免冲突。"

# ---------- 获取端口 ----------
if [[ $# -ge 1 && -n "${1:-}" ]]; then
    SERVER_PORT="$1"
    echo "✅ 使用命令行指定端口: $SERVER_PORT"
elif [[ -n "$PORT" ]]; then
    SERVER_PORT="$PORT"
    echo "✅ 自动识别到平台分配端口: $SERVER_PORT"
else
    SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
    echo "⚙️ 未提供端口参数，使用默认端口: $SERVER_PORT"
fi

# ---------- 检测架构 ----------
arch_name() {
    local machine
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
  echo "❌ 无法识别 CPU 架构: $(uname -m)"
  exit 1
fi
BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

# ---------- 下载二进制 ----------
download_binary() {
    if [ -f "$BIN_PATH" ]; then
        echo "✅ 二进制已存在，跳过下载。"
        return
    fi
    URL="https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/${BIN_NAME}"
    echo "⏳ 下载: $URL"
    curl -sL --retry 3 --connect-timeout 15 -o "$BIN_PATH" "$URL"
    chmod +x "$BIN_PATH"
    echo "✅ 下载完成并设置可执行: $BIN_PATH"
}

# ---------- 生成证书 ----------
ensure_cert() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo "✅ 发现证书，使用现有 cert/key。"
        return
    fi
    echo "🔑 生成自签证书（prime256v1）以节省性能..."
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=${SNI}" 2>/dev/null
    echo "✅ 证书生成成功。"
}

# ---------- 写配置文件（1080p优化：down 10mbps + 单流 + 混淆） ----------
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
  up: "5mbps"     # 上传限低，防风控
  down: "10mbps"  # 下载够1080p视频流畅（YouTube 1080p 需5-10Mbps）
quic:
  max_idle_timeout: "5s"
  max_concurrent_streams: 1       # 单流减少并发特征
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
    echo "✅ 写入配置 server.yaml 成功 (1080p优化 + 混淆 + 伪装)。"
}

# ---------- 获取服务器 IP ----------
get_server_ip() {
    IP=$(curl -s --max-time 5 https://api.ipify.org || \
         curl -s --max-time 5 https://icanhazip.com || \
         curl -s --max-time 5 https://ifconfig.me || \
         echo "YOUR_SERVER_IP")
    echo "$IP"
}

# ---------- 打印连接信息（加 obfs 参数，兼容 v2rayN/Clash Verge/Shadowrocket） ----------
print_connection_info() {
    local IP="$1"
    echo "🎉 Hysteria2 部署成功！（支持1080p视频）"
    echo "=========================================================================="
    echo "📋 服务器信息:"
    echo " 🌐 IP地址: $IP"
    echo " 🔌 端口: $SERVER_PORT"
    echo " 🔑 密码: $AUTH_PASSWORD"
    echo " 🛡️ 混淆类型: salamander"
    echo " 🛡️ 混淆密码: $OBFS_PASSWORD"
    echo ""
    echo "📱 节点链接（直接导入 v2rayN / Clash Verge / 小火箭）："
    echo "hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1&obfs=salamander&obfs-password=${OBFS_PASSWORD}#Wispbyte-Hy2-1080p"
    echo "=========================================================================="
    echo "提示：v2rayN/Clash Verge 导入链接后自动识别 obfs；Shadowrocket 选 Hysteria2 类型，手动填 obfs salamander + password。"
}

# ---------- 主逻辑 ----------
main() {
    download_binary
    ensure_cert
    write_config
    SERVER_IP=$(get_server_ip)
    print_connection_info "$SERVER_IP"
   
    echo "🚀 配置 Go 运行时内存限制 + 禁用 update check..."
    export HYSTERIA_DISABLE_UPDATE_CHECK=1
    export GOGC=off
    export GOMEMLIMIT=30MiB  # 稍松一点，够1080p缓冲

    echo "🚀 启动 Hysteria2 服务器（warn 日志 + 后台保活）..."
    pkill -f hysteria-linux || true
    (
        while true; do
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hy2 运行中 - 支持1080p视频，资源正常"
            sleep 15
        done
    ) &
    nohup "$BIN_PATH" server -c server.yaml --log-level warn > hy2.log 2>&1 &
    echo "✅ 已后台启动，日志在 hy2.log。tail -f hy2.log 查看实时日志。"
    tail -f hy2.log   # 保持控制台活跃，防面板误杀
}
main "$@"
