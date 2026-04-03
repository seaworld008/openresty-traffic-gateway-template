# OpenResty 单节点网关最佳实践模板

这个仓库是一套面向中小团队的 OpenResty 自建部署模板，目标不是“能跑起来就行”，而是尽量贴近生产可维护实践：单台 Linux 主机、Docker Compose 部署、所有持久化状态都放在当前仓库目录、目录结构清晰，后续其他项目可以直接 clone 后快速启动。

推荐 GitHub 中文描述：

- 面向生产的 OpenResty 流量网关模板，支持热点活动流量保护、等待室准入、关键链路保护与可复用策略控制。

## 这套模板解决什么问题

它不仅解决 OpenResty 如何启动，也解决后续怎么维护：

- 域名路由按站点文件拆分
- 所有站点子配置直接平铺在 `openresty/conf.d/`，避免额外目录层级
- 通用代理与 TLS 配置收敛到 snippets
- 日志、缓存、证书、ACME 状态都能在磁盘上直接看到
- 证书生命周期统一放在 `ssl/` 目录维护
- 没有真实业务服务时，也能用示例后端做本地烟雾测试

## 第一层默认能力层

当前模板已经内置一层适合日常业务网关的高级能力，并通过真实案例站点组合起来：

- JWT 鉴权
- HMAC / 时间戳签名校验
- 限流
- 基础灰度
- 基于配置文件的动态路由
- Redis 支持
- 统一请求 ID
- Header / Body 改写
- 上游失败重试与简单熔断
- 黑白名单 / UA / IP 风控基础版

这些能力统一下沉在 [openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)，站点本身只做策略组合，避免各业务域名重复造轮子。

## 第二阶段高并发等待室

针对抢课、报名、秒杀、抢票这类“短时间大波峰 + 多步骤关键链路”的场景，当前仓库新增了第二阶段能力：

- 等待室 / 排队入口
- 准入通行证
- 已准入用户的关键路径保护
- 入口流量与关键流程流量分层治理

这部分实现位于：

- [openresty/lua/admission](/data/openresty-install/openresty/lua/admission)
- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
- [examples/waitroom-best-practice.md](/data/openresty-install/examples/waitroom-best-practice.md)

这一层的目标不是“让所有人都能冲进后端”，而是：

- 在系统安全负载内，让已放行用户尽量走完关键步骤
- 超出安全负载后，把新流量放进排队区
- 尽量减少业务服务、数据库和支付链路被冲崩的风险

## 目标架构说明

### 架构 A：单机入口网关

典型流量路径：

```text
互联网 -> OpenResty -> 多个后端应用服务
```

OpenResty 位于所有应用服务之前，负责：

- 按域名路由
- TLS 终止
- 反向代理回源到内部服务
- 可选的静态资源缓存
- 提供统一的 HTTP 日志出口

这是中小团队最常见的第一阶段生产形态，因为应用服务不需要直接暴露公网，所有公网流量都统一由入口网关处理。

### 架构 B：单机入口承接多个业务域名

典型流量路径：

```text
Internet -> OpenResty
                  ├── www.example.com -> frontend
                  ├── api.example.com -> api-service
                  ├── admin.example.com -> admin-service
                  └── static.example.com -> static files / object storage / upstream
```

为什么按 `conf.d/*.conf` 平铺拆分：

- 每个域名可以独立变更
- 一份文件对应一个业务入口，认知成本低
- 回滚时影响面更小
- 多人同时改配置时更不容易冲突

为什么证书、日志、缓存目录要结构化：

- 证书状态可以单独备份
- 日志和缓存的磁盘增长更容易观察
- 排障时不需要到容器内部四处翻找

新增一个域名时，最小改动流程通常是：

1. 复制一个最接近的站点配置文件
2. 修改 `server_name`、证书路径和 `proxy_pass`
3. 申请证书
4. 执行配置校验并 reload

### 架构 C：OpenResty 作为统一 HTTPS 与安全入口

典型流量路径：

```text
互联网 -> OpenResty(443/80) -> Docker 私有网络中的内部应用服务
```

为什么把 TLS、转发和基础限流集中在入口层：

- 后端服务不需要直接开放公网端口
- HTTPS 策略统一
- 应用服务本身可以更简单
- 超时、上传限制、Header 规则都能统一落在一处

这套模板里体现的默认实践包括：

