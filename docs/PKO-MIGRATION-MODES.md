# CAMO PKO Migration: Two-Mode Testing Framework

## Overview

The PKO migration testing scripts now support **two deployment modes** to validate different migration scenarios. Both modes include comprehensive logging and validation.

---

## Mode 1: PKO-Managed Cleanup (RECOMMENDED)

### Description
Deploy ClusterPackage with OLM resources still present. PKO's cleanup phases automatically remove OLM artifacts before deploying the operator.

### When to Use
- **Primary testing scenario** - validates the complete PKO migration process
- Tests that PKO cleanup phases work correctly
- Simulates real-world migration where OLM is still running
- Required for validating cleanup phase ordering (cleanup-rbac, cleanup-deploy before rbac, deploy)

### How It Works
1. OLM resources (Subscription, CSV, CatalogSource) remain on cluster
2. Deploy ClusterPackage
3. PKO runs cleanup phases FIRST:
   - `cleanup-rbac` phase: Removes old RBAC resources (if needed)
   - `cleanup-deploy` phase: Removes OLM Subscription, CSV, CatalogSource
4. PKO then runs deployment phases:
   - `crds` phase: Update/create CRDs
   - `namespace` phase: Ensure namespace exists
   - `rbac` phase: Deploy new RBAC resources
   - `deploy` phase: Deploy operator

### Validation Checks
- ✅ Verify Subscription was removed by PKO
- ✅ Verify CSV was removed by PKO
- ✅ Verify CatalogSource was removed by PKO
- ✅ Verify operator deployed successfully
- ✅ Verify all PKO-managed resources exist

### Expected Outcome
PKO cleanup phases successfully remove all OLM resources before deploying the operator.

---

## Mode 2: Manual Cleanup

### Description
Manually delete OLM resources before deploying ClusterPackage. PKO deploys into a clean state without running cleanup phases.

### When to Use
- Faster deployment (no cleanup phase wait time)
- When you want to isolate PKO deployment from cleanup testing
- When OLM resources are already corrupted/problematic
- For baseline comparison against Mode 1

### How It Works
1. Manually delete OLM resources (Subscription, CSV, CatalogSource)
2. Deploy ClusterPackage
3. PKO runs deployment phases only:
   - `crds` phase: Update/create CRDs
   - `namespace` phase: Ensure namespace exists
   - `rbac` phase: Deploy RBAC resources
   - `deploy` phase: Deploy operator
4. Cleanup phases may still be defined but have nothing to clean up

### Validation Checks
- ✅ Verify OLM resources remain absent
- ✅ Verify operator deployed successfully
- ✅ Verify all PKO-managed resources exist
- ⚠️  Warning if OLM resources reappear (indicates Hive sync is active)

### Expected Outcome
PKO deploys successfully into clean state without OLM interference.

---

## Updated Phase Flow

### Phase 4: Prepare for Migration (phase4-prepare-migration.sh)
**New behavior:**
1. Check current OLM resource state
2. Ask user to choose Mode 1 or Mode 2
3. If Mode 1: Skip to Phase 5 (leave OLM intact)
4. If Mode 2: Delete OLM resources, verify cleanup

**Saves to config:**
- `MIGRATION_MODE=1` or `MIGRATION_MODE=2`
- `OLM_CLEANUP_METHOD=pko-managed` or `manual`

### Phase 5: Deploy PKO (phase5-deploy-pko.sh)
**New behavior:**
1. Check MIGRATION_MODE from config
2. Verify pre-deployment state matches expected mode
3. Create ClusterPackage with proper config
4. Apply ClusterPackage
5. Record deployment start time

**Mode-aware messaging:**
- Mode 1: Explains PKO will run cleanup phases
- Mode 2: Explains PKO deploys into clean state

### Phase 6: Monitor Deployment (phase6-monitor-deployment.sh)
**New behavior:**
1. Monitor ClusterPackage deployment progress
2. **Mode-specific validation:**
   - Mode 1: Verify PKO cleanup removed OLM resources
   - Mode 2: Verify OLM resources remain absent
3. Validate PKO-deployed resources
4. Check ClusterPackage status

