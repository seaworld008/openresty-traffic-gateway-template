# OpenResty 运维手册

## 1. 适用对象

这份手册面向：

- 日常值班运维
- 实施工程师
- 平台工程师

目标是让运维人员不看代码，也能完成：

- 启动
- 停止
- 配置变更
- 证书管理
- 排障
- 等待室查看

## 2. 日常命令

### 初始化

```bash
make init
```

### 本地证书

```bash
make local-certs
```

### 启动服务

```bash
make up
```

### 停止服务

```bash
make down
```

### 重启服务

```bash
make restart
```

### 查看运行状态

```bash
make ps
```

### 校验配置

```bash
make check
```

### 重新加载配置

```bash
make reload
```

### 查看网关日志

```bash
make logs
```

## 3. 证书管理

### 本地测试模式

```bash
./ssl/scripts/init-local-certs.sh
```

### 生产申请证书

```bash
./ssl/scripts/init-cert.sh --email ops@example.com domain1 domain2
```

### 续签证书

```bash
make renew
```

### 证书迁移前备份

至少备份：

- `ssl/certbot/conf/`
- `openresty/conf.d/`
- `openresty/snippets/`
- `.env`

## 4. 等待室日常查看

### 命令行摘要

```bash
make waitroom-summary
```

默认使用 `.env` 中的 `GATEWAY_OPS_TOKEN`。

### 浏览器查看

打开：

```text
https://enroll.example.test/ops/waitroom.html
```

输入正确的 `X-Ops-Token` 后可查看：

- 当前稳态容量
- 当前突发容量
- 当前活跃准入数
- 当前排队人数

## 5. 高峰活动前检查清单

活动开始前建议至少完成以下检查：

1. `make check`
2. `make ps`
3. 确认外部 Redis 可连接
4. 确认等待室策略参数与当前系统容量匹配
5. 确认 `GATEWAY_OPS_TOKEN`、`GATEWAY_QUEUE_SECRET` 已替换默认值
6. 跑一遍：

```bash
make test-first-layer
make test-waitroom
```

如时间允许，再跑：

```bash
make test-comprehensive
```

## 6. 活动高峰时如何观察

重点看三类信息：

### 6.1 等待室摘要

观察：

- `active_count`
- `queue_total`
- `steady_capacity`
- `burst_capacity`

判断逻辑：

- `active_count` 长期贴近 `steady_capacity`
  说明已经在稳态容量边界
- `active_count` 持续贴近 `burst_capacity`
  说明已经进入突发缓冲阶段
- `queue_total` 快速上升
  说明新流量被成功拦在等待室，而不是冲进业务服务

### 6.2 OpenResty 错误日志

主要看：

- 配置错误
- 上游 502/504
- Redis 不可用

### 6.3 站点 access/error log

重点看：

- 抢课入口
- 支付入口
- 合作方入口

## 7. 常见故障处理

### 7.1 等待室返回 `redis_unavailable`

处理步骤：

1. 检查 Redis 是否存活
2. 检查网络连通性
3. 检查 `.env` 中的 Redis 地址与端口
4. 观察是否是短时抖动还是持续不可用

### 7.2 等待室所有请求都在排队

先看摘要接口：

- `active_count`
- `burst_capacity`
- `queue_total`

常见原因：

- 活跃准入人数已经打满
- token TTL 过长，老用户迟迟不释放
- 业务链路过慢，导致名额回收变慢

### 7.3 已准入用户关键步骤被拒绝

先确认：

- 用户是否携带准入 Cookie
- token 是否过期
- 用户标识是否一致

### 7.4 限流过于频繁

分两种情况：

- 第一层接口频繁 429：检查普通限流参数
- 等待室入口频繁 429：检查等待室入口限流键是否合理，尤其是政务云环境下是否拿到了正确的用户标识

## 8. 变更流程建议

### 小改动

例如：

- 改域名
- 改上游地址
- 改日志路径

流程：

1. 改配置
2. `make check`
3. `make reload`

### 中改动

例如：

- 改第一层策略
- 改等待室容量参数
- 改关键路径

流程：

1. 改配置/策略
2. `make check`
3. `make test-first-layer`
4. `make test-waitroom`
5. `make reload`

### 大改动

例如：

- 新增热点活动系统
- 新增新域名系统
- 调整等待室模型

流程：

1. 新增站点文件
2. 新增策略
3. 完整验证
4. 低峰窗口上线

## 9. 运维建议

- 默认值只适合测试，不适合生产
- 不要把真实证书、真实密钥提交到 Git
- 高峰活动前不要做无关配置变更
- 等待室和普通 API 应分开观察
- 已准入关键链路优先于新流量入口

## 10. 相关文档

- [docs/ARCHITECTURE.md](/data/openresty-install/docs/ARCHITECTURE.md)
- [docs/CONFIGURATION.md](/data/openresty-install/docs/CONFIGURATION.md)
- [examples/waitroom-best-practice.md](/data/openresty-install/examples/waitroom-best-practice.md)
