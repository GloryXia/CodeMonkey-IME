# ============================================================
# 开发专用输入法 — Makefile
# ============================================================

.PHONY: install uninstall deploy sync-dicts test clean help model-sidecar model-sidecar-health model-sidecar-service-install model-sidecar-service-uninstall model-sidecar-service-status model-sidecar-service-logs

SHELL := /bin/bash
RIME_DIR := $(HOME)/Library/Rime

# 默认目标
help: ## 显示帮助
	@echo "开发专用输入法 — 开发专用输入法"
	@echo ""
	@echo "可用命令："
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

install: ## 安装 开发专用输入法 到 Rime
	@chmod +x scripts/install.sh
	@bash scripts/install.sh

uninstall: ## 卸载 开发专用输入法
	@chmod +x scripts/uninstall.sh
	@bash scripts/uninstall.sh

deploy: ## 触发 Rime 重新部署
	@echo "触发 Rime 重新部署..."
	@osascript -e 'tell application id "im.rime.inputmethod.Squirrel" to deploy' 2>/dev/null || \
		echo "⚠ 请手动在 Squirrel 菜单中点击「重新部署」"
	@echo "✓ 部署完成"

sync-dicts: ## 从 rime-ice 同步词库
	@chmod +x scripts/sync_dicts.sh
	@bash scripts/sync_dicts.sh

test: ## 运行测试
	@echo "运行 Lua 测试..."
	@if command -v lua &> /dev/null; then \
		lua tests/test_utils.lua && \
		lua tests/test_context_detector.lua && \
		lua tests/test_hybrid_processor.lua && \
		lua tests/test_hybrid_filter.lua && \
		lua tests/test_candidate_rerank_filter.lua && \
		lua tests/test_model_feature_extractor.lua && \
		lua tests/test_model_cache.lua && \
		lua tests/test_model_logger.lua && \
		lua tests/test_model_bridge.lua && \
		lua tests/test_punctuation_processor.lua && \
		echo "✓ 所有测试通过"; \
	else \
		echo "⚠ 未安装 Lua，跳过测试"; \
		echo "  安装: brew install lua"; \
	fi

dev-install: ## 开发模式安装（创建符号链接）
	@echo "创建符号链接到 Rime 目录..."
	@mkdir -p $(RIME_DIR)/lua
	@mkdir -p $(RIME_DIR)/dicts
	@ln -sf $(PWD)/schema/hybrid_ime.schema.yaml $(RIME_DIR)/
	@ln -sf $(PWD)/schema/hybrid_ime.dict.yaml $(RIME_DIR)/
	@ln -sf $(PWD)/lua/*.lua $(RIME_DIR)/lua/
	@ln -sf $(PWD)/dicts/*.yaml $(RIME_DIR)/dicts/
	@ln -sf $(PWD)/dicts/*.txt $(RIME_DIR)/dicts/
	@echo "✓ 符号链接创建完成（修改代码后运行 make deploy 即可生效）"

clean: ## 清理临时文件
	@rm -rf .tmp_rime_ice
	@echo "✓ 临时文件已清理"

status: ## 检查安装状态
	@echo "开发专用输入法 安装状态："
	@echo ""
	@echo "Rime 目录: $(RIME_DIR)"
	@if [ -f "$(RIME_DIR)/hybrid_ime.schema.yaml" ]; then \
		echo "  ✓ hybrid_ime.schema.yaml"; \
	else \
		echo "  ✗ hybrid_ime.schema.yaml (未安装)"; \
	fi
	@if [ -d "$(RIME_DIR)/lua" ] && [ -f "$(RIME_DIR)/lua/hybrid_init.lua" ]; then \
		echo "  ✓ Lua 脚本"; \
	else \
		echo "  ✗ Lua 脚本 (未安装)"; \
	fi
	@if [ -d "$(RIME_DIR)/dicts" ]; then \
		echo "  ✓ 自定义词典"; \
	else \
		echo "  ✗ 自定义词典 (未安装)"; \
	fi
	@if [ -d "$(RIME_DIR)/cn_dicts" ]; then \
		echo "  ✓ 中文词库"; \
	else \
		echo "  ✗ 中文词库 (未同步，运行 make sync-dicts)"; \
	fi
	@echo ""

model-sidecar: ## 启动本地模型 sidecar stub
	@chmod +x scripts/start_model_sidecar.sh
	@bash scripts/start_model_sidecar.sh

model-sidecar-health: ## 检查本地模型 sidecar stub 健康状态
	@/usr/bin/curl --silent --show-error --fail http://127.0.0.1:39571/health || \
		echo "⚠ sidecar 未启动"

model-sidecar-service-install: ## 安装并启动 sidecar 的 launchd 用户服务
	@chmod +x scripts/install_model_sidecar_service.sh
	@bash scripts/install_model_sidecar_service.sh

model-sidecar-service-uninstall: ## 卸载 sidecar 的 launchd 用户服务
	@chmod +x scripts/uninstall_model_sidecar_service.sh
	@bash scripts/uninstall_model_sidecar_service.sh

model-sidecar-service-status: ## 查看 sidecar launchd 用户服务状态
	@launchctl print gui/$$UID/com.hybridime.modeld

model-sidecar-service-logs: ## 查看 sidecar 服务日志
	@tail -n 50 "$(HOME)/Library/Rime/modeld/model_sidecar.stdout.log" 2>/dev/null || true
	@tail -n 50 "$(HOME)/Library/Rime/modeld/model_sidecar.stderr.log" 2>/dev/null || true