**Validation differences:**
- Mode 1: **FAIL** if OLM resources still exist (cleanup didn't work)
- Mode 2: **WARNING** if OLM resources reappear (Hive sync issue)

---

## Logging

All phases now write detailed logs to `logs/phase${N}-YYYYMMDD-HHMMSS.log`

**Log contents:**
- Timestamps (start, end, each step)
- All command output (stdout + stderr)
- Validation results
- User confirmations
- Error messages
- Cluster state snapshots

**Log location:** `/path/to/pko-testing/logs/`

**Example logs:**
```
logs/phase4-20260323-153000.log  # Migration mode selection
logs/phase5-20260323-153200.log  # ClusterPackage deployment
logs/phase6-20260323-153400.log  # Deployment monitoring and validation
```

**Log benefits:**
- Review what happened without re-running
- Debug issues by examining exact command output
- Share logs with team for analysis
- Build context for Claude when troubleshooting

---

## Usage Examples

### Mode 1: Full Migration Test (Recommended)

```bash
# Phase 3: Prepare cluster (backup, pause Hive)
./phase3-prepare-cluster.sh

# Phase 4: Choose migration mode
./phase4-prepare-migration.sh
# Select: 1 (PKO-managed cleanup)
# OLM resources left intact

# Phase 5: Deploy PKO
./phase5-deploy-pko.sh
# Deploys ClusterPackage with OLM still present

# Phase 6: Monitor and validate
./phase6-monitor-deployment.sh
# Watches PKO cleanup OLM resources
# Validates cleanup succeeded
# Validates operator deployed

# Phase 7: Functional test
./phase7-functional-test.sh
```

### Mode 2: Clean Deployment

```bash
# Phase 3: Prepare cluster
./phase3-prepare-cluster.sh

# Phase 4: Choose migration mode
./phase4-prepare-migration.sh
# Select: 2 (Manual cleanup)
# Script deletes OLM resources

# Phase 5: Deploy PKO
./phase5-deploy-pko.sh
# Deploys ClusterPackage into clean state

# Phase 6: Monitor and validate
./phase6-monitor-deployment.sh
# Validates operator deployed
# Checks OLM resources stay gone

# Phase 7: Functional test
./phase7-functional-test.sh
```

---

## Comparison Matrix

| Aspect | Mode 1 (PKO Cleanup) | Mode 2 (Manual) |
|--------|---------------------|-----------------|
| **OLM state at deploy** | Resources present | Resources removed |
| **Cleanup phases** | Run and tested | May run but no-op |
| **Deployment speed** | Slower (cleanup wait) | Faster (clean state) |
| **Validation focus** | Cleanup + deploy | Deploy only |
| **Real-world simulation** | Yes (mirrors production) | No (pre-cleaned) |
| **Use case** | Primary testing | Baseline/troubleshooting |
| **Fail condition** | OLM not cleaned | OLM reappears |

---

## Troubleshooting

### Mode 1: PKO Cleanup Failed

**Symptom:** Phase 6 validation shows OLM resources still present

**Causes:**
- Cleanup phases not running (phase order wrong)
- Cleanup Job missing/incorrect resources
- PKO permissions insufficient to delete OLM resources
- Hive sync restored resources during cleanup

**Debug steps:**
1. Check ClusterPackage status: `oc get clusterpackage configure-alertmanager-operator -o yaml`
2. Look for cleanup phase execution in status
3. Check cleanup Job logs: `oc logs -n openshift-monitoring job/camo-cleanup-olm`
4. Verify phase ordering in deploy_pko/manifest.yaml
5. Check logs: `logs/phase6-*.log`

### Mode 2: OLM Resources Reappeared

**Symptom:** Phase 6 shows OLM resources exist again

**Causes:**
- Hive sync is not paused
- SelectorSyncSet restored OLM resources

**Debug steps:**
1. Verify Hive sync paused: `oc get selectorsyncset -A`
2. Check if resources have recent timestamps
3. Review logs: `logs/phase6-*.log`
4. Re-pause Hive sync and delete OLM resources again

---

## Best Practices

1. **Always start with Mode 1** - It's the complete test
2. **Use Mode 2 for debugging** - If Mode 1 fails, try Mode 2 to isolate issues
3. **Check logs** - Review logs after each phase
4. **Pause Hive sync** - Critical for both modes
5. **Compare modes** - Run both on different clusters to compare behavior
6. **Document findings** - Note any differences in logs/behavior

---

## Next Steps After This Phase

After choosing a mode in Phase 4:
1. Run Phase 5 to deploy ClusterPackage
2. Run Phase 6 to monitor and validate
3. Run Phase 7 to test operator functionality
4. Run Phase 8 to cleanup (if needed)

All logs will be in `/path/to/pko-testing/logs/`
