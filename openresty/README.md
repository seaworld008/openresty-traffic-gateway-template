# OpenResty deployment directory

This directory is self-contained and can be deployed directly as the runtime
directory, for example:

```bash
cp -a openresty /data/openresty
cd /data/openresty
cp .env.example .env
docker compose up -d
```

All bind mounts in `docker-compose.yml` are relative to this directory.
