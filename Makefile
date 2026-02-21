SHELL := /bin/bash

.PHONY: help build test e2e check clean \
	moo-up moo-bootstrap moo-logs moo-down moo-reset \
	proxy-test core-test ios-test macos-build

help:
	@echo "Available targets:"
	@echo "  make build         # Build all components"
	@echo "  make test          # Run language-level tests"
	@echo "  make e2e           # Run end-to-end smoke test"
	@echo "  make check         # test + e2e"
	@echo "  make clean         # Remove local build artifacts"
	@echo "  make moo-up        # Start local LambdaMOO container"
	@echo "  make moo-bootstrap # Bootstrap local MOO DB"
	@echo "  make moo-logs      # Follow local MOO logs"
	@echo "  make moo-down      # Stop local MOO stack"
	@echo "  make moo-reset     # Stop local MOO stack and delete DB volume"

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

check: test e2e

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

