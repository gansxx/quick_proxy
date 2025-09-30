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
TUN_ENABLED=false
TUN_INTERFACE=""
ORIGINAL_DEFAULT_ROUTE=""

# Cleanup function
cleanup() {
    echo "Cleaning up..."

    # Stop hysteria process
    if [[ -n "${HY_PID:-}" ]]; then
        echo "Stopping hysteria client (PID: $HY_PID)..."
        kill $HY_PID 2>/dev/null || true
    fi

    # Clean up TUN interface if enabled
    if [[ "$TUN_ENABLED" == true ]]; then
        echo "Cleaning up TUN interface..."
        cleanup_tun_interface
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

# Clear system proxy function (standalone operation)
clear_system_proxy() {
    echo "🧹 Clearing system proxy settings..."

    local desktop_env=$(detect_desktop_environment)
    echo "Detected desktop environment: $desktop_env"

    case "${desktop_env,,}" in
        *gnome*|*unity*|*cinnamon*)
            if command -v gsettings >/dev/null 2>&1; then
                echo "Clearing GNOME proxy settings..."
                gsettings set org.gnome.system.proxy mode 'none'
                echo "✅ GNOME proxy settings cleared"
            else
                echo "⚠️ gsettings not found, clearing environment variables"
                unset http_proxy https_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY
                echo "✅ Environment proxy variables cleared"
            fi
            ;;
        *kde*|*plasma*)
            if command -v kwriteconfig5 >/dev/null 2>&1; then
                echo "Clearing KDE proxy settings..."
                kwriteconfig5 --file kioslaverc --group 'Proxy Settings' --key ProxyType 0
                dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:''
                echo "✅ KDE proxy settings cleared"
            else
                echo "⚠️ kwriteconfig5 not found, clearing environment variables"
                unset http_proxy https_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY
                echo "✅ Environment proxy variables cleared"
            fi
            ;;
        *)
            echo "Clearing environment proxy variables..."
            unset http_proxy https_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY
            echo "✅ Environment proxy variables cleared"
            ;;
    esac

    echo ""
    echo "🎉 System proxy settings have been cleared!"
    echo "Your system should now use direct internet connection."
}

# JSON storage functions for saved links
LINKS_DIR="./saved_links"
LINKS_FILE="$LINKS_DIR/links.json"
BACKUP_DIR="$LINKS_DIR/backups"

init_links_storage() {
    mkdir -p "$LINKS_DIR" "$BACKUP_DIR"

    if [[ ! -f "$LINKS_FILE" ]]; then
        cat > "$LINKS_FILE" << 'EOF'
{
  "links": [],
  "metadata": {
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0"
  }
}
EOF
    fi
}

# Check if jq is available, fallback to basic parsing if not
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Generate unique ID for a link
generate_link_id() {
    local timestamp=$(date +%s)
    local random=$(shuf -i 1000-9999 -n 1 2>/dev/null || echo $RANDOM)
    echo "link_${timestamp}_${random}"
}

# Create backup of links file
backup_links_file() {
    if [[ -f "$LINKS_FILE" ]]; then
        local backup_name="links_backup_$(date +%Y%m%d_%H%M%S).json"
        cp "$LINKS_FILE" "$BACKUP_DIR/$backup_name"
        echo "Backup created: $BACKUP_DIR/$backup_name"
    fi
}

