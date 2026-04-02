# 第二阶段高并发等待室最佳实践

这套方案不是“把普通限流调得更狠”，而是把流量分成两类：

- 新进入热点活动的流量
- 已经拿到准入资格、正在完成关键交易链路的流量

对应到抢课、报名、秒杀、抢票这类场景，核心原则是：

- 新人流量先过等待室
- 已准入用户拿到短期通行证
- 加车、确认、支付、订单查询等关键步骤走受保护通道
- 系统超过安全负载时，新流量排队，不直接冲业务服务

## 为什么适合你们的场景

针对“抢课 -> 加购物车 -> 支付”这类连续动作，普通限流会出现：

- 抢课成功
- 购物车被限
- 支付又被挡

这会让用户体验非常差。

等待室 + 准入通行证的好处是：

- 在系统可承载范围内，尽量保证一旦放进来的用户能完成关键链路
- 超出系统可承载范围后，把新流量拦在入口层排队
- 不把所有压力都压到应用、数据库和支付链路上

## 当前仓库里的实现方式

### 策略配置

策略配置位于 [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua)。

当前示例策略：

- `policy_id`
- `activity_id`
- `paths.join`
- `paths.status`
- `paths.waitroom`
- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`
- `queue.ttl_seconds`
- `queue.poll_interval_seconds`
- `protected.paths`

真正迁移到别的业务时，最常改的是：

- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`
- `protected.paths`
- 入口域名和路径

比如：

- 大系统可以设成 `steady=10000, burst=12000`
- 小系统可以设成 `steady=2000, burst=2400`

逻辑层本身不需要改。

### 路由与站点

示例站点位于 [openresty/conf.d/sites/case-enroll-waitroom.conf](/data/openresty-install/openresty/conf.d/sites/case-enroll-waitroom.conf)。

路径拆分：

- `/api/enroll/submit`
  新用户进入等待室入口
- `/api/queue/status`
  前端轮询排队状态
- `/api/cart/add`
- `/api/checkout/confirm`
- `/api/pay/create`
- `/api/order/status`
  已准入用户关键链路

### OpenResty 只做什么

OpenResty 只做入口治理：

- 准入判断
- 排队状态
- 签发通行证
- 校验通行证
- 保护关键路径

它不替代业务系统做：

- 库存扣减
- 座位锁定
- 订单状态机
- 支付幂等

## Redis 状态模型

当前实现使用外部 Redis 保存：

- 活跃准入列表
- 排队 ticket
- 用户到 ticket 的映射
- 用户已激活 token 的映射

Redis 只用于等待室和准入状态，不要求每个支付或购物车请求都重打 Redis。

关键链路上，通行证校验主要走本地 HMAC 验签，尽量降低热点路径延迟。

## 真实 IP 不是核心依赖

这套等待室方案的核心识别键，默认应该是：

1. `X-User-Id`
2. 业务侧用户 Cookie
3. URL 中的 `user_id`
4. 最后才回退到来源 IP

原因很简单：

- 在政务云内网、统一 ELB、统一内网代理等环境里，经常拿不到真实客户端 IP
- 如果所有请求看起来都来自一个内网 ELB IP，那么按 IP 限流会误伤所有用户

所以当前实现里：

- 等待室入口与轮询的限流键，优先按用户标识
- 只有拿不到用户标识时，才回退到来源 IP

## 真实 IP 配置改为可选启用

当前仓库里，真实 IP 解析已经从主配置中拆出来，不再默认启用。

如果你的环境能可靠透传真实 IP，可以把下面这个示例文件启用：

- [openresty/conf.d/10-real-ip.conf.example](/data/openresty-install/openresty/conf.d/10-real-ip.conf.example)

启用方式：

```bash
cp openresty/conf.d/10-real-ip.conf.example openresty/conf.d/10-real-ip.conf
./ssl/scripts/reload-openresty.sh
```

