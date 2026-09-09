SHELL := /bin/bash

APP_NAME := Borders
EXECUTABLE_NAME := borders
BUILD_DIR := .build
DIST_DIR := dist
DEV_APP := $(BUILD_DIR)/Debug/$(APP_NAME).app
DIST_APP := $(DIST_DIR)/$(APP_NAME).app
INSTALLED_APP := $(HOME)/Applications/$(APP_NAME).app

.DEFAULT_GOAL := default
.PHONY: default help build dist install dev run test clean

default:
	@$(MAKE) --no-print-directory help

help:
	@echo "Borders Makefile guide"
	@echo ""
	@printf '%b\n' \
		'make dev\tBuild, install, and launch the current Debug app' \
		'make run\tAlias for make dev' \
		'make build\tBuild the Debug app without installing it' \
		'make dist\tBuild the Release app into dist/ for GitHub artifacts' \
		'make install\tInstall the current Release app into ~/Applications' \
		'make test\tRun the strict Swift build as a smoke test' \
		'make clean\tRemove local build and distribution artifacts' \
	| while IFS=$$'\t' read -r command description; do \
		printf '  %-16s %s\n' "$$command" "$$description"; \
	done

build:
	@Scripts/build-app.sh Debug

dist:
	@Scripts/build-app.sh Release
	@mkdir -p "$(DIST_DIR)"
	@rm -rf "$(DIST_APP)"
	@ditto "$(BUILD_DIR)/Release/$(APP_NAME).app" "$(DIST_APP)"
	@echo "Built $(DIST_APP)"

install: dist
	@mkdir -p "$(HOME)/Applications"
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(DIST_APP)" "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

dev: build
	@mkdir -p "$(HOME)/Applications"
	@pkill -x "$(EXECUTABLE_NAME)" >/dev/null 2>&1 || true
	@for attempt in {1..100}; do \
		if ! pgrep -x "$(EXECUTABLE_NAME)" >/dev/null; then break; fi; \
		sleep 0.1; \
	done
	@if pgrep -x "$(EXECUTABLE_NAME)" >/dev/null; then \
		echo "Borders did not quit. Quit it and run make dev again." >&2; exit 1; \
	fi
	@rm -rf "$(INSTALLED_APP)"
	@ditto "$(DEV_APP)" "$(INSTALLED_APP)"
	@open -n "$(INSTALLED_APP)"
	@echo "Running $(INSTALLED_APP)"

run: dev

test:
	@Scripts/build-app.sh Debug

clean:
	@rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