# Save link information to JSON storage
save_link_info() {
    local name="$1"
    local uri="$2"
    local host="$3"
    local port="$4"
    local auth="$5"
    local sni="$6"

    init_links_storage
    backup_links_file

    local link_id=$(generate_link_id)
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if has_jq; then
        # Use jq for proper JSON manipulation
        local new_link=$(jq -n \
            --arg id "$link_id" \
            --arg name "$name" \
            --arg uri "$uri" \
            --arg host "$host" \
            --arg port "$port" \
            --arg auth "$auth" \
            --arg sni "$sni" \
            --arg created "$timestamp" \
            --arg last_used "$timestamp" \
            '{
                id: $id,
                name: $name,
                uri: $uri,
                parsed: {
                    host: $host,
                    port: $port,
                    auth: $auth,
                    sni: $sni
                },
                created: $created,
                last_used: $last_used,
                usage_count: 1
            }')

        jq --argjson newlink "$new_link" '.links += [$newlink]' "$LINKS_FILE" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"
    else
        # Fallback: basic JSON manipulation without jq
        # Remove the last } and ]} to append new entry
        head -n -2 "$LINKS_FILE" > "$LINKS_FILE.tmp"

        # Add comma if not the first entry
        if grep -q '"links": \[\]' "$LINKS_FILE.tmp"; then
            sed -i 's/"links": \[\]/"links": [/' "$LINKS_FILE.tmp"
        else
            echo '    ,' >> "$LINKS_FILE.tmp"
        fi

        # Add the new link entry
        cat >> "$LINKS_FILE.tmp" << EOF
    {
      "id": "$link_id",
      "name": "$name",
      "uri": "$uri",
      "parsed": {
        "host": "$host",
        "port": "$port",
        "auth": "$auth",
        "sni": "$sni"
      },
      "created": "$timestamp",
      "last_used": "$timestamp",
      "usage_count": 1
    }
  ]
}
EOF
        mv "$LINKS_FILE.tmp" "$LINKS_FILE"
    fi

    echo "✅ Link saved as '$name' (ID: $link_id)"
    return 0
}

# Load link information by name or ID
load_link_info() {
    local identifier="$1"

    if [[ ! -f "$LINKS_FILE" ]]; then
        echo "❌ No saved links found" >&2
        return 1
    fi

    local link_data
    if has_jq; then
        # Try to find by name first, then by ID
        link_data=$(jq -r ".links[] | select(.name == \"$identifier\" or .id == \"$identifier\")" "$LINKS_FILE" 2>/dev/null)

        if [[ -z "$link_data" || "$link_data" == "null" ]]; then
            echo "❌ Link '$identifier' not found" >&2
            return 1
        fi

        # Extract the URI and update usage
        URI=$(echo "$link_data" | jq -r '.uri')
        local link_id=$(echo "$link_data" | jq -r '.id')

        # Update last_used and usage_count
        local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg id "$link_id" --arg timestamp "$timestamp" \
           '(.links[] | select(.id == $id) | .last_used) = $timestamp |
            (.links[] | select(.id == $id) | .usage_count) += 1' \
           "$LINKS_FILE" > "$LINKS_FILE.tmp" && mv "$LINKS_FILE.tmp" "$LINKS_FILE"
    else
        # Fallback: basic grep-based search
        if grep -q "\"name\": \"$identifier\"" "$LINKS_FILE" || grep -q "\"id\": \"$identifier\"" "$LINKS_FILE"; then
            URI=$(grep -A 10 -B 2 "\"name\": \"$identifier\"\|\"id\": \"$identifier\"" "$LINKS_FILE" | grep '"uri"' | cut -d'"' -f4)
            if [[ -z "$URI" ]]; then
                echo "❌ Failed to extract URI for '$identifier'" >&2
                return 1
            fi
        else
            echo "❌ Link '$identifier' not found" >&2
            return 1
        fi
    fi

    echo "✅ Loaded saved link: $identifier"
    echo "URI: $URI"
    return 0
}

