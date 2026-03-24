# Configuration Structure

## Overview

PKO testing uses two separate configuration files:
1. **`user-config`** - User-provided settings (tracked in git as `.example`)
2. **`runtime-state`** - Script-generated values (not tracked in git)

## File: `user-config`

**Purpose**: User-provided settings that rarely change

**Location**: `<operator>/config/user-config`

**Created from**: `cp config/user-config.example config/user-config`

**Contains**:
- Container registry settings (quay.io username)
- Image tag base (scripts append git commit SHA)
- Cluster information (name, API URL)
- Operator settings (namespace, repository path)

**Example**:
```bash
# Container Registry
IMAGE_REGISTRY=quay.io
IMAGE_REPOSITORY=myusername

# Image Tagging
IMAGE_TAG_BASE=test  # Scripts append git SHA: test-abc1234

# Cluster
CLUSTER_ID=my-test-cluster
CLUSTER_SERVER=https://api.my-cluster.example.com:6443

# Operator
OPERATOR_NAMESPACE=openshift-monitoring
CAMO_REPO=../configure-alertmanager-operator
```

**Git tracking**: `.example` file tracked, actual file gitignored

---

## File: `runtime-state`

**Purpose**: Script-generated values from test execution

**Location**: `<operator>/config/runtime-state`

**Created by**: Scripts automatically generate this file

**Updated by**: Each phase script updates relevant sections

**Contains**:

### Test Execution Tracking
- `LAST_RUN_PHASE` - Which phase ran last
- `LAST_RUN_TIMESTAMP` - When it ran
- `LAST_RUN_STATUS` - success/failed
- `LAST_RUN_LOG` - Path to log file

### Image Information (phase1)
- `IMAGE_NAME` - Operator image name
- `IMAGE_TAG_BASE` - User-provided base tag
- `GIT_COMMIT_SHORT` - Git short SHA (abc1234)
- `GIT_COMMIT_LONG` - Git full SHA
- `IMAGE_TAG` - Computed tag (test-abc1234)
- `OPERATOR_IMAGE` - Full operator image URI
- `PKO_IMAGE` - Full PKO package image URI
- `BUILD_TIMESTAMP` - When images were built

### Cluster Information (phase3)
- `CLUSTER_NAME` - Cluster display name
- `CLUSTER_ID` - Cluster identifier
- `CLUSTER_UUID` - Unique cluster UUID
- `CLUSTER_VERSION` - OpenShift version
- `CLUSTER_PLATFORM` - AWS/GCP/Azure/etc
- `CLUSTER_REGION` - Cloud region
- `CLUSTER_INFRA_NAME` - Infrastructure name
- `BACKUP_TIMESTAMP` - When backup was taken
- `BACKUP_DIR` - Path to backup directory

### Migration Configuration (phase4)
- `MIGRATION_MODE` - 1 (PKO cleanup) or 2 (manual)
- `OLM_CLEANUP_METHOD` - pko-managed/manual

### Deployment Information (phase5)
- `DEPLOY_START_TIME` - Unix timestamp of deployment
- `CLUSTERPACKAGE_NAME` - Name of ClusterPackage
- `CLUSTERPACKAGE_MANIFEST` - Path to manifest file

### Validation Results (phase6)
- `DEPLOYMENT_STATUS` - PKO deployment status
- `OLM_CLEANUP_VALIDATED` - true/false
- `PKO_RESOURCES_VALIDATED` - true/false
- `VALIDATION_TIMESTAMP` - When validation completed

**Git tracking**: NOT tracked (in .gitignore)

---

## Image Tagging Strategy

Images are automatically tagged with git commit SHA:

```bash
# User provides base tag in user-config
IMAGE_TAG_BASE=test

# Scripts detect git commit
GIT_COMMIT_SHORT=$(git rev-parse --short=7 HEAD)  # abc1234

# Scripts compute full tag
IMAGE_TAG="${IMAGE_TAG_BASE}-${GIT_COMMIT_SHORT}"  # test-abc1234

# Scripts build full image URIs
OPERATOR_IMAGE="${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
PKO_IMAGE="${OPERATOR_IMAGE}-pko"
```

**Benefits**:
- Reproducible builds (tag matches exact commit)
- Easy to identify which code version is deployed
- Automatic - no manual tag updates needed

---

## Usage in Scripts

### Loading Configuration

Every phase script should load config at the start:

```bash
#!/bin/bash
set -e

PHASE_NUM=1
OPERATOR_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config functions
source "$SCRIPT_DIR/load-config.sh"

# Load user config and runtime state
load_config "$OPERATOR_DIR"

# Now all variables are available
echo "Building $OPERATOR_IMAGE with tag $IMAGE_TAG"
```

### Saving Runtime State

After generating values, save them:

```bash
# Set variables
IMAGE_NAME=configure-alertmanager-operator
GIT_COMMIT_SHORT=$(git rev-parse --short=7 HEAD)
GIT_COMMIT_LONG=$(git rev-parse HEAD)
IMAGE_TAG="${IMAGE_TAG_BASE}-${GIT_COMMIT_SHORT}"
OPERATOR_IMAGE="${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
PKO_IMAGE="${OPERATOR_IMAGE}-pko"
BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Save to runtime-state
save_runtime_state "$OPERATOR_DIR" "phase1-build-images" "success"
```

### Capturing Cluster Info

Phase 3 should capture cluster details:

```bash
# Get cluster information
CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
CLUSTER_UUID=$(oc get clusterversion -o jsonpath='{.spec.clusterID}')
CLUSTER_VERSION=$(oc get clusterversion -o jsonpath='{.status.desired.version}')
CLUSTER_PLATFORM=$(oc get infrastructure cluster -o jsonpath='{.status.platform}')
CLUSTER_REGION=$(oc get infrastructure cluster -o jsonpath='{.status.platformStatus.aws.region}')

# Save to runtime-state
save_runtime_state "$OPERATOR_DIR" "phase3-prepare-cluster" "success"
```

---

## Migration from Legacy Config

Old single-file config (`pko-test-config`) is still supported:

```bash
# If user-config doesn't exist, load-config.sh falls back to legacy file
if [ -f pko-test-config ]; then
    source pko-test-config  # Still works
    echo "⚠️  Consider migrating to user-config + runtime-state"
fi
```

**To migrate**:
1. Split `pko-test-config` into user settings and runtime values
2. Create `user-config` with user settings
3. Let scripts generate `runtime-state`
4. Delete old `pko-test-config`

---

## Benefits of Two-File Approach

### user-config
- ✅ User edits once
- ✅ No script-generated clutter
- ✅ Easy to version control (as .example)
- ✅ Clear what user must provide

### runtime-state
- ✅ Always up-to-date with last run
- ✅ Captures full test context
- ✅ Resumable (know where you left off)
- ✅ Debugging (exact images, timestamps)
- ✅ Never committed (prevents stale data)

---

## Example Files

See:
- `camo/config/user-config.example` - User settings template
- `camo/config/runtime-state.example` - Generated values example
- `common/load-config.sh` - Config loading functions
