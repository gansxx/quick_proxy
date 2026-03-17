# Quick Proxy / Hysteria2 使用说明

当前仓库内旧脚本（如 `quick_proxy.sh`）已落后，建议改用 `hysteria` 客户端直接读取配置文件启动。

## 推荐启动方式（默认配置文件）

`hysteria` 默认会读取当前目录下的 `config.yaml`。

```bash
chmod +x ./hysteria
./hysteria
```

等价显式写法：

```bash
./hysteria client -c config.yaml
```

## 配置方式

1. 复制示例配置并填写你的节点信息：

```bash
cp config.yaml.tun.example config.yaml
```

2. 修改以下关键字段：
- `server`
- `auth`
- `tls.sni`
- `route.ipv4Exclude`（必须替换为真实服务端 IP/32）

3. 启动后确认日志包含：
- `connected to server`
- `TUN listening`

## TUN 配置注意事项

- `tun.address.ipv4` 需要有足够地址空间，推荐 `172.19.0.1/29` 或更大前缀。
- 避免使用 `100.100.x.x` 地址（有 Tailscale 时冲突风险高）。
- 全局路由走 TUN 时，务必在 `route.ipv4Exclude` 中排除服务端地址，避免路由环路。

更多排障记录见：
- `docs/tun-mode-config-issue.md`
- `docs/dns-issue-record.md`

## 以 daemon 方式启动（避免阻塞会话）

### nohup 后台启动

```bash
nohup ./hysteria client -c config.yaml > ./logs/hysteria.out.log 2>&1 &
echo $! > ./hysteria.pid
```

### 检查状态

```bash
ps -fp "$(cat ./hysteria.pid)"
tail -f ./logs/hysteria.out.log
```

### 关闭

```bash
kill "$(cat ./hysteria.pid)"
rm -f ./hysteria.pid
```

若 pid 文件丢失：

```bash
pkill -f "./hysteria client -c config.yaml"
```

## 目录说明

- `config.yaml`: 实际运行配置（建议本地保存，不要提交敏感信息）
- `config.yaml.tun.example`: TUN 配置示例模板
- `docs/`: 问题排查和修复记录
