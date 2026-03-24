# CAMO PKO Full E2E Testing Plan

**Date**: 2026-03-23
**Cluster**: maclarkrosa0323 (OCP 4.21.5)
**PR**: https://github.com/openshift/configure-alertmanager-operator/pull/496
**Commit**: 32c73df8

---

## Objective

Complete end-to-end testing of CAMO PKO migration including:
1. Building images with correct architecture (macOS → linux/amd64)
2. Testing PKO cleanup of OLM resources
3. Testing PKO deployment with all fixes
4. Verifying operator functionality
5. Testing cleanup scripts

---

## Current State

### What We've Tested (Partial)
- ✅ Phase 4: Prepare migration (Mode 1)
- ✅ Phase 5: Deploy PKO (3+ iterations)
- ⚠️  Result: PKO deployed successfully, operator pod crashed

### Root Cause of Failure
- **Used pre-built images** (test-afae58f) without macOS cross-compilation flags
- Images built for darwin/arm64, cluster needs linux/amd64
- Error: "exec container process (missing dynamic library?)"

### What We Haven't Tested
- ❌ Phase 1: Build images (with GOOS=linux GOARCH=amd64)
- ❌ Phase 2: Push images
- ❌ Phase 3: Prepare cluster
- ❌ Phase 6: Monitor deployment
- ❌ Phase 7: Functional testing
- ❌ Phase 8: Cleanup

---

## Testing Plan

### Phase 0: Pre-Testing Cleanup

**Goal**: Clean cluster state, restore OLM deployment

**Steps**:
```bash
# 1. Remove current PKO deployment
cd /Users/maclark/clusters/maclarkrosa0323/pko-testing/camo
../common/phase8-cleanup.sh

# Verify cleanup:
oc get clusterpackage configure-alertmanager-operator  # Should not exist
oc get deployment -n openshift-monitoring configure-alertmanager-operator  # Should not exist

# 2. Unpause Hive to restore OLM
# (Get Hive SelectorSyncSet name and remove pause annotation)

# 3. Wait for Hive to rebuild OLM
# Monitor:
oc get subscription -n openshift-monitoring configure-alertmanager-operator -w
oc get csv -n openshift-monitoring | grep configure-alertmanager
oc get deployment -n openshift-monitoring configure-alertmanager-operator

# 4. Verify OLM deployment working
oc get pods -n openshift-monitoring | grep configure-alertmanager
oc logs -n openshift-monitoring deployment/configure-alertmanager-operator
```

**Success Criteria**:
- ✅ PKO resources removed
- ✅ OLM Subscription exists
- ✅ CSV exists and phase=Succeeded
- ✅ Operator pod running via OLM
- ✅ No errors in operator logs

---

### Phase 1: Build Images (NEW - WITH CORRECT FLAGS)

**Goal**: Build images with macOS cross-compilation flags

**Command**:
```bash
cd /Users/maclark/clusters/maclarkrosa0323/pko-testing/camo
../common/phase1-build-images.sh --quay-username maclark
```

**What It Does**:
- Checks out pko-cleanup-improvements branch (commit 32c73df8)
- Builds operator image with: **GOOS=linux GOARCH=amd64** ALLOW_DIRTY_CHECKOUT=true
- Builds PKO package image from deploy_pko/
- Tags images: test-32c73df (based on git commit)

**Verify**:
```bash
# Check images built
podman images | grep configure-alertmanager-operator

# Verify architecture
podman inspect quay.io/maclark/configure-alertmanager-operator:test-32c73df | jq '.[0].Architecture'
# Should show: "amd64"
```

**Success Criteria**:
- ✅ Operator image built (test-32c73df)
- ✅ PKO package image built (test-32c73df)
- ✅ Image architecture = amd64 (NOT arm64)
- ✅ Config file updated with new image tags

**Estimated Time**: 15 minutes

---

### Phase 2: Push Images

**Goal**: Push images to Quay.io

**Command**:
```bash
../common/phase2-push-images.sh --auto-confirm
```

**What It Does**:
- Pushes quay.io/maclark/configure-alertmanager-operator:test-32c73df
- Pushes quay.io/maclark/configure-alertmanager-operator-pko:test-32c73df

**Manual Step**:
- Set images to PUBLIC in Quay.io UI (cluster needs to pull them)

**Success Criteria**:
- ✅ Both images pushed
- ✅ Images visible in Quay.io
- ✅ Images set to PUBLIC

**Estimated Time**: 5 minutes

---

### Phase 3: Prepare Cluster

**Goal**: Verify cluster state before migration

