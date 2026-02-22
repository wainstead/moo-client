SHELL := /bin/bash

.PHONY: help build test e2e check clean \
	moo-up moo-bootstrap moo-logs moo-down moo-reset \
	proxy-test core-test ios-test macos-build \
	proxy-status proxy-down proxy-down-all everything-up everything-down down-everything \
	cli-build cli-run cli-smoke cli-scenario classifier-parity coverage

help:
	@echo "Available targets:"
	@echo "  make build         # Build all components"
	@echo "  make test          # Run language-level tests"
	@echo "  make coverage      # Run multi-language test coverage summary"
	@echo "  make e2e           # Run end-to-end smoke test"
	@echo "  make check         # test + e2e"
	@echo "  make clean         # Remove local build artifacts"
	@echo "  make moo-up        # Start local LambdaMOO container"
	@echo "  make moo-bootstrap # Bootstrap local MOO DB"
	@echo "  make moo-logs      # Follow local MOO logs"
	@echo "  make moo-down      # Stop local MOO stack"
	@echo "  make moo-reset     # Stop local MOO stack and delete DB volume"
	@echo "  make proxy-status  # Show running mooproxy listeners"
	@echo "  make proxy-down    # Stop any process listening on TCP 9000"
	@echo "  make proxy-down-all # Stop all local mooproxy processes"
	@echo "  make everything-up # Start local MOO, bootstrap DB, and fresh proxy on 127.0.0.1:9000"
	@echo "  make everything-down # Stop local MOO stack and all mooproxy processes"
	@echo "  make cli-build     # Build moo-cli (Rust debug client)"
	@echo "  make cli-run       # Run moo-cli against local proxy"
	@echo "  make cli-smoke     # Run scripted moo-cli smoke test"
	@echo "  make cli-scenario  # Run scripted moo-cli scenario smoke test"
	@echo "  make classifier-parity # Verify Rust/Swift classifier parity on shared fixtures"

build:
	cd proxy && go build ./...
	cd core && cargo build
	cd ios-app && swift build
	cd macos-app && swift build

proxy-test:
	cd proxy && go test ./...

core-test:
	cd core && cargo test

ios-test:
	cd ios-app && swift test && swift run MooIOSRelaySelfTest

macos-build:
	cd macos-app && swift build

test: proxy-test core-test ios-test macos-build

e2e:
	./scripts/test_e2e.sh

check: test e2e classifier-parity cli-scenario

clean:
	rm -rf core/target
	rm -rf ios-app/.build
	rm -rf macos-app/.build
	rm -f proxy/mooproxy

moo-up:
	./scripts/run_local_moo.sh up

moo-bootstrap:
	./scripts/run_local_moo.sh bootstrap

moo-logs:
	./scripts/run_local_moo.sh logs

moo-down:
	./scripts/run_local_moo.sh down

moo-reset:
	./scripts/run_local_moo.sh reset

proxy-status:
	@echo "mooproxy listeners:"
	@lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '$$1=="mooproxy"' || true

proxy-down:
	@pids=$$(lsof -tiTCP:9000 -sTCP:LISTEN 2>/dev/null || true); \
	if [[ -n "$$pids" ]]; then \
	  echo "stopping listeners on :9000 -> $$pids"; \
	  kill $$pids; \
	else \
	  echo "no listener on :9000"; \
	fi

proxy-down-all:
	@pids=$$(pgrep -f mooproxy 2>/dev/null || true); \
	if [[ -n "$$pids" ]]; then \
	  echo "stopping mooproxy processes -> $$pids"; \
	  kill $$pids; \
	else \
	  echo "no mooproxy processes found"; \
	fi

everything-up:
	@$(MAKE) moo-up
	@$(MAKE) moo-bootstrap
	@$(MAKE) proxy-down-all
	@(cd proxy && go build -o mooproxy ./cmd/mooproxy && nohup ./mooproxy -mode local -listen 127.0.0.1:9000 -upstream 127.0.0.1:7777 >/tmp/mooproxy.log 2>&1 &)
	@sleep 1
	@pids=$$(lsof -tiTCP:9000 -sTCP:LISTEN 2>/dev/null || true); \
	if [[ -n "$$pids" ]]; then \
	  echo "started proxy on :9000 -> $$pids (log: /tmp/mooproxy.log)"; \
	else \
	  echo "failed to start proxy on :9000; check /tmp/mooproxy.log"; \
	  exit 1; \
	fi

everything-down:
	@$(MAKE) moo-down
	@$(MAKE) proxy-down-all

down-everything: everything-down

cli-build:
	cd core && cargo build --bin moo-cli

cli-run:
	cd core && cargo run --bin moo-cli -- connect --ws-url ws://127.0.0.1:9000/ws

cli-smoke:
	./scripts/test_cli_smoke.sh

cli-scenario:
	./scripts/test_cli_scenario.sh

classifier-parity:
	./scripts/test_classifier_parity.sh

coverage:
	./scripts/test_coverage.sh
