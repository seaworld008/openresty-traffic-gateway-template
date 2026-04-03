# OpenResty 场景化接入指南

## 1. 这份指南解决什么问题

这份文档直接回答两个实施问题：

1. 新加一个网站或 API，应该从哪个模板开始
2. 一个已经在跑的老站，怎么渐进式加限流、风控、熔断或等待室

如果你只想快速判断选型，先看第 2 节。
如果你要直接照着改配置，按第 3 节开始操作。

## 2. 先判断你属于哪种场景

### 场景 A：普通网站 / 前端站点

适合：

- 官网
- 活动展示页
- 普通前端
- BFF 前的简单站点入口

推荐模板：

- [openresty/conf.d/frontend-proxy.conf.example](/data/openresty-install/openresty/conf.d/frontend-proxy.conf.example)
- [openresty/conf.d/static-local-root.conf.example](/data/openresty-install/openresty/conf.d/static-local-root.conf.example)

特点：

- 只做反向代理或静态托管
- 不需要第一层高级能力
- 不需要等待室

### 场景 B：普通业务 API / 后台 / 控制台

适合：

- 普通 API
- 管理后台
- 控制台
- 内部管理系统

推荐模板：

- [openresty/conf.d/api-proxy.conf.example](/data/openresty-install/openresty/conf.d/api-proxy.conf.example)
- [openresty/conf.d/admin-console-proxy.conf.example](/data/openresty-install/openresty/conf.d/admin-console-proxy.conf.example)

特点：

- 需要基础代理
- 可能需要简单限流
- 还不需要 JWT / HMAC / 动态路由 / 等待室

### 场景 C：需要第一层公共能力的 API

适合：

- 合作方接入
- 外部回调入口
- 需要 JWT / HMAC 的网关
- 需要动态路由、灰度、基础风控、简单熔断的接口

推荐模板：

- [openresty/conf.d/risk-protected-proxy.conf.example](/data/openresty-install/openresty/conf.d/risk-protected-proxy.conf.example)
- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)
- [openresty/conf.d/gray-release-proxy.conf.example](/data/openresty-install/openresty/conf.d/gray-release-proxy.conf.example)

特点：

- 站点层只绑定 `gateway_policy`
- 能力下沉到 [openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)
- 适合“一个老 API 站点逐步加能力”

### 场景 D：热点活动入口 / 等待室

适合：

- 抢课
- 报名
- 秒杀
- 放号预约
- 抢票

推荐模板：

- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
- [openresty/conf.d/waitroom-java-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-java-gateway.conf.example)

特点：

- 不只是普通限流
- 需要入口排队、状态轮询和关键路径保护
- 策略核心是 `capacity.steady` 与 `capacity.burst`
- 如果业务统一先打到 Java gateway，可直接使用 Java gateway 版本模板

## 3. 新站接入的标准流程

无论哪种场景，都建议按下面顺序做：

1. 选一个最接近的模板
2. 复制成新的 `.conf`
3. 修改域名、证书路径、日志名和当前子配置文件内的 upstream
4. 如果启用了第一层或等待室，再绑定策略
5. `make check`
6. 按场景执行功能测试
7. `make reload`

### 3.1 复制模板后用 `confctl.sh` 做运维检查

新增站点时，直接复制最接近的模板：

```bash
cp openresty/conf.d/frontend-proxy.conf.example openresty/conf.d/www.example.com.conf
```

或：

```bash
cp openresty/conf.d/waitroom-enrollment-gateway.conf.example openresty/conf.d/enroll-campus-a.conf
```

如果你们是 OpenResty -> Java gateway 架构，也可以直接复制：

```bash
cp openresty/conf.d/waitroom-java-gateway.conf.example openresty/conf.d/enroll-java-gateway.conf
```

改完后，用 `confctl.sh` 做检查和 reload：

```bash
cd openresty/conf.d
./confctl.sh test
./confctl.sh reload
```

复制后，至少检查这些字段：

- `server_name`
- `ssl_certificate`
- `ssl_certificate_key`
- `access_log`
- `error_log`
- `proxy_pass`
- 子配置文件中的 `upstream`
- `set $gateway_policy ...`
- `set $admission_policy ...`

## 4. 各场景的可操作步骤

