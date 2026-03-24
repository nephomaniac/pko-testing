# macOS Cross-Compilation Fix for OpenShift Operators

## Problem

When building OpenShift operator images on macOS (arm64) for deployment to OpenShift clusters (amd64), the standard boilerplate Makefile approach fails because:

1. **GOOS/GOARCH only affects Go binary compilation**, not the container base images
2. The **Dockerfile pulls arm64 base images** by default on macOS
3. This results in an **amd64 Go binary inside an arm64 container**, causing runtime errors:
   ```
   exec container process (missing dynamic library?) `/usr/local/bin/configure-alertmanager-operator`: No such file or directory
   ```
4. The error occurs because the arm64 base image lacks the x86-64 dynamic linker (`/lib64/ld-linux-x86-64.so.2`) needed to run the amd64 binary

## Root Cause

The boilerplate's standard.mk `docker-build` target does not support passing `--platform` flag to podman/docker:
```make
docker-build: isclean
	${CONTAINER_ENGINE} build --pull -f $(OPERATOR_DOCKERFILE) -t $(OPERATOR_IMAGE_URI) .
```

Setting `GOOS=linux GOARCH=amd64` environment variables only controls the Go build step inside the container, not which base image architecture is pulled.

## Solution

### Option 1: Modify Dockerfile (Recommended for Local Testing)

Add `--platform=linux/amd64` to both `FROM` statements in `build/Dockerfile`:

```dockerfile
FROM --platform=linux/amd64 quay.io/redhat-services-prod/openshift/boilerplate:image-v8.3.4 AS builder

RUN mkdir -p /workdir
WORKDIR /workdir
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN make go-build

####
FROM --platform=linux/amd64 registry.access.redhat.com/ubi9/ubi-minimal:9.7-1773939694

ENV USER_UID=1001 \
    USER_NAME=configure-alertmanager-operator

COPY --from=builder /workdir/build/_output/bin/* /usr/local/bin/
COPY build/bin /usr/local/bin
RUN  /usr/local/bin/user_setup

ENTRYPOINT ["/usr/local/bin/entrypoint"]
USER ${USER_UID}

LABEL io.openshift.managed.name="configure-alertmanager-operator" \
      io.openshift.managed.description="Operator to configure Alertmanager with PagerDuty and Dead Man's Snitch."
```

**Build command:**
```bash
podman build --pull -f build/Dockerfile -t <image> .
```

The `--platform` flag in the Dockerfile ensures both the builder and runtime stages use amd64 base images.

### Option 2: Use podman build directly with platform flag (Alternative)

If you don't want to modify the Dockerfile:
```bash
podman build --platform linux/amd64 --pull -f build/Dockerfile -t <image> .
```

However, this may not work correctly if the Dockerfile doesn't use build args, as podman won't pass platform info into the container.

## Verification

After building, verify the image architecture:
```bash
# Check image metadata
podman inspect <image> | jq -r '.[0].Architecture'
# Should output: amd64

# Extract and check the binary
podman create --name temp <image>
podman cp temp:/usr/local/bin/<operator-binary> ~/binary
podman rm temp
file ~/binary
# Should show: ELF 64-bit LSB executable, x86-64
```

## What Didn't Work

❌ **GOOS=linux GOARCH=amd64 with make docker-build**
- Only affects Go compilation, not base image selection
- Results in amd64 binary in arm64 container

❌ **GOARCH=linux/amd64 (alternative syntax)**
- Not standard Go syntax, doesn't affect container platform
- Boilerplate ignores this

❌ **Setting CONTAINER_ENGINE_EXTRA_FLAGS**
- Boilerplate's standard.mk doesn't support this variable

## Future Boilerplate Enhancement

The boilerplate should be enhanced to support cross-compilation on macOS:

### Proposed Changes to `boilerplate/openshift/golang-osd-operator/standard.mk`:

```make
# Add platform detection and configuration
BUILD_PLATFORM ?= $(shell uname -s)
ifeq ($(BUILD_PLATFORM),Darwin)
    CONTAINER_PLATFORM_FLAG ?= --platform linux/amd64
else
    CONTAINER_PLATFORM_FLAG ?=
endif

.PHONY: docker-build
docker-build: isclean
	${CONTAINER_ENGINE} build --pull $(CONTAINER_PLATFORM_FLAG) -f $(OPERATOR_DOCKERFILE) -t $(OPERATOR_IMAGE_URI) .
```

This would:
1. Detect macOS automatically
2. Add `--platform linux/amd64` flag on macOS
3. Keep existing behavior on Linux
4. Allow override via `CONTAINER_PLATFORM_FLAG` environment variable

### Alternative: Update Standard Dockerfile Template

Boilerplate could provide a standard Dockerfile that uses build args:

```dockerfile
ARG TARGETPLATFORM=linux/amd64
FROM --platform=${TARGETPLATFORM} quay.io/redhat-services-prod/openshift/boilerplate:image-v8.3.4 AS builder
...
ARG TARGETPLATFORM=linux/amd64
FROM --platform=${TARGETPLATFORM} registry.access.redhat.com/ubi9/ubi-minimal:...
```

Then make could pass `--build-arg TARGETPLATFORM=linux/amd64` when needed.

## Testing Checklist

When testing cross-compiled images:

- [ ] Build completes without errors
- [ ] `podman inspect <image> | jq -r '.[0].Architecture'` returns `amd64`
- [ ] Binary inside container is x86-64: `file <binary>`
- [ ] Push image to registry
- [ ] Deploy to OpenShift cluster (amd64)
- [ ] Pod starts successfully (no "exec format error" or "missing dynamic library")
- [ ] Operator functions correctly

## Related Documentation

- Podman multi-architecture builds: https://docs.podman.io/en/latest/markdown/podman-build.1.html#platform-os-arch-variant
- Docker buildx platforms: https://docs.docker.com/build/building/multi-platform/
- OpenShift CLAUDE.md: `~/.claude/CLAUDE.md` (section: "Building Container Images with Boilerplate on macOS")
