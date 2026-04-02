# 第二阶段等待室能力说明

这个目录存放第二阶段高并发等待室能力，适合：

- 抢课
- 热点报名
- 秒杀
- 抢票
- 放号预约

## 模块职责

- `policies.lua`
  第二阶段策略配置
- `policies.production.example.lua`
  生产策略模板示例
- `service.lua`
  第二阶段主入口，负责 join/status/protected/summary
- `store.lua`
  Redis 状态存储与原子状态迁移
- `token.lua`
  准入 token 编解码与校验
- `util.lua`
  第二阶段辅助响应和鉴权函数

## 对外接口

- `content_join.lua`
  入口准入接口
- `content_status.lua`
  排队状态接口
- `access_protected.lua`
  已准入关键路径保护
- `content_summary.lua`
  只读运维摘要接口

## 策略模型

当前策略核心字段：

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
- `queue.cleanup_batch`
- `protected.paths`

## 设计原则

- 默认不依赖真实 IP
- 优先按用户标识识别和限流
- 稳态容量、突发缓冲、超限排队三层分离
- 已准入用户走关键路径保护，不再和新流量竞争
- Redis 只用于等待室状态，不要求关键链路每次都重打 Redis

## 运维入口

- 只读摘要接口：`/api/ops/waitroom/summary`
- 只读运维页：`/ops/waitroom.html`
