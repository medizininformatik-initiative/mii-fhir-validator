# Developer entry points for mii-fhir-validator. Run `make help` for the list.
#
# Linters that are not installed are skipped with a notice; STRICT=1 (used in CI) makes a
# missing tool an error. Install them with: brew install shellcheck hadolint actionlint

STRICT ?= 0
SH_FILES = $(shell git ls-files --cached --others --exclude-standard -- '*.sh')
DOCKERFILES = $(shell git ls-files --cached --others --exclude-standard -- '*Dockerfile')
COMPOSE = docker compose --env-file .env.default

# $(call require,tool): continue if tool exists; otherwise skip the recipe, or fail with STRICT=1.
require = if ! command -v $(1) >/dev/null 2>&1; then \
	if [ "$(STRICT)" = 1 ]; then echo "error: $(1) not installed (STRICT=1)"; exit 1; fi; \
	echo "skip: $(1) not installed"; exit 0; fi

.PHONY: help doctor check lint lint-strict lint-sh lint-docker lint-actions lint-compose check-sync \
	test-hooks test-runner test-entrypoint test test-file docs-install docs docs-dev

## help: List the targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'

## doctor: Report which prerequisites for checks, tests, docs and the stack are present
doctor:
	@./scripts/doctor.sh

## check: Everything that needs no terminology stack: lint, check-sync, hook/runner/entrypoint tests
check: lint check-sync test-hooks test-runner test-entrypoint

## lint: ShellCheck, hadolint, actionlint and docker compose config (missing tools: skipped)
lint: lint-sh lint-docker lint-actions lint-compose

## lint-strict: lint, failing when a linter is not installed (what CI runs)
lint-strict:
	@$(MAKE) --no-print-directory lint STRICT=1

## lint-sh: ShellCheck all tracked and untracked, non-ignored *.sh files
lint-sh:
	@$(call require,shellcheck); echo "shellcheck: $(words $(SH_FILES)) files"; shellcheck -S warning $(SH_FILES)

## lint-docker: hadolint all Dockerfiles (config: .hadolint.yaml)
lint-docker:
	@$(call require,hadolint); echo "hadolint: $(DOCKERFILES)"; hadolint $(DOCKERFILES)

## lint-actions: actionlint all GitHub workflows (also shellchecks run: blocks)
lint-actions:
	@$(call require,actionlint); echo "actionlint: .github/workflows"; actionlint

## lint-compose: Validate docker-compose.yml per profile and the CI override (uses .env.default, never .env)
lint-compose:
	@$(call require,docker); \
	for p in blaze ontoserver; do \
		echo "docker compose config: profile $$p"; \
		COMPOSE_PROFILES=$$p $(COMPOSE) config -q || exit 1; \
	done; \
	echo "docker compose config: CI override"; \
	COMPOSE_PROFILES=blaze $(COMPOSE) -f docker-compose.yml -f .github/configs/docker-compose.ci.yml config -q

## check-sync: Compare IG versions, image tags, terminology BOM and SNOMED CT release across files
check-sync:
	@./scripts/check-sync.sh

## test-hooks: Regression tests for the Claude Code policy hooks (synthetic input, nothing executed)
test-hooks:
	@./tests/hooks/run.sh

## test-runner: Synthetic tests for scripts/test/validate-test-resources.sh (fake curl, no network)
test-runner:
	@./tests/runner/run.sh

## test-entrypoint: Entrypoint tests in a container with a stub java (needs Docker, no terminology)
test-entrypoint:
	@./tests/entrypoint/run.sh

## test: Integration test: validate .github/test-resources/*.json against a running stack (VALIDATOR_URL)
test:
	@./scripts/test/validate-test-resources.sh

## test-file: Integration test for one resource: make test-file FILE=.github/test-resources/valid-observation.json
test-file:
	@test -n "$(FILE)" || { echo "Usage: make test-file FILE=path/to/resource.json"; exit 1; }
	@./scripts/test/validate-test-resources.sh "$(FILE)"

## docs-install: Install the docs dependencies (npm ci in docs/)
docs-install:
	@$(MAKE) --no-print-directory -C docs install

## docs: Build the docs site into docs/.vitepress/dist (run docs-install first)
docs:
	@$(MAKE) --no-print-directory -C docs build

## docs-dev: Serve the docs with live reload (run docs-install first)
docs-dev:
	@$(MAKE) --no-print-directory -C docs dev
