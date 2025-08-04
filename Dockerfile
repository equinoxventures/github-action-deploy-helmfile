FROM public.ecr.aws/docker/library/python:3.11.4-slim-bullseye

ARG TARGETARCH
ARG TARGETOS
ENV IMAGE_ARCH=$TARGETARCH
ENV IMAGE_OS=$TARGETOS
ENV KUBECTL_VERSION=1.32.3
ENV HELM_VERSION=3.18.4
ENV HELMFILE_VERSION=1.1.3
ENV CHAMBER_VERSION=2.13.2
ENV HELM_DIFF_VERSION=3.9.8
ENV HELM_GIT_VERSION=0.15.1
ENV HELM_SECRETS_VERSION=4.6.5
ENV HELM_S3_VERSION=0.16.0


ENV HELM_DATA_HOME=/root/.local/share/helm
ENV HELM_CONFIG_HOME=/root/.config/helm
ENV HELM_CACHE_HOME=/root/.cache/helm

# Update CA certificates and install required packages
RUN apt-get update && apt-get install -y ca-certificates apt-utils curl unzip

RUN if [ "$TARGETARCH" = "amd64" ]; then \
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
    elif [ "$TARGETARCH" = "arm64" ]; then \
      curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"; \
    else \
      echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# Replace HTTP with HTTPS in sources.list
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list

RUN curl -1sLf 'https://dl.cloudsmith.io/public/cloudposse/packages/cfg/setup/bash.deb.sh' | bash

RUN apt-get update && apt-get install -y \
    bash \
    yq \
    jq \
    git \
    sops

COPY entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT [ "/usr/local/bin/entrypoint" ]