# List all saved links
list_saved_links() {
    if [[ ! -f "$LINKS_FILE" ]]; then
        echo "No saved links found."
        return 0
    fi

    if has_jq; then
        local count=$(jq '.links | length' "$LINKS_FILE")
        if [[ "$count" -eq 0 ]]; then
            echo "No saved links found."
            return 0
        fi

        echo "📋 Saved Links ($count):"
        echo "===================="
        jq -r '.links[] | "🔗 \(.name) (ID: \(.id))\n   Host: \(.parsed.host):\(.parsed.port)\n   Usage: \(.usage_count) times\n   Last used: \(.last_used)\n"' "$LINKS_FILE"
    else
        echo "📋 Saved Links:"
        echo "===================="
        grep -A 15 '"name":' "$LINKS_FILE" | grep -E '"name"|"host"|"port"|"usage_count"|"last_used"' | \
        while read -r line; do
            if [[ "$line" =~ \"name\" ]]; then
                name=$(echo "$line" | cut -d'"' -f4)
                echo "🔗 $name"
            elif [[ "$line" =~ \"host\" ]]; then
                host=$(echo "$line" | cut -d'"' -f4)
                echo -n "   Host: $host"
            elif [[ "$line" =~ \"port\" ]]; then
                port=$(echo "$line" | cut -d'"' -f4)
                echo ":$port"
            fi
        done
    fi
}

# TUN interface management functions
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo "❌ TUN mode requires root privileges. Please run with sudo." >&2
        return 1
    fi
    return 0
}

check_tun_support() {
    # Check if TUN module is available
    if ! lsmod | grep -q "^tun "; then
        echo "🔧 Loading TUN module..."
        modprobe tun || {
            echo "❌ Failed to load TUN module. Please ensure TUN support is available." >&2
            return 1
        }
    fi

    # Check if /dev/net/tun exists
    if [[ ! -c /dev/net/tun ]]; then
        echo "❌ /dev/net/tun device not found. TUN support not available." >&2
        return 1
    fi

    return 0
}

setup_tun_interface() {
    local tun_name="hysteria-tun"
    local tun_ip="10.0.0.1"
    local tun_subnet="10.0.0.0/24"

    echo "🔧 Setting up TUN interface: $tun_name"

    # Create TUN interface
    ip tuntap add name "$tun_name" mode tun || {
        echo "❌ Failed to create TUN interface $tun_name" >&2
        return 1
    }

    # Configure IP address
    ip addr add "$tun_ip/24" dev "$tun_name" || {
        echo "❌ Failed to assign IP to TUN interface" >&2
        ip tuntap del name "$tun_name" mode tun 2>/dev/null
        return 1
    }

    # Bring interface up
    ip link set dev "$tun_name" up || {
        echo "❌ Failed to bring up TUN interface" >&2
        ip tuntap del name "$tun_name" mode tun 2>/dev/null
        return 1
    }

    # Store current default route for restoration
    ORIGINAL_DEFAULT_ROUTE=$(ip route show default | head -1)

    # Set up routing - route all traffic through TUN interface
    echo "🔧 Setting up routing for global proxy..."

    # Get the current default gateway
    local gateway=$(ip route show default | awk '/default/ { print $3; exit }')
    local interface=$(ip route show default | awk '/default/ { print $5; exit }')

    if [[ -n "$gateway" && -n "$interface" ]]; then
        # Add specific route for the proxy server to avoid routing loop
        if [[ -n "$HOST" ]]; then
            echo "🔧 Adding route for proxy server $HOST via $gateway"
            ip route add "$HOST/32" via "$gateway" dev "$interface" 2>/dev/null || true
        fi

        # Replace default route with TUN interface
        ip route del default 2>/dev/null || true
        ip route add default dev "$tun_name" metric 1 || {
            echo "❌ Failed to set default route through TUN interface" >&2
            cleanup_tun_interface "$tun_name"
            return 1
        }

        # Add route for local network to maintain local connectivity
        local local_network=$(ip route | grep "$interface" | grep -E '192\.168\.|10\.|172\.' | head -1 | awk '{print $1}')
        if [[ -n "$local_network" && -n "$gateway" ]]; then
            ip route add "$local_network" via "$gateway" dev "$interface" 2>/dev/null || true
        fi
    else
        echo "⚠️  Warning: Could not determine current gateway. TUN routing may not work properly."
    fi

    # Configure DNS to use a public DNS server through the TUN interface
    echo "🔧 Configuring DNS..."
    cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
    cat > /etc/resolv.conf <<EOF
# Temporary DNS configuration for hysteria TUN mode
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    TUN_INTERFACE="$tun_name"
    TUN_ENABLED=true

    echo "✅ TUN interface $tun_name configured successfully"
    echo "   • Interface: $tun_name ($tun_ip/24)"
    echo "   • Status: UP"
    echo "   • Global routing: Enabled"

    return 0
}

cleanup_tun_interface() {
    local tun_name="${1:-$TUN_INTERFACE}"

    if [[ -z "$tun_name" ]]; then
        return 0
    fi

    echo "🧹 Cleaning up TUN interface: $tun_name"

    # Restore original DNS configuration
    if [[ -f /etc/resolv.conf.bak ]]; then
        echo "🔧 Restoring original DNS configuration..."
        mv /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
    fi

    # Restore original default route
    if [[ -n "$ORIGINAL_DEFAULT_ROUTE" ]]; then
        echo "🔧 Restoring original default route..."
        ip route del default 2>/dev/null || true
        ip route add $ORIGINAL_DEFAULT_ROUTE 2>/dev/null || true
    fi

    # Remove TUN interface
    if ip link show "$tun_name" >/dev/null 2>&1; then
        ip link set dev "$tun_name" down 2>/dev/null || true
        ip tuntap del name "$tun_name" mode tun 2>/dev/null || true
        echo "✅ TUN interface $tun_name removed"
    fi

    TUN_ENABLED=false
    TUN_INTERFACE=""
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
Usage: $0 [-z URI] [-p PORT] [--save-as NAME] [--load NAME] [--list-saved] [--no-system-proxy] [--daemon] [--tun] [--clear-proxy] | URI

Creates a quick proxy server from a hysteria2 link and registers it as system proxy.

Examples:
    $0 "hysteria2://uuid@1.2.3.4:9989?security=tls&alpn=h3&insecure=1&sni=www.bing.com"
    $0 -z "hysteria2://..." -p 1080 --no-system-proxy
    $0 -z "hysteria2://..." --daemon
    $0 -z "hysteria2://..." --tun --daemon
    $0 -z "hysteria2://..." --save-as "my-server"
    $0 --load "my-server"
    $0 --list-saved
    $0 --clear-proxy

Options:
    -z, --uri            hysteria2 URI
    -p, --port           SOCKS5 listening port (default: 1080)
    --save-as NAME       Save current URI with given name for future use
    --load NAME          Load a previously saved URI by name or ID
    --list-saved         List all saved links
    --no-system-proxy    Don't register as system proxy
    --daemon             Run in background (daemon mode)
    --tun                Enable TUN mode for global transparent proxy (requires root)
    --clear-proxy        Clear/disable system proxy settings and exit
    -h, --help           show this help
EOF
    exit 2
}

# Default values
URI=""
SOCKS_PORT="1080"
SET_SYSTEM_PROXY=true
DAEMON_MODE=false
TUN_MODE=false
CLEAR_PROXY=false
SAVE_AS=""
LOAD_LINK=""
LIST_SAVED=false

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
        --tun)
            TUN_MODE=true; shift;;
        --clear-proxy)
            CLEAR_PROXY=true; shift;;
        --save-as)
            SAVE_AS="$2"; shift 2;;
        --load)
            LOAD_LINK="$2"; shift 2;;
        --list-saved)
            LIST_SAVED=true; shift;;
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

