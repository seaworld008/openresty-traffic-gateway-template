# 仓库协作约定

本文件的目标是帮助后续进入这个仓库的人类工程师或 AI 编码工具，快速建立一致的工作方式。

## 1. 仓库定位

这是一个面向生产实践的 OpenResty 自建部署模板，包含两层能力：

1. 第一层公共网关能力
   路径：`openresty/lua/gateway/`
2. 第二阶段高并发等待室能力
   路径：`openresty/lua/admission/`

## 2. 修改原则

- 优先保持结构清晰，不要把逻辑重新堆回单个大文件。
- 新增域名时优先复制站点文件，不要把多个系统混在同一个 `server` 中。
- 公共逻辑优先放到 `lua/` 模块或 `snippets/`，站点文件只负责组装。
- 默认保持中文注释和中文文档。

## 3. 文档同步要求

只要改动了配置、策略、脚本或模块，必须同步检查并更新对应文档。

最少检查：

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/OPERATIONS.md`
- `docs/CONFIGURATION.md`
- `examples/waitroom-best-practice.md`

如果改动影响“如何新增系统”，还要检查：

- `docs/ADD_NEW_SYSTEM.md`

如果改动影响模块职责或入口文件，还要检查：

- `openresty/lua/gateway/README.md`
- `openresty/lua/admission/README.md`

## 4. 测试同步要求

如果改动影响第一层公共能力，至少检查：

- `examples/scripts/test-first-layer.sh`
- `examples/scripts/benchmark_gateway.py`

如果改动影响第二阶段等待室，至少检查：

- `examples/scripts/test-waitroom.sh`
- `examples/scripts/benchmark_waitroom.py`

如果改动范围较大，应检查：

- `examples/scripts/run_comprehensive_validation.sh`

## 5. 真实 IP 约定

- 默认不要把真实 IP 当成核心依赖。
- 默认优先按 `X-User-Id / 业务 Cookie / user_id` 识别用户。
- 只有环境能可靠透传真实 IP 时，才启用 `openresty/conf.d/10-real-ip.conf.example`。

## 6. 第二阶段容量约定

第二阶段等待室策略采用两层容量：

- `capacity.steady`
- `capacity.burst`

不要再退回单一 `max_active` 语义。

## 7. 改动完成后的最小检查

至少执行：

```bash
make check
```

如果改动第一层能力：

```bash
make test-first-layer
```

如果改动第二阶段等待室：

```bash
make test-waitroom
```

如果改动较大：

```bash
make test-comprehensive
```
