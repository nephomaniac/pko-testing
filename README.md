# PKO Testing Framework

Reusable testing framework for migrating OpenShift operators from OLM to PKO.

## Overview

This repository provides operator-agnostic scripts for testing OLM to PKO migrations. The same scripts work for any operator - you just provide operator-specific configuration.

**Supported Operators:**
- **CAMO** - Configure Alertmanager Operator
- **RMO** - Route Monitor Operator
- **OME** - OSD Metrics Exporter

## Quick Start

The easiest way to get started is using the **Phase 0 Setup Helper**:

```bash
cd pko-testing/camo  # or rmo/ or ome/
../common/phase0-setup.sh
```

This interactive menu will guide you through:
- ✓ Creating your configuration
- ✓ Viewing current status
- ✓ Running phases in the correct order
- ✓ Resuming from failures

**See [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) for detailed instructions.**

---

## Structure

```
pko-testing/
├── common/                      # Shared operator-agnostic scripts
│   ├── load-config.sh           # Config loading and state management
│   ├── validate-pko-image.sh    # Validate PKO package images
│   ├── phase0-setup.sh          # Interactive setup helper (START HERE)
│   ├── phase1-build-images.sh   # Build operator and PKO images
│   ├── phase2-push-images.sh    # Push images to registry
│   ├── phase3-prepare-cluster.sh # Backup, pause Hive
│   ├── phase4-prepare-migration.sh # Choose migration mode
│   ├── phase5-deploy-pko.sh     # Deploy ClusterPackage
│   ├── phase6-monitor-deployment.sh # Monitor and validate
│   ├── phase7-functional-test.sh # Functional tests
│   └── phase8-cleanup.sh        # Cleanup and restore
├── camo/                        # CAMO configuration
│   ├── config/
│   │   ├── user-config.example  # User-provided settings
│   │   └── runtime-state        # Auto-generated (gitignored)
│   ├── logs/                    # Execution logs (gitignored)
│   └── backups/                 # Resource backups (gitignored)
├── rmo/                         # RMO configuration
├── ome/                         # OME configuration
└── docs/                        # Documentation
    ├── GETTING-STARTED.md       # Start here!
    ├── CONFIG-STRUCTURE.md      # Configuration details
    ├── PKO-MIGRATION-MODES.md   # Mode 1 vs Mode 2
    └── USING-PREBUILT-IMAGES.md # Use Konflux/CI builds
```

## Features

### Interactive Setup (Phase 0)
- Menu-driven configuration wizard
- Auto-detects operator type
- Shows current status and progress
- Recommends next phase to run
- One-click phase execution

### Two-File Configuration
- **user-config** - You edit (registry, cluster, images)
- **runtime-state** - Scripts generate (tags, timestamps, status)

See [docs/CONFIG-STRUCTURE.md](docs/CONFIG-STRUCTURE.md) for details.

### Pre-Built Image Support
- Use Konflux CI builds
- Use released versions
- Skip slow local builds
- Automatic image validation

See [docs/USING-PREBUILT-IMAGES.md](docs/USING-PREBUILT-IMAGES.md) for details.

### Two Migration Modes
- **Mode 1**: PKO cleanup (PKO removes OLM resources)
- **Mode 2**: Manual cleanup (you delete OLM first)

See [docs/PKO-MIGRATION-MODES.md](docs/PKO-MIGRATION-MODES.md) for details.

### Comprehensive Logging
- Each phase logs to separate file
- Includes timestamps and status
- Easy debugging and review

---

## Manual Usage

If you prefer not to use the interactive Phase 0 helper:

### 1. Create Configuration

```bash
cd pko-testing/camo  # Choose your operator
cp config/user-config.example config/user-config
nano config/user-config
```

**Required settings:**
- Container registry and username
- Cluster ID and API server
- Operator namespace

**OR** uncomment `OPERATOR_IMAGE` and `PKO_IMAGE` to use pre-built images.

### 2. Run Phases

**With local build:**
```bash
../common/phase1-build-images.sh
../common/phase2-push-images.sh
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh
../common/phase5-deploy-pko.sh
../common/phase6-monitor-deployment.sh
../common/phase7-functional-test.sh
```

**With pre-built images (skip phase1-2):**
```bash
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh
../common/phase5-deploy-pko.sh
../common/phase6-monitor-deployment.sh
../common/phase7-functional-test.sh
```

---

## Adding New Operator

```bash
# Create operator directory
mkdir -p newoperator/{config,logs,backups}
touch newoperator/{config,logs,backups}/.gitkeep

# Copy config template
cp camo/config/user-config.example newoperator/config/

# Edit for your operator
nano newoperator/config/user-config.example

# Test with Phase 0 helper
cd newoperator
../common/phase0-setup.sh
```

---

## Documentation

- **[GETTING-STARTED.md](docs/GETTING-STARTED.md)** - Quick start guide
- **[CONFIG-STRUCTURE.md](docs/CONFIG-STRUCTURE.md)** - Configuration file structure
- **[PKO-MIGRATION-MODES.md](docs/PKO-MIGRATION-MODES.md)** - Migration mode comparison
- **[USING-PREBUILT-IMAGES.md](docs/USING-PREBUILT-IMAGES.md)** - Pre-built image usage

---

## Example Workflow

```bash
# 1. Start the setup helper
cd pko-testing/camo
../common/phase0-setup.sh

# 2. Choose option 1 to create config
# Edit configuration settings

# 3. Choose option 6 to run next phase
# Repeat until migration complete

# 4. View logs if needed (option 5)
```

The helper remembers where you left off and suggests the next phase automatically.

---

## Requirements

- OpenShift cluster access (oc CLI configured)
- Container runtime (podman or docker)
- Git (for commit SHA tagging)
- Operator source repository (for local builds)
- OR pre-built operator and PKO images

---

## License

This testing framework is for internal Red Hat use.
