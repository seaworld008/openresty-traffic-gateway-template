# 常用运维命令入口，方便新项目 clone 后直接使用。

.PHONY: init local-certs pull up down up-local down-local restart ps logs check reload renew clean redis-test-up redis-test-down conf-examples-on conf-examples-off test-first-layer test-waitroom benchmark-waitroom waitroom-summary benchmark-gateway test-comprehensive

init:
	cp -n .env.example .env || true
	mkdir -p openresty/logs openresty/cache ssl/certbot/conf ssl/certbot/www
	chmod +x ssl/scripts/*.sh

local-certs:
	./ssl/scripts/init-local-certs.sh

pull:
	docker compose pull openresty
	docker compose --profile ops pull certbot

up:
	docker compose up -d

down:
	docker compose down

up-local:
	docker compose -f docker-compose.yml -f examples/backend/docker-compose.local.yml up -d

down-local:
	docker compose -f docker-compose.yml -f examples/backend/docker-compose.local.yml down --remove-orphans

restart:
	docker compose down
	docker compose up -d

ps:
	docker compose ps

logs:
	docker compose logs -f openresty

check:
	bash -n ssl/scripts/*.sh
	docker compose config >/dev/null
	docker compose exec -T openresty openresty -t

reload:
	./ssl/scripts/reload-openresty.sh

renew:
	./ssl/scripts/renew-cert.sh

redis-test-up:
	docker rm -f openresty-local-redis >/dev/null 2>&1 || true
	docker run -d --name openresty-local-redis --network openresty-install_gateway --network-alias redis redis:7.2.5-alpine

redis-test-down:
	docker rm -f openresty-local-redis >/dev/null 2>&1 || true

conf-examples-on:
	bash examples/scripts/activate_conf_examples.sh

conf-examples-off:
	bash examples/scripts/deactivate_conf_examples.sh

test-first-layer:
	bash examples/scripts/test-first-layer.sh

test-waitroom:
	bash examples/scripts/test-waitroom.sh

benchmark-waitroom:
	python3 examples/scripts/benchmark_waitroom.py

benchmark-gateway:
	python3 examples/scripts/benchmark_gateway.py

waitroom-summary:
	curl -k -H "X-Ops-Token: $${GATEWAY_OPS_TOKEN:-change-this-before-production}" --resolve enroll.example.test:443:127.0.0.1 https://enroll.example.test/api/ops/waitroom/summary

test-comprehensive:
	bash examples/scripts/run_comprehensive_validation.sh

clean:
	docker compose down