**Command**:
```bash
../common/phase3-prepare-cluster.sh
```

**What It Does**:
- Verifies cluster connection
- Checks PKO installation
- Documents baseline state

**Success Criteria**:
- ✅ Cluster accessible
- ✅ PKO running
- ✅ OLM deployment active

**Estimated Time**: 5 minutes

---

### Phase 4: Prepare Migration

**Goal**: Configure migration mode and update config with new images

**Command**:
```bash
../common/phase4-prepare-migration.sh
```

**What It Does**:
- Prompts for migration mode (select Mode 1: PKO cleanup)
- Updates config with new image tags (test-32c73df)
- Verifies OLM resources exist

**Success Criteria**:
- ✅ Mode 1 selected
- ✅ Config updated with test-32c73df images
- ✅ OLM Subscription, CSV, CatalogSource exist

**Estimated Time**: 5 minutes

---

### Phase 5: Deploy PKO

**Goal**: Deploy CAMO via PKO with cleanup

**Command**:
```bash
../common/phase5-deploy-pko.sh
```

**What It Does**:
1. Generates ClusterPackage from CAMO's template (hack/pko/clusterpackage.yaml)
2. Substitutes variables: REPO_NAME, PKO_IMAGE, OPERATOR_IMAGE, FEDRAMP
3. Applies ClusterPackage to cluster
4. PKO runs phases in order:
   - cleanup-rbac → cleanup-deploy → crds → namespace → rbac → deploy

**Monitor During Deployment**:
```bash
# Watch ClusterPackage status
oc get clusterpackage configure-alertmanager-operator -w

# Watch cleanup job
oc get jobs -n openshift-monitoring olm-cleanup -w
oc logs -n openshift-monitoring job/olm-cleanup -f

# Watch operator deployment
oc get deployment -n openshift-monitoring configure-alertmanager-operator -w
oc get pods -n openshift-monitoring | grep configure-alertmanager
```

**Success Criteria**:
- ✅ ClusterPackage created
- ✅ Cleanup job runs successfully
- ✅ OLM resources deleted (Subscription, CSV, CatalogSource, ClusterRoleBinding, ServiceAccount)
- ✅ No PKO validation errors
- ✅ No resource adoption conflicts
- ✅ Operator deployment created
- ✅ Operator pod created and **RUNNING** (not crashing!)

**Estimated Time**: 10-15 minutes

---

### Phase 6: Monitor Deployment

**Goal**: Watch deployment progress and verify phases complete

**Command**:
```bash
../common/phase6-monitor-deployment.sh
```

**What It Does**:
- Watches ClusterPackage status
- Shows phase progression
- Displays pod status
- Shows operator logs

**Success Criteria**:
- ✅ All phases complete
- ✅ Operator pod running
- ✅ No errors in logs

**Estimated Time**: 10-15 minutes

---

### Phase 7: Functional Testing

**Goal**: Verify operator is functioning correctly

**Command**:
```bash
../common/phase7-functional-test.sh
```

**Tests to Run**:

**1. Readiness Check**:
```bash
POD=$(oc get pods -n openshift-monitoring -l name=configure-alertmanager-operator -o name | head -1)
oc exec -n openshift-monitoring $POD -- curl -s http://localhost:8081/healthz
# Should return: OK
```

**2. Prometheus Access (ClusterRoleBinding working)**:
```bash
# Check operator logs for Prometheus queries
oc logs -n openshift-monitoring $POD | grep -i prometheus

# Should NOT see 403 errors
# Should see successful queries
```

**3. AlertmanagerConfig**:
```bash
# Check if operator is managing AlertmanagerConfig
oc get alertmanagerconfig -n openshift-monitoring

# Check operator reconciliation
oc logs -n openshift-monitoring $POD | grep -i "reconciling\|alertmanager"
```

**4. Resource Ownership**:
```bash
# Verify resources owned by PKO (not Hive)
oc get deployment -n openshift-monitoring configure-alertmanager-operator -o yaml | grep -A5 "labels:"
# Should NOT have: hive.openshift.io/managed: "true"

oc get clusterrolebinding configure-alertmanager-operator-prom -o yaml | grep -A5 "labels:"
# Should have PKO labels, NOT Hive labels
```

**Success Criteria**:
- ✅ Readiness endpoint returns OK
- ✅ Operator can query Prometheus (no 403 errors)
- ✅ AlertmanagerConfig reconciliation working
- ✅ Resources owned by PKO, not Hive
- ✅ No crashes or errors in logs

**Estimated Time**: 20-30 minutes

---

### Phase 8: Cleanup

**Goal**: Remove PKO deployment and restore cluster

