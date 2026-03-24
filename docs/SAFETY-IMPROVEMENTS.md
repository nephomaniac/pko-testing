# Safety Improvements Summary

## Changes Made (2026-03-23)

### Problem
Phase 3 script accidentally ran on Hive management cluster instead of target test cluster, causing resource deletion on the wrong cluster.

### Root Cause
1. Script paused for manual Hive operations, allowing cluster context switch
2. No verification after the pause before continuing destructive operations
3. No confirmation before executing delete/apply commands

---

## Solution 1: Enhanced Cluster Verification

### Multi-Level Cluster Identity Verification

**Created:** `cluster-verification.sh` - Shared verification functions

**Three-layer verification:**
1. **Cluster UUID** - Unique identifier from `oc get clusterversion`
2. **Server URL** - API endpoint (unique per cluster)
3. **Infrastructure name** - Additional safety check

**Stored in config file:**
```bash
CLUSTER_ID=YOUR_CLUSTER_NAME              # User-provided name
CLUSTER_UUID=12345678-90ab-...          # Global unique ID
CLUSTER_SERVER=https://api...           # API endpoint
CLUSTER_USER=backplane-cluster-admin    # For reference
```

### Verification Points Added

All phases now verify cluster connection:

- **Phase 1** - Optional early setup if logged into cluster
- **Phase 3** - Mandatory verification, saves cluster UUID/ID
- **Phase 3 (after Hive pause)** - ⚠️ CRITICAL re-verification
- **Phase 4, 5, 6, 7, 8** - Start of each phase
- **Phase 8 (after Hive restore)** - ⚠️ CRITICAL re-verification

### Error Message Example

If cluster mismatch detected:
```
❌ CLUSTER MISMATCH ERROR!

Expected cluster:
  ID: YOUR_CLUSTER_NAME
  UUID: abc123-def456-...
  Server: https://api.test-cluster.com:6443

Current cluster:
  UUID: xyz789-ghi012-...
  Server: https://api.hive-cluster.com:6443

Context: After Hive pause - returning to target cluster

You are connected to the WRONG cluster!

Please login to the correct test cluster:
  ocm backplane login YOUR_CLUSTER_NAME
```

---

## Solution 2: Operation Confirmation

### Pre-Execution Confirmation

**Created:** `confirm_operation()` function in `cluster-verification.sh`

Before every destructive operation (delete/apply), shows:
1. Operation type
2. Target cluster (name, ID, server)
3. Exact oc commands to be executed
4. Confirmation prompt (requires "yes")

### Confirmation Example

```
╔════════════════════════════════════════════════════════════════╗
║                    ⚠️  CONFIRMATION REQUIRED                    ║
╚════════════════════════════════════════════════════════════════╝

Operation Type: DELETE OLM RESOURCES

Target Cluster:
  Name: YOUR_CLUSTER_NAME
  ID: YOUR_CLUSTER_NAME
  Server: https://api.YOUR_CLUSTER_NAME.abc1.s1.openshiftapps.com:6443

Commands to execute:
  → oc delete subscription configure-alertmanager-operator -n openshift-monitoring
  → oc delete csv configure-alertmanager-operator.v1.2.3 -n openshift-monitoring
  → oc delete catalogsource configure-alertmanager-operator-registry -n openshift-monitoring

════════════════════════════════════════════════════════════════

Execute these commands on cluster 'YOUR_CLUSTER_NAME'? (yes/no):
```

### Operations Protected

**Phase 4 - Remove OLM:**
- Scale down deployment (before scaling)
- Delete OLM resources (before deleting subscription, CSV, catalogsource)

**Phase 5 - Deploy PKO:**
- Apply ClusterPackage (before oc apply)

**Phase 8 - Cleanup:**
- Delete ClusterPackage (before oc delete)
- Manual deployment deletion (before oc delete)

---

## Enhanced Configuration File

**Location:** `.camo-pko-test-config`