- 通过共享 snippet 输出常见安全头
- 采用相对稳妥的代理超时设置
- 默认上传限制可在站点级单独覆盖
- access log 和 error log 分离，分别用于流量分析和故障排查

### 架构 D：未来扩展到双机或前置负载均衡

当前仓库是单节点方案，但目录和配置风格已经为后续扩展预留空间：

- upstream 写法已经支持横向扩容
- 证书目录和配置目录都容易迁移
- 后续可以在前面接 keepalived、云 SLB 或硬件 LB
- 多台 OpenResty 可以继续复用这套结构，再叠加证书同步机制

## 仓库目录结构

```text
.
├── docker-compose.yml
├── .env.example
├── README.md
├── docs/plans/
├── openresty/
│   ├── nginx.conf
│   ├── conf.d/
│   │   ├── 00-global.conf
│   │   ├── 01-upstreams.conf
│   │   ├── 10-real-ip.conf.example
│   │   ├── README.md
│   │   ├── frontend-proxy.conf.example
│   │   ├── api-proxy.conf.example
│   │   ├── admin-console-proxy.conf.example
│   │   ├── static-local-root.conf.example
│   │   ├── risk-protected-proxy.conf.example
│   │   ├── partner-api-gateway.conf.example
│   │   ├── gray-release-proxy.conf.example
│   │   ├── llm-api-proxy.conf.example
│   │   ├── llm-relay-token-guard.conf.example
│   │   └── waitroom-enrollment-gateway.conf.example
│   ├── snippets/
│   ├── logs/
│   ├── cache/
│   ├── certs/
│   ├── html/
│   └── lua/
├── ssl/
│   ├── acme/
│   ├── certbot/
│   ├── scripts/
│   └── README.md
└── examples/
```

## 为什么必须固定镜像 tag

默认 OpenResty 镜像固定为：

```yaml
openresty/openresty:1.29.2.2-1-bookworm-fat
```

必须使用完整 tag，而不是 `latest` 或浮动 tag，原因有四个：

- 不同环境的网关行为才能可重复
- 升级动作才是显式、可审查的
- 底层镜像静默变化会让排障变得更难
- 只有知道上一版到底是什么，回滚才可靠

Certbot 镜像也在 `.env.example` 里固定了 tag，理由完全相同。

补充说明：

- 原始目标 tag `openresty/openresty:1.29.2.3-0-bookworm-fat` 在本机实际拉取时返回 `manifest unknown`
- 因此这里按“官方镜像 + 稳定版本 + 完整 tag”原则，改为已经验证存在的 `openresty/openresty:1.29.2.2-1-bookworm-fat`
- Certbot 镜像实际可拉取的完整 tag 为 `certbot/certbot:v5.4.0`，需要保留 `v` 前缀

## GitHub 展示建议

### 推荐仓库名

- `openresty-traffic-gateway-template`

### 推荐 GitHub 中文描述

- 面向生产的 OpenResty 流量网关模板，支持热点活动流量保护、等待室准入、关键链路保护与可复用策略控制。

### 推荐 GitHub 英文描述

- Production-ready OpenResty gateway template with traffic protection, waitroom admission control, and reusable policy-based routing.

### 推荐 Topics

- `openresty`
- `nginx`
- `gateway`
- `reverse-proxy`
- `traffic-control`
- `rate-limit`
- `waitroom`
- `admission-control`
- `high-concurrency`
- `hotspot-protection`
- `flash-sale`
- `ticketing`
- `enrollment`
- `policy-based-routing`
- `traffic-gateway`

### 推荐搜索关键词

为了让 GitHub 搜索、站内检索和搜索引擎更容易命中，建议在 README 首屏或项目简介中长期保留这些中英文关键词：

- OpenResty
- Nginx Gateway
- 流量网关
- 反向代理
- 热点活动保护
- 等待室
- 排队准入
- Admission Control
- Waitroom
- 高并发
- 抢课
- 报名系统
- 秒杀
- 预约放号
- Reverse Proxy
- Traffic Protection
- Protected Checkout Flow

## 快速开始

### 1. 初始化环境

```bash
cp .env.example .env
mkdir -p openresty/logs openresty/cache ssl/certbot/conf ssl/certbot/www
chmod +x ssl/scripts/*.sh
```

如果你希望统一走仓库内置命令，也可以直接执行：

```bash
make init
```

### 2. 本地烟雾测试模式

先为示例域名生成本地自签证书：

```bash
./ssl/scripts/init-local-certs.sh
```

再启动整套服务：

