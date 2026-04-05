IMAGE_NAME ?= panora-versioning-pipe
IMAGE_TAG  ?= local

.PHONY: build run shell lint help

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
	shellcheck -s sh scripts/**/*.sh pipe.sh

.DEFAULT_GOAL := help
