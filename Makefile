IMAGE_NAME ?= panora-versioning-pipe
IMAGE_TAG  ?= local

.PHONY: build run shell lint help build-test test test-unit test-unit-filter test-integration test-integration-bitbucket test-integration-all test-integration-filter test-integration-bitbucket-filter

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the Docker image
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

run: build ## Run the pipe with a mounted working directory
	docker run --rm \
		-v "$$(pwd):/workspace" \
		-w /workspace \
		-e BITBUCKET_PR_ID=$${BITBUCKET_PR_ID:-} \
		-e BITBUCKET_BRANCH=$${BITBUCKET_BRANCH:-} \
		-e BITBUCKET_PR_DESTINATION_BRANCH=$${BITBUCKET_PR_DESTINATION_BRANCH:-} \
		-e BITBUCKET_COMMIT=$${BITBUCKET_COMMIT:-} \
		$(IMAGE_NAME):$(IMAGE_TAG)

shell: build ## Open an interactive shell in the container
	docker run --rm -it \
		-v "$$(pwd):/workspace" \
		-w /workspace \
		$(IMAGE_NAME):$(IMAGE_TAG) /bin/bash

lint: ## Run shellcheck on all scripts (requires shellcheck)
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Install: brew install shellcheck"; exit 1; }
	shellcheck --exclude=SC1091 scripts/**/*.sh pipe.sh

build-test: build ## Build the test Docker image (bats-core)
	docker build -f tests/Dockerfile.test --build-arg BASE_IMAGE=$(IMAGE_NAME):$(IMAGE_TAG) -t $(IMAGE_NAME)-test:$(IMAGE_TAG) .

test: test-unit ## Run all local tests (unit only, integration requires credentials)

test-unit: build-test ## Run unit tests in Docker
	docker run --rm $(IMAGE_NAME)-test:$(IMAGE_TAG) bats -r tests/unit/

test-unit-filter: build-test ## Run specific test: make test-unit-filter F=config-parser/getters
	docker run --rm $(IMAGE_NAME)-test:$(IMAGE_TAG) bats tests/unit/$(F).bats

test-integration: ## Run integration tests — GitHub (requires gh CLI authenticated)
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_github.py

test-integration-bitbucket: ## Run integration tests — Bitbucket (requires BB_TOKEN)
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_bitbucket.py -x

test-integration-all: ## Run integration tests on both platforms
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_github.py test_bitbucket.py -x

test-integration-filter: ## Run specific integration scenario: make test-integration-filter S=feat-major-bump
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_github.py -k "$(S)"

test-integration-bitbucket-filter: ## Run specific Bitbucket scenario: make test-integration-bitbucket-filter S=feat-major-bump
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_bitbucket.py -x -k "$(S)"

.DEFAULT_GOAL := help