```bash
docker compose -f docker-compose.yml -f examples/backend/docker-compose.local.yml up -d
```

或者：

```bash
make up-local
```

执行配置校验：

```bash
docker compose exec -T openresty openresty -t
```

或者：

```bash
make check
```

也可以在站点配置目录直接执行：

```bash
cd openresty/conf.d
./confctl.sh test
```

然后按 [examples/curl-tests.md](/data/openresty-install/examples/curl-tests.md) 中的步骤做验证。

### 3. 生产证书申请

先启动 OpenResty，让 ACME webroot 可以被访问到：

```bash
docker compose up -d openresty
```

再申请证书：

```bash
./ssl/scripts/init-cert.sh --email ops@example.com \
  www.example.com api.example.com admin.example.com static.example.com
```

第一次在真实域名上验证时，建议先走 staging：

```bash
./ssl/scripts/init-cert.sh --email ops@example.com --staging \
  www.example.com api.example.com admin.example.com static.example.com
```

## Compose 设计说明

- `openresty` 是唯一对外暴露的服务，绑定 `80:80` 和 `443:443`
- `certbot` 是工具型服务，通过脚本执行 `docker compose run --rm` 来调用
- 主 `docker-compose.yml` 只保留核心服务；示例后端已拆到 `examples/backend/docker-compose.local.yml`
- 所有挂载目录都基于仓库相对路径
- 日志、缓存和证书都可以跨容器重建持久保留

## 配置设计说明

### 主配置

`openresty/nginx.conf` 负责 worker、events、日志格式、HTTP 基础优化，并装载 `openresty/conf.d/*.conf`。

### 全局配置

`openresty/conf.d/00-global.conf` 统一放这些内容：

- Docker 内置 DNS 解析
- ACME challenge 路径
- 请求限流区域
- 缓存路径定义
- 默认健康检查接口

### Upstreams

`openresty/conf.d/01-upstreams.conf` 把后端拓扑从站点路由中分离出来，后续扩容应用实例时，通常只需要改 upstream 定义。

### 站点文件

每个站点示例都遵循同一结构：

1. `80` 端口用于 ACME challenge 和 HTTPS 跳转
2. `443` 端口挂载证书并提供正式流量入口
3. 引入共享 TLS 和安全头 snippets
4. 保留当前站点自己的代理、缓存或限流逻辑

额外约定：

- `80` 端口的 HTTP server 只做 ACME challenge 和 301 跳转
- HTTP 跳转 server 默认不写 access log
- 正式业务日志只保留在 `443` 入口 server

### Snippets

- `proxy-common.conf`：统一反向代理头和超时参数
- `ssl-common.conf`：统一 TLS 参数
- `security-headers.conf`：统一安全响应头
- `cache-common.conf`：统一静态资源缓存策略
- `gateway-phase-common.conf`：统一挂载 Lua access/header/body/log 阶段能力

### 第一层能力层

公共能力代码位于 [openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)：

- [openresty/lua/gateway/init.lua](/data/openresty-install/openresty/lua/gateway/init.lua)：统一入口，负责把策略、鉴权、风控、路由和改写串起来
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)：案例策略配置文件，也是动态路由的配置来源
- [openresty/lua/gateway/redis_client.lua](/data/openresty-install/openresty/lua/gateway/redis_client.lua)：外部 Redis 连接封装
- [openresty/lua/gateway/jwt.lua](/data/openresty-install/openresty/lua/gateway/jwt.lua)：HS256 JWT 校验
- [openresty/lua/gateway/signature.lua](/data/openresty-install/openresty/lua/gateway/signature.lua)：HMAC / 时间戳签名校验
- [openresty/lua/gateway/risk.lua](/data/openresty-install/openresty/lua/gateway/risk.lua)：IP / UA 风控
- [openresty/lua/gateway/router.lua](/data/openresty-install/openresty/lua/gateway/router.lua)：配置化路由与灰度决策
- [openresty/lua/gateway/circuit_breaker.lua](/data/openresty-install/openresty/lua/gateway/circuit_breaker.lua)：基础熔断
- [openresty/lua/gateway/rewrite.lua](/data/openresty-install/openresty/lua/gateway/rewrite.lua)：请求 Header / Body 改写
- [openresty/lua/gateway/response.lua](/data/openresty-install/openresty/lua/gateway/response.lua)：响应头与 JSON 响应体补写

### 高级案例站点

