# 第一层高级能力测试说明

这份文档覆盖以下能力的真实测试方式：

- JWT 鉴权
- HMAC / 时间戳签名校验
- 限流
- 基础灰度
- 基于配置文件的动态路由
- Redis 支持
- 统一请求 ID
- Header / Body 改写
- 上游失败重试与简单熔断
- 黑白名单 / UA / IP 风控

## 测试前提

1. 先执行：

```bash
make init
./ssl/scripts/init-local-certs.sh
docker compose up -d
```

2. 再启动一个仓库外的本机 Redis 容器，挂到当前 Compose 网络：

```bash
make redis-test-up
```

3. 把测试数据写入 Redis：

```bash
docker exec openresty-local-redis redis-cli SET gateway:gray:enabled 1
docker exec openresty-local-redis redis-cli SET gateway:partner:test-client \
  '{"tenant":"acme","jwt_secret":"partner-jwt-secret","hmac_secret":"partner-hmac-secret"}'
```

4. 保证本机 hosts 或 `curl --resolve` 已覆盖以下域名：

- `risk-gateway.example.test`
- `partner-api.example.test`
- `gray-release.example.test`

## 案例 1：风控与稳定性网关

配置文件：

- [openresty/conf.d/risk-protected-proxy.conf.example](/data/openresty-install/openresty/conf.d/risk-protected-proxy.conf.example)
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

### 1. 默认请求通过

```bash
curl -k -I --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/
```

关注返回头：

- `X-Gateway-Route: risk_default`
- `X-Gateway-Circuit-State: closed`

### 2. UA 风控拦截

```bash
curl -k -i \
  -H 'User-Agent: evil-bot/1.0' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/
```

预期：

- HTTP `403`
- 返回 JSON 错误体
- `code` 为 `ua_blocked`

### 3. IP 黑白名单

黑名单：

```bash
curl -k -i \
  -H 'X-Forwarded-For: 198.51.100.24' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/denylist
```

白名单：

```bash
curl -k -i \
  -H 'X-Forwarded-For: 203.0.113.10' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/allowlist
```

### 4. 限流

```bash
seq 1 25 | xargs -I{} -P25 sh -c \
  "curl -k -o /dev/null -s -w '%{http_code}\n' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/" | sort | uniq -c
```

预期：同时看到 `200` 和 `429`，说明限流生效。

### 5. 失败重试与简单熔断

```bash
for i in 1 2 3; do
  curl -k -i \
    --resolve risk-gateway.example.test:443:127.0.0.1 \
    https://risk-gateway.example.test/unstable | sed -n '1,16p'
done
```

预期：

- 前两次返回 `502`
- 第三次走 fallback，返回 `200`
- 第三次响应头 `X-Gateway-Circuit-State: open`

## 案例 2：合作方 API 接入网关

配置文件：

- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

### 1. 生成 JWT

```bash
JWT_TOKEN=$(python3 - <<'PY'
import base64, hashlib, hmac, json, time

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

header = b64url(json.dumps({'alg':'HS256','typ':'JWT'}, separators=(',', ':')).encode())
payload = b64url(json.dumps({'sub':'partner-user-1','exp':int(time.time())+3600}, separators=(',', ':')).encode())
signing_input = f"{header}.{payload}".encode()
signature = b64url(hmac.new(b'partner-jwt-secret', signing_input, hashlib.sha256).digest())
print(f"{header}.{payload}.{signature}")
PY
)
```

### 2. 未鉴权请求被拒绝

```bash
curl -k -i \
  --resolve partner-api.example.test:443:127.0.0.1 \
  https://partner-api.example.test/v1/orders
```

预期：

- HTTP `401`
- `code` 为 `missing_partner_key`

### 3. JWT + Redis + Body/Header 改写

```bash
curl -k -sS \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H 'X-Partner-Key: test-client' \
  -H 'Content-Type: application/json' \
  -H 'X-Remove-Me: yes' \
  -d '{"order_id":"ORD-1001","amount":128}' \
  https://partner-api.example.test/v1/orders
```

预期：

- 返回 JSON
- 上游能看到 `X-Partner-Tenant: acme`
- 请求体被注入 `gateway_request_id`、`gateway_route`、`partner_tenant`
- `X-Remove-Me` 不再透传

### 4. HMAC / 时间戳签名校验

```bash
TS=$(date +%s)
SIG=$(printf 'POST\n/v1/hooks/inventory\n%s\n%s' "$TS" '{"event":"inventory.low"}' \
  | openssl dgst -sha256 -hmac 'partner-hmac-secret' -binary \
  | xxd -p -c 256)

curl -k -i \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H 'X-Partner-Key: test-client' \
  -H "X-Timestamp: $TS" \
  -H "X-Signature: $SIG" \
  -H 'Content-Type: application/json' \
  -d '{"event":"inventory.low"}' \
  https://partner-api.example.test/v1/hooks/inventory
```

预期：

- HTTP `200`
- 返回 JSON
- 响应中带有 `gateway_request_id`、`gateway_route`、`partner_tenant`

### 5. 基于配置文件的动态路由

默认走稳定后端：

```bash
curl -k -sS \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H 'X-Partner-Key: test-client' \
  https://partner-api.example.test/v1/dispatch
```

带 `X-Route-Version: echo` 时走 echo 后端：

```bash
curl -k -sS \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H 'X-Partner-Key: test-client' \
  -H 'X-Route-Version: echo' \
  https://partner-api.example.test/v1/dispatch
```

## 案例 3：基础灰度发布

配置文件：

- [openresty/conf.d/gray-release-proxy.conf.example](/data/openresty-install/openresty/conf.d/gray-release-proxy.conf.example)
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

### 1. 默认稳定版本

```bash
curl -k -i \
  --resolve gray-release.example.test:443:127.0.0.1 \
  https://gray-release.example.test/
```

预期：

- `X-Gray-Variant: stable`
- 返回稳定后端内容

### 2. Header 灰度

```bash
curl -k -i \
  -H 'X-Gray-Release: canary' \
  --resolve gray-release.example.test:443:127.0.0.1 \
  https://gray-release.example.test/
```

预期：

- `X-Gray-Variant: canary`
- 返回 canary 后端 JSON

### 3. Redis 统一关闭灰度

```bash
docker exec openresty-local-redis redis-cli SET gateway:gray:enabled 0
curl -k -i \
  -H 'X-Gray-Release: canary' \
  --resolve gray-release.example.test:443:127.0.0.1 \
  https://gray-release.example.test/
```

预期：

- 即使带了灰度 Header，也回到稳定后端
- `X-Gray-Variant: stable`

## 一键自动化验证

```bash
make test-first-layer
```

## 测试完成后清理

```bash
make redis-test-down
docker compose down
```