# Handle clear proxy mode (standalone operation)
if [[ "$CLEAR_PROXY" = true ]]; then
    # Validate that no conflicting options are used
    if [[ -n "$URI" || "$DAEMON_MODE" = true || "$TUN_MODE" = true ]]; then
        echo "❌ --clear-proxy cannot be used with other proxy options" >&2
        exit 1
    fi

    clear_system_proxy
    exit 0
fi

# Handle list saved links mode
if [[ "$LIST_SAVED" = true ]]; then
    # Validate that no conflicting options are used
    if [[ -n "$URI" || -n "$SAVE_AS" || -n "$LOAD_LINK" || "$DAEMON_MODE" = true || "$TUN_MODE" = true ]]; then
        echo "❌ --list-saved cannot be used with other options" >&2
        exit 1
    fi

    list_saved_links
    exit 0
fi

# Handle load link mode
if [[ -n "$LOAD_LINK" ]]; then
    # Validate that URI is not also provided
    if [[ -n "$URI" ]]; then
        echo "❌ Cannot use both --load and direct URI" >&2
        exit 1
    fi

    if ! load_link_info "$LOAD_LINK"; then
        exit 1
    fi
    # URI is now set by load_link_info
fi

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
echo "TUN Mode: $([ "$TUN_MODE" = true ] && echo "Enabled" || echo "Disabled")"
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

# Handle save functionality if requested
if [[ -n "$SAVE_AS" ]]; then
    echo "💾 Saving link configuration as '$SAVE_AS'..."

    if save_link_info "$SAVE_AS" "$URI" "$HOST" "$PORT" "$AUTH" "$SNI"; then
        echo "✅ Link configuration saved successfully"
    else
        echo "❌ Failed to save link configuration" >&2
        # Continue with proxy setup even if save fails
    fi
    echo ""
