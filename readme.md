# Quick Proxy - Hysteria2 代理快速启动工具

一个用于快速设置 Hysteria2 代理服务器的脚本，支持 SOCKS5 代理模式和 TUN 全局透明代理模式。

## 功能特性

- 🚀 **快速启动**: 从 hysteria2:// 链接快速启动代理
- 🔧 **自动配置**: 自动检测和配置系统代理设置
- 🌐 **TUN 模式**: 支持全局透明代理，无需配置应用程序
- 🛡️ **安全验证**: 自动验证认证令牌格式
- 📊 **连接测试**: 自动测试代理连接可用性
- 🧹 **自动清理**: 退出时自动恢复原始网络设置
- 📝 **详细日志**: 成功和失败日志记录

## 权限授予
```bash
chmod +x quick_proxy.sh
chmod +x hysteria
```

## 使用示例

### SOCKS5 代理模式（默认）

```bash
# 启动代理并自动配置系统代理
./quick_proxy.sh "hysteria2://your-uuid@server.com:9989?security=tls&alpn=h3&insecure=1&sni=www.bing.com"

# 仅启动代理，不配置系统代理
./quick_proxy.sh --no-system-proxy "hysteria2://..."

# 后台守护进程模式
./quick_proxy.sh --daemon "hysteria2://..."

# 使用自定义端口
./quick_proxy.sh -p 8080 "hysteria2://..."
```

### TUN 全局透明代理模式（新功能）

```bash
# 启用 TUN 模式全局代理（需要 root 权限）
sudo ./quick_proxy.sh --tun "hysteria2://your-uuid@server.com:9989?..."

# TUN 模式 + 后台守护进程
sudo ./quick_proxy.sh --tun --daemon "hysteria2://..."

# TUN 模式说明：
# - 所有网络流量自动通过代理
# - 无需配置应用程序代理设置
# - 需要 root 权限
# - 自动配置路由和 DNS
```

## 命令行选项

| 选项 | 描述 |
|------|------|
| `-z, --uri` | Hysteria2 URI 链接 |
| `-p, --port` | SOCKS5 监听端口（默认：1080） |
| `--no-system-proxy` | 不配置系统代理 |
| `--daemon` | 后台守护进程模式 |
| `--tun` | 启用 TUN 全局透明代理模式（需要 root） |
| `-h, --help` | 显示帮助信息 |

## TUN 模式详细说明

### 系统要求
- Linux 系统
- Root 权限
- 内核支持 TUN 模块

### 工作原理
1. 创建 `hysteria-tun` 网络接口（10.0.0.1/24）
2. 修改系统路由表，所有流量通过 TUN 接口
3. 保留代理服务器的直连路由避免循环
4. 配置公共 DNS 服务器
5. 退出时自动恢复原始网络配置

### TUN 模式优势
- ✅ 全局透明代理，无需配置应用程序
- ✅ 支持所有网络应用程序
- ✅ 自动处理 DNS 查询
- ✅ 完全的系统级代理

### 验证 TUN 模式
```bash
# 检查外部 IP（应显示代理服务器 IP）
curl https://api.ipify.org

# 测试连通性
ping 8.8.8.8

# 查看路由信息
ip route show
```

## 日志和调试

### 日志文件位置
- 成功日志: `./logs/quick_proxy_success.log`
- 失败日志: `./logs/quick_proxy_failures.log`
- Hysteria 日志: `./hysteria.log`

### 常见问题排查
1. **TUN 模式启动失败**: 检查是否有 root 权限和 TUN 模块支持
2. **连接测试失败**: 检查 hysteria.log 文件获取详细错误信息
3. **DNS 解析问题**: TUN 模式会临时修改 /etc/resolv.conf

## 支持的桌面环境

- **GNOME/Unity/Cinnamon**: 使用 gsettings 配置
- **KDE/Plasma**: 使用 kwriteconfig5 配置
- **其他环境**: 使用环境变量配置

## 安全注意事项

- ⚠️ TUN 模式需要 root 权限，请确保脚本来源可信
- ⚠️ 脚本会临时修改系统网络配置
- ⚠️ 使用 Ctrl+C 正常退出以恢复网络设置
- ⚠️ 守护进程模式请记录 PID 以便后续停止
