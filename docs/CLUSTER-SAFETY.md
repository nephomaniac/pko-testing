# Cluster Connection Safety Features

This document explains the strict cluster validation safety features that prevent accidental operations on the wrong cluster.

## Overview

All PKO testing scripts now include **mandatory cluster validation** that:
- ✅ **CANNOT be bypassed** - exits immediately if cluster mismatch detected
- ✅ **Uses authoritative OCM data** when available
- ✅ **Supports multiple identifiers** - name, external_id, or UUID
- ✅ **Validates before ANY operations** - no auto-accept, no warnings
- ✅ **Prevents AI/script auto-acceptance** - hard fail on mismatch

## How It Works

### 1. OCM Integration (Recommended)

When `ocm` CLI is available and you're logged in:

```bash
# Validation fetches authoritative cluster data from OCM
fetch_cluster_from_ocm "maclarkrosa0323"
# Returns:
#   UUID: 6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
#   Name: maclarkrosa0323
#   External ID: maclarkrosa0323-8vwbd
#   API URL: https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443
```

**Benefits:**
- **Authoritative data** - OCM is source of truth
- **Multiple identifiers** - can match by any of: UUID, name, external_id
- **Cached** - stored in `config/runtime-state` for reuse
- **Flexible** - config can use any identifier, validation handles all

### 2. Basic Validation (Fallback)

When OCM is not available:

```bash
# Compares configured cluster info against current oc connection
# Checks:
#   - Cluster UUID (from clusterversion.spec.clusterID)
#   - Cluster name (from infrastructure.status.infrastructureName)
#   - Server URL (from oc config)
```

**Still safe:**
- Server URL match is required
- Cluster name or UUID can provide additional validation
- Hard fail if mismatches detected

## Configuration Flexibility

Your `config/user-config` can specify the cluster using **any** of these identifiers:

```bash
# Option 1: Cluster name (human-readable)
CLUSTER_ID=maclarkrosa0323

# Option 2: External ID (ROSA format)
CLUSTER_ID=maclarkrosa0323-8vwbd

# Option 3: UUID (OpenShift cluster ID)
CLUSTER_ID=6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
```

**Validation handles all formats:**
- Tries to match against OCM data (if available)
- Falls back to direct comparison if no OCM
- Server URL provides additional verification

## Validation Flow

```
1. Script starts
   ↓
2. Load config (CLUSTER_ID, CLUSTER_SERVER)
   ↓
3. Fetch cluster from OCM (if available)
   - Search by name, external_id, or UUID
   - Cache result in config/runtime-state
   ↓
4. Get current oc connection info
   - Current cluster UUID
   - Current cluster name
   - Current server URL
   ↓
5. Validation logic:
   
   If OCM data available:
     ✓ Match UUID? → PASS
     ✓ Match external_id? → PASS
     ✓ Match API URL? → PASS
     ✗ No matches? → FAIL (exit 1)
   
   If no OCM data:
     ✓ Match cluster name/UUID? → PASS
     ✓ Match server URL? → PASS
     ✗ Mismatches detected? → FAIL (exit 1)
   ↓
6. Continue with operations (only if validated)
```

## Error Examples

### Example 1: Wrong Cluster

```
❌ CLUSTER VALIDATION FAILED!

You are connected to the WRONG cluster!

Current cluster connection:
  UUID: aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb
  Name: wrong-cluster
  Server: https://api.wrong-cluster.example.com:6443

Expected cluster (from OCM):
  UUID: 6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
  Name: maclarkrosa0323
  External ID: maclarkrosa0323-8vwbd
  Server: https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443

What to do:
1. Logout from current cluster:
   oc logout

2. Login to the correct cluster:
   oc login --server=https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443 --username=cluster-admin

3. Re-run this script: scenario-selector.sh
```

**Result:** Script exits immediately. NO operations are performed.

### Example 2: Not Connected

```
❌ ERROR: Not connected to any cluster!

You must be logged in to a cluster to run this script.

Expected cluster: maclarkrosa0323
Expected server: https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443

OCM Details:
  Name: maclarkrosa0323
  External ID: maclarkrosa0323-8vwbd
  ID: 6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
  API URL: https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443

Please login:
  oc login --server=https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443 --username=cluster-admin
```

**Result:** Script exits immediately. User must login first.

## Scripts with Mandatory Validation

These scripts ALL validate cluster before proceeding:

- `scenario-selector.sh` - Initial scenario setup
- `phase1-build-images.sh` - Building images
- `phase2-push-images.sh` - Pushing images
- `phase3-prepare-cluster.sh` - Cluster preparation
- `phase4-prepare-migration.sh` - Migration prep
- `phase5-deploy-pko.sh` - PKO deployment
- `deploy-olm-from-quay.sh` - OLM deployment

**No exceptions.** Every script validates before running.

## OCM Setup (Recommended)

To enable OCM-based validation:

### 1. Install OCM CLI

```bash
# macOS
brew install ocm

# Or download from:
# https://github.com/openshift-online/ocm-cli/releases
```

