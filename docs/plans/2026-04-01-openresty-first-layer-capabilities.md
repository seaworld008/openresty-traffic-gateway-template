# OpenResty 第一层能力层实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 在现有单节点 OpenResty 网关模板上，增加中小团队日常最常用的第一层高级网关能力，并用多个真实业务风格案例站点把这些能力组合起来。

**架构：** 公共能力全部下沉到 `openresty/lua/` 与共享 snippets 中，站点配置只负责声明策略和组合功能。Redis 不进入仓库 Compose 编排，而是通过可配置外部地址接入；本机测试时使用单独启动的 Redis 容器挂到同一 Docker 网络。

**技术栈：** OpenResty Lua、resty.redis、Docker Compose、Shell 脚本、Markdown 文档

---

### Task 1: 扩展基础运行时与示例后端

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.env.example`
- Modify: `openresty/nginx.conf`
- Create: `examples/advanced-tests.md`
- Create: `examples/scripts/test-first-layer.sh`

**Step 1: 增加外部 Redis 所需环境变量**

让 OpenResty 能通过环境变量读取 Redis 地址、端口、库号和超时参数。

**Step 2: 增加适合请求回显与 JSON 测试的示例后端**

新增一个固定 tag 的 HTTP echo / httpbin 风格后端，用于 header/body 改写与签名校验案例。

**Step 3: 为 Lua 能力层声明共享字典**

为熔断状态、临时缓存和灰度状态预留 `lua_shared_dict`。

### Task 2: 实现公共 Lua 能力层

**Files:**
- Create: `openresty/lua/gateway/init.lua`
- Create: `openresty/lua/gateway/config_loader.lua`
- Create: `openresty/lua/gateway/request_id.lua`
- Create: `openresty/lua/gateway/redis_client.lua`
- Create: `openresty/lua/gateway/jwt.lua`
- Create: `openresty/lua/gateway/signature.lua`
- Create: `openresty/lua/gateway/risk.lua`
- Create: `openresty/lua/gateway/router.lua`
- Create: `openresty/lua/gateway/circuit_breaker.lua`
- Create: `openresty/lua/gateway/rewrite.lua`
- Create: `openresty/lua/gateway/response.lua`
- Create: `openresty/lua/gateway/util.lua`
- Create: `openresty/lua/gateway/policies.lua`

**Step 1: 实现统一请求上下文与请求 ID**

确保每个请求都有统一请求 ID，并回写到上游 Header 和响应 Header。

**Step 2: 实现 Redis 客户端与配置装载**

封装 Redis 连接与基础 get/set 读取，支持外部 Redis 地址。

**Step 3: 实现 JWT 与 HMAC/时间戳校验**

先支持最常见、最稳妥的 HS256 JWT 和共享密钥 HMAC 签名。

**Step 4: 实现基础风控与路由逻辑**

包含 IP 黑白名单、UA 拦截、基础限流辅助、动态路由与灰度决策。

**Step 5: 实现简单熔断**

支持基于失败次数和冷却时间的基础熔断，打开后走 fallback 上游。

**Step 6: 实现请求/响应改写**

支持常见 header 注入、删除、透传，以及 JSON body 的轻量级请求改写。

### Task 3: 增加案例站点配置

**Files:**
- Create: `openresty/conf.d/sites/case-risk-gateway.conf`
- Create: `openresty/conf.d/sites/case-partner-api.conf`
- Create: `openresty/conf.d/sites/case-gray-release.conf`
- Create: `openresty/snippets/gateway-phase-common.conf`

**Step 1: 风控与稳定性案例**

案例域名 `risk-gateway.example.test`，实现日志、限流、IP/UA 风控、黑白名单、上游失败重试和简单熔断。

**Step 2: 对接型 API 案例**

案例域名 `partner-api.example.test`，实现 JWT、HMAC/时间戳、Redis 支持、统一请求 ID、header/body 改写和动态路由。

**Step 3: 灰度发布案例**

案例域名 `gray-release.example.test`，实现按 Header/Cookie/百分比的基础灰度与配置化动态路由。

### Task 4: 编写本机真实测试流程

**Files:**
- Modify: `README.md`
- Modify: `examples/curl-tests.md`
- Modify: `ssl/scripts/init-local-certs.sh`
- Modify: `Makefile`
- Modify: `examples/advanced-tests.md`
- Modify: `examples/scripts/test-first-layer.sh`

**Step 1: 扩展本地证书脚本**

让新增案例域名也能一键生成自签证书。

**Step 2: 编写高级能力测试文档**

覆盖 Redis 启动、数据预热、JWT/HMAC 构造、风险案例与灰度案例验证命令。

**Step 3: 编写自动化测试脚本**

脚本负责启动外部 Redis 容器、写入测试数据、拉起网关栈并执行校验。

### Task 5: 端到端验证

**Files:**
- Modify: `README.md`

**Step 1: 校验 Lua 文件与配置语法**

Run: `docker compose exec -T openresty openresty -t`
预期结果：配置语法通过

**Step 2: 启动外部 Redis 容器并写入测试数据**

Run: `docker run ... redis:7.x ...`
预期结果：Redis 可以被 OpenResty 访问

**Step 3: 启动网关和示例后端**

Run: `docker compose up -d`
预期结果：所有案例域名可访问

**Step 4: 执行高级能力测试**

覆盖 JWT、HMAC、限流、黑白名单、UA 拦截、灰度、动态路由、改写、熔断。

**Step 5: 回写验证结果**

把真实可用的命令与注意事项写回文档。
