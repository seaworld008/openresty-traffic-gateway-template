# Curl 烟雾测试

这些命令已经在本仓库于 `2026-04-03` 本机重新执行验证通过。

## 0. 测试前提

在执行下面的 `curl` 之前，请先完成：

```bash
make init
./ssl/scripts/init-local-certs.sh
bash examples/scripts/activate_conf_examples.sh
docker compose -f docker-compose.yml -f examples/backend/docker-compose.local.yml up -d
```

说明：

- `docker-compose.yml` 只负责 OpenResty 主栈
- 示例后端在 `examples/backend/docker-compose.local.yml`
- 如果不启用 `*.conf.example` 对应的 `.conf`，下面这些域名路由默认不会生效

## 1. 准备域名解析

可以把下面这些记录写入 `/etc/hosts`：

```text
127.0.0.1 www.example.test
127.0.0.1 api.example.test
127.0.0.1 admin.example.test
127.0.0.1 static.example.test
127.0.0.1 risk-gateway.example.test
127.0.0.1 partner-api.example.test
127.0.0.1 gray-release.example.test
```

或者在每条命令里使用 `curl --resolve`。

## 2. 验证 HTTP 跳转

```bash
curl -I --resolve www.example.test:80:127.0.0.1 http://www.example.test/
curl -I --resolve api.example.test:80:127.0.0.1 http://api.example.test/
curl -I --resolve admin.example.test:80:127.0.0.1 http://admin.example.test/
curl -I --resolve static.example.test:80:127.0.0.1 http://static.example.test/
```

预期结果：返回 `301`，并跳转到 `https://...`。

## 3. 验证 HTTPS 回源代理

只有本地自签证书场景才需要加 `-k`：

```bash
curl -k --resolve www.example.test:443:127.0.0.1 https://www.example.test/
curl -k --resolve api.example.test:443:127.0.0.1 https://api.example.test/
curl -k --resolve admin.example.test:443:127.0.0.1 https://admin.example.test/
```

预期结果：每个响应都能看到来自 `whoami` 容器的后端信息。

## 4. 验证静态站点与缓存头

```bash
curl -k --resolve static.example.test:443:127.0.0.1 https://static.example.test/
curl -k -I --resolve static.example.test:443:127.0.0.1 https://static.example.test/assets/site.css
```

预期结果：

- HTML 页面由 OpenResty 直接提供
- CSS 响应返回 `Cache-Control: public, max-age=3600, immutable`

## 5. 验证健康检查接口

```bash
curl -i http://127.0.0.1/healthz
```

预期结果：返回 `200 OK`，响应体为 `ok`。

## 6. 高级能力案例

高级能力测试请参考 [examples/advanced-tests.md](/data/openresty-install/examples/advanced-tests.md)。

测试完成后，如需清理示例配置，可执行：

```bash
bash examples/scripts/deactivate_conf_examples.sh
```
