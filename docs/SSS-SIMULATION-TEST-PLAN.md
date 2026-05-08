# SSS Simulation Test Plan

## Prerequisites

- Hive sync paused to the test cluster (prevents hive from overwriting test state)
- `oc` logged in with cluster-admin or elevated backplane access
- PKO installed on the cluster

## Hive Simulation

Since we don't have hive access in tests, we simulate hive's SSS behavior:

- **SSS create**: `oc apply` the resources the SSS would sync
- **SSS update**: `oc apply` with updated resource specs
- **SSS remove (Upsert mode)**: Do nothing — resources persist (orphaned)
- **SSS remove (Sync mode)**: `oc delete` the resources the SSS synced

## Migration Phases to Test

### Phase 1: Cluster in OLM State (simulate OLM SSS active)

Simulate what hive + OLM creates on a managed cluster:

**Step 1a: Apply SSS-synced resources (simulate hive)**
```bash
# CatalogSource
oc apply -f olm-simulation/catalogsource.yaml
# Subscription
oc apply -f olm-simulation/subscription.yaml
# ClusterRoleBinding-prom
oc apply -f olm-simulation/clusterrolebinding-prom.yaml
```

**Step 1b: Apply OLM-created resources (simulate OLM reacting to Subscription)**
```bash
# ServiceAccount (OLM creates from CSV)
oc apply -f olm-simulation/serviceaccount.yaml
# Deployment (OLM creates from CSV, with CSV ownerRef controller:false)
oc apply -f olm-simulation/deployment.yaml
# OLM-generated RBAC (simulate with generated-style names)
oc apply -f olm-simulation/olm-clusterrole-view.yaml
oc apply -f olm-simulation/olm-clusterrole-edit.yaml
oc apply -f olm-simulation/olm-clusterrolebinding-view.yaml
oc apply -f olm-simulation/olm-clusterrolebinding-edit.yaml
oc apply -f olm-simulation/olm-role.yaml
oc apply -f olm-simulation/olm-rolebinding.yaml
```

**Verify:** `detect_deployment_state` returns "olm"

### Phase 2: OLM SSS Removed (simulate delete:true)

Since OLM SSS uses `resourceApplyMode: Upsert`, removing the SSS
leaves all resources orphaned on the managed cluster.

**Simulate:** Do nothing to the resources. They persist.
The test should verify all OLM resources still exist after
"SSS removal".

### Phase 3: PKO SSS Created (simulate PKO SSS active)

**Step 3a: Apply ClusterPackage (simulate hive syncing PKO SSS)**
```bash
oc apply -f - <<EOF
apiVersion: package-operator.run/v1alpha1
kind: ClusterPackage
metadata:
  name: configure-alertmanager-operator
  annotations:
    package-operator.run/collision-protection: IfNoController
spec:
  image: <PKO_IMAGE>:<VERSION>
  config:
    image: <OPERATOR_IMAGE>:<VERSION>
    fedramp: "false"
    version: "<VERSION>"
EOF
```

**Step 3b: Verify PKO adoption and deployment**
- ClusterPackage Available=True
- PKO adopted ServiceAccount (now has PKO ownerRef)
- PKO adopted Deployment (now has PKO ownerRef)
- PKO adopted ClusterRoleBinding-prom (now has PKO ownerRef)
- PKO created new Role, RoleBinding, ClusterRoles, CRBs (with PKO names)
- Cleanup Job ran and deleted Subscription, CSV, CatalogSource
- OLM-generated RBAC deleted (cascade from CSV deletion)
- Operator pod running

### Phase 4: PKO-to-PKO Upgrade

**Step 4a: Update ClusterPackage to new version**
```bash
oc patch clusterpackage configure-alertmanager-operator --type=merge -p '{
  "spec": {
    "image": "<PKO_IMAGE>:<NEW_VERSION>",
    "config": {
      "image": "<OPERATOR_IMAGE>:<NEW_VERSION>",
      "version": "<NEW_VERSION>"
    }
  }
}'
```

**Step 4b: Verify**
- ClusterPackage Available=True
- New cleanup Job created (olm-cleanup-<NEW_VERSION>)
- Old cleanup Job cleaned up with archived ObjectSet
- No immutability errors
- Operator pod running

### Phase 5: PKO SSS Removed (simulate rollback/disaster)

Since PKO SSS uses `resourceApplyMode: Sync`, removing the SSS
causes hive to DELETE the ClusterPackage from the managed cluster.

**Simulate:**
```bash
oc delete clusterpackage configure-alertmanager-operator
```

**Verify:**
- All PKO-managed resources are deleted (reverse phase order)
- Operator is no longer running
- Namespace is clean (no CAMO resources)

## Verification Script

After each phase, run:
```bash
./common/dump-olm-state.sh openshift-monitoring configure-alertmanager-operator
```

Compare the output against expected state for that phase.

## Test Execution Order

| Test | Prereq State | Action | Expected End State |
|------|-------------|--------|-------------------|
| T1 | neither | Simulate OLM SSS + OLM install | olm |
| T2 | olm | Simulate OLM SSS removal (Upsert) | olm (orphaned) |
| T3 | olm (orphaned) | Deploy PKO ClusterPackage | pko |
| T4 | pko | PKO upgrade (version change) | pko (new revision) |
| T5 | pko | Simulate PKO SSS removal (Sync) | neither |
| T6 | neither | Deploy PKO fresh (no OLM history) | pko |
| T7 | pko (from T6) | PKO upgrade | pko (new revision) |

## OLM Simulation Fixtures Needed

Each fixture should include the correct labels and ownerReferences
that the real OLM/SSS would set:

- `hive.openshift.io/managed: "true"` on SSS-synced resources
- `olm.managed: "true"` on OLM-created resources
- `operators.coreos.com/<operator>.<namespace>: ""` label
- CSV ownerReference (controller: false) on Deployment
- No ownerReference on ServiceAccount
- No ownerReference on CRB-prom (SSS-synced)
