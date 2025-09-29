#!/usr/bin/env bash
# quick_proxy.sh — quickly set up a proxy server from a hysteria2 link and register as system proxy
set -euo pipefail

chmod +x hysteria

# Create logs directory if it doesn't exist
LOGS_DIR="./logs"
mkdir -p "$LOGS_DIR"

# Global variables for cleanup
HY_PID=""
ORIGINAL_PROXY_SETTINGS=""
PROXY_ENABLED=false

# Cleanup function
cleanup() {
    echo "Cleaning up..."

    # Stop hysteria process
    if [[ -n "${HY_PID:-}" ]]; then
        echo "Stopping hysteria client (PID: $HY_PID)..."
        kill $HY_PID 2>/dev/null || true
    fi

    # Restore original proxy settings if we changed them
    if [[ "$PROXY_ENABLED" == true ]]; then
        echo "Restoring original proxy settings..."
        restore_system_proxy
    fi

    # Clean up temporary files
    rm -f tmp.json
    if [[ -f "hysteria.log" ]]; then
        rm -f hysteria.log
    fi

    echo "Cleanup completed."
}

# Set trap for cleanup on exit and signals
trap cleanup EXIT INT TERM

# Logging functions
log_failure() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOGS_DIR/quick_proxy_failures.log"
    echo "[$timestamp] FAILED: URI=$URI, HOST=$HOST, PORT=$PORT, AUTH=$AUTH, ERROR=$1" >> "$log_file"
    echo "[$timestamp] Hysteria log:" >> "$log_file"
    if [[ -f "hysteria.log" ]]; then
        tail -20 "hysteria.log" >> "$log_file"
    fi
    echo "---" >> "$log_file"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$LOGS_DIR/quick_proxy_success.log"
    echo "[$timestamp] SUCCESS: URI=$URI, HOST=$HOST, PORT=$PORT, AUTH=$AUTH, STATUS=$1" >> "$log_file"
}

# System proxy management functions
detect_desktop_environment() {
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        echo "$XDG_CURRENT_DESKTOP"
    elif [[ -n "${DESKTOP_SESSION:-}" ]]; then
        echo "$DESKTOP_SESSION"
    elif [[ -n "${GDMSESSION:-}" ]]; then
        echo "$GDMSESSION"
    else
        echo "unknown"
    fi
}

set_system_proxy_gnome() {
    local proxy_host="$1"
    local proxy_port="$2"

    echo "Setting GNOME system proxy..."

    # Enable manual proxy mode
    gsettings set org.gnome.system.proxy mode 'manual'

    # Set SOCKS proxy
    gsettings set org.gnome.system.proxy.socks host "$proxy_host"
    gsettings set org.gnome.system.proxy.socks port "$proxy_port"

    # Enable SOCKS proxy for all protocols
    gsettings set org.gnome.system.proxy.http host "$proxy_host"
    gsettings set org.gnome.system.proxy.http port "$proxy_port"
    gsettings set org.gnome.system.proxy.https host "$proxy_host"
    gsettings set org.gnome.system.proxy.https port "$proxy_port"
    gsettings set org.gnome.system.proxy.ftp host "$proxy_host"
    gsettings set org.gnome.system.proxy.ftp port "$proxy_port"

    echo "✅ GNOME proxy settings updated"
}

restore_system_proxy_gnome() {
    echo "Restoring GNOME proxy settings..."
    gsettings set org.gnome.system.proxy mode 'none'
    echo "✅ GNOME proxy settings restored"
}

set_system_proxy_kde() {
    local proxy_host="$1"
    local proxy_port="$2"

    echo "Setting KDE system proxy..."

    # KDE proxy settings via kwriteconfig5
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 1
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key socksProxy "socks://$proxy_host:$proxy_port"
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpProxy "socks://$proxy_host:$proxy_port"
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key httpsProxy "socks://$proxy_host:$proxy_port"
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ftpProxy "socks://$proxy_host:$proxy_port"

    # Notify KDE applications of the change
    dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:''

    echo "✅ KDE proxy settings updated"
}

