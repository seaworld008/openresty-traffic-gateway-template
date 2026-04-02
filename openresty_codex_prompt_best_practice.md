# OpenResty 中小公司流量网关实现提示词（给 Codex 使用）

> 说明：这份文档是给 Codex / GPT-Codex 之类代码代理直接执行的实现提示词，不是最终实施手册本身。目标是让代理按照要求，产出一套可运行、可维护、适合中小公司落地的 OpenResty 单节点流量网关项目。

---

## 1. 背景与目标

我们是一家中小公司，希望使用 **OpenResty** 作为统一流量网关，承接常见的反向代理、HTTPS 终止、自动 SSL 续签、按域名分业务拆分配置、基础安全加固、日志与运维友好等能力。

请你基于下面要求，直接帮我生成一套 **可运行的项目目录、配置文件、Docker Compose 部署文件、示例子配置、证书续签脚本与说明文档**。

这不是概念设计题，而是要给出一套 **能落地、能启动、能维护、结构清晰** 的实现。

---

## 2. 硬性要求

请严格满足以下要求：

1. **使用 Docker Compose 部署**。
2. **单节点部署**，核心组件为：
   - OpenResty
   - 自动 SSL 证书申请/续签组件（单独目录管理）
3. **所有目录、配置、数据资料默认都放在当前目录 `.` 下**，不要写到 `/opt`、`/data`、`/srv` 之类固定宿主机目录。
4. **业务域名示例全部放到子配置文件中**，不要把所有 server 块全堆到主配置文件里。
5. 需要给出一些 **常见子配置文件示例**。
6. OpenResty 镜像必须使用 **官方镜像**，并且使用 **明确、固定、完整的 tag**，不要用 `latest`。
7. 需要包含 **自动 SSL 证书续签**，并将这部分放在**单独目录**中，便于单独维护。
8. 输出结果要兼顾：
   - 中小公司可维护性
   - 配置清晰
   - 易于新增域名
   - 易于排错
   - 尽量贴近生产可用

---

## 3. 镜像与版本要求

OpenResty 请默认使用下面这个镜像：

```yaml
image: openresty/openresty:1.29.2.3-0-bookworm-fat
```

要求：

1. 这是默认目标镜像，不要写成 `latest`。
2. 在你生成的 README 中说明为什么使用完整 tag，而不是浮动 tag。
3. 如果你在实现时发现该 tag 在仓库实际不可拉取，请：
   - 保持“**官方镜像 + 最新稳定大版本 + 完整 tag**”原则
   - 在 README 中明确写出你最终实际使用的 tag 和原因
   - 不要 silently fallback

---

## 4. 希望你先理解并体现在方案里的常见中小公司网关架构

请在 README / 手册中先用清晰、通俗但专业的方式描述下面这些中小公司常见架构，并说明 OpenResty 在里面扮演什么角色。

### 架构 A：单机入口网关

适用：
- 小型业务
- 访问量不高到中等
- 几个域名/子域名
- 后端是多个内部 HTTP 服务

典型流量路径：

```text
Internet -> OpenResty -> 多个后端应用服务
```

请说明：
- 域名路由
- TLS 终止
- 回源代理
- 静态资源缓存（可选）
- 日志集中出口

### 架构 B：单机入口 + 多业务域名

适用：
- 官网、后台、API、活动页共用一台入口机
- 希望按域名拆配置

典型流量路径：

```text
Internet -> OpenResty
                  ├── www.example.com -> frontend
                  ├── api.example.com -> api-service
                  ├── admin.example.com -> admin-service
                  └── static.example.com -> static files / object storage / upstream
```

请说明：
- 为什么业务域名要拆到 conf.d 子文件
- 为什么证书、日志、缓存目录要结构化
- 新增域名时如何最小改动

### 架构 C：OpenResty 作为统一 HTTPS 与安全入口

适用：
- 后端应用不想直接暴露公网
- 希望统一做 HTTPS、Header 处理、限流、基础防护

典型流量路径：

```text
Internet -> OpenResty(443/80)
                    -> internal app services (private network / docker network)
```

请说明：
- 为什么把 TLS、转发、基础限流集中到入口层
- 常见安全 header
- 常见超时参数
- 上传大小限制
- 访问日志 / 错误日志分工

### 架构 D：后期可扩展到双机或负载均衡前置

请简单说明当前是单节点方案，但目录和配置风格应尽量为将来扩展保留余地，例如：
- 可扩展到 keepalived / SLB / 云 LB 前置
- 可扩展到多台 OpenResty
- 证书目录与配置目录易迁移
- upstream 写法便于横向扩展

---

