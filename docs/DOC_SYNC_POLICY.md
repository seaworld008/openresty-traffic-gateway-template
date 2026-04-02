# 文档同步约定

这份文档专门用于约束“代码变更后，哪些文档必须同步更新”。

## 1. 修改站点文件时

至少检查：

- `README.md`
- `docs/CONFIGURATION.md`

## 2. 修改第一层公共能力时

至少检查：

- `README.md`
- `openresty/lua/gateway/README.md`
- `docs/ARCHITECTURE.md`
- `docs/CONFIGURATION.md`

## 3. 修改第二阶段等待室时

至少检查：

- `README.md`
- `openresty/lua/admission/README.md`
- `examples/waitroom-best-practice.md`
- `docs/ARCHITECTURE.md`
- `docs/CONFIGURATION.md`
- `docs/OPERATIONS.md`

## 4. 修改测试脚本时

至少检查：

- `README.md`
- 对应 `examples/*.md`

## 5. 修改默认运维方式时

至少检查：

- `README.md`
- `docs/OPERATIONS.md`
- `Makefile`

## 6. 最低要求

任何影响使用方式、部署方式、策略方式、测试方式的改动，都不能只改代码不改文档。
