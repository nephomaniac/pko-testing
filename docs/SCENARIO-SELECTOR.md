# Scenario Selector and OLM Deployment Utilities

This guide covers the new scenario-based testing workflow introduced to support multiple PKO testing paths including production-like OLM→PKO migrations.

## Overview

The PKO testing framework now supports **4 different testing scenarios** that adapt to your cluster state and testing goals:

1. **Fresh PKO Deployment** - Direct PKO deployment without OLM
2. **OLM→PKO Migration (Local Images)** - Full build + simulated OLM migration
3. **OLM→PKO Migration (Production Images)** - Production-like deployment using quay.io
4. **Cleanup Testing Only** - Test migration with existing OLM deployment

## New Utilities

### scenario-selector.sh

**Purpose:** Intelligently determines the testing scenario based on cluster state and user preferences.

**Location:** `common/scenario-selector.sh`

**Usage:**
```bash
cd /path/to/pko-testing/ome  # or camo, rmo
../common/scenario-selector.sh
```

**What it does:**
1. **Checks cluster state:**
   - Verifies cluster connectivity
   - Detects if Hive is paused or active
   - Identifies current operator deployment (OLM/PKO/manual/none)
   - Summarizes current state

2. **Presents scenario options:**
   - Lists all 4 scenarios with descriptions
   - Recommends best scenario based on current state
   - Provides default selection

3. **Configures workflow:**
   - Sets flags in `config/runtime-state` that control phase behavior
   - Determines which phases to skip
   - Identifies which OLM deployment method to use

4. **Optional cleanup:**
   - Offers to clean up existing PKO deployment if detected
   - Removes ClusterPackage and orphaned resources

5. **Provides next steps:**
   - Shows exact commands to run based on selected scenario
   - Lists phases in correct order

**Output:** Creates/updates `config/runtime-state` with scenario configuration

### deploy-olm-from-quay.sh

**Purpose:** Deploy operators via OLM using production images from quay.io registries.

**Location:** `common/deploy-olm-from-quay.sh`

**Usage:**
```bash
cd /path/to/pko-testing/ome  # or camo, rmo
../common/deploy-olm-from-quay.sh
```

**What it does:**
1. **Loads configuration:**
   - Reads `config/operator-config` for OLM template path
   - Reads `config/user-config` for cluster settings
   - Gets OLM image settings from operator-config or prompts user

2. **Processes OLM template:**
   - Extracts resources from SelectorSyncSet wrapper
   - Handles both Template and direct YAML formats
   - Uses Python (if available) or falls back to sed/awk

3. **Substitutes parameters:**
   - Replaces `${REGISTRY_IMG}`, `${IMAGE_DIGEST}`, `${CHANNEL}`, etc.
   - Handles both digest and tag-based images
   - Creates fully-resolved resource manifests

4. **Deploys to cluster:**
   - Applies Namespace, RBAC, CatalogSource, Subscription, OperatorGroup
   - Monitors CatalogSource readiness
   - Waits for CSV installation
   - Checks operator pod status

5. **Reports results:**
   - Shows deployed resources
   - Provides status check commands
   - Suggests next steps

**Prerequisites:**
- OLM template exists in operator repo (e.g., `hack/olm-registry/olm-artifacts-template.yaml`)
- Operator-config has `OLM_TEMPLATE_PATH` set
- Operator-config has `OLM_REGISTRY_IMAGE` and `OLM_CHANNEL` set (or will prompt)

## Configuration Files

### operator-config

New OLM-related fields:

```bash
# OLM Production Images (for deploy-olm-from-quay.sh)
OLM_REGISTRY_IMAGE="quay.io/app-sre/operator-registry@sha256:..."
OLM_OPERATOR_IMAGE="quay.io/app-sre/operator:v0.1.xxx"
OLM_CHANNEL="staging"
OLM_TEMPLATE_PATH="hack/olm-registry/olm-artifacts-template.yaml"
```

### runtime-state

New scenario configuration fields (set by scenario-selector.sh):

```bash
# Scenario Configuration
TESTING_SCENARIO=3
HIVE_PAUSED=yes
INITIAL_DEPLOYMENT_STATE=none
INITIAL_DEPLOYMENT_METHOD=none

# Workflow Flags
SKIP_BUILD_OPERATOR=true
SKIP_BUILD_PKO=false
SKIP_PUSH_IMAGES=true
SKIP_OLM_DEPLOYMENT=false
USE_PRODUCTION_OLM=true
USE_SIMULATED_OLM=false
CLEANUP_EXISTING_PKO=false
```

## Testing Scenarios in Detail

### Scenario 1: Fresh PKO Deployment

**When to use:**
- Testing PKO deployment only (no OLM migration)
- Quick deployment testing
- Verifying PKO package structure

**Workflow:**
```bash
# Select scenario
../common/scenario-selector.sh
# Choose: 1

# Build images
../common/phase1-build-images.sh

# Push images
../common/phase2-push-images.sh

# Deploy PKO
../common/phase5-deploy-pko.sh

# Monitor
../common/phase6-monitor-deployment.sh

# Test
../common/phase7-functional-test.sh
```

