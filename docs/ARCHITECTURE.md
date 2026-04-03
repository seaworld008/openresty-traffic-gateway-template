# OpenResty 网关架构设计说明

## 1. 文档目的

这份文档描述当前仓库的最终架构形态，目标读者包括：

- 运维工程师
- 平台工程师
- 实施工程师
- 需要基于本仓库扩展新业务系统的研发人员

本文只讨论当前仓库已经落地的方案，不讨论尚未实现的理想形态。

## 2. 总体设计目标

当前仓库围绕四个目标设计：

1. 单节点自建部署，结构清晰，可快速 clone 并启动
2. 同时支持普通反向代理场景和热点活动场景
3. 在不明显增加系统复杂度的前提下，尽量提高稳定性和可维护性
4. 通过策略配置而不是改代码的方式，支持不同系统、不同容量模型和不同流量治理策略

额外的结构约束：

- 主 `docker-compose.yml` 只保留核心服务
- 本地联调示例后端统一放在 `examples/backend/`

## 3. 架构分层

当前架构可以理解成三层：

### 3.1 基础网关层

基础网关层负责：

- 80/443 入口
- TLS 终止
- 域名路由
- 基础反向代理
- 日志
- 缓存
- 通用安全 Header
- 常见超时、连接和请求大小控制

关键文件：

- [docker-compose.yml](/data/openresty-install/docker-compose.yml)
- [examples/backend/docker-compose.local.yml](/data/openresty-install/examples/backend/docker-compose.local.yml)
- [openresty/nginx.conf](/data/openresty-install/openresty/nginx.conf)
- [openresty/conf.d/00-global.conf](/data/openresty-install/openresty/conf.d/00-global.conf)
- [openresty/conf.d/01-upstreams.conf](/data/openresty-install/openresty/conf.d/01-upstreams.conf)
- [openresty/snippets](/data/openresty-install/openresty/snippets)

### 3.2 第一层公共能力层

第一层能力层用于普通 API / BFF / 合作方接入类场景，提供：

- JWT 鉴权
- HMAC / 时间戳签名
- 统一请求 ID
- 动态路由
- 基础灰度
- 风控
- Header / Body 改写
- Redis 辅助配置
- 上游失败重试与简单熔断

关键文件：

- [openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)
- [openresty/conf.d/risk-protected-proxy.conf.example](/data/openresty-install/openresty/conf.d/risk-protected-proxy.conf.example)
- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)
- [openresty/conf.d/gray-release-proxy.conf.example](/data/openresty-install/openresty/conf.d/gray-release-proxy.conf.example)

### 3.3 第二阶段高并发等待室层

第二阶段等待室层面向热点报名、抢课、秒杀、预约放号等场景，提供：

- 等待室入口
- 排队状态查询
- 准入通行证
- 稳态容量与突发缓冲
- 已准入用户关键步骤保护
- 轻量运维摘要

关键文件：

- [openresty/lua/admission](/data/openresty-install/openresty/lua/admission)
- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
- [openresty/conf.d/waitroom-java-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-java-gateway.conf.example)
- [openresty/html/waitroom/index.html](/data/openresty-install/openresty/html/waitroom/index.html)
- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)

## 4. 为什么要区分第一层和第二阶段

这两个层次解决的问题不同。

### 4.1 第一层适合“普通高并发接口”

例如：

- API 网关
- 合作方回调入口
- 管理后台 API
- 内容服务 API
- 支付回调接口

这类场景更关注：

- 鉴权
- 风控
- 动态路由
- 熔断
- 灰度
- 基础限流

### 4.2 第二阶段适合“热点活动入口”

例如：

- 抢课报名
- 秒杀下单
- 放号预约
- 抢名额
- 热点活动报名

这类场景不能只靠普通限流，因为普通限流容易出现：

- 第一步放行
- 第二步被限掉
- 第三步支付被阻断

所以第二阶段方案的核心不是“多加几个 limit_req”，而是：

- 新流量先做准入判断
- 已准入用户继续走关键链路
- 超限流量进入等待室

## 5. 第二阶段的工程思路

第二阶段借鉴了业界常见的稳态保护思路，接近于：

- 稳态容量保护
- 短时突发缓冲
- 超限排队
- 已准入关键链路保护

在 OpenResty 中落地为：

- `capacity.steady`
- `capacity.burst`
- `queue`
- `token`
- `protected.paths`

这些参数都在策略中定义，而不是写死在 Lua 逻辑里。

## 6. 为什么第二阶段默认不依赖真实 IP

在很多真实环境里，例如：

- 政务云内网
- 统一 ELB
- 内网 WAF / Ingress / 代理前置

OpenResty 经常看不到真实客户端 IP，只能看到统一的上游出口 IP。

如果在这种环境下强依赖真实 IP：

- 用户限流会误伤
- 排队会失真
- 风控会失真

所以当前方案默认这样做：

1. 优先按 `X-User-Id`
2. 其次按业务 Cookie
3. 再次按 `user_id` 参数
4. 最后才回退到来源 IP

真实 IP 解析只保留为可选增强能力，见：

- [openresty/conf.d/10-real-ip.conf.example](/data/openresty-install/openresty/conf.d/10-real-ip.conf.example)

## 7. 通用扩展方式

这套架构支持扩展到多个系统。

推荐复用方式：

### 7.1 一个系统一套策略

不同业务系统应使用不同策略，而不是共用一套容量参数。

例如：

- 系统 A：`steady=10000, burst=12000`
- 系统 B：`steady=2000, burst=2400`
- 系统 C：只启用第一层，不启用等待室

### 7.2 一个域名一个站点文件

不同系统继续保持“一个域名一个站点文件”的结构。

这样可以保证：

- 改动边界清晰
- 回滚容易
- merge conflict 少

### 7.3 公共逻辑不下沉到站点文件

公共逻辑应尽量留在：

- [openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)
- [openresty/lua/admission](/data/openresty-install/openresty/lua/admission)

站点文件只负责：

- 绑定策略
- 绑定域名
- 指定关键路径
- 指定回源 upstream

当前仓库约定：业务 upstream 也直接写在各自站点模板中。

这样做的原因是：

- 复制模板时更容易保持单文件闭环
- 回滚时不用跨多个配置文件同步修改
- 对“等待室 -> Java gateway”这类单系统入口尤其友好

## 8. 当前架构的边界

这套方案当前已经适合作为生产基线，但仍然有边界：

- 它可以保护入口，不替代业务系统的库存、座位、订单状态机
- 它适合单节点和中小规模扩展，不等于已经做成分布式多机高可用平台
- 它已经有轻量观测，但不是完整监控平台

## 9. 推荐的上线使用方式

建议按以下顺序使用：

1. 在新系统上先启基础网关层
2. 再按业务需要启第一层公共能力
3. 只有热点活动入口才启第二阶段等待室
4. 通过压测确定 `capacity.steady` 与 `capacity.burst`
5. 上线前跑 [examples/scripts/run_comprehensive_validation.sh](/data/openresty-install/examples/scripts/run_comprehensive_validation.sh)

## 10. 相关文档

- [README.md](/data/openresty-install/README.md)
- [docs/OPERATIONS.md](/data/openresty-install/docs/OPERATIONS.md)
- [docs/CONFIGURATION.md](/data/openresty-install/docs/CONFIGURATION.md)
- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
- [examples/waitroom-best-practice.md](/data/openresty-install/examples/waitroom-best-practice.md)
