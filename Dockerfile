# Versions encoded in the git tag — keep ARG defaults in sync with the tag
# when bumping: update both ARGs, commit, then tag as
#   envoy-{ENVOY_VERSION}-coraza-{CORAZA_VERSION}  (e.g. envoy-v1.37.1-coraza-v1.3.0)
ARG ENVOY_VERSION=v1.37.1

# --- Build stage ---
FROM envoyproxy/envoy:contrib-${ENVOY_VERSION} AS builder

ARG CORAZA_VERSION=v1.3.0
ARG GO_VERSION=1.26.1
# TARGETARCH is injected automatically by docker buildx (amd64 / arm64)
ARG TARGETARCH=amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl tar ca-certificates gcc g++ \
    && rm -rf /var/lib/apt/lists/*

# Install Go from official tarball (handles any version, any arch)
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local

ENV PATH="/usr/local/go/bin:$PATH" \
    GOPATH="/go" \
    CGO_ENABLED=1

# Fetch coraza-envoy-go-filter source at pinned version
RUN mkdir /src && \
    curl -fsSL "https://github.com/united-security-providers/coraza-envoy-go-filter/archive/refs/tags/${CORAZA_VERSION}.tar.gz" \
      | tar -xz --strip-components 1 -C /src

WORKDIR /src

# Standard build — pure-Go re2/libinjection, no CGO runtime deps
RUN go build \
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
