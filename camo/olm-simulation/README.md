# CAMO OLM Simulation Fixtures

These YAML files simulate the resources that exist on a managed cluster
when CAMO is deployed via OLM (SelectorSyncSet from hive).

Use these to set up a test cluster in "OLM state" before testing
PKO migration.

## Resources

Based on investigation of a live OLM stage cluster (2026-04-23):

| Resource | Source | ownerRef | controller? |
|----------|--------|----------|-------------|
| CatalogSource | OLM SSS | none | n/a |
| Subscription | OLM SSS | none | n/a |
| ClusterRoleBinding-prom | OLM SSS | none | n/a |
| ServiceAccount | OLM (from CSV) | none | n/a |
| Deployment | OLM (from CSV) | CSV ref | controller: false |

## Usage

```bash
source ../common/detect-cluster-state.sh

# Option 1: Simulate OLM state
simulate_olm_state "openshift-monitoring" "configure-alertmanager-operator" \
  "$(pwd)/olm-simulation"

# Option 2: Apply manually
for f in olm-simulation/*.yaml; do
  oc apply -f "$f"
done
```

## Notes

- The Deployment uses a placeholder image — it won't actually run
  the operator. The purpose is to test PKO adoption of the resource,
  not operator functionality.
- The CSV is intentionally omitted — on real clusters, the CSV would
  exist but PKO doesn't need to adopt it (the cleanup Job deletes it).
- Labels match what hive/OLM would set (`hive.openshift.io/managed`,
  `olm.managed`, etc.)
