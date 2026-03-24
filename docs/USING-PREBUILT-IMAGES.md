# Using Pre-Built Images

## Overview

You can use pre-built images instead of building locally. This is useful for:
- Testing Konflux CI-built images
- Using images from CD pipelines
- Skipping slow local builds
- Testing specific released versions

## Quick Start

### 1. Set Image URIs in user-config

Edit `config/user-config` and uncomment the pre-built image lines:

```bash
# Pre-built Images (Option 2: Use existing images - SKIPS BUILD PHASES)
OPERATOR_IMAGE=quay.io/openshift/configure-alertmanager-operator:v0.1.810
PKO_IMAGE=quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810
```

### 2. Run Tests (Skip Build Phases)

```bash
# Start from phase 3 (prepare cluster)
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh
../common/phase5-deploy-pko.sh
# ...
```

Phase 1 and 2 are automatically skipped when pre-built images are provided.

---

## Image Validation

Scripts automatically validate pre-built images:

### What Gets Checked

**For Operator Images:**
- ✅ Image exists and is pullable
- ✅ Registry credentials work

**For PKO Package Images:**
- ✅ Image exists and is pullable
- ✅ Contains `package/manifest.yaml`
- ✅ Manifest is valid `PackageManifest` kind
- ✅ Has proper PKO package structure

### Manual Validation

You can manually validate an image:

```bash
# Validate PKO package image
../common/validate-pko-image.sh \
  quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810

# Validate operator image
../common/validate-pko-image.sh \
  quay.io/openshift/configure-alertmanager-operator:v0.1.810 \
  operator
```

### Validation Failures

If validation fails, scripts will:
1. Show detailed error message
2. Explain what's missing/wrong
3. Exit before attempting deployment
4. Suggest fixing image or building locally

---

## Use Cases

### Testing Konflux CI Builds

Konflux builds images automatically on PR/push:

```bash
# 1. Find Konflux-built image from PR
# Check PR comments for image URLs

# 2. Set in user-config
OPERATOR_IMAGE=quay.io/redhat-user-workloads/.../configure-alertmanager-operator:sha-abc1234
PKO_IMAGE=quay.io/redhat-user-workloads/.../configure-alertmanager-operator-pko:sha-abc1234

# 3. Run tests
../common/phase3-prepare-cluster.sh
```

### Testing Released Versions

Test specific operator releases:

```bash
# Use production release
OPERATOR_IMAGE=quay.io/openshift/configure-alertmanager-operator:v0.1.810
PKO_IMAGE=quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810
```

### Using Nightly Builds

Test latest nightly builds:

```bash
# Use nightly tag
OPERATOR_IMAGE=quay.io/openshift/configure-alertmanager-operator:nightly
PKO_IMAGE=quay.io/openshift/configure-alertmanager-operator-pko:nightly
```

---

## Phase Behavior

### With Local Build (default)

```
Phase 1: Build images ← RUNS (builds from source)
Phase 2: Push images  ← RUNS (pushes to registry)
Phase 3: Prepare cluster
Phase 4: Choose migration mode
Phase 5: Deploy PKO
Phase 6: Monitor deployment
Phase 7: Functional test
```

### With Pre-Built Images

```
Phase 1: Build images ← SKIPPED (images provided)
Phase 2: Push images  ← SKIPPED (images exist)
Phase 3: Prepare cluster ← START HERE
Phase 4: Choose migration mode
Phase 5: Deploy PKO
Phase 6: Monitor deployment
Phase 7: Functional test
```

Scripts detect pre-built images and skip build/push automatically.

---

## Configuration Examples

### Minimal (Pre-Built Images Only)

```bash
# config/user-config

# Pre-built images
OPERATOR_IMAGE=quay.io/openshift/configure-alertmanager-operator:v0.1.810
PKO_IMAGE=quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810

# Cluster
CLUSTER_ID=my-test-cluster
CLUSTER_SERVER=https://api.my-cluster.example.com:6443

# Operator
OPERATOR_NAMESPACE=openshift-monitoring
```

**Note**: When using pre-built images, you don't need:
- `IMAGE_REGISTRY`
- `IMAGE_REPOSITORY`
- `IMAGE_TAG_BASE`
- `CAMO_REPO`

### Full (Build + Pre-Built Fallback)

```bash
# config/user-config

# Build settings (if images not provided)
IMAGE_REGISTRY=quay.io
IMAGE_REPOSITORY=myusername
IMAGE_TAG_BASE=test
CAMO_REPO=../configure-alertmanager-operator

# Pre-built images (optional - uncomment to use)
# OPERATOR_IMAGE=quay.io/openshift/configure-alertmanager-operator:v0.1.810
# PKO_IMAGE=quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810

# Cluster
CLUSTER_ID=my-test-cluster
CLUSTER_SERVER=https://api.my-cluster.example.com:6443

# Operator
OPERATOR_NAMESPACE=openshift-monitoring
```

**Behavior**: Builds locally unless pre-built images uncommented.

---

## Troubleshooting

### Image Pull Fails

**Error**: `Cannot pull image: quay.io/org/image:tag`

**Causes**:
- Image doesn't exist
- Wrong tag/version
- Missing registry credentials
- Private repository

**Fix**:
```bash
# Login to registry
podman login quay.io
# Or
docker login quay.io

# Verify image exists
podman pull quay.io/org/image:tag
```

### Not a Valid PKO Package

**Error**: `Not a valid PKO package (missing package/manifest.yaml)`

**Cause**: You provided an operator image instead of PKO package image

**Fix**: Make sure PKO image URL ends with `-pko`:
```bash
# Wrong (operator image)
PKO_IMAGE=quay.io/org/configure-alertmanager-operator:v1

# Correct (PKO package image)
PKO_IMAGE=quay.io/org/configure-alertmanager-operator-pko:v1
```

### Manifest Not Valid PackageManifest

**Error**: `manifest.yaml is not a PackageManifest`

**Cause**: Image contains `package/manifest.yaml` but it's not the right format

**Fix**: Rebuild PKO package image using `make pko-image` or use different image

---

## Best Practices

1. **Always validate images first**:
   ```bash
   ../common/validate-pko-image.sh $PKO_IMAGE
   ```

2. **Match versions**: Operator and PKO images should have same tag
   ```bash
   # Good
   OPERATOR_IMAGE=quay.io/org/camo:v0.1.810
   PKO_IMAGE=quay.io/org/camo-pko:v0.1.810

   # Bad (mismatched versions)
   OPERATOR_IMAGE=quay.io/org/camo:v0.1.810
   PKO_IMAGE=quay.io/org/camo-pko:v0.1.809
   ```

3. **Test locally first**: Validate images work before deploying
   ```bash
   podman run --rm $PKO_IMAGE ls /package
   # Should show manifest.yaml and other files
   ```

4. **Use specific tags**: Avoid `:latest` tag for reproducible tests
   ```bash
   # Good (specific version)
   PKO_IMAGE=quay.io/org/camo-pko:v0.1.810

   # Avoid (latest changes)
   PKO_IMAGE=quay.io/org/camo-pko:latest
   ```

---

## See Also

- [CONFIG-STRUCTURE.md](CONFIG-STRUCTURE.md) - Configuration file structure
- `common/validate-pko-image.sh` - Image validation script
- `common/load-config.sh` - Config loading logic
