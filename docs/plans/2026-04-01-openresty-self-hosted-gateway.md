# OpenResty 自建网关实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标：** 构建一套偏生产实践的 OpenResty 单节点网关模板，包含可复用配置、证书自动化脚本、示例后端和完整运维文档。

**架构：** 使用 Docker Compose 管理 OpenResty 和 Certbot，所有持久化数据都放在仓库根目录下。OpenResty 配置拆成主配置、共享 snippets、upstream 定义和按域名拆分的站点配置，保证新增域名时改动面最小。

**技术栈：** Docker Compose、OpenResty、Certbot、Nginx/OpenResty 配置、Shell 脚本、Markdown 文档

---

### Task 1: 创建项目骨架

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Create: `README.md`
- Create: `openresty/nginx.conf`
- Create: `openresty/conf.d/00-global.conf`
- Create: `openresty/conf.d/01-upstreams.conf`
- Create: `openresty/conf.d/sites/example-www.conf`
- Create: `openresty/conf.d/sites/example-api.conf`
- Create: `openresty/conf.d/sites/example-admin.conf`
- Create: `openresty/conf.d/sites/example-static.conf`
- Create: `openresty/snippets/proxy-common.conf`
- Create: `openresty/snippets/ssl-common.conf`
- Create: `openresty/snippets/security-headers.conf`
- Create: `openresty/snippets/cache-common.conf`
- Create: `openresty/lua/.gitkeep`
- Create: `openresty/logs/.gitkeep`
- Create: `openresty/cache/.gitkeep`
- Create: `openresty/certs/.gitkeep`
- Create: `openresty/html/.gitkeep`
- Create: `ssl/acme/.gitkeep`
- Create: `ssl/certbot/conf/.gitkeep`
- Create: `ssl/certbot/www/.gitkeep`
- Create: `ssl/scripts/init-cert.sh`
- Create: `ssl/scripts/renew-cert.sh`
- Create: `ssl/scripts/reload-openresty.sh`
- Create: `ssl/README.md`
- Create: `examples/backend/docker-compose.example.yml`
- Create: `examples/curl-tests.md`

**Step 1: 创建固定镜像 tag 和相对路径挂载的基础文件**

确保所有持久化目录都落在仓库中，并且每类文件的职责清晰。

**Step 2: 检查文件结构**

Run: `find . -maxdepth 4 | sort`
预期结果：计划内的目录和文件都已生成

### Task 2: 实现可维护的 OpenResty 配置

**Files:**
- Modify: `openresty/nginx.conf`
- Modify: `openresty/conf.d/00-global.conf`
- Modify: `openresty/conf.d/01-upstreams.conf`
- Modify: `openresty/conf.d/sites/example-www.conf`
- Modify: `openresty/conf.d/sites/example-api.conf`
- Modify: `openresty/conf.d/sites/example-admin.conf`
- Modify: `openresty/conf.d/sites/example-static.conf`
- Modify: `openresty/snippets/proxy-common.conf`
- Modify: `openresty/snippets/ssl-common.conf`
- Modify: `openresty/snippets/security-headers.conf`
- Modify: `openresty/snippets/cache-common.conf`

**Step 1: 编写全局默认配置**

包含日志格式、gzip、real IP 行为、map 定义、上传大小、超时和缓存路径。

**Step 2: 编写共享 snippets**

把代理头、TLS 策略、安全头和缓存策略独立出来，避免重复。

**Step 3: 编写按域名拆分的站点示例**

提供独立的 HTTP challenge、HTTPS server、upstream 路由和静态站点示例。

**Step 4: 校验配置语法**

Run: `docker compose config`
预期结果：Compose 配置可以正确渲染

### Task 3: 实现证书脚本与运维流程

**Files:**
- Modify: `ssl/scripts/init-cert.sh`
- Modify: `ssl/scripts/renew-cert.sh`
- Modify: `ssl/scripts/reload-openresty.sh`
- Modify: `ssl/README.md`

**Step 1: 编写生产 ACME 签发脚本**

使用 `certbot certonly --webroot`，并处理域名参数与清晰的使用说明。

**Step 2: 编写续签脚本**

基于持久化的 certbot 状态做续签，成功后调用 reload 脚本。

**Step 3: 编写 OpenResty reload 脚本**

通过 `docker compose exec` 执行 reload，失败输出要清晰。

**Step 4: 赋予执行权限并做 Shell 语法检查**

Run: `bash -n ssl/scripts/*.sh`
预期结果：没有语法错误

### Task 4: 增加本地验证后端与测试流程

**Files:**
- Modify: `docker-compose.yml`
- Modify: `examples/backend/docker-compose.example.yml`
- Modify: `examples/curl-tests.md`

**Step 1: 增加轻量后端容器**

使用简单的 HTTP echo / whoami 服务，本地验证域名路由。

**Step 2: 编写 hosts 与 curl 验证说明**

覆盖 HTTP 跳转、HTTPS 路由、响应头、回源响应和静态资源检查。

**Step 3: 本地启动整套服务**

Run: `docker compose up -d`
预期结果：容器成功启动

### Task 5: 编写部署与维护文档

**Files:**
- Modify: `README.md`
- Modify: `ssl/README.md`
- Modify: `examples/curl-tests.md`

**Step 1: 说明目标架构和为什么这套布局适合生产**

覆盖需求里提到的四类架构，并说明 OpenResty 所处位置。

**Step 2: 说明初始化和改动流程**

覆盖 clone、环境初始化、本地测试、生产签发、新增域名、reload、续签、日志和回滚。

**Step 3: 说明运维最佳实践**

覆盖固定 tag、备份范围、告警建议、升级路径和扩展到多节点 / LB 的方式。

### Task 6: 端到端验证项目

**Files:**
- Modify: `README.md`

**Step 1: 校验 Shell 脚本**

Run: `bash -n ssl/scripts/*.sh`
预期结果：无输出

**Step 2: 在容器里校验 OpenResty 配置**

Run: `docker compose run --rm openresty openresty -t`
预期结果：`syntax is ok / test is successful`

**Step 3: 启动整套服务**

Run: `docker compose up -d`
预期结果：网关和示例后端都正常可用

**Step 4: 执行 HTTP / HTTPS 烟雾测试**

按照文档对 localhost 执行 `--resolve` 或 hosts 映射测试
预期结果：跳转、TLS 终止、域名路由和静态资源响应都符合文档说明

**Step 5: 把实际验证过的命令写回 README**

确保文档与真实验证结果一致。