- [openresty/conf.d/risk-protected-proxy.conf.example](/data/openresty-install/openresty/conf.d/risk-protected-proxy.conf.example)
  日常风控入口案例，覆盖限流、UA 风控、IP 黑白名单、失败重试和简单熔断。
- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)
  对接型 API 案例，覆盖 JWT、HMAC、Redis 合作方配置、统一请求 ID、Header / Body 改写和动态路由。
- [openresty/conf.d/gray-release-proxy.conf.example](/data/openresty-install/openresty/conf.d/gray-release-proxy.conf.example)
  灰度发布案例，覆盖 Header 灰度、按百分比灰度和 Redis 统一开关。
- [openresty/conf.d/llm-api-proxy.conf.example](/data/openresty-install/openresty/conf.d/llm-api-proxy.conf.example)
  大模型 API 网关模板，适合 OpenAI 兼容接口、内部推理服务与流式输出场景。
- [openresty/conf.d/llm-relay-token-guard.conf.example](/data/openresty-install/openresty/conf.d/llm-relay-token-guard.conf.example)
  大模型中转源站保护模板，适合只允许本机或可信中转层访问的 relay 场景。
- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
  第二阶段等待室案例，覆盖入口排队、准入通行证、关键步骤保护和通用可调阈值策略。

### 第二阶段策略怎么调

等待室策略位于 [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua)。

最常调整的是：

- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`
- `queue.ttl_seconds`
- `queue.poll_interval_seconds`
- `protected.paths`

如果某个系统压测结论是“最大安全合理并发 10000”，就可以把该策略设为 `steady=10000, burst=12000`。
如果另一个系统只有 `2000`，就可以设为 `steady=2000, burst=2400`。
这套逻辑本身不需要改。

### 第二阶段默认不依赖真实 IP

等待室与准入保护的核心身份键，默认优先用：

- `X-User-Id`
- 业务用户 Cookie
- `user_id` 参数

只有拿不到这些标识时，才回退到来源 IP。
这样在政务云、统一内网 ELB、统一代理出口等环境里，仍然可以稳定工作。

如果你的环境能可靠透传真实客户端 IP，可以按需启用：

- [openresty/conf.d/10-real-ip.conf.example](/data/openresty-install/openresty/conf.d/10-real-ip.conf.example)

## 如何新增一个生产域名

1. 从 `openresty/conf.d/` 里复制一个最接近的站点文件
2. 修改 `server_name`
3. 改成真实域名对应的证书路径
4. 调整 `proxy_pass` 或静态资源 root
5. 执行 `docker compose exec -T openresty openresty -t`
6. 用 `./ssl/scripts/init-cert.sh` 申请证书
7. 用 `./ssl/scripts/reload-openresty.sh` 触发重载

如果你要处理的是“老站如何渐进式加限流、风控、熔断”或“热点活动如何接入等待室”，请直接参考：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
  按场景给出可操作步骤、最小改动点、检查命令和回滚建议

## 日常运维命令

如果你希望降低使用门槛，建议优先使用 `Makefile` 里的固定入口命令。

### 校验配置

```bash
docker compose exec -T openresty openresty -t
```

```bash
make check
```

### 配置改完后 reload

```bash
./ssl/scripts/reload-openresty.sh
```

```bash
make reload
```

### 续签证书

```bash
./ssl/scripts/renew-cert.sh
```

```bash
make renew
```

### 查看日志

```bash
tail -f openresty/logs/error.log
tail -f openresty/logs/access.log
```

按站点拆分的 access / error 日志也会写到 `openresty/logs/` 下。

### 启动外部 Redis 测试容器

注意：Redis 不在仓库 Compose 里固化，只在本机或测试环境中作为外部依赖接入。

```bash
make redis-test-up
```

### 关闭外部 Redis 测试容器

```bash
make redis-test-down
```

### 测试第二阶段等待室

```bash
make test-waitroom
```

### 跑第二阶段并发模拟

```bash
make benchmark-waitroom
```

如果需要更高并发模拟，可以直接带参数：

```bash
python3 examples/scripts/benchmark_waitroom.py --total 300 --concurrency 300
```

### 跑第一层网关并发压测

```bash
make benchmark-gateway
```

更高一点的压测示例：

```bash
python3 examples/scripts/benchmark_gateway.py \
  --frontend-total 4000 \
  --frontend-concurrency 400 \
  --risk-total 1500 \
  --risk-concurrency 150 \
  --partner-total 1200 \
  --partner-concurrency 120