restore_system_proxy_kde() {
    echo "Restoring KDE proxy settings..."
    kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0
    dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:''
    echo "✅ KDE proxy settings restored"
}

set_system_proxy_env() {
    local proxy_host="$1"
    local proxy_port="$2"
    local proxy_url="socks5://$proxy_host:$proxy_port"

    echo "Setting environment variable proxy..."
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export ftp_proxy="$proxy_url"
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export FTP_PROXY="$proxy_url"

    # Write to shell profile for persistence
    local shell_profile=""
    if [[ -n "${BASH_VERSION:-}" ]]; then
        shell_profile="$HOME/.bashrc"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_profile="$HOME/.zshrc"
    else
        shell_profile="$HOME/.profile"
    fi

    if [[ -w "$shell_profile" ]]; then
        echo "# Quick proxy settings - auto-generated" >> "$shell_profile"
        echo "export http_proxy='$proxy_url'" >> "$shell_profile"
        echo "export https_proxy='$proxy_url'" >> "$shell_profile"
        echo "export ftp_proxy='$proxy_url'" >> "$shell_profile"
        echo "export HTTP_PROXY='$proxy_url'" >> "$shell_profile"
        echo "export HTTPS_PROXY='$proxy_url'" >> "$shell_profile"
        echo "export FTP_PROXY='$proxy_url'" >> "$shell_profile"
        echo "✅ Proxy environment variables set and saved to $shell_profile"
    else
        echo "✅ Proxy environment variables set for current session"
    fi
}

restore_system_proxy_env() {
    echo "Restoring environment proxy settings..."
    unset http_proxy https_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY

    # Remove from shell profile
    local shell_profile=""
    if [[ -n "${BASH_VERSION:-}" ]]; then
        shell_profile="$HOME/.bashrc"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        shell_profile="$HOME/.zshrc"
    else
        shell_profile="$HOME/.profile"
    fi

    if [[ -f "$shell_profile" ]]; then
        # Remove lines added by this script
        sed -i '/# Quick proxy settings - auto-generated/,+6d' "$shell_profile" 2>/dev/null || true
    fi

    echo "✅ Environment proxy settings restored"
}

set_system_proxy() {
    local proxy_host="$1"
    local proxy_port="$2"
    local desktop_env=$(detect_desktop_environment)

    echo "Detected desktop environment: $desktop_env"

    case "${desktop_env,,}" in
        *gnome*|*unity*|*cinnamon*)
            if command -v gsettings >/dev/null 2>&1; then
                set_system_proxy_gnome "$proxy_host" "$proxy_port"
            else
                echo "gsettings not found, falling back to environment variables"
                set_system_proxy_env "$proxy_host" "$proxy_port"
            fi
            ;;
        *kde*|*plasma*)
            if command -v kwriteconfig5 >/dev/null 2>&1; then
                set_system_proxy_kde "$proxy_host" "$proxy_port"
            else
                echo "kwriteconfig5 not found, falling back to environment variables"
                set_system_proxy_env "$proxy_host" "$proxy_port"
            fi
            ;;
        *)
            echo "Unknown desktop environment, setting environment variables"
            set_system_proxy_env "$proxy_host" "$proxy_port"
            ;;
    esac

    PROXY_ENABLED=true
}

restore_system_proxy() {
    local desktop_env=$(detect_desktop_environment)

    case "${desktop_env,,}" in
        *gnome*|*unity*|*cinnamon*)
            if command -v gsettings >/dev/null 2>&1; then
                restore_system_proxy_gnome
            else
                restore_system_proxy_env
            fi
            ;;
        *kde*|*plasma*)
            if command -v kwriteconfig5 >/dev/null 2>&1; then
                restore_system_proxy_kde
            else
                restore_system_proxy_env
            fi
            ;;
        *)
            restore_system_proxy_env
            ;;
    esac
}