### 4.1 普通网站 / 前端站点

推荐起点：

- [openresty/conf.d/frontend-proxy.conf.example](/data/openresty-install/openresty/conf.d/frontend-proxy.conf.example)

最小修改点：

1. 改 `server_name`
2. 改证书路径
3. 改日志文件名
4. 改 `proxy_pass`

最小检查：

```bash
make check
curl -k --resolve www.example.com:443:127.0.0.1 https://www.example.com/
```

适合什么阶段：

- 新系统刚上线
- 暂时只要 HTTPS 统一入口
- 后端自己处理业务认证和权限

### 4.2 普通 API / 后台 / 控制台

推荐起点：

- [openresty/conf.d/api-proxy.conf.example](/data/openresty-install/openresty/conf.d/api-proxy.conf.example)
- [openresty/conf.d/admin-console-proxy.conf.example](/data/openresty-install/openresty/conf.d/admin-console-proxy.conf.example)

最小修改点：

1. 改 `server_name`
2. 改证书路径
3. 改日志文件名
4. 改 `proxy_pass`
5. 按需要调整 `limit_req`

如果只是普通 API，建议先只用基础模板，不要一开始就挂很多高级能力。

最小检查：

```bash
make check
curl -k --resolve api.example.com:443:127.0.0.1 https://api.example.com/healthz
```

### 4.3 合作方 API / 外部接入 API

推荐起点：

- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)

你需要同时改两处：

1. 站点文件
设置新的 `gateway_policy`

2. 策略文件
[openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua) 中增加策略

最小步骤：

1. 复制模板
2. 修改 `server_name`
3. 设置 `set $gateway_policy your_policy`
4. 在策略文件里新增路由和鉴权规则
5. 准备 Redis 中的合作方配置
6. `make check`
7. `make test-first-layer`

什么时候用这个模板：

- 需要 JWT
- 需要 HMAC / 时间戳签名
- 需要按请求头动态分流
- 需要请求/响应改写

### 4.4 热点活动入口 / 等待室

推荐起点：

- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
- [openresty/conf.d/waitroom-java-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-java-gateway.conf.example)

你需要同时改两处：

1. 站点文件
设置 `set $admission_policy your_policy`

2. 策略文件
[openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua) 中增加策略

必改字段：

- `paths.join`
- `paths.status`
- `paths.waitroom`
- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`
- `protected.paths`
- 子配置文件内的业务 `upstream`

如果你们的真实架构是：

```text
OpenResty -> Java gateway -> Nacos / 多个后端服务
```

建议直接使用 `waitroom-java-gateway.conf.example`：

- OpenResty 只负责等待室和关键路径保护
- Java gateway 继续负责服务发现和向后路由
- OpenResty 不需要理解后面的 Nacos 拓扑

最小检查：

```bash
make check
make test-waitroom
```

上线前建议：

```bash
make test-comprehensive
```

## 5. 老站如何增量接入能力

这是最常见也最容易改乱的场景。建议遵循一个原则：

先保留原代理结构，只把“能力入口”挂上去，不要一上来重写整个站点文件。

### 5.1 老站加基础限流

如果你现在只有一个普通反向代理：

```nginx
location / {
    include /etc/nginx/snippets/proxy-common.conf;
    proxy_pass http://api_backend;
}
```

要先加最轻量的限流，可以改成：

```nginx
location / {
    limit_req zone=per_ip_api burst=40 nodelay;
    include /etc/nginx/snippets/proxy-common.conf;
    proxy_pass http://api_backend;
}
```

适合：

- 普通 API
- 简单后台
- 还不需要第一层 Lua 能力

### 5.2 老站加第一层风控 / 熔断 / 动态路由

如果你希望在已有站点上叠加第一层能力，最小骨架如下：

```nginx
set $gateway_policy risk_gateway;
set $gateway_upstream api_backend;
set $gateway_upstream_uri $request_uri;
set $gateway_route default_route;
set $gateway_request_id "";
set $gateway_client_ip "";
set $gateway_circuit_state closed;
set $gateway_gray_variant stable;

include /etc/nginx/snippets/gateway-phase-common.conf;

