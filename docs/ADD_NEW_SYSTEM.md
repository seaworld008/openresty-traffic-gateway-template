# 新增一个系统的操作说明

## 1. 先判断这个系统属于哪一类

### 类型 A：普通 API / 后台 / 合作方接入

适合：

- 第一层公共能力
- 不需要等待室

参考：

- [openresty/conf.d/case-partner-api.conf](/data/openresty-install/openresty/conf.d/case-partner-api.conf)
- [openresty/lua/gateway/policies.lua](/data/openresty-install/openresty/lua/gateway/policies.lua)

### 类型 B：热点活动入口

适合：

- 抢课
- 报名
- 秒杀
- 抢票

参考：

- [openresty/conf.d/case-enroll-waitroom.conf](/data/openresty-install/openresty/conf.d/case-enroll-waitroom.conf)
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

## 3. 新增热点活动系统

1. 复制 [case-enroll-waitroom.conf](/data/openresty-install/openresty/conf.d/case-enroll-waitroom.conf)
2. 修改 `server_name`
3. 修改 `admission_policy`
4. 修改热点入口、排队接口、关键受保护路径
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