**Command**:
```bash
../common/phase8-cleanup.sh
```

**What It Does**:
- Deletes ClusterPackage
- Verifies all CAMO resources removed
- Provides instructions to unpause Hive

**Verify**:
```bash
# Check ClusterPackage deleted
oc get clusterpackage configure-alertmanager-operator
# Should not exist

# Check resources cleaned up
oc get deployment -n openshift-monitoring configure-alertmanager-operator
oc get clusterrolebinding configure-alertmanager-operator-prom
# Should not exist
```

**Post-Cleanup**:
- Unpause Hive SelectorSyncSet
- Verify Hive restores OLM deployment

**Success Criteria**:
- ✅ ClusterPackage deleted
- ✅ All CAMO resources removed
- ✅ Hive can restore OLM

**Estimated Time**: 10 minutes

---

## Issues We're Testing For

### 1. attributeRestrictions Deprecated Field
- **Fixed in**: 32c73df8
- **Test**: PKO deployment should succeed without validation errors
- **Expected**: No "field not declared in schema" errors

### 2. ClusterRoleBinding API Version
- **Fixed in**: 32c73df8
- **Test**: ClusterRoleBindings should create successfully
- **Expected**: No "watch is not supported" errors

### 3. ClusterRoleBinding Adoption Conflict
- **Fixed in**: 32c73df8
- **Test**: Cleanup job should delete configure-alertmanager-operator-prom
- **Expected**: No "refusing adoption" errors

### 4. ServiceAccount Adoption Conflict
- **Fixed in**: 32c73df8
- **Test**: Cleanup job should delete SA, PKO recreates without Hive labels
- **Expected**: No "refusing adoption" errors

### 5. Missing Prometheus RBAC
- **Fixed in**: 32c73df8
- **Test**: Operator should query Prometheus successfully
- **Expected**: No 403 errors in logs

### 6. Operator Image Architecture
- **Fixed in**: phase1-build-images.sh (GOOS=linux GOARCH=amd64)
- **Test**: Operator pod should run without crashing
- **Expected**: No "No such file or directory" errors

### 7. FEDRAMP Type Validation
- **Fixed in**: phase5-deploy-pko.sh (commit 391ab33)
- **Test**: ClusterPackage should accept fedramp as string
- **Expected**: No "must be of type string" errors

---

## Success Criteria Summary

### Overall Success
- ✅ All 8 phases complete without errors
- ✅ Operator pod running (correct architecture)
- ✅ All functionality tests pass
- ✅ Cleanup works correctly

### Key Validations
- ✅ PKO cleanup removes all OLM resources
- ✅ PKO deployment creates all required resources
- ✅ No validation errors from PKO
- ✅ No adoption conflicts
- ✅ Operator fully functional
- ✅ Resources owned by PKO (not Hive)

---

## Timeline

**Total Estimated Time: 2-3 hours**

| Phase | Task | Time |
|-------|------|------|
| 0 | Pre-testing cleanup | 15 min |
| 1 | Build images | 15 min |
| 2 | Push images | 5 min |
| 3 | Prepare cluster | 5 min |
| 4 | Prepare migration | 5 min |
| 5 | Deploy PKO | 10-15 min |
| 6 | Monitor deployment | 10-15 min |
| 7 | Functional testing | 20-30 min |
| 8 | Cleanup | 10 min |
| - | Documentation | 15-30 min |

---

## Post-Testing Actions

### If All Tests Pass ✅

1. **Update PR #496**:
   - Add testing evidence to description
   - Note OCP version tested (4.21.5)
   - Remove do-not-merge/hold label
   - Request final review

2. **Document Results**:
   - Update this file with test results
   - Note any observations
   - Record logs if helpful

3. **Clean Up Test Cluster**:
   - Run phase8-cleanup.sh
   - Unpause Hive
   - Verify OLM restored

### If Any Tests Fail ❌

1. **Capture Evidence**:
   - Save logs: `oc logs ...`
   - Save resource YAMLs: `oc get ... -o yaml`
   - Note exact error messages

2. **Investigate**:
   - Analyze root cause
   - Check if it's a new issue or known issue not fully fixed

3. **Fix and Retest**:
   - Create new commit in CAMO repo
   - Rebuild images
   - Retest affected phases

---

## Notes

- **Architecture is critical**: Must build with GOOS=linux GOARCH=amd64 on macOS
- **We skipped phase1 before**: Used pre-built images, that's why operator crashed
- **Script already has the flags**: phase1-build-images.sh line 84-87
- **All fixes are in 32c73df8**: Ready for full test