## 5. 你最终需要输出的项目内容

请直接生成一个完整项目，至少包含以下内容：

```text
.
├── docker-compose.yml
├── .env.example
├── README.md
├── openresty/
│   ├── nginx.conf
│   ├── conf.d/
│   │   ├── 00-global.conf
│   │   ├── 01-upstreams.conf
│   │   ├── sites/
│   │   │   ├── example-www.conf
│   │   │   ├── example-api.conf
│   │   │   ├── example-admin.conf
│   │   │   └── example-static.conf
│   ├── lua/
│   │   └── (如有需要可放公共 Lua 脚本)
│   ├── snippets/
│   │   ├── proxy-common.conf
│   │   ├── ssl-common.conf
│   │   ├── security-headers.conf
│   │   └── cache-common.conf
│   ├── logs/
│   ├── cache/
│   ├── certs/
│   └── html/
├── ssl/
│   ├── acme/
│   ├── certbot/
│   ├── scripts/
│   │   ├── init-cert.sh
│   │   ├── renew-cert.sh
│   │   └── reload-openresty.sh
│   └── README.md
└── examples/
    ├── backend/
    │   └── docker-compose.example.yml
    └── curl-tests.md
```

你可以微调目录，但必须满足以下原则：
- **主项目目录整洁**
- **SSL 相关单独目录**
- **站点子配置单独目录**
- **可复用片段配置独立目录**
- **日志/缓存/证书目录可见、可维护**

---

## 6. Compose 设计要求

请生成一份适合中小公司单节点的 `docker-compose.yml`，要求：

1. 至少包含：
   - `openresty`
   - `certbot`（或你认为更适合、同样常见且稳妥的 ACME 组件）
2. 端口：
   - `80:80`
   - `443:443`
3. 挂载目录全部基于当前目录相对路径，例如：
   - `./openresty/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf:ro`
   - `./openresty/conf.d:/etc/nginx/conf.d:ro`
   - `./openresty/logs:/var/log/openresty`
   - `./ssl/...`
4. 要考虑：
   - OpenResty reload
   - 证书续签后自动 reload
   - 日志持久化
   - 证书持久化
   - 缓存目录持久化
5. compose 文件中要写必要注释。
6. 不要搞得过于花哨，优先可读性和可维护性。

---

## 7. OpenResty / Nginx 配置要求

### 7.1 主配置要求

`nginx.conf` 中至少要体现：

- 合理的 `worker_processes`
- `worker_connections`
- `events` 区
- `http` 基础优化
- `include /etc/nginx/conf.d/*.conf;`
- `include /etc/nginx/conf.d/sites/*.conf;`
- JSON 或较规范的 access log 格式（任选一种，但要适合生产排障）
- error log 等级建议
- `sendfile`
- `tcp_nopush`
- `tcp_nodelay`
- `keepalive_timeout`
- `client_max_body_size`
- gzip（如你认为适合）
- proxy 常见超时
- upstream keepalive（如适合）

### 7.2 子配置要求

请把业务站点按子文件拆分，并至少提供以下示例：

1. `example-www.conf`
   - `www.example.com`
   - 反代到一个前端服务
   - HTTP 跳转 HTTPS

2. `example-api.conf`
   - `api.example.com`
   - 反代到 API 服务
   - 常见代理头
   - 超时配置
   - 可选基础限流示例

3. `example-admin.conf`
   - `admin.example.com`
   - 可演示 IP 白名单或 basic auth（二选一或都给）

4. `example-static.conf`
   - `static.example.com`
   - 静态资源缓存示例
   - 适合活动页、图片、前端静态资源

### 7.3 snippets 要求

请把可复用配置抽到 snippets，例如：

- `proxy-common.conf`
- `ssl-common.conf`
- `security-headers.conf`
- `cache-common.conf`

并在 README 中说明：
- 为什么要抽 snippets
- 哪些配置适合全局复用
- 哪些配置应该按站点单独覆盖

---

## 8. SSL 自动申请与续签要求

请为中小公司给出一套简单可靠的实现。

要求：

1. 使用 **Let’s Encrypt / ACME** 常见方案。
2. SSL 逻辑必须放在单独目录，例如 `./ssl/`。
3. 至少包含：
   - 初始化申请证书脚本
   - 周期续签脚本
   - 续签完成后 reload OpenResty 的脚本
4. README 中要写清楚：
   - 首次申请步骤
   - 续签方式
   - 续签失败怎么排查
   - 如何新增域名证书
