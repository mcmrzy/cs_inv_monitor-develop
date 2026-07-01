# ============================================================
# CS-INV-MONITOR 统一构建入口
# 用法: make help 查看所有可用命令
# ============================================================

.PHONY: help build test lint docker clean run

# ---------- 全局变量 ----------
GO := go
FLUTTER := flutter
NPM := npm
DOCKER_COMPOSE := docker compose -f deploy/docker-compose.yml

# ---------- 帮助（默认目标） ----------
help: ## 显示所有可用命令
	@echo "=== CS-INV-MONITOR 构建命令 ==="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ==================== Go 服务 ====================

build-api: ## 构建 inv_api_server
	cd inv_api_server && $(GO) build -ldflags="-s -w" -o ../bin/inv-api-server ./cmd/main.go

build-device: ## 构建 inv_device_server
	cd inv_device_server && $(GO) build -ldflags="-s -w" -o ../bin/inv-device-server ./cmd/main.go

build-gateway: ## 构建 api-gateway
	cd api-gateway && $(GO) build -ldflags="-s -w" -o ../bin/api-gateway ./main.go

build-bridge: ## 构建 mqtt-kafka-bridge
	cd mqtt-kafka-bridge && $(GO) build -ldflags="-s -w" -o ../bin/mqtt-kafka-bridge ./main.go

build-go: build-api build-device build-gateway build-bridge ## 构建所有 Go 服务

test-api: ## 测试 inv_api_server
	cd inv_api_server && $(GO) test ./... -v -count=1

test-device: ## 测试 inv_device_server
	cd inv_device_server && $(GO) test ./... -v -count=1

test-go: test-api test-device ## 运行所有 Go 测试

vet-go: ## Go vet 静态检查
	cd inv_api_server && $(GO) vet ./...
	cd inv_device_server && $(GO) vet ./...
	cd api-gateway && $(GO) vet ./...
	cd mqtt-kafka-bridge && $(GO) vet ./...

tidy: ## 所有 Go 模块 go mod tidy
	cd inv_api_server && $(GO) mod tidy
	cd inv_device_server && $(GO) mod tidy
	cd api-gateway && $(GO) mod tidy
	cd mqtt-kafka-bridge && $(GO) mod tidy

# ==================== Flutter App ====================

build-app: ## 构建 Flutter APK
	cd inv_app && $(FLUTTER) build apk --release

test-app: ## 运行 Flutter 测试
	cd inv_app && $(FLUTTER) test

analyze-app: ## Flutter 静态分析
	cd inv_app && $(FLUTTER) analyze

# ==================== 前端 ====================

build-web: ## 构建管理后台
	cd inv-admin-frontend && $(NPM) run build

dev-web: ## 启动前端开发服务器
	cd inv-admin-frontend && $(NPM) run dev

lint-web: ## 前端 lint 检查
	cd inv-admin-frontend && $(NPM) run lint

type-check: ## TypeScript 类型检查
	cd inv-admin-frontend && npx tsc --noEmit

# ==================== Docker ====================

docker-up: ## 启动所有 Docker 服务（构建+启动）
	$(DOCKER_COMPOSE) up -d --build

docker-down: ## 停止所有 Docker 服务
	$(DOCKER_COMPOSE) down

docker-logs: ## 查看所有服务日志
	$(DOCKER_COMPOSE) logs -f

docker-build: ## 仅构建 Docker 镜像（不启动）
	$(DOCKER_COMPOSE) build

docker-restart: ## 重启指定服务 (SERVICE=inv-api-server)
	$(DOCKER_COMPOSE) restart $(SERVICE)

# ==================== 本地开发 ====================

run-api: ## 本地运行 API Server
	cd inv_api_server && $(GO) run ./cmd/main.go -config config.yaml

run-device: ## 本地运行 Device Server
	cd inv_device_server && $(GO) run ./cmd/main.go -config config.yaml

run-gateway: ## 本地运行 API Gateway
	cd api-gateway && $(GO) run ./main.go -config config.yaml

# ==================== Git Hooks ====================

install-hooks: ## 安装 Git hooks（pre-commit + commit-msg）
	git config core.hooksPath .githooks
	@echo "Git hooks installed."

# ==================== 清理 ====================

clean: ## 清理编译产物
	rm -rf bin/
	cd inv_app && $(FLUTTER) clean 2>/dev/null || true

clean-all: clean ## 深度清理（含 node_modules、.dart_tool）
	rm -rf inv_app/.dart_tool inv_app/build
	rm -rf inv-admin-frontend/node_modules inv-admin-frontend/dist
