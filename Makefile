SHELL := /bin/bash

APP_NAME := Borders
EXECUTABLE_NAME := borders
BUILD_DIR := .build
DIST_DIR := dist
DEV_APP := $(BUILD_DIR)/Debug/$(APP_NAME).app
DIST_APP := $(DIST_DIR)/$(APP_NAME).app
INSTALLED_APP := $(HOME)/Applications/$(APP_NAME).app

.DEFAULT_GOAL := default
.PHONY: default help build dist install dev run test unit-test complexity mutation mutation-execute clean

COMPLEXITY_THRESHOLD ?= 7
LIZARD ?= uvx lizard

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
		'make test\tRun the unit tests and the strict Swift build' \
		'make unit-test\tRun the unit tests only' \
		'make complexity\tReport functions above the cyclomatic complexity ratchet' \
		'make mutation\tPlan mutation testing for BordersCore without running it' \
		'make mutation-execute\tRun the mutation cycle; nonzero exit when mutants survive' \
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
	@# Ask the running copy to quit over its control socket. A signal kills it
	@# mid-draw and leaves its overlay windows for the window server to clean
	@# up; a graceful exit lets AppKit take them down. Older builds predate the
	@# quit command, so a signal remains the fallback.
	@"$(BUILD_DIR)/debug/$(EXECUTABLE_NAME)" quit >/dev/null 2>&1 || true
	@for attempt in {1..50}; do \
		if ! pgrep -x "$(EXECUTABLE_NAME)" >/dev/null; then break; fi; \
		sleep 0.1; \
	done
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

test: unit-test
	@Scripts/build-app.sh Debug

unit-test:
	@swift test

# The ratchet only ever moves down. A function above it is a prompt to split
# it, not a prompt to raise the number.
complexity:
	@mkdir -p .run
	@$(LIZARD) -l swift Sources -C $(COMPLEXITY_THRESHOLD) --warnings_only | tee .run/complexity.txt
	@if [ -s .run/complexity.txt ]; then \
		echo "Functions above CCN $(COMPLEXITY_THRESHOLD). Split them or justify the change." >&2; \
		exit 1; \
	fi
	@echo "No function in Sources exceeds cyclomatic complexity $(COMPLEXITY_THRESHOLD)."

mutation:
	@Scripts/mutation-test.sh $(MUTATION_ARGS)

mutation-execute:
	@Scripts/mutation-test.sh $(MUTATION_ARGS) --execute

clean:
	@rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