fi

# TUN mode setup and validation
if [[ "$TUN_MODE" = true ]]; then
    echo "🔧 Setting up TUN mode..."

    # Check root privileges
    if ! check_root_privileges; then
        log_failure "TUN mode requires root privileges"
        exit 8
    fi
    echo "✅ Root privileges confirmed"

    # Check TUN support
    if ! check_tun_support; then
        log_failure "TUN support not available"
        exit 9
    fi
    echo "✅ TUN support available"

    # Override system proxy setting for TUN mode
    SET_SYSTEM_PROXY=false
    echo "ℹ️  System proxy disabled (TUN mode provides global proxy)"
fi

# Create JSON config file
if [[ "$TUN_MODE" = true ]]; then
    # TUN mode configuration
    cat > tmp.json <<EOF
{
  "server": "$HOST:$PORT",
  "auth": "$AUTH",
  "tls": {
    "sni": "$SNI",
    "insecure": true,
    "alpn": ["h3"]
  },
  "tun": {
    "name": "hysteria-tun",
    "mtu": 1500
  }
}
EOF
else
    # SOCKS5 mode configuration
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
fi

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

# Setup TUN interface if TUN mode is enabled
if [[ "$TUN_MODE" = true ]]; then
    echo "⏳ Waiting for hysteria client to initialize..."
    sleep 2  # Give hysteria a moment to start up

    if ! setup_tun_interface; then
        log_failure "Failed to setup TUN interface"
        exit 10
    fi
fi

# Test connection based on mode
if [[ "$TUN_MODE" = true ]]; then
    # In TUN mode, test direct internet connection
    echo "🌐 Testing TUN mode global proxy connection..."

    # Wait a bit for routing to stabilize
    echo "⏳ Waiting for routing to stabilize..."
    sleep 3

    # Test direct connection (should go through TUN interface)
    status=$(curl -s -o /dev/null -w "%{http_code}" https://google.com --connect-timeout 15 || true)
    echo "HTTP status: ${status}"
    if [[ "$status" == "301" || "$status" == "200" ]]; then
        echo "✅ TUN模式全局代理测试成功（返回 $status）"
        log_success "HTTP $status - TUN mode global proxy test successful"
    else
        echo "❌ TUN模式代理测试未通过，状态码: ${status}"
        echo "检查hysteria.log获取更多信息"
        log_failure "TUN mode proxy test failed - HTTP status: ${status}"
        exit 4
    fi
else
    # SOCKS5 mode - original logic
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
if [[ "$TUN_MODE" = true ]]; then
    echo "   • Mode: ✅ TUN (Global Transparent Proxy)"
    echo "   • Interface: $TUN_INTERFACE (10.0.0.1/24)"
    echo "   • Server: $HOST:$PORT"
    echo "   • Status: ✅ Active"
    echo "   • Global Routing: ✅ Enabled"
else
    echo "   • SOCKS5: 127.0.0.1:$SOCKS_PORT"
    echo "   • Server: $HOST:$PORT"
    echo "   • Status: ✅ Active"
    if [[ "$SET_SYSTEM_PROXY" = true ]]; then
        echo "   • System Proxy: ✅ Enabled"
    fi
fi
echo ""
if [[ "$TUN_MODE" = true ]]; then
    echo "🌐 Global Proxy Active:"
    echo "   All network traffic is automatically routed through the proxy"
    echo "   No manual configuration needed for applications"
    echo ""
    echo "📝 Verification:"
    echo "   curl https://api.ipify.org  # Check your external IP"
    echo "   ping 8.8.8.8  # Test connectivity"
else
    echo "🔧 Manual Configuration:"
    echo "   HTTP/HTTPS Proxy: 127.0.0.1:$SOCKS_PORT"
    echo "   SOCKS5 Proxy: 127.0.0.1:$SOCKS_PORT"
    echo ""
    echo "📝 Usage:"
    echo "   curl -x socks5h://127.0.0.1:$SOCKS_PORT https://example.com"
fi
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