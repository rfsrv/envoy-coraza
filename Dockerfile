# Versions encoded in the git tag — keep ARG defaults in sync with the tag
# when bumping: update both ARGs, commit, then tag as
#   envoy-{ENVOY_VERSION}-coraza-{CORAZA_VERSION}  (e.g. envoy-v1.37.1-coraza-v1.3.0)
ARG ENVOY_VERSION=v1.37.1
ARG GO_VERSION=1.25.8

# --- Build stage ---
# Use a dedicated Go image so we get a native Go toolchain + proper cross-compilers.
# The build always runs on the native runner arch; TARGETARCH controls the output.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS builder

ARG CORAZA_VERSION=v1.3.0
# TARGETARCH / TARGETOS injected by docker buildx (amd64 / arm64)
ARG TARGETARCH
ARG TARGETOS=linux

# Install cross-compilers for CGO builds targeting the non-native arch.
# Both are installed; only the one matching TARGETARCH is actually used.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl tar \
        gcc-x86-64-linux-gnu g++-x86-64-linux-gnu \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

ENV CGO_ENABLED=1

# Fetch coraza-envoy-go-filter source at pinned version
RUN mkdir /src && \
    curl -fsSL "https://github.com/united-security-providers/coraza-envoy-go-filter/archive/refs/tags/${CORAZA_VERSION}.tar.gz" \
      | tar -xz --strip-components 1 -C /src

WORKDIR /src

# Cross-compile the Go filter shared library.
# Set CC to the correct cross-compiler based on TARGETARCH.
RUN case "${TARGETARCH}" in \
      amd64) export CC=x86_64-linux-gnu-gcc CXX=x86_64-linux-gnu-g++ ;; \
      arm64) export CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++ ;; \
    esac && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build \
      -o /coraza-waf.so \
      -buildmode=c-shared \
      -tags="coraza.rule.multiphase_evaluation,memoize_builders" \
      .

# --- Final image ---
FROM envoyproxy/envoy:contrib-${ENVOY_VERSION}

COPY --from=builder /coraza-waf.so /etc/envoy/coraza-waf.so

LABEL org.opencontainers.image.title="envoy-coraza" \
      org.opencontainers.image.description="Envoy proxy contrib image with Coraza WAF Go filter" \
      org.opencontainers.image.source="https://github.com/rfsrv/envoy-coraza"
