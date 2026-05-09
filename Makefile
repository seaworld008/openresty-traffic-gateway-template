# 常用运维命令入口，方便新项目 clone 后直接使用。

.PHONY: init local-certs pull up down up-local down-local restart ps logs check reload renew clean redis-test-up redis-test-down conf-examples-on conf-examples-off test-first-layer test-waitroom benchmark-waitroom waitroom-summary benchmark-gateway test-comprehensive

init:
	cp -n openresty/.env.example openresty/.env || true
	mkdir -p openresty/logs openresty/cache openresty/certs

local-certs:
	./ssl/scripts/init-local-certs.sh

pull:
	docker compose --project-directory openresty -f openresty/docker-compose.yml pull openresty

up:
	docker compose --project-directory openresty -f openresty/docker-compose.yml up -d

down:
	docker compose --project-directory openresty -f openresty/docker-compose.yml down

up-local:
	DOCKER_NETWORK_NAME=openresty_gateway docker compose -f openresty/docker-compose.yml -f examples/backend/docker-compose.local.yml up -d

down-local:
	DOCKER_NETWORK_NAME=openresty_gateway docker compose -f openresty/docker-compose.yml -f examples/backend/docker-compose.local.yml down --remove-orphans

restart:
	docker compose --project-directory openresty -f openresty/docker-compose.yml down
	docker compose --project-directory openresty -f openresty/docker-compose.yml up -d

ps:
	docker compose --project-directory openresty -f openresty/docker-compose.yml ps

logs:
	docker compose --project-directory openresty -f openresty/docker-compose.yml logs -f openresty

check:
	docker compose --project-directory openresty -f openresty/docker-compose.yml config >/dev/null
	docker compose --project-directory openresty -f openresty/docker-compose.yml exec -T openresty openresty -t

reload:
	docker compose --project-directory openresty -f openresty/docker-compose.yml exec -T openresty openresty -s reload

renew:
	@echo "证书续签请在具体生产环境中按 openresty/certs 挂载策略处理"

redis-test-up:
	docker rm -f openresty-local-redis >/dev/null 2>&1 || true
	docker run -d --name openresty-local-redis --network openresty_gateway --network-alias redis redis:7.2.5-alpine

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
	docker compose --project-directory openresty -f openresty/docker-compose.yml down
