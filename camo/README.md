# CAMO PKO Migration Testing

Configure Alertmanager Operator (CAMO) migration from OLM to PKO.

## Quick Start

### 1. Setup

```bash
# From this directory (camo/)
cp config/pko-test-config.example config/pko-test-config
nano config/pko-test-config
```

**Edit these values**:
- `IMAGE_REPOSITORY`: Your quay.io username
- `IMAGE_NAME`: configure-alertmanager-operator
- `IMAGE_TAG`: Git commit SHA
- `CLUSTER_ID`: Your test cluster name
- `CLUSTER_SERVER`: Cluster API URL
- `OPERATOR_NAMESPACE`: openshift-monitoring

### 2. Set CAMO Repository Path

```bash
export CAMO_REPO=/path/to/configure-alertmanager-operator
# Or edit config/pko-test-config
```

### 3. Run Migration

```bash
# Run all phases
../common/run-all-phases.sh

# Or run individually
../common/phase1-build-images.sh
../common/phase2-push-images.sh
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh  # Choose Mode 1 or 2
../common/phase5-deploy-pko.sh
../common/phase6-monitor-deployment.sh
../common/phase7-functional-test.sh
```

## CAMO-Specific Notes

### Namespace
CAMO deploys to `openshift-monitoring` namespace.

### CRD
- `alertmanagers.managed.openshift.io`

### ServiceAccount
- `configure-alertmanager-operator`

### ClusterRole
- `configure-alertmanager-operator`

## Logs

All execution logs are in `logs/`:
```bash
tail -f logs/phase6-*.log
```

## Backups

OLM resources backed up to `backups/backup-TIMESTAMP/` by phase 3.

## Cleanup

```bash
# Restore from backup if needed
../common/phase8-cleanup.sh
```
