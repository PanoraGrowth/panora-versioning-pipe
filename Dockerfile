# Dockerfile for Versioning Pipe
# Docker image for automated versioning, changelog generation, and version file updates

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

USER pipe

ENTRYPOINT ["/pipe/pipe.sh"]
