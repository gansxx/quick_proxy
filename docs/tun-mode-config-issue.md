# TUN 模式配置问题记录

## 问题现象
- `./hysteria` 启动时可连接服务端，但 TUN 初始化失败。
- 典型报错：`failed to create tun stack: need one more IPv4 address in first prefix for system stack`

## 根因
- `tun.address.ipv4` 之前使用了过小/不合适前缀，无法给系统栈再分配一个 IPv4。
- 历史配置使用过 `100.100.x.x` 网段，和本机 `tailscale0` 所在地址体系（CGNAT 范围）存在冲突风险。
- `route.ipv4Exclude/ipv6Exclude` 早期用了文档示例保留地址，未明确排除实际服务端，存在路由环路风险。

## 修复方案
- 改为私有且足够可分配地址的前缀，例如：`172.19.0.1/29`。
- 明确排除服务端地址：`35.77.91.182/32`。
- 保持默认全局路由通过 TUN，排除项仅保留必须直连地址。

## 当前可用示例
见仓库根目录 `config.yaml.tun.example`。

## 验证步骤
```bash
./hysteria client -c config.yaml
# 看到以下日志表示 TUN 正常建立
# connected to server
# TUN listening
```

## 备注
- 启动前请确保无残留 hysteria 进程，避免设备/路由冲突导致误判。