location / {
    limit_req zone=per_ip_api burst=40 nodelay;
    include /etc/nginx/snippets/proxy-common.conf;
    proxy_next_upstream_tries 2;
    proxy_pass http://$gateway_upstream$gateway_upstream_uri;
}
```

然后再去 [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua) 里给这个站点增加策略。

推荐做法：

1. 先复制最接近的案例模板
2. 把变量和 Lua phase include 挪到你的老站配置里
3. 先只启一个最小策略
4. 通过后再继续加 JWT、HMAC、灰度或改写

不要直接把多个案例模板拼在同一个 `server` 里。

### 5.3 老站改造成热点活动入口

如果一个老站只是普通代理，但要临时承接热点活动入口，不建议只在原 `location /` 上继续堆 `limit_req`。

更推荐的做法是：

1. 新增一个独立域名或独立站点文件
2. 复制等待室模板
3. 只把热点入口与关键路径切到等待室方案
4. 其余普通页面仍保持原代理

原因：

- 回滚边界更清楚
- 等待室策略和普通站点策略不会互相污染
- 活动结束后可以单独下线

## 6. 站点文件里哪些地方通常要改

### 必改项

- `server_name`
- 证书路径
- access / error log 文件名
- `proxy_pass`

### 按场景改

- `limit_req`
- `set $gateway_policy`
- `set $admission_policy`
- `location = /api/...`
- `client_max_body_size`
- `proxy_read_timeout`
- `proxy_send_timeout`

### 尽量不要随便动

- `include /etc/nginx/snippets/ssl-common.conf`
- `include /etc/nginx/snippets/security-headers.conf`
- `include /etc/nginx/snippets/proxy-common.conf`

这些共享片段的意义就是统一收口，不要在每个站点里重新复制一份。

## 7. 策略文件怎么改

### 第一层策略

位置：

- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

适合改：

- 路由规则
- JWT / HMAC 鉴权
- 动态路由
- 灰度
- 风控
- 熔断 fallback
- 请求/响应改写

### 第二阶段策略

位置：

- [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua)

适合改：

- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`
- `queue.poll_interval_seconds`
- `protected.paths`

## 8. 修改后的最小验证矩阵

### 只改基础代理

```bash
make check
```

### 改第一层能力

```bash
make check
make test-first-layer
```

### 改等待室

```bash
make check
make test-waitroom
```

### 改动较大或不确定影响面

```bash
make test-comprehensive
```

## 9. 常见错误

### 把多个系统塞进同一个 `server`

结果：

- 认知边界混乱
- 回滚困难
- 文档和运维都容易失真

更推荐：

- 一个域名一个站点文件
- 一个系统一套策略

### 用真实 IP 作为唯一识别键

默认不要这样做。
尤其在 ELB、WAF、政务云代理前置场景里，真实 IP 经常不可靠。

优先顺序应该是：

1. `X-User-Id`
2. 业务 Cookie
3. `user_id`
4. 最后才回退到来源 IP

### 热点活动只靠 `limit_req`

如果业务是连续关键步骤，不要把“更狠的普通限流”当成等待室替代品。
普通限流无法保证已准入用户顺利走完关键链路。

## 10. 回滚建议

### 配置回滚

1. 恢复上一个站点文件版本
2. `make check`
3. `make reload`

### 策略回滚

1. 恢复上一个 `gateway_policy` 或 `admission_policy`
2. `make check`
3. 跑对应测试
4. `make reload`

### 热点活动临时下线

如果等待室只是临时活动使用，活动结束后建议：

1. 保留策略文件
2. 下线对应站点文件或切回普通代理模板
3. 不要把临时活动路径长期堆在日常站点上

## 11. 相关文档

- [README.md](/data/openresty-install/README.md)
- [docs/ARCHITECTURE.md](/data/openresty-install/docs/ARCHITECTURE.md)
- [docs/CONFIGURATION.md](/data/openresty-install/docs/CONFIGURATION.md)
- [docs/OPERATIONS.md](/data/openresty-install/docs/OPERATIONS.md)
- [docs/ADD_NEW_SYSTEM.md](/data/openresty-install/docs/ADD_NEW_SYSTEM.md)
- [examples/waitroom-best-practice.md](/data/openresty-install/examples/waitroom-best-practice.md)
