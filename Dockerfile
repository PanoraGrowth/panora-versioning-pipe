# Dockerfile for Versioning Pipe
# Multi-stage build: stage 1 compiles the Go binary, stage 2 is the pure-Go
# runtime image. Bash/jq/yq/curl were removed in GO-12.

# =============================================================================
# Stage 1 — build the Go binary
# =============================================================================
FROM golang:1.26-alpine AS builder

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILT_AT=unknown

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/

RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags "-s -w \
      -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.Version=${VERSION} \
      -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.Commit=${COMMIT} \
      -X github.com/PanoraGrowth/panora-versioning-pipe/internal/util/version.BuiltAt=${BUILT_AT}" \
    -o /out/panora-versioning ./cmd/panora-versioning

# =============================================================================
# Stage 2 — runtime image (pure Go)
# =============================================================================
FROM public.ecr.aws/docker/library/alpine:3.19

LABEL maintainer="Panora Growth <oss@panoragrowth.com>"
LABEL description="Automated versioning, changelog generation, and version file updates for CI/CD pipelines"

# Upgrade base packages first to pull in security patches (e.g. musl CVE-2026-40200)
RUN apk upgrade --no-cache

# Runtime deps:
#   git    — the Go binary shells out to `git` for all repo operations
#   tzdata — ENV TZ=UTC below requires tzdata; UTC tag timestamps are a
#            documented contract (see GO-11 behavior delta).
RUN apk add --no-cache \
    git \
    tzdata \
    && rm -rf /var/cache/apk/*

# Set timezone (consumed by tag timestamp formatter)
ENV TZ=UTC

# Create non-root user for runtime
RUN adduser -D -u 1001 pipe

WORKDIR /pipe

# Bundled YAML defaults (commit-types.yml, defaults.yml). Resolved at runtime
# by internal/config.ResolveBundledFile — path override via PANORA_DEFAULTS_DIR.
COPY config/defaults/ /etc/panora/defaults/

# Go binary
COPY --from=builder /out/panora-versioning /usr/local/bin/panora-versioning

USER pipe

ENTRYPOINT ["/usr/local/bin/panora-versioning"]