**Before:**
```bash
IMAGE_REGISTRY=quay.io
IMAGE_REPOSITORY=YOUR_USERNAME
...
```

**After:**
```bash
# CAMO PKO Testing Configuration
# Generated: Sun Mar 23 15:30:00 PDT 2026

# Image Configuration
QUAY_USERNAME=YOUR_USERNAME
IMAGE_REGISTRY=quay.io
IMAGE_REPOSITORY=YOUR_USERNAME
IMAGE_NAME=configure-alertmanager-operator
IMAGE_TAG=test-afae58f
OPERATOR_IMAGE=quay.io/YOUR_QUAY_USERNAME/configure-alertmanager-operator:test-afae58f
PKO_IMAGE=quay.io/YOUR_QUAY_USERNAME/configure-alertmanager-operator-pko:test-afae58f

# Cluster Verification
CLUSTER_ID=YOUR_CLUSTER_NAME
CLUSTER_SERVER=https://api.YOUR_CLUSTER_NAME.abc1.s1.openshiftapps.com:6443
CLUSTER_USER=backplane-cluster-admin
CLUSTER_UUID=12345678-90ab-cdef-1234-567890abcdef
```

---

## Files Modified

### Created
- `cluster-verification.sh` - Shared verification and confirmation functions
- `CLUSTER-VERIFICATION.md` - Documentation
- `SAFETY-IMPROVEMENTS.md` - This file

### Updated
- `phase1-build-images.sh` - Added cluster info capture
- `phase3-prepare-cluster.sh` - Added verification at start and after Hive pause
- `phase4-remove-olm.sh` - Added verification and confirmations
- `phase5-deploy-pko.sh` - Added verification and confirmation
- `phase6-monitor-deployment.sh` - Added verification
- `phase7-functional-test.sh` - Added verification
- `phase8-cleanup.sh` - Added verification and confirmations (including after Hive restore)

---

## How It Prevents the Original Issue

**Original Issue:** Phase 3 ran on Hive cluster after Hive pause

**Prevention Layers:**

1. **Cluster UUID saved in Phase 3**
   - When user enters cluster ID, saves UUID from `oc get clusterversion`

2. **Re-verification after Hive pause**
   - Before continuing, verifies cluster UUID matches saved value
   - Clear warning: "CRITICAL: Verify you are connected to the TARGET test cluster"

3. **Operation confirmation**
   - Even if verification passes, shows cluster name before each delete/apply
   - User sees exactly which cluster commands will run on

4. **Explicit "yes" required**
   - Must type "yes" (not just "y") to proceed with destructive operations

**Result:** If user switches to Hive cluster during pause, verification fails with clear error before any commands execute.

---

## Testing Recommendations

### Test Cluster Mismatch Detection

1. Run phase 3 on correct cluster (saves cluster UUID)
2. Login to different cluster: `ocm backplane login other-cluster`
3. Try to continue to phase 4
4. **Expected:** Script exits with cluster mismatch error
5. Login back to correct cluster: `ocm backplane login YOUR_CLUSTER_NAME`
6. Phase 4 should proceed

### Test Operation Confirmation

1. Run phase 4 on test cluster
2. Observe confirmation prompts before scale/delete operations
3. Review cluster name, ID, and commands
4. Type "yes" to proceed or anything else to cancel

---

## Additional Safety Features

### Backup Before Changes
Phase 3 creates backup before any modifications:
- Location: `backup-YYYYMMDD-HHMMSS/`
- Contains: CSV, Subscription, CatalogSource, Deployment YAML

### Restoration Procedure
If wrong cluster was modified:
1. Stop immediately
2. Check backup directory
3. Apply backup resources: `oc apply -f backup-YYYYMMDD-HHMMSS/subscription.yaml`
4. Login to correct cluster
5. Resume from current phase

---

## Questions?

See `CLUSTER-VERIFICATION.md` for detailed explanation of the verification system.
