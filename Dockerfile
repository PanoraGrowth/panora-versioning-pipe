# Dockerfile for Versioning Pipe
# Docker image for automated versioning, changelog generation, and version file updates

FROM public.ecr.aws/docker/library/alpine:3.19

LABEL maintainer="Panora Growth <oss@panoragrowth.com>"
LABEL description="Automated versioning, changelog generation, and version file updates for CI/CD pipelines"

# Install dependencies
RUN apk add --no-cache \
    bash \
    git \
    curl \
    jq \
    coreutils \
    tzdata \
    gettext \
    && rm -rf /var/cache/apk/*

# Install yq (YAML processor)
RUN curl -sSL https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Set timezone
ENV TZ=UTC

# Create working directory
WORKDIR /pipe

# Copy scripts
COPY scripts/ /pipe/

# Make all scripts executable
RUN find /pipe -name "*.sh" -exec chmod +x {} \;

# Entry point script
COPY pipe.sh /pipe/
RUN chmod +x /pipe/pipe.sh

ENTRYPOINT ["/pipe/pipe.sh"]
