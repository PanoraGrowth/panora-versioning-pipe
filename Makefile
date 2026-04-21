IMAGE_NAME ?= panora-versioning-pipe
IMAGE_TAG  ?= local

GO_BINARY     ?= panora-versioning
GO_VERSION    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
GO_COMMIT     ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
GO_BUILT_AT   ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
GO_LDFLAGS    := -s -w \
  -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.Version=$(GO_VERSION) \
  -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.Commit=$(GO_COMMIT) \
  -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.BuiltAt=$(GO_BUILT_AT)

.PHONY: build run help test test-unit test-integration test-integration-bitbucket test-integration-all test-integration-go test-integration-filter test-integration-bitbucket-filter go-build go-test go-lint go-tidy build-preview-image

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build the Docker image (pure Go runtime)
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

test: test-unit ## Run all local tests (unit only; integration requires credentials)

test-unit: ## Run Go unit tests with race detector
	go test ./... -race -count=1

test-integration: ## Run integration tests — GitHub (parallel, requires gh CLI authenticated)
	cd tests/integration && pip install -q -r requirements.txt && pytest -v -n 15 --dist worksteal test_github.py

test-integration-bitbucket: ## Run integration tests — Bitbucket (requires BB_TOKEN)
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_bitbucket.py -x

test-integration-all: ## Run integration tests on both platforms
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_github.py test_bitbucket.py -x

test-integration-go: ## Run Go integration tests locally (requires docker + go)
	@command -v docker >/dev/null 2>&1 || { echo "docker not found"; exit 1; }
	go build -o bin/$(GO_BINARY) ./cmd/panora-versioning
	cd tests/integration && pip install -q -r requirements.txt && \
	  PANORA_GO_BINARY=$(CURDIR)/bin/$(GO_BINARY) pytest -v test_go_*.py

test-integration-filter: ## Run specific integration scenario (sequential): make test-integration-filter S=feat-minor-bump
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_github.py -k "$(S)"

test-integration-bitbucket-filter: ## Run specific Bitbucket scenario: make test-integration-bitbucket-filter S=feat-minor-bump
	cd tests/integration && pip install -q -r requirements.txt && pytest -v test_bitbucket.py -x -k "$(S)"

go-build: ## Build the Go binary locally with version ldflags injected
	go build -ldflags "$(GO_LDFLAGS)" -o bin/$(GO_BINARY) ./cmd/panora-versioning

go-test: test-unit ## Alias for test-unit (Go unit tests)

go-lint: ## Run go vet, gofmt check, and golangci-lint
	go vet ./...
	@unformatted="$$(gofmt -l .)"; \
	if [ -n "$$unformatted" ]; then \
	  echo "gofmt failures:"; echo "$$unformatted"; exit 1; \
	fi
	@command -v golangci-lint >/dev/null 2>&1 || { echo "golangci-lint not found. Install: https://golangci-lint.run/"; exit 1; }
	golangci-lint run

go-tidy: ## Ensure go.mod and go.sum are tidy
	go mod tidy

build-preview-image: ## Build and push a preview image to GHCR: make build-preview-image TAG=pr-N
	@test -n "$(TAG)" || { echo "Usage: make build-preview-image TAG=pr-N"; exit 1; }
	docker build -t ghcr.io/panoragrowth/panora-versioning-pipe:$(TAG) .
	docker push ghcr.io/panoragrowth/panora-versioning-pipe:$(TAG)

.DEFAULT_GOAL := help
