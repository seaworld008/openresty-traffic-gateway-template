# OpenResty 配置与扩展手册

## 1. 目标

这份文档说明如何：

- 改现有配置
- 新增一个系统
- 调整等待室容量
- 选择是否启用第一层和第二阶段能力

如果你要找“按场景操作”的详细步骤，例如：

- 新站怎么接
- 老站怎么增量加限流 / 风控 / 熔断
- 热点活动怎么接等待室

请直接看：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)

## 2. 配置分层

### 2.1 主配置

- [openresty/nginx.conf](/data/openresty-install/openresty/nginx.conf)

负责：

- worker
- 连接数
- 日志格式
- 共享字典
- 顶层 include

### 2.2 全局配置

- [openresty/conf.d/00-global.conf](/data/openresty-install/openresty/conf.d/00-global.conf)

负责：

- 全局 map
- 限流区
- 缓存路径
- 默认 server

### 2.3 Upstream

- [openresty/conf.d/01-upstreams.conf](/data/openresty-install/openresty/conf.d/01-upstreams.conf)

负责后端服务拓扑定义。

当前 upstream 已按运行期 DNS 解析方式配置，因此主栈不再强依赖本地示例后端必须存在。

### 2.4 可选真实 IP

- [openresty/conf.d/10-real-ip.conf.example](/data/openresty-install/openresty/conf.d/10-real-ip.conf.example)

只有在环境能够可靠透传真实 IP 时才启用。

### 2.5 站点文件

- [openresty/conf.d](/data/openresty-install/openresty/conf.d)

每个域名一个模板文件，直接平铺在 `conf.d/` 下，统一使用 `*.conf.example`。

### 2.6 Lua 逻辑

- 第一层公共能力：[openresty/lua/gateway](/data/openresty-install/openresty/lua/gateway)
- 第二阶段等待室：[openresty/lua/admission](/data/openresty-install/openresty/lua/admission)

### 2.7 本地测试后端

- [examples/backend/docker-compose.local.yml](/data/openresty-install/examples/backend/docker-compose.local.yml)

这个文件只用于本地联调与功能验证，不属于生产主栈。

### 2.8 场景化接入指引

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)

当你要做“新增站点”或“老站改造”时，优先先看这份文档，再回来改具体配置。

## 3. 如何修改容量参数

第二阶段容量配置位于：

- [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua)

### 3.1 稳态容量

```lua
capacity = {
    steady = 10000,
    burst = 12000,
}
```

`steady` 表示稳态安全容量。

### 3.2 突发容量

`burst` 表示短时突发缓冲容量。

建议：

- `burst` 通常设置为 `steady` 的 1.1 到 1.3 倍
- 不建议把 `burst` 设得过大，否则会失去“缓冲”的意义，变成直接放大压力

## 4. 如何新增一个热点活动系统

推荐流程：

### 第一步：复制站点文件

复制：

- [waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)

改成你的新系统文件，例如：

- `campus-a-enrollment-gateway.conf`

### 第二步：修改域名和策略 ID

例如：

```nginx
server_name campus-a.example.com;
set $admission_policy campus_a_enroll;
```

### 第三步：新增策略

在策略文件中新增一套策略：

```lua
campus_a_enroll = {
    policy_id = "campus_a_enroll",
    activity_id = "campus-a-2026-spring",
    ...
}
```

### 第四步：修改关键路径

根据业务实际改：

- 报名入口
- 排队状态接口
- 加车
- 确认
- 支付
- 订单查询

### 第五步：校验并测试

```bash
make check
make test-waitroom
```

## 5. 如何新增一个普通 API 系统

如果新系统不需要等待室，只需要第一层公共能力：

1. 复制 [partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example) 或其他合适模板
2. 绑定新的 `gateway_policy`
3. 在 [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua) 中增加策略
4. `make check`

## 6. 什么时候启用哪一层

### 只启基础网关层

适合：

- 官网
- 静态资源
- 普通后台

### 启第一层公共能力

适合：

- 合作方 API
- 外部回调
- 动态路由
- 基础风控
- 大模型 API 入口
- 大模型 Relay 源站保护

### 启第二阶段等待室

适合：

- 抢课
- 热点报名
- 秒杀
- 放号预约

## 7. 参数建议

### 小系统

可参考：

- `steady = 2000`
- `burst = 2400`
- `token.ttl_seconds = 600`
- `queue.poll_interval_seconds = 3`

### 中大型系统

可参考：

- `steady = 10000`
- `burst = 12000`
- `token.ttl_seconds = 900`
- `queue.poll_interval_seconds = 3`

### 政务云保守模板

可参考：

- `steady = 6000`
- `burst = 7200`
- `token.ttl_seconds = 900`
- `queue.poll_interval_seconds = 3`

这些值不是固定模板，只是容量起点。
最终仍应以压测和真实业务链路时长为准。

## 8. 如何启用真实 IP

如果上游网络能可靠透传真实 IP：

```bash
cp openresty/conf.d/10-real-ip.conf.example openresty/conf.d/10-real-ip.conf
make reload
```

如果不能可靠透传，就不要启用。

## 9. 如何回滚

### 回滚配置

1. 恢复上一个版本的配置文件
2. `make check`
3. `make reload`

### 回滚策略参数

如果只是容量参数调错：

1. 把 `capacity.steady` / `capacity.burst` 改回原值
2. `make check`
3. `make reload`

## 10. 推荐管理方式

为了后续多系统管理清晰，建议遵循：

- 一个域名一个站点文件
- 一类系统一套策略
- 先改策略，再改代码
- 默认参数只用于测试，不直接用于生产

## 11. 相关文档

- [docs/ARCHITECTURE.md](/data/openresty-install/docs/ARCHITECTURE.md)
- [docs/OPERATIONS.md](/data/openresty-install/docs/OPERATIONS.md)
- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
- [README.md](/data/openresty-install/README.md)