5. 请优先选一种**中小公司最容易维护**的方式，不要堆太复杂的外部依赖。
6. 如果采用 `webroot` 模式，请给出 OpenResty 中对应的 `.well-known/acme-challenge/` 配置。
7. 如果采用 sidecar / certbot 容器定时任务模式，请设计得清楚明白。

---

## 9. 常见最佳实践要求

请在 README / 手册中补充一节“中小公司最佳实践”，至少包括：

1. **目录分层原则**
2. **新增业务域名的标准操作步骤**
3. **证书新增与续签流程**
4. **如何做配置变更前校验**（例如先 `nginx -t` 再 reload）
5. **日志排障方式**
6. **常见错误排查**，例如：
   - 证书路径错误
   - 域名未解析到本机
   - upstream 不通
   - 80/443 被占用
   - 配置 include 路径错误
   - 容器挂载路径错误
7. **安全建议**，例如：
   - 隐藏版本号
   - 基础安全 header
   - 管理后台限制
   - 限流与连接数限制示例
8. **后续扩展建议**，例如：
   - 接入 WAF/CDN
   - 接入 Prometheus / 日志采集
   - 上游改为多实例 upstream
   - 灰度发布

---

## 10. 实现风格要求

请你实现时遵循以下风格：

1. **优先稳妥、常见、易维护**，不要为了炫技搞过度复杂。
2. 注释要足够清晰，适合中小公司运维、SRE、后端一起维护。
3. 配置要偏生产可用，而不是最小 demo。
4. 文件命名要有层次感、可读性。
5. README 要包含：
   - 架构说明
   - 目录说明
   - 启动步骤
   - 首次签发证书步骤
   - 新增站点步骤
   - 日常运维步骤
   - 常见故障排查
6. 若你生成 shell 脚本，请使用：
   - `set -euo pipefail`
   - 清晰日志输出
   - 必要参数检查
7. 尽量避免把业务域名、邮箱、IP 写死到不可改的位置，能参数化的尽量参数化。
8. `.env.example` 里给出常用变量示例，例如：
   - `ACME_EMAIL`
   - `PRIMARY_DOMAIN`
   - `CERTBOT_STAGING`
   - `TZ`

---

## 11. 交付物要求

请你最终直接输出：

1. 完整项目目录树
2. 每个关键文件的完整内容
3. 一份高质量 `README.md`
4. 所有示例配置文件
5. 所有脚本文件
6. 说明如何启动验证
7. 给出最小验证命令，例如：
   - `docker compose up -d`
   - `docker compose ps`
   - `docker compose logs -f openresty`
   - `curl -I http://www.example.com`
   - `curl -k https://api.example.com/health`

请不要只给思路，**请直接给完整文件内容**。

---

## 12. 可选增强（有余力可加入，但不要喧宾夺主）

如果不会显著增加复杂度，可以额外加入：

1. 一个简单的健康检查 location，例如 `/nginx_status` 或 `/healthz`
2. 一个基础限流示例
3. 一个基础连接数限制示例
4. 一个简单的 Lua 示例（例如统一请求 ID 或 header 注入），但仅在不破坏整体可维护性的前提下
5. 日志格式里带上：
   - request_id
   - upstream_addr
   - upstream_response_time
   - host
   - status

---

## 13. 明确禁止事项

请不要这样做：

1. 不要使用 `latest` 镜像 tag。
2. 不要把所有站点配置塞进一个大文件。
3. 不要把所有文件都写成最小 demo，缺少注释和说明。
4. 不要默认把证书、日志、缓存写进容器内部而不持久化。
5. 不要依赖特别冷门、维护成本高的方案。
6. 不要把 README 写得过于简略。
7. 不要用需要额外大型组件才能工作的方案（例如一上来就强依赖 K8s / Consul / etcd），当前目标是单机 compose。

---

## 14. 你可以参考的实现方向（不是强制，但建议）

你可以按下面思路落地：

- OpenResty 负责：
  - 80/443 接入
  - HTTP -> HTTPS 跳转
  - TLS 终止
  - 按 Host 分流
  - 反向代理
  - 缓存 / 安全 header / 基础限流
- Certbot 负责：
  - `webroot` 模式申请证书
  - 定时续签
  - 续签成功后调用 reload 脚本
- 目录全部基于当前目录
- 站点配置按域名拆分
- 公共片段按 snippets 复用
- 通过 README 把运维动作标准化

---

## 15. 希望最终达到的效果

最终我希望拿到的是一套：

- 中小公司能直接改域名后就开始用
- 配置结构清晰
- SSL 可自动续签
- 业务域名易增删
- 能作为统一流量入口长期维护
- 日后容易扩展为多实例或前置负载均衡

请你直接按以上要求输出完整实现，不要只给摘要。

