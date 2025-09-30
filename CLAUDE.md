# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Quick Proxy is a Hysteria2 proxy management tool that provides:
- **SOCKS5 proxy mode**: Standard proxy with automatic system proxy configuration
- **TUN mode**: Global transparent proxy requiring root privileges
- **Desktop environment integration**: Automatic proxy configuration for GNOME/KDE/others
- **Link management**: Save, load, and manage Hysteria2 proxy configurations
- **System proxy control**: Clear/disable system proxy settings
- **Logging and monitoring**: Connection testing and comprehensive logging

## Architecture

### Core Components

**quick_proxy.sh** - Main script handling:
- CLI argument parsing and validation
- Hysteria2 URI parsing and configuration generation
- System proxy management across desktop environments
- TUN interface creation and routing configuration
- Link storage and retrieval (save/load functionality)
- Process lifecycle management with proper cleanup

**proxy_manager.sh** - Management script providing:
- CRUD operations for saved links (create, read, update, delete)
- Usage statistics and analytics
- Import/export functionality
- Bulk operations and link organization

**hysteria** - Precompiled Hysteria2 client binary (x86-64, statically linked)

**saved_links/** - JSON storage system:
- `links.json` - Main configuration database
- `backups/` - Automatic backups of configuration changes

### Key Functions

- **System Proxy Management**: Desktop environment detection (GNOME/KDE/etc.) and appropriate proxy configuration
- **TUN Interface Management**: Network interface creation, routing table modification, DNS configuration
- **Link Management**: JSON-based storage with automatic backups and usage tracking
- **Connection Testing**: Automated proxy validation for both SOCKS5 and TUN modes
- **Configuration Persistence**: Save/load named proxy configurations for easy reuse
- **Cleanup Logic**: Comprehensive restoration of original network settings on exit

### Operating Modes

1. **SOCKS5 Mode** (default): Creates local SOCKS5 proxy, optionally configures system proxy
2. **TUN Mode** (`--tun`): Creates transparent proxy via TUN interface, requires root privileges
3. **Daemon Mode** (`--daemon`): Background operation with process management

## Common Commands

### Basic Usage
```bash
# Make scripts executable
chmod +x quick_proxy.sh hysteria proxy_manager.sh

# SOCKS5 mode with system proxy configuration
./quick_proxy.sh "hysteria2://uuid@server.com:9989?security=tls&alpn=h3&insecure=1&sni=www.bing.com"

# TUN mode (requires root)
sudo ./quick_proxy.sh --tun "hysteria2://..."

# Daemon mode
./quick_proxy.sh --daemon "hysteria2://..."

# Custom port without system proxy
./quick_proxy.sh -p 8080 --no-system-proxy "hysteria2://..."

# Clear/disable system proxy
./quick_proxy.sh --clear-proxy
```

### Link Management
```bash
# Save a proxy configuration with a name
./quick_proxy.sh "hysteria2://..." --save-as "my-server"

# Load a saved configuration
./quick_proxy.sh --load "my-server"

# List all saved configurations
./quick_proxy.sh --list-saved

# Use the management script for advanced operations
./proxy_manager.sh list                    # List all saved links
./proxy_manager.sh show my-server          # Show detailed info
./proxy_manager.sh rename old-name new-name # Rename a link
./proxy_manager.sh delete my-server        # Delete a link
./proxy_manager.sh update my-server "new-uri" # Update URI
./proxy_manager.sh stats                   # Usage statistics
./proxy_manager.sh export backup.json      # Export all links
./proxy_manager.sh import backup.json      # Import links
```

### Testing and Debugging
```bash
# View success logs
cat ./logs/quick_proxy_success.log

# View failure logs
cat ./logs/quick_proxy_failures.log

# Monitor hysteria client logs
tail -f hysteria.log

# Test connection manually (SOCKS5 mode)
curl -x socks5h://127.0.0.1:1080 https://example.com

# Test TUN mode connectivity
curl https://api.ipify.org  # Should show proxy server IP
ping 8.8.8.8                # Test connectivity
ip route show               # Check routing table
```

## Development Notes

### Signal Handling and Cleanup
The script implements comprehensive cleanup via `trap` handlers for EXIT/INT/TERM signals. All network changes are automatically reverted.

### Security Considerations
- TUN mode requires root privileges and modifies system networking
- Script validates Hysteria2 URI format before processing
- Temporary configuration files are cleaned up automatically
- Original network settings are preserved and restored

### Desktop Environment Support
Auto-detection and configuration for:
- **GNOME/Unity/Cinnamon**: Uses `gsettings`
- **KDE/Plasma**: Uses `kwriteconfig5`
- **Fallback**: Environment variables for other environments

### Error Handling
- Comprehensive logging to `./logs/` directory
- Connection testing with timeout handling
- Process monitoring with automatic failure detection
- Graceful degradation when tools are unavailable

### Network Configuration (TUN Mode)
- Creates `hysteria-tun` interface with 10.0.0.1/24
- Modifies routing table to route all traffic through TUN
- Preserves direct route to proxy server to prevent loops
- Temporarily modifies `/etc/resolv.conf` for DNS

### Link Storage System
- **JSON Format**: Uses structured JSON for reliable data persistence
- **Automatic Backups**: Creates timestamped backups before any destructive operation
- **Usage Tracking**: Maintains usage statistics (count, last used, created date)
- **jq Integration**: Optimized JSON operations when jq is available, fallback to basic parsing
- **Conflict Prevention**: Validates unique names and prevents data corruption
- **Import/Export**: Full configuration portability between systems

### Command Line Interface
**quick_proxy.sh options**:
- `--clear-proxy`: Standalone proxy clearing (no other options allowed)
- `--save-as NAME`: Save current configuration with given name
- `--load NAME`: Load saved configuration by name or ID
- `--list-saved`: Display all saved configurations
- Conflict detection prevents incompatible option combinations

**proxy_manager.sh commands**:
- Full CRUD operations with input validation
- Colored output for improved readability
- Interactive confirmations for destructive operations
- Comprehensive error handling and user feedback