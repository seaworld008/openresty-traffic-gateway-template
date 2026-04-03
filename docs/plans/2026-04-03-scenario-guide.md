# 场景化接入指南与综合校验修正 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 新增场景化接入指南，收敛现有文档入口，并修复综合测试与文档中的已知失真点。

**Architecture:** 采用“单篇主指南 + 多文档入口链接”的文档结构，不新增新能力模块，只修复影响综合测试与文档可信度的最小脚本问题。实施中先修计划与文档，再跑完整验证，根据结果回补测试脚本或文档引用。

**Tech Stack:** Markdown, Bash, Python 3, OpenResty, Docker Compose

---

### Task 1: 新建设计与计划文档

**Files:**
- Create: `docs/plans/2026-04-03-scenario-guide-design.md`
- Create: `docs/plans/2026-04-03-scenario-guide.md`

**Step 1: 写入设计文档**

说明背景、目标、设计决策、变更范围、验证策略与非目标。

**Step 2: 写入实现计划**

明确文档新增、文档同步和测试修正的范围。

**Step 3: 复核文件名与日期**

Run: `ls docs/plans | tail`
Expected: 能看到新增的两个计划文件

### Task 2: 新增场景化接入指南

**Files:**
- Create: `docs/SCENARIO_GUIDE.md`

**Step 1: 定义文档结构**

至少包含：

- 场景判断矩阵
- 新站接入流程
- 老站改造流程
- 普通站点 / API / 后台 / 热点活动场景步骤
- 回滚与常见误区

**Step 2: 写出可执行步骤**

每个场景都给出：

- 该选哪个模板
- 要改哪些字段
- 最小检查命令
- 常见错法

**Step 3: 校对与仓库真实结构一致**

Run: `rg -n "SCENARIO_GUIDE|场景化" docs README.md openresty`
Expected: 新指南被后续入口文档正确引用

### Task 3: 同步入口文档

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/CONFIGURATION.md`
- Modify: `docs/OPERATIONS.md`
- Modify: `docs/ADD_NEW_SYSTEM.md`
- Modify: `openresty/conf.d/README.md`
- Modify: `openresty/lua/gateway/README.md`
- Modify: `openresty/lua/admission/README.md`
- Modify: `examples/waitroom-best-practice.md`
- Modify: `examples/advanced-tests.md`

**Step 1: 补充主指南入口**

把详细操作说明统一指向 `docs/SCENARIO_GUIDE.md`。

**Step 2: 修正文档失效引用**

移除或修正不存在的文件路径、页面路径和示例说明。

**Step 3: 检查文档覆盖要求**

Run: `rg -n "SCENARIO_GUIDE|ops/waitroom|sites/case|policies.production.example" README.md docs openresty examples`
Expected: 不再保留已知错误引用；场景指南入口存在

### Task 4: 修复综合测试失真点

**Files:**
- Modify: `examples/scripts/benchmark_waitroom.py`
- Modify: `examples/scripts/run_comprehensive_validation.sh`

**Step 1: 让等待室压测脚本支持参数**

补充 `argparse`，支持 `--total` 和 `--concurrency`。

**Step 2: 保持综合脚本调用方式一致**

确认 `run_comprehensive_validation.sh` 调用参数与脚本接口一致。

**Step 3: 先做静态检查**

Run: `python3 examples/scripts/benchmark_waitroom.py --help`
Expected: 显示 `--total` 与 `--concurrency`

### Task 5: 执行校验与综合测试

**Files:**
- Modify: `README.md` or related docs if test发现文档需要补充
- Modify: `examples/scripts/*` if test发现脚本问题

**Step 1: 基础校验**

Run: `make check`
Expected: 配置语法通过

**Step 2: 综合测试**

Run: `make test-comprehensive`
Expected: 第一层测试、等待室测试、并发模拟和摘要查询全部通过

**Step 3: 如失败则最小修复**

根据失败点修复脚本、配置或文档描述，并重新执行相关命令直到通过。

### Task 6: 收尾、提交与推送

**Files:**
- Modify: `git` working tree metadata only

**Step 1: 汇总变更**

Run: `git status --short`
Expected: 只包含本次新增与修改

**Step 2: 提交**

Run: `git add ... && git commit -m "docs: add scenario guide and fix validation scripts"`
Expected: 生成新提交

**Step 3: 推送**

Run: `git push origin main`
Expected: 远端更新成功
