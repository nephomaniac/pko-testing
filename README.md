# PKO Testing Framework

Reusable testing framework for migrating OpenShift operators from OLM to PKO.

## Overview

This repository provides operator-agnostic scripts for testing OLM to PKO migrations. The same scripts work for any operator - you just provide operator-specific configuration.

## Structure

```
pko-testing/
├── common/                      # Shared operator-agnostic scripts
│   ├── cluster-verification.sh  # Cluster safety checks
│   ├── phase1-build-images.sh   # Build operator and PKO images
│   ├── phase2-push-images.sh    # Push images to registry  
│   ├── phase3-prepare-cluster.sh # Backup, pause Hive
│   ├── phase4-prepare-migration.sh # Choose mode, cleanup
│   ├── phase5-deploy-pko.sh     # Deploy ClusterPackage
│   ├── phase6-monitor-deployment.sh # Monitor and validate
│   ├── phase7-functional-test.sh # Functional tests
│   ├── phase8-cleanup.sh        # Cleanup and restore
│   └── run-all-phases.sh        # Run all phases
├── camo/                        # CAMO configuration
│   ├── config/
│   │   └── .pko-test-config.example
│   ├── logs/                    # Execution logs
│   └── backups/                 # Resource backups
├── rmo/                         # RMO configuration
├── ome/                         # OME configuration
└── docs/                        # Documentation
```

## Quick Start

### 1. Choose Operator

```bash
cd camo/  # or rmo/, ome/
```

### 2. Setup Config

```bash
cp config/.pko-test-config.example config/.pko-test-config
nano config/.pko-test-config
```

### 3. Run Migration

```bash
# Run from operator directory
../common/run-all-phases.sh

# Or run individual phases
../common/phase1-build-images.sh
../common/phase2-push-images.sh
# ...
```

## Configuration

Each operator directory contains only:
- **config/** - Operator-specific settings
- **logs/** - Execution logs
- **backups/** - Resource backups

Common scripts read config from `./config/.pko-test-config` in the current directory.

## Adding New Operator

```bash
# Create operator directory
mkdir -p newoperator/{config,logs,backups}
touch newoperator/{config,logs,backups}/.gitkeep

# Copy config template from existing operator
cp camo/config/.pko-test-config.example newoperator/config/

# Edit for your operator
nano newoperator/config/.pko-test-config

# Run from operator directory
cd newoperator
../common/phase1-build-images.sh
```

See full README in each operator directory.
