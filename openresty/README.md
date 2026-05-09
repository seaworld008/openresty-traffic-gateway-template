# OpenResty 部署目录

这个目录是唯一的生产部署入口。部署到服务器时，只需要复制或拉取仓库的
`openresty/` 子目录，并把它作为运行目录，例如 `/data/openresty`。

```bash
cp -a openresty /data/openresty
cd /data/openresty
cp .env.example .env
docker compose up -d
```

`docker-compose.yml` 中所有 bind mount 都使用相对路径，例如：

```yaml
./nginx.conf
./conf.d
./lua
./logs
./cache
./html
./certs
```

仓库根目录用于维护文档、示例和测试脚本，不是生产运行目录。
