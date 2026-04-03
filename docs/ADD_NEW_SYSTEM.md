# 新增一个系统的操作说明

如果你希望看到按场景拆开的详细步骤，包括：

- 新站怎么接
- 老站怎么渐进式加限流 / 风控 / 熔断
- 热点活动怎么单独接入等待室

请优先看：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)

## 1. 先判断这个系统属于哪一类

### 类型 A：普通 API / 后台 / 合作方接入

适合：

- 第一层公共能力
- 不需要等待室

参考：

- [openresty/conf.d/partner-api-gateway.conf.example](/data/openresty-install/openresty/conf.d/partner-api-gateway.conf.example)
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

### 类型 B：热点活动入口

适合：

- 抢课
- 报名
- 秒杀
- 抢票

参考：

- [openresty/conf.d/waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
- [openresty/conf.d/waitroom-java-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-java-gateway.conf.example)
- [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua)

## 2. 新增普通系统

1. 复制最接近的站点文件
2. 修改 `server_name`
3. 修改 `gateway_policy`
4. 修改 upstream 或 `proxy_pass`
5. 在第一层策略文件中增加新策略
6. 执行：

```bash
make check
make test-first-layer
```

如果你在 `openresty/conf.d/` 目录下操作，也可以先执行 `./confctl.sh test` 再跑测试。

## 3. 新增热点活动系统

1. 复制 [waitroom-enrollment-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-enrollment-gateway.conf.example)
   如果你们是 OpenResty -> Java gateway 架构，也可以直接复制 [waitroom-java-gateway.conf.example](/data/openresty-install/openresty/conf.d/waitroom-java-gateway.conf.example)
2. 修改 `server_name`
3. 修改 `admission_policy`
4. 修改热点入口、排队接口、关键受保护路径
   同时修改当前子配置文件里的业务 `upstream`
5. 在 [openresty/lua/admission/policies.lua](/data/openresty-install/openresty/lua/admission/policies.lua) 中增加新策略
6. 根据压测结果设置：
   - `capacity.steady`
   - `capacity.burst`
   - `token.ttl_seconds`
7. 执行：

```bash
make check
make test-waitroom
```

如果你在 `openresty/conf.d/` 目录下操作，也可以先执行 `./confctl.sh test` 再跑测试。

## 4. 新增系统后必须同步的内容

至少同步检查：

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/CONFIGURATION.md`
- `docs/OPERATIONS.md`

如果新增的是热点活动系统，还应同步：

- `examples/waitroom-best-practice.md`

## 5. 推荐流程

1. 先复制站点文件
2. 再新增策略
3. 再跑测试
4. 最后补文档

不要先改核心公共逻辑，除非已有能力确实不够。
