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
sed -i 's/REPLACE_WITH_DOMAIN/www.example.com/g' openresty/conf.d/frontend-proxy.conf
```

例如启用热点活动等待室模板：

```bash
cp openresty/conf.d/waitroom-enrollment-gateway.conf.example openresty/conf.d/waitroom-enrollment-gateway.conf
sed -i 's/REPLACE_WITH_DOMAIN/enroll.example.com/g' openresty/conf.d/waitroom-enrollment-gateway.conf
```

复制后请按实际情况修改：

- `server_name`
- 证书路径（默认已跟随同一个域名占位符）
- `proxy_pass`
- `gateway_policy` / `admission_policy`
- 日志文件名

## 4.1 一键按域名生成模板

如果你希望直接生成一份可编辑配置，可以使用：

```bash
cd openresty/conf.d
./confctl.sh new frontend-proxy.conf.example www.example.com
```

或：

```bash
cd openresty/conf.d
./confctl.sh new waitroom-enrollment-gateway.conf.example enroll.example.com enroll-campus-a.conf
```

模板里统一使用 `REPLACE_WITH_DOMAIN` 占位符，所以对于同类型站点，替换一次域名就可以得到一份基本可用的配置骨架。

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