**Flags set:**
- `SKIP_OLM_DEPLOYMENT=true`

**Phases skipped:**
- OLM deployment
- Migration/cleanup phases

### Scenario 2: OLM→PKO Migration (Local Images)

**When to use:**
- Testing full migration with custom code changes
- Developing new operator features
- Testing both OLM and PKO with same codebase

**Workflow:**
```bash
# Select scenario
../common/scenario-selector.sh
# Choose: 2

# Build operator and PKO images
../common/phase1-build-images.sh

# Push to registry
../common/phase2-push-images.sh

# Deploy OLM (simulated)
../common/install-via-olm.sh

# Prepare migration
../common/phase4-prepare-migration.sh

# Deploy PKO with cleanup
../common/phase5-deploy-pko.sh

# Monitor
../common/phase6-monitor-deployment.sh

# Test
../common/phase7-functional-test.sh
```

**Flags set:**
- `USE_SIMULATED_OLM=true`

**Notes:**
- Uses `install-via-olm.sh` which creates mock OLM resources
- Tests migration logic but not production-like OLM deployment

### Scenario 3: OLM→PKO Migration (Production Images)

**When to use:**
- Testing production-like migrations
- Validating cleanup logic with real OLM deployments
- Testing PKO package against stable operator versions
- Reproducing production migration scenarios

**Workflow:**
```bash
# Select scenario
../common/scenario-selector.sh
# Choose: 3

# Deploy OLM from quay.io
../common/deploy-olm-from-quay.sh

# Build PKO package image only
../common/phase1-build-images.sh

# Push PKO image
../common/phase2-push-images.sh

# Prepare migration
../common/phase4-prepare-migration.sh

# Deploy PKO with cleanup
../common/phase5-deploy-pko.sh

# Monitor
../common/phase6-monitor-deployment.sh

# Test
../common/phase7-functional-test.sh
```

**Flags set:**
- `USE_PRODUCTION_OLM=true`
- `SKIP_BUILD_OPERATOR=true`
- `SKIP_PUSH_IMAGES=true` (only pushes PKO image)

**Notes:**
- Most production-like testing scenario
- Uses real OLM templates from operator repo
- Tests actual SelectorSyncSet resource extraction
- Validates parameter substitution logic

### Scenario 4: Test PKO Cleanup Only

**When to use:**
- OLM already deployed on cluster
- Testing migration/cleanup logic only
- Quick cleanup testing iterations

**Workflow:**
```bash
# Select scenario (OLM already deployed)
../common/scenario-selector.sh
# Choose: 4

# Build PKO package image only
../common/phase1-build-images.sh

# Push PKO image
../common/phase2-push-images.sh

# Prepare migration
../common/phase4-prepare-migration.sh

# Deploy PKO with cleanup
../common/phase5-deploy-pko.sh

# Monitor
../common/phase6-monitor-deployment.sh

# Test
../common/phase7-functional-test.sh
```

**Flags set:**
- `SKIP_BUILD_OPERATOR=true`
- `SKIP_OLM_DEPLOYMENT=true`

**Notes:**
- Assumes OLM is already deployed (manually or by previous test)
- Only builds PKO package
- Focuses on testing cleanup and migration phases

## Smart Defaults

The scenario selector provides intelligent defaults based on cluster state:

| Current State | Recommended Scenario | Reason |
|--------------|---------------------|---------|
| No deployment | Scenario 3 | Production-like testing is best default |
| OLM deployed | Scenario 4 | Test cleanup with existing OLM |
| PKO deployed | (prompts to cleanup) | Warns about existing PKO |
| Both OLM + PKO | (prompts to cleanup) | Detects conflict, offers cleanup |

## Phase Script Integration

Phase scripts automatically check `runtime-state` flags:

**phase1-build-images.sh:**
- Checks `SKIP_BUILD_OPERATOR` - skips operator build if true
- Checks `SKIP_BUILD_PKO` - skips PKO build if true

**phase2-push-images.sh:**
- Checks `SKIP_PUSH_IMAGES` - exits early if true
- Only pushes images that were built in phase1

**phase3-prepare-cluster.sh:**
- Checks `USE_PRODUCTION_OLM` - runs deploy-olm-from-quay.sh if true
- Checks `USE_SIMULATED_OLM` - runs install-via-olm.sh if true
- Checks `SKIP_OLM_DEPLOYMENT` - skips OLM entirely if true

**phase4-prepare-migration.sh:**
- Always runs (prepares PKO migration resources)

**phase5-deploy-pko.sh:**
- Deploys ClusterPackage
- Cleanup job runs based on cluster state

## Example: OME Production Migration Test

