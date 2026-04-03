# 场景化接入指南与综合校验修正设计

## 1. 背景

当前仓库已经具备较清晰的模块化结构：

- 站点文件负责域名、证书、location 和策略绑定
- `openresty/lua/gateway/` 负责第一层公共能力
- `openresty/lua/admission/` 负责第二阶段等待室

但对实施人员来说，现有文档仍然偏“按文件介绍能力”，不够“按场景指导接入”。
特别是以下两类动作，仍然需要靠读者自己拼接：

- 新增一个普通站点、API 或热点活动入口
- 在一个已有站点上增量接入限流、风控、熔断或等待室

同时，审查过程中还发现两类影响交付质量的问题：

- 综合测试脚本调用等待室压测脚本时，参数接口不一致
- 部分文档引用了不存在的文件路径或页面

## 2. 目标

这次改动的目标不是新增新的网关能力，而是把“怎么接入能力”讲清楚，并确保仓库的测试与文档叙述一致。

具体目标：

1. 新增一篇可直接操作的场景化接入指南
2. 在 README 和现有手册中建立统一入口，减少重复描述
3. 修复综合测试中已知的不一致点
4. 在不改动 LLM 中转站能力边界的前提下，整理非 LLM 场景接入说明

## 3. 设计决策

### 3.1 新增单篇主指南，而不是分散补丁式更新

采用新增 `docs/SCENARIO_GUIDE.md` 的方式，集中承载：

- 怎么判断应该选基础代理、第一层能力还是等待室
- 新站如何接入
- 老站如何渐进式改造
- 每类场景最小改动点
- 检查命令、回滚方式、常见误区

这样做的原因：

- 现有 `README.md`、`docs/CONFIGURATION.md`、`docs/ADD_NEW_SYSTEM.md` 更适合做索引和摘要
- 真正详细的步骤如果继续散落在多处，后续维护成本会越来越高

### 3.2 同步修正文档入口，但不重复堆砌内容

现有文档只保留：

- 架构定位
- 配置分层
- 操作入口
- 指向场景指南的链接

详细步骤收敛到新指南，避免后续多处文档互相漂移。

### 3.3 修复综合测试的最小必要问题

为保证“先测试、再收尾”可执行，需要补齐以下问题：

- 让 `examples/scripts/benchmark_waitroom.py` 支持 `--total` 和 `--concurrency`
- 校对与测试和页面相关的文档引用，删掉或修正不存在的路径

## 4. 变更范围

预计涉及：

- 新增：
  - `docs/SCENARIO_GUIDE.md`
  - `docs/plans/2026-04-03-scenario-guide.md`
- 修改：
  - `README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/CONFIGURATION.md`
  - `docs/OPERATIONS.md`
  - `docs/ADD_NEW_SYSTEM.md`
  - `openresty/conf.d/README.md`
  - `openresty/lua/gateway/README.md`
  - `openresty/lua/admission/README.md`
  - `examples/waitroom-best-practice.md`
  - `examples/advanced-tests.md`
  - `examples/scripts/benchmark_waitroom.py`
  - `examples/scripts/run_comprehensive_validation.sh`

## 5. 验证策略

至少执行：

- `make check`
- `make test-comprehensive`

如果综合测试中发现新的失真项，以“最小修复、保持现有能力边界不扩张”为原则处理。

## 6. 非目标

这次不做以下内容：

- 不新增 LLM 中转站组合模板
- 不修改第一层或第二阶段的核心策略模型
- 不引入新的 Lua 功能模块
