使用示例：

  # 启动代理并自动配置系统代理
  ./quick_proxy.sh "hysteria2://your-uuid@server.com:9989?security=tls&alpn=h3&insecure=1&sni=www.bing.com"

  # 仅启动代理，不配置系统代理
  ./quick_proxy.sh --no-system-proxy "hysteria2://..."

  # 后台守护进程模式
  ./quick_proxy.sh --daemon "hysteria2://..."

  # 使用自定义端口
  ./quick_proxy.sh -p 8080 "hysteria2://..."
