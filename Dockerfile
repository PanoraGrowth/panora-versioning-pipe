# Dockerfile for Versioning Pipe
# Multi-stage build: stage 1 compiles the Go binary, stage 2 keeps the
# existing Bash entry point (pipe.sh) and bundles both so the migration
# can progress incrementally.

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
# Stage 2 — runtime image (Bash legacy + Go binary)
# =============================================================================
FROM public.ecr.aws/docker/library/alpine:3.19

LABEL maintainer="Panora Growth <oss@panoragrowth.com>"
LABEL description="Automated versioning, changelog generation, and version file updates for CI/CD pipelines"

# Upgrade base packages first to pull in security patches (e.g. musl CVE-2026-40200)
RUN apk upgrade --no-cache

# Install dependencies + yq from Alpine community repo (integrity verified by APK signing)
RUN apk add --no-cache \
    bash \
    git \
    curl \
    jq \
    yq \
    coreutils \
    tzdata \
    gettext \
    && rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=UTC

# Create non-root user for runtime
RUN adduser -D -u 1001 pipe

# Create working directory
WORKDIR /pipe

# Copy scripts
COPY scripts/ /pipe/

# Make all scripts executable (must run as root, before USER directive)
RUN find /pipe -name "*.sh" -exec chmod +x {} \;

# Entry point script
COPY pipe.sh /pipe/
RUN chmod +x /pipe/pipe.sh

# Bundle the Go binary. Wave N removes bash/yq/jq/curl once every subcommand
# lives in Go; until then both runtimes coexist inside the same image.
COPY --from=builder /out/panora-versioning /usr/local/bin/panora-versioning

USER pipe

ENTRYPOINT ["/pipe/pipe.sh"]