```bash
# Login to test cluster
oc login --server=https://api.cluster.example.com:6443 --username=cluster-admin

# Navigate to OME testing directory
cd /Users/maclark/sandbox/pko-testing/ome

# Ensure configuration is ready
cat config/operator-config
# Verify OLM_REGISTRY_IMAGE and OLM_TEMPLATE_PATH are set

cat config/user-config
# Verify IMAGE_REGISTRY, IMAGE_REPOSITORY, CLUSTER_* are set

# Run scenario selector
../common/scenario-selector.sh

# It detects:
# ✓ Connected to cluster
# ✓ Hive is PAUSED
# ✗ No operator deployed
# 💡 Recommends: Scenario 3

# Select scenario 3
# Enter: 3

# It configures:
# SKIP_BUILD_OPERATOR=true
# USE_PRODUCTION_OLM=true
# Tells you to run deploy-olm-from-quay.sh next

# Follow the suggested steps:

# 1. Deploy OLM from quay.io
../common/deploy-olm-from-quay.sh
# Uses: quay.io/app-sre/osd-metrics-exporter-registry@sha256:...
# Deploys: CatalogSource, Subscription, OperatorGroup, RBAC
# Result: ✓ osd-metrics-exporter.v0.1.483-gf3edcbc (Succeeded)

# 2. Build PKO package image
../common/phase1-build-images.sh
# Skips operator build (uses quay.io version)
# Builds: osd-metrics-exporter-pko:test-abc1234

# 3. Push PKO image
../common/phase2-push-images.sh
# Pushes: quay.io/maclark/osd-metrics-exporter-pko:test-abc1234

# 4. Prepare migration
../common/phase4-prepare-migration.sh
# Creates PKO cleanup job
# Prepares ClusterPackage with cleanup config

# 5. Deploy PKO with migration
../common/phase5-deploy-pko.sh
# Deploys ClusterPackage
# Cleanup job removes OLM resources
# PKO adopts operator resources

# 6. Monitor deployment
../common/phase6-monitor-deployment.sh
# Watches ClusterPackage status
# Verifies operator pod health
# Checks cleanup job completion

# 7. Run functional tests
../common/phase7-functional-test.sh
# Verifies operator functionality
# Checks metrics/alerts
# Validates RBAC

# Success! OLM→PKO migration complete with production images
```

## Troubleshooting

### Scenario selector fails with "Not connected to cluster"

**Solution:**
```bash
oc login --server=$CLUSTER_SERVER --username=$CLUSTER_USER
```

### deploy-olm-from-quay.sh fails with "OLM template not found"

**Solution:**
Check `config/operator-config`:
```bash
OLM_TEMPLATE_PATH="hack/olm-registry/olm-artifacts-template.yaml"
```

Verify file exists:
```bash
ls -la $OME_REPO/hack/olm-registry/olm-artifacts-template.yaml
```

### deploy-olm-from-quay.sh fails parameter substitution

**Solution:**
Verify `config/operator-config` has all required fields:
```bash
OLM_REGISTRY_IMAGE="quay.io/app-sre/operator-registry@sha256:..."
OLM_CHANNEL="staging"
```

Check if registry image includes digest (`@sha256:...`)

### Phase scripts ignore scenario flags

**Solution:**
Verify `config/runtime-state` exists and has correct flags:
```bash
cat config/runtime-state
```

Re-run scenario-selector.sh to regenerate configuration.

### OLM deployment succeeds but CSV stays in "Installing" phase

**Possible causes:**
1. CatalogSource image is invalid
2. Operator image pull fails
3. RBAC issues

**Debug:**
```bash
oc get catalogsource -n $OPERATOR_NAMESPACE
oc describe catalogsource $CATALOGSOURCE_NAME -n $OPERATOR_NAMESPACE
oc logs -n $OPERATOR_NAMESPACE -l name=$OPERATOR_NAME
oc get events -n $OPERATOR_NAMESPACE --sort-by='.lastTimestamp'
```

## Best Practices

1. **Always run scenario-selector.sh first**
   - It sets up the correct workflow flags
   - Prevents accidental phase execution in wrong order

2. **Check Hive status before testing**
   - Pause Hive to prevent reconciliation interference
   - Scenario selector detects and warns about active Hive

3. **Use Scenario 3 for production validation**
   - Most closely matches production deployments
   - Tests real OLM template processing
   - Validates actual migration path

4. **Use Scenario 2 for development**
   - Test code changes before pushing to quay.io
   - Faster iteration (no waiting for image builds)

5. **Clean up between test runs**
   - Delete PKO ClusterPackage before re-testing
   - Remove OLM resources if re-deploying
   - Scenario selector can help with cleanup

6. **Review runtime-state before each phase**
   - Understand which flags are set
   - Verify scenario configuration matches intent

## See Also

- [GETTING-STARTED.md](GETTING-STARTED.md) - Initial setup and configuration
- [PKO-MIGRATION-MODES.md](PKO-MIGRATION-MODES.md) - Details on cleanup modes
- [USING-PREBUILT-IMAGES.md](USING-PREBUILT-IMAGES.md) - Working with pre-built images
- [CONFIG-STRUCTURE.md](CONFIG-STRUCTURE.md) - Configuration file reference