# Authentication validation function
validate_auth() {
    local auth="$1"
    if [[ -z "$auth" ]]; then
        log_failure "Empty authentication token"
        return 1
    fi

    # Check if auth token follows UUID format (basic validation)
    if [[ ! "$auth" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        log_failure "Invalid authentication token format: $auth"
        return 1
    fi

    return 0
}

usage() {
    cat <<EOF
Usage: $0 [-z URI] [-p PORT] [--no-system-proxy] [--daemon] | URI

Creates a quick proxy server from a hysteria2 link and registers it as system proxy.

Examples:
    $0 "hysteria2://uuid@1.2.3.4:9989?security=tls&alpn=h3&insecure=1&sni=www.bing.com"
    $0 -z "hysteria2://..." -p 1080 --no-system-proxy
    $0 -z "hysteria2://..." --daemon

Options:
    -z, --uri            hysteria2 URI
    -p, --port           SOCKS5 listening port (default: 1080)
    --no-system-proxy    Don't register as system proxy
    --daemon             Run in background (daemon mode)
    -h, --help           show this help
EOF
    exit 2
}

# Default values
URI=""
SOCKS_PORT="1080"
SET_SYSTEM_PROXY=true
DAEMON_MODE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -z|--uri)
            URI="$2"; shift 2;;
        -p|--port)
            SOCKS_PORT="$2"; shift 2;;
        --no-system-proxy)
            SET_SYSTEM_PROXY=false; shift;;
        --daemon)
            DAEMON_MODE=true; shift;;
        -h|--help)
            usage;;
        --)
            shift; break;;
        -*)
            echo "Unknown option: $1" >&2; usage;;
        *)
            # positional argument
            if [[ -z "$URI" ]]; then
                URI="$1"
            fi
            shift;;
    esac
done

if [[ -z "$URI" ]]; then
    echo "No URI provided" >&2
    usage
fi

