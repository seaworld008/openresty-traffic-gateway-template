# conf.d 使用说明

这个目录分成两类文件：

## 1. 核心运行配置

- `00-global.conf`
  全局 map、默认 server、限流区、ACME challenge 等基础配置
- `01-upstreams.conf`
  upstream 定义
- `10-real-ip.conf.example`
  可选真实 IP 配置模板，仅在上游能可靠透传真实 IP 时启用

这三类文件属于网关基础层，不建议随意删除。

## 2. 站点模板文件

所有站点案例统一改成 `*.conf.example`，按场景命名。

补充约定：

- 模板内允许保留简短中文注释
- 注释只用于说明“这个块是做什么的”和“复制后通常改哪里”
- 不建议在模板里写成长篇操作手册，详细步骤仍放在文档中

### 普通场景

- `frontend-proxy.conf.example`
  普通前端网站反向代理
- `api-proxy.conf.example`
  普通 API 反向代理
- `admin-console-proxy.conf.example`
  管理后台 / 控制台入口
- `static-local-root.conf.example`
  本地静态站点托管

### OpenResty 第一层高级能力场景

- `risk-protected-proxy.conf.example`
  基础风控、限流、简单熔断
- `partner-api-gateway.conf.example`
  JWT / HMAC / 动态路由 / Header&Body 改写
- `gray-release-proxy.conf.example`
  灰度发布与流量分流
- `llm-api-proxy.conf.example`
  通用大模型 API 反向代理
- `llm-relay-token-guard.conf.example`
  大模型中转 API 的源站令牌保护，使用 `map` 做本机与源站令牌判断

### OpenResty 第二阶段等待室场景

- `waitroom-enrollment-gateway.conf.example`
  抢课 / 报名 / 热点活动等待室

## 3. 为什么要用 `.conf.example`

这样做的目的很简单：

- 模板仓库 clone 下来后，不会默认启用所有案例
- 运行中的配置和模板配置分开
- 运维新增系统时，直接复制模板更清晰

## 4. 如何启用一个模板

### 手工启用

例如启用前端站点模板：

```bash
cp openresty/conf.d/frontend-proxy.conf.example openresty/conf.d/frontend-proxy.conf
sed -i 's/web.example.com/www.example.com/g' openresty/conf.d/frontend-proxy.conf
```

例如启用热点活动等待室模板：

```bash
cp openresty/conf.d/waitroom-enrollment-gateway.conf.example openresty/conf.d/waitroom-enrollment-gateway.conf
sed -i 's/enroll.example.com/enroll-campus-a.example.com/g' openresty/conf.d/waitroom-enrollment-gateway.conf
```

复制后请按实际情况修改：

- `server_name`
- 证书路径（默认已跟随同一个域名占位符）
- `proxy_pass`
- `gateway_policy` / `admission_policy`
- 日志文件名

## 4.1 配置检查与 reload

当前目录下的 `confctl.sh` 是面向 Docker Compose 部署的 OpenResty 运维入口，用于：

- 检查配置
- reload 配置
- 重启容器
- 查看日志
- 查看服务状态

例如：

```bash
cd openresty/conf.d
./confctl.sh test
./confctl.sh reload
./confctl.sh ps
```

如果你要新增站点配置，请直接复制最接近的 `*.conf.example` 为对应 `.conf`，再手工修改域名、证书路径、日志名和 `proxy_pass`。

### 本地测试时批量启用

本仓库提供两个辅助脚本：

```bash
./examples/scripts/activate_conf_examples.sh
./examples/scripts/deactivate_conf_examples.sh
```

它们会把所有 `*.conf.example` 批量复制成对应 `.conf`，或批量清理这些临时启用的配置。

## 5. 每个模板的共同规则

### HTTP（80）

- 只负责 `/.well-known/acme-challenge/`
- 其余请求统一 301 跳转到 HTTPS
- 不记录 access log

### HTTPS（443）

- 承担正式业务流量
- 只在这里记录站点级 access log / error log
- 所有业务代理、静态资源、第一层 Lua 能力、第二阶段等待室都挂在这里

## 6. 怎么选模板

### 官网 / 普通前端站点

- `frontend-proxy.conf.example`
- `static-local-root.conf.example`

### 普通业务 API

- `api-proxy.conf.example`

### 控制台 / 后台

- `admin-console-proxy.conf.example`

### 需要第一层高级能力

- `risk-protected-proxy.conf.example`
- `partner-api-gateway.conf.example`
- `gray-release-proxy.conf.example`
- `llm-api-proxy.conf.example`
- `llm-relay-token-guard.conf.example`

### 需要热点活动保护

- `waitroom-enrollment-gateway.conf.example`

## 7. 启用后如何检查

```bash
make check
make reload
```

如果启用了第一层高级能力案例，建议继续执行：

```bash
make test-first-layer
```

如果启用了第二阶段等待室案例，建议继续执行：

```bash
make test-waitroom
```

如果你不确定该选哪个模板，或者要在老站上渐进式接入第一层能力 / 等待室，请直接看：

- [docs/SCENARIO_GUIDE.md](/data/openresty-install/docs/SCENARIO_GUIDE.md)
