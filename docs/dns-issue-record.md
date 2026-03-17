# DNS 解析问题记录

## 问题现象
- `curl google.com` 返回：`curl: (6) Could not resolve host: google.com`。

## 根因
- 服务器 `/etc/resolv.conf` 曾指向 `/run/systemd/resolve/resolv.conf`，但 `systemd-resolved` 处于 `inactive`。
- 结果是系统没有有效 DNS 解析器，导致域名解析失败。

## 修复方案（已验证）
- 使用可用的静态 resolver：
  - `223.5.5.5`
  - `1.1.1.1`
- 示例：
```bash
cat >/etc/resolv.conf <<EOR
nameserver 223.5.5.5
nameserver 1.1.1.1
options timeout:1 attempts:2
EOR
```

## 可选标准化方案
- 启用并使用 `systemd-resolved`：
```bash
systemctl enable --now systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

## 验证结果
- `getent hosts google.com` 可返回 IPv6/IPv4 记录。
- 在 TUN 运行期间 `curl -I https://google.com` 可得到 HTTP 响应。

## 注意事项
- 若脚本会改写 `/etc/resolv.conf`，请保证退出时能恢复原状，避免再次出现无 DNS 可用状态。