# Basic URI validation
if [[ ! "$URI" =~ ^hysteria2:// ]]; then
    echo "❌ Invalid URI format. Must start with 'hysteria2://'" >&2
    log_failure "Invalid URI format: $URI"
    exit 7
fi

echo "🚀 Quick Proxy Setup Starting..."
echo "URI: $URI"
echo "SOCKS5 Port: $SOCKS_PORT"
echo "System Proxy: $([ "$SET_SYSTEM_PROXY" = true ] && echo "Enabled" || echo "Disabled")"
echo "Daemon Mode: $([ "$DAEMON_MODE" = true ] && echo "Enabled" || echo "Disabled")"
echo ""

# Parse URI components (same logic as original script)
PROTO="${URI%%://*}"
REST="${URI#*://}"
REST="${REST%%#*}"  # Remove fragment
AUTH="${REST%%@*}"
HOST_PORT="${REST#*@}"
# Extract port and query separately
HOST="${HOST_PORT%%:*}"
PORT_QUERY="${HOST_PORT#*:}"
PORT="${PORT_QUERY%%\?*}"
QUERY="${PORT_QUERY#*\?}"

# Parse query parameters
SNI="www.bing.com"
if [[ -n "$QUERY" && "$QUERY" != "$PORT_QUERY" ]]; then
    # Extract SNI from query (remove fragment first)
    QUERY_CLEAN="${QUERY%%#*}"
    SNI_PART="${QUERY_CLEAN##*sni=}"
    if [[ "$SNI_PART" != "$QUERY_CLEAN" ]]; then
        SNI="${SNI_PART%%&*}"
        SNI="${SNI%%#*}"  # Remove any remaining fragment
    fi
fi

# Validate authentication token
echo "🔐 Validating authentication token..."
if ! validate_auth "$AUTH"; then
    echo "❌ 认证验证失败" >&2
    exit 5
fi
echo "✅ 认证验证通过"

# Create JSON config file
cat > tmp.json <<EOF
{
  "server": "$HOST:$PORT",
  "auth": "$AUTH",
  "tls": {
    "sni": "$SNI",
    "insecure": true,
    "alpn": ["h3"]
  },
  "socks5": {
    "listen": "127.0.0.1:$SOCKS_PORT"
  }
}
EOF

# Check hysteria binary
HYSTERIA_BIN="./hysteria"
if [[ ! -x "$HYSTERIA_BIN" ]]; then
    echo "❌ Warning: hysteria binary not found or not executable at $HYSTERIA_BIN" >&2
    echo "Please put hysteria client next to this script or edit HYSTERIA_BIN." >&2
    log_failure "Hysteria binary not found or not executable at $HYSTERIA_BIN"
    exit 6
fi

# Start hysteria client
echo "🔄 Starting hysteria client..."
"$HYSTERIA_BIN" client -c tmp.json >hysteria.log 2>&1 &
HY_PID=$!
echo "Hysteria client started with PID: $HY_PID"

# Wait for local socks5 listen (timeout) by trying to open a TCP connection
echo "⏳ Waiting for local socks5 127.0.0.1:$SOCKS_PORT to be ready..."
WAIT=0
MAX_WAIT=15
while true; do
    # try opening a TCP connection using bash /dev/tcp — quick and reliable
    if (echo > /dev/tcp/127.0.0.1/$SOCKS_PORT) >/dev/null 2>&1; then
        break
    fi
    sleep 1
    WAIT=$((WAIT+1))
    if [[ $WAIT -ge $MAX_WAIT ]]; then
        echo "❌ socks5 not listening after ${MAX_WAIT}s. Showing hysteria.log:" >&2
        sed -n '1,200p' hysteria.log >&2 || true
        log_failure "Connection timeout - socks5 proxy not ready after ${MAX_WAIT}s"
        exit 3
    fi
done

echo "✅ SOCKS5 proxy is listening on 127.0.0.1:$SOCKS_PORT"

# Test proxy connection
echo "🌐 Testing proxy connection..."
status=$(curl -s -o /dev/null -w "%{http_code}" -x socks5h://127.0.0.1:$SOCKS_PORT https://google.com --connect-timeout 10 || true)
echo "HTTP status: ${status}"
if [[ "$status" == "301" ]]; then
    echo "✅ 代理测试成功（返回 301 重定向）"
    log_success "HTTP $status - Proxy test successful"
else
    echo "❌ 代理测试未通过，状态码: ${status}"
    log_failure "Proxy test failed - HTTP status: ${status}"
    exit 4
fi

# Set system proxy if requested
if [[ "$SET_SYSTEM_PROXY" = true ]]; then
    echo "🔧 Setting up system proxy..."
    set_system_proxy "127.0.0.1" "$SOCKS_PORT"
    echo "✅ System proxy configured"
fi

echo ""
echo "🎉 Quick Proxy Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 Proxy Details:"
echo "   • SOCKS5: 127.0.0.1:$SOCKS_PORT"
echo "   • Server: $HOST:$PORT"
echo "   • Status: ✅ Active"
if [[ "$SET_SYSTEM_PROXY" = true ]]; then
echo "   • System Proxy: ✅ Enabled"
fi
echo ""
echo "🔧 Manual Configuration:"
echo "   HTTP/HTTPS Proxy: 127.0.0.1:$SOCKS_PORT"
echo "   SOCKS5 Proxy: 127.0.0.1:$SOCKS_PORT"
echo ""
echo "📝 Usage:"
echo "   curl -x socks5h://127.0.0.1:$SOCKS_PORT https://example.com"
echo ""

if [[ "$DAEMON_MODE" = true ]]; then
    echo "🔄 Running in daemon mode..."
    echo "To stop the proxy, run: kill $HY_PID"
    echo "Log file: $(pwd)/hysteria.log"
    # Disable cleanup trap for daemon mode
    trap - EXIT INT TERM
    echo "✅ Proxy is running in background"
    exit 0
else
    echo "🛑 Press Ctrl+C to stop the proxy and restore system settings"
    echo ""

    # Keep running until interrupted
    while true; do
        if ! kill -0 $HY_PID 2>/dev/null; then
            echo "❌ Hysteria client has stopped unexpectedly"
            log_failure "Hysteria client stopped unexpectedly"
            exit 3
        fi
        sleep 5
    done
fi