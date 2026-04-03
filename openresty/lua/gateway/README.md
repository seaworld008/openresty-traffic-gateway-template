# 第一层公共网关能力说明

这个目录存放第一层公共网关能力，适合普通 API、合作方接入、后台服务、动态路由和基础风控场景。

## 模块职责

- `init.lua`
  第一层入口，负责串联请求 ID、鉴权、风控、路由、改写和熔断逻辑
- `policies.lua`
  第一层策略配置
- `request_id.lua`
  统一请求 ID
- `redis_client.lua`
  Redis 连接封装
- `jwt.lua`
  HS256 JWT 校验
- `signature.lua`
  HMAC / 时间戳签名校验
- `risk.lua`
  IP / UA 风控
- `router.lua`
  动态路由与灰度决策
- `circuit_breaker.lua`
  简化版熔断
- `rewrite.lua`
  请求 Header / Body 改写
- `response.lua`
  响应 Header / JSON 改写
- `util.lua`
  通用工具函数

## 调用阶段

- `access.lua`
  运行在 `access_by_lua`
- `header_filter.lua`
  运行在 `header_filter_by_lua`
- `body_filter.lua`
  运行在 `body_filter_by_lua`
- `log.lua`
  运行在 `log_by_lua`

## 适合什么场景

- 普通反向代理 API
- 合作方接口
- 动态路由 API
- 带 JWT/HMAC 的接入层
- 需要基础熔断、风控、灰度的服务

## 不适合什么场景

- 热点活动入口
- 抢课 / 秒杀 / 抢票主入口
- 需要等待室和准入保护的关键链路

这类场景应优先看：

- `openresty/lua/admission/`

如果你要把这些能力接到一个新站或老站上，实施步骤见：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
