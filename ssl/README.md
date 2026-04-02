# SSL / ACME 运维说明

这个目录把证书申请、续签和 OpenResty reload 逻辑，从网关配置本身中独立出来，方便单独维护和排障。

## 目录说明

- `certbot/conf/`：持久化保存 Let's Encrypt 账户信息与已签发证书
- `certbot/www/`：OpenResty 暴露出去的 ACME webroot challenge 目录
- `scripts/init-cert.sh`：生产证书申请脚本
- `scripts/renew-cert.sh`：续签脚本，可被 cron 或 systemd timer 调用
- `scripts/reload-openresty.sh`：先校验配置，再执行 OpenResty reload
- `scripts/init-local-certs.sh`：本地烟雾测试使用的自签证书脚本

## 生产申请流程

1. 确认 DNS 已经解析到当前网关主机。
2. 确认公网已经放通 `80/tcp` 与 `443/tcp`。
3. 先启动 OpenResty：`docker compose up -d openresty`
4. 申请证书，例如：

```bash
./ssl/scripts/init-cert.sh --email ops@example.com \
  www.example.com api.example.com admin.example.com static.example.com
```

5. 证书签发完成后 reload OpenResty。脚本内部已经自动处理。

## 证书续签

手工执行：

```bash
./ssl/scripts/renew-cert.sh
```

推荐的宿主机 cron 示例：

```cron
17 3 * * * cd /path/to/openresty-install && ./ssl/scripts/renew-cert.sh >> ./openresty/logs/cert-renew.log 2>&1
```

## 本地烟雾测试模式

生成与示例域名匹配的自签证书：

```bash
./ssl/scripts/init-local-certs.sh
```

这个脚本会写出与 Certbot 正常签发时一致的目录结构，因此本地测试模式和生产模式可以共用同一套站点配置文件，无需额外改证书路径。

## 运维建议

- 主机迁移前务必备份 `ssl/certbot/conf/`。
- 要把证书目录权限纳入运维规范，但不要把真实证书或账户密钥提交到 Git。
- 首次在真实域名上签发时，建议先加 `--staging` 验证 ACME 链路，再正式申请生产证书。