### 2. Login to OCM

```bash
# Get token from: https://console.redhat.com/openshift/token
ocm login --token=YOUR_TOKEN

# Verify login
ocm whoami
```

### 3. Test OCM Integration

```bash
cd ~/sandbox/pko-testing/ome
../common/fetch-cluster-from-ocm.sh maclarkrosa0323
```

**Output:**
```
✓ Cluster found in OCM:
  ID: 6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
  Name: maclarkrosa0323
  External ID: maclarkrosa0323-8vwbd
  API URL: https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443
  State: ready
  Region: us-east-1
  Product: rosa

✓ Cached to: config/runtime-state
```

## OCM Cache

OCM data is cached in `config/runtime-state`:

```bash
# OCM Cluster Cache
# Fetched from OCM at 2026-03-25T03:45:00Z
OCM_CLUSTER_ID="6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f"
OCM_CLUSTER_NAME="maclarkrosa0323"
OCM_CLUSTER_EXTERNAL_ID="maclarkrosa0323-8vwbd"
OCM_CLUSTER_API_URL="https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443"
OCM_CLUSTER_STATE="ready"
OCM_CLUSTER_REGION="us-east-1"
OCM_CLUSTER_PRODUCT="rosa"
OCM_CACHE_TIMESTAMP=1711334700
# End OCM Cluster Cache
```

**Cache benefits:**
- Faster validation (no API call every time)
- Works offline after initial fetch
- Updated when scenario-selector runs

## Why This Matters

### Problem Prevented

Without strict validation:
```bash
# User thinks they're on cluster A
# Actually on cluster B
../common/phase5-deploy-pko.sh

# ❌ Deploys PKO to WRONG cluster
# ❌ Could delete OLM resources on wrong cluster
# ❌ Could disrupt production services
```

### Solution Implemented

With strict validation:
```bash
# User on wrong cluster
../common/phase5-deploy-pko.sh

# ❌ CLUSTER VALIDATION FAILED!
# Script exits immediately
# NO operations performed
# User must switch to correct cluster
```

## AI/Script Safety

The validation **cannot be bypassed by AI or automated scripts** because:

1. **No auto-accept mechanism** - Hard exit on mismatch
2. **No warning prompts** - Exits before any user input
3. **No override flags** - Cannot be disabled
4. **Runs before operations** - Validation is first step
5. **Exit code 1** - Kills script execution immediately

**Example - AI cannot proceed:**
```bash
# AI/script tries to run scenario selector on wrong cluster
../common/scenario-selector.sh

# Exit code: 1 (failure)
# No prompts, no warnings, just immediate exit
# AI/script execution halts
```

## Best Practices

### 1. Always Use OCM When Available

```bash
# Install OCM CLI
brew install ocm

# Login
ocm login --token=YOUR_TOKEN

# Validation will be more robust
```

### 2. Use Cluster Name in Config

```bash
# Easier to read and remember
CLUSTER_ID=maclarkrosa0323

# Not:
CLUSTER_ID=6e1a2ea8-c502-4ac1-b188-58dd1d27ca6f
```

OCM validation handles the mapping to UUID automatically.

### 3. Verify Connection Before Starting

```bash
# Check where you are
oc whoami
oc cluster-info

# Run scenario selector (validates automatically)
../common/scenario-selector.sh
```

### 4. Update Config If Needed

If validation fails but you're certain you're on the right cluster:

```bash
# Check current connection
oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'
# Output: maclarkrosa0323-8vwbd

# Update config/user-config
CLUSTER_ID=maclarkrosa0323-8vwbd
CLUSTER_SERVER=https://api.maclarkrosa0323.ggrv.s1.devshift.org:6443
```

## Troubleshooting

### Validation fails but I'm on the right cluster

**Check:**
1. Is `CLUSTER_ID` in config correct?
2. Does it match cluster name, external_id, or UUID?
3. Is server URL exactly correct?

**Fix:**
```bash
# Get current values
oc config view --minify -o jsonpath='{.clusters[0].cluster.server}'
oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'

# Update config/user-config with correct values
```

### OCM not finding cluster

**Possible causes:**
1. Not logged in to OCM: `ocm login --token=YOUR_TOKEN`
2. Cluster not in OCM (test cluster, non-managed cluster)
3. Using wrong identifier (try cluster UUID instead)

**Result:** Falls back to basic validation (still safe)

### Want to skip validation (DANGEROUS)

**Answer:** You can't. This is intentional.

The validation exists to prevent destructive operations on wrong clusters. There is no bypass mechanism.

If you absolutely must disable it, edit the script source code - but you do so at your own risk.

## See Also

- [SCENARIO-SELECTOR.md](SCENARIO-SELECTOR.md) - Scenario workflows
- [AI-ASSISTANT-GUIDE.md](AI-ASSISTANT-GUIDE.md) - AI assistance guide
- [GETTING-STARTED.md](GETTING-STARTED.md) - Initial setup