如果你的环境只能看到统一的 ELB 内网 IP，就不要启用它。

## 对高并发更友好的点

和第一阶段相比，第二阶段这条热点链路做了刻意约束：

- 不走重的 body 改写逻辑
- 不把关键路径放在复杂动态路由之下
- 关键链路使用静态 upstream
- 准入成功后，后续关键路径主要做本地令牌校验
- Redis 查询集中在等待室入口和状态查询接口

## 推荐的生产调参思路

### 1. `capacity.steady`

这个值不是拍脑袋定，而是根据压测定出来的“稳态安全值”。

如果你们压测结论是：

- 98% 成功率以上
- 关键接口 2 秒内
- 所有服务器负载仍然健康
- 最大安全合理并发为 `10000`

那么就把等待室策略里的 `capacity.steady` 设为 `10000`。

如果另一个系统只有 `2000`，就设成 `2000`。

### 2. `capacity.burst`

这个值是突发缓冲层，思路上更接近 Sentinel / Resilience4j 的“稳态保护 + 短时突发缓冲 + 超限排队”。

例如：

- `capacity.steady = 10000`
- `capacity.burst = 12000`

表示：

- `10000` 以内属于稳态准入
- `10000` 到 `12000` 属于短时突发缓冲
- `12000` 以上统一进入等待室排队

如果你们的业务峰值非常陡，但持续时间短，这层很有价值。

### 3. `token.ttl_seconds`

这个值要覆盖“用户已准入后完成关键链路”的典型时长。

比如：

- 抢课 + 加车 + 确认 + 支付，一般可设 `300` 到 `900` 秒

不要太短，否则会让已准入用户流程中断。  
也不要太长，否则会导致新用户长时间进不来。

### 4. `queue.poll_interval_seconds`

建议默认 `3` 秒左右，并允许业务前端加一点随机抖动。  
避免所有排队用户在整数秒同时轮询。

## 真实测试

### 功能测试

```bash
make test-waitroom
```

这个测试会验证：

- 前四个用户在稳态容量和突发缓冲内拿到准入
- 第五个用户进入排队
- 已准入用户可以继续购物车与支付
- 未准入用户不能直接走关键步骤
- token TTL 到期后，排队用户能够补位获得准入

### 并发模拟

```bash
make benchmark-waitroom
```

当前脚本会并发发起一波报名请求，观察：

- admitted 数量
- queued 数量
- HTTP 状态分布

脚本已支持参数化，例如：

```bash
python3 examples/scripts/benchmark_waitroom.py --total 300 --concurrency 300
```

## 轻量运维观测

为了不引入额外监控系统，当前仓库补了一条低复杂度的运维摘要接口：

- `GET /api/ops/waitroom/summary`

它会返回：

- 当前策略 ID
- 稳态容量
- 突发容量
- 当前活跃准入数
- 当前排队人数
- 当前关键受保护路径

调用示例：

```bash
curl -k \
  -H 'X-Ops-Token: change-this-before-production' \
  --resolve enroll.example.test:443:127.0.0.1 \
  https://enroll.example.test/api/ops/waitroom/summary
```

说明：

- `X-Ops-Token` 默认来自 `.env` 里的 `GATEWAY_OPS_TOKEN`
- 生产必须改掉默认值
- 这条接口适合值班排障、临时观察和参数核对

如果以后你们需要更完整的监控，再把这条接口结果接到 Prometheus / Loki / Grafana 即可。

对应的只读运维页：

- `GET /ops/waitroom.html`

这个页面只是调用摘要接口，不引入额外服务，适合临时观察。

## 接入到其他业务时的建议

如果你们后续还有：

- 秒杀
- 抢票
- 抢名额
- 预约放号

都可以复用同一套等待室能力，只换：

- 域名
- 入口路径
- 关键受保护路径
- `capacity.steady`
- `capacity.burst`
- `token.ttl_seconds`

这就是这套方案通用的地方。