```

### 查看等待室当前状态

```bash
make waitroom-summary
```

这条接口是第二阶段的轻量运维摘要，适合查看：

- 当前稳态容量
- 当前突发容量
- 当前活跃准入数
- 当前排队人数
- 当前受保护关键路径

生产环境请务必修改 `.env` 中的 `GATEWAY_OPS_TOKEN`。

### 一键综合验证

```bash
make test-comprehensive
```

## 详细手册

为方便实施、运维和后续扩展，当前仓库补充了三份详细手册：

- [docs/ARCHITECTURE.md](/data/openresty-install/docs/ARCHITECTURE.md)
  当前最终架构设计说明
- [docs/OPERATIONS.md](/data/openresty-install/docs/OPERATIONS.md)
  日常运维、排障、活动高峰前检查与变更流程
- [docs/CONFIGURATION.md](/data/openresty-install/docs/CONFIGURATION.md)
  配置修改、扩系统、调容量、启停不同能力层的操作说明

另外还有两份补充文档：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
  按场景说明如何新增站点、改造老站、接入第一层能力或等待室
- [docs/ADD_NEW_SYSTEM.md](/data/openresty-install/docs/ADD_NEW_SYSTEM.md)
  新增一个系统时的快速操作说明
- [docs/DOC_SYNC_POLICY.md](/data/openresty-install/docs/DOC_SYNC_POLICY.md)
  后续改代码时应同步更新哪些文档的约定

### 停止服务

```bash
docker compose down
```

```bash
make down
```

如果当前是本地联调模式，推荐直接执行：

```bash
make down-local
```

## 运维最佳实践

- 真实证书和账户密钥绝对不要提交到 Git。
- 备份时至少覆盖 `ssl/certbot/conf/`、`openresty/conf.d/`、`openresty/snippets/` 和 `.env`。
- 证书续签建议由宿主机 cron 或 systemd timer 触发，而不是依赖容器内隐藏循环。
- 升级镜像时一定要先在预发布环境验证新 tag，再推进到生产。
- HSTS 只有在真实生产域名的 HTTPS 已完全稳定后再开启。
- 扩容优先从 upstream 横向加后端实例开始，单节点真成为瓶颈时再考虑多台网关。

## 排障指南

### OpenResty 启动失败

- 先执行 `docker compose logs openresty`
- 再执行 `docker compose run --rm openresty openresty -t`
- 确认证书文件确实存在于 `ssl/certbot/conf/live/<domain>/`

### ACME 签发失败

- 确认公网 DNS 已经解析到当前主机
- 确认公网可以访问 `80/tcp`
- 确认对应 `server_name` 已配置并能处理 `/.well-known/acme-challenge/`
- 建议先用 `--staging` 重试

### Upstream 返回 502 / 504

- 执行 `docker compose ps`
- 检查 upstream 中的服务名是否和 Compose 服务名一致
- 查看 `openresty/logs/` 下对应站点的 error log

## 维护与升级流程

1. 先把仓库部署到预发布环境。
2. 显式修改固定镜像 tag。
3. 执行 `docker compose pull`。
4. 执行 `docker compose exec -T openresty openresty -t` 或 `docker compose run --rm openresty openresty -t`。
5. 启动服务并跑一遍 curl 烟雾测试。
6. 确认无误后再把同一提交推到生产。

## 仓库内验证说明

以后只要模板有改动，都建议同步更新本地验证命令和结果。验证入口见 [examples/curl-tests.md](/data/openresty-install/examples/curl-tests.md)，设计背景见 `docs/plans/` 下的说明文档。

本仓库已在本机于 `2026-04-03` 重新完成以下实际验证：

- `make check`
- `make test-comprehensive`

验证结果摘要：

- OpenResty 配置语法通过
- `risk-gateway.example.test` 已验证 UA 风控、IP 黑白名单、限流和简单熔断
- `partner-api.example.test` 已验证 JWT、HMAC、Redis 合作方配置、Header / Body 改写和动态路由
- `gray-release.example.test` 已验证灰度命中与 Redis 统一关闭灰度
- `enroll.example.test` 已验证等待室入口、准入通行证、关键路径保护和排队补位
- 综合验证中的第一层并发压测、等待室并发模拟与等待室摘要查询全部通过
- 本地自动化测试中的 Redis 已按带密码模式验证通过

高级能力测试命令与说明见 [examples/advanced-tests.md](/data/openresty-install/examples/advanced-tests.md)。
