# Getting Started with PKO Testing

## Quick Start

The easiest way to get started is using the Phase 0 setup helper:

```bash
cd pko-testing/camo  # or rmo/ or ome/
../common/phase0-setup.sh
```

This interactive menu will guide you through:
- Creating your configuration
- Viewing current status
- Running the next recommended phase

---

## Manual Setup

If you prefer to set up manually:

### 1. Create Configuration

```bash
cd pko-testing/camo  # Choose your operator
cp config/user-config.example config/user-config
nano config/user-config
```

**Required Settings:**
- `IMAGE_REGISTRY` - Your container registry (e.g., quay.io)
- `IMAGE_REPOSITORY` - Your username/org
- `CLUSTER_ID` - Test cluster name
- `CLUSTER_SERVER` - Cluster API URL

**OR** for pre-built images:
- Uncomment `OPERATOR_IMAGE` and `PKO_IMAGE`
- Set to Konflux or released image URLs

### 2. Run Phases in Order

**With Local Build (default):**
```bash
../common/phase1-build-images.sh
../common/phase2-push-images.sh
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh
../common/phase5-deploy-pko.sh
../common/phase6-monitor-deployment.sh
../common/phase7-functional-test.sh
```

**With Pre-Built Images:**
```bash
# Skip phase1 and phase2
../common/phase3-prepare-cluster.sh
../common/phase4-prepare-migration.sh
../common/phase5-deploy-pko.sh
../common/phase6-monitor-deployment.sh
../common/phase7-functional-test.sh
```

---

## Phase 0: Setup Helper

The setup helper (`phase0-setup.sh`) provides an interactive menu for managing your testing environment.

### Features

**Configuration Management:**
- Create `user-config` from example template
- View current configuration
- Edit configuration with your preferred editor
- Auto-detects operator type (CAMO/RMO/OME)

**Status Monitoring:**
- Shows config status (exists/missing)
- Displays runtime state (last phase, status, timestamp)
- Recommends next phase to run
- Detects pre-built image usage

**Workflow Automation:**
- One-click launch of next recommended phase
- Automatic phase skipping for pre-built images
- View phase execution logs
- Resume from last successful phase

### Usage

```bash
cd pko-testing/camo  # or rmo/ or ome/
../common/phase0-setup.sh
```

**Menu Options:**
1. **Create user-config from example** - Initial setup wizard
2. **View current configuration** - Display config with line numbers
3. **Edit configuration** - Open in $EDITOR (nano by default)
4. **View runtime state** - Show last run info and generated values
5. **View logs** - List and view phase execution logs
6. **Run next recommended phase** - Execute the next step automatically
0. **Exit** - Quit the helper

### How It Works

The setup helper:
1. Detects which operator directory you're in (camo/rmo/ome)
2. Checks if `user-config` exists
3. Reads `runtime-state` to determine progress
4. Recommends the next phase based on:
   - Last successful phase completed
   - Whether pre-built images are configured
   - Current migration state

**Phase Progression:**
- No runtime-state → Start at phase1 (or phase3 with pre-built images)
- Last phase succeeded → Suggest next sequential phase
- Last phase failed → Suggest re-running same phase

### Example Session

```
========================================================================
  PKO Testing Framework - Configuration & Setup (Phase 0)
========================================================================

Operator: Configure Alertmanager Operator
Directory: /Users/maclark/clusters/maclarkrosa0323/pko-testing/camo

Configuration Status:
-------------------
✓ user-config exists
  → Using pre-built images:
    - Operator: quay.io/openshift/configure-alertmanager-operator:v0.1.810
    - PKO: quay.io/openshift/configure-alertmanager-operator-pko:v0.1.810
✓ runtime-state exists
  → Last phase: phase5-deploy-pko
  → Status: success
  → Timestamp: 2026-03-23T14:30:00Z

Next Recommended Phase: phase6-monitor-deployment

Options:
--------
1. Create user-config from example
2. View current configuration
3. Edit configuration
4. View runtime state
5. View logs
6. Run next recommended phase

0. Exit

Choose an option:
```

---

## Configuration Options

See [CONFIG-STRUCTURE.md](CONFIG-STRUCTURE.md) for detailed configuration documentation.

### Two-File Approach

**user-config** (you edit):
- Registry settings
- Cluster information
- Image tag base
- Operator repository path
- OR pre-built image URIs

**runtime-state** (auto-generated):
- Last run phase/status
- Computed image tags
- Cluster details
- Migration mode
- Deployment timestamps

### Pre-Built Images

See [USING-PREBUILT-IMAGES.md](USING-PREBUILT-IMAGES.md) for using Konflux or released images.

**Benefits:**
- Skip slow local builds
- Test CI-built images before merge
- Test specific released versions
- Faster iteration

**Requirements:**
- Images must be pullable (credentials if private)
- PKO images must contain valid `package/manifest.yaml`
- Validation runs automatically

---

## Migration Modes

See [PKO-MIGRATION-MODES.md](PKO-MIGRATION-MODES.md) for detailed mode documentation.

### Mode 1: PKO Cleanup (Recommended)

**What:** PKO removes OLM resources via cleanup phases

**When to use:**
- Standard PKO migration testing
- Validating cleanup phase functionality
- Most common use case

**Process:**
1. Pause Hive sync (if applicable)
2. Leave OLM resources in place
3. Deploy PKO ClusterPackage
4. PKO cleanup phases remove OLM
5. PKO deploy phases install operator

### Mode 2: Manual Cleanup

**What:** Manually delete OLM resources before PKO

**When to use:**
- Testing PKO without cleanup phases
- Simulating post-cleanup state
- Debugging PKO deployment issues

**Process:**
1. Pause Hive sync (if applicable)
2. Manually delete OLM resources
3. Deploy PKO ClusterPackage
4. PKO only runs deploy phases

---

## Troubleshooting

### user-config not found

**Error:** Script can't find configuration file

**Fix:** Run Phase 0 helper and choose option 1 to create from example

### Image pull failures

**Error:** Cannot pull pre-built images

**Fix:**
1. Login to registry: `podman login quay.io`
2. Verify image exists: `podman pull <image-uri>`
3. Check credentials if private repository

### Invalid PKO package

**Error:** Pre-built image not a valid PKO package

**Fix:**
1. Verify image URI ends with `-pko`
2. Use validation script: `../common/validate-pko-image.sh <image>`
3. Rebuild using `make pko-image` or use different image

### Phase fails

**Check logs:**
```bash
cd pko-testing/camo
ls -lht logs/  # Find latest log
less logs/phase5-*.log
```

**Resume from failure:**
1. Fix the issue
2. Run Phase 0 helper
3. Choose option 6 (run next phase)
4. Helper will suggest re-running failed phase

### Wrong operator directory

**Error:** Unknown operator or resources not found

**Fix:** Ensure you're in correct directory:
- `pko-testing/camo` for Configure Alertmanager Operator
- `pko-testing/rmo` for Route Monitor Operator
- `pko-testing/ome` for OSD Metrics Exporter

---

## Next Steps

After getting started:
1. Review [CONFIG-STRUCTURE.md](CONFIG-STRUCTURE.md) for configuration details
2. Read [PKO-MIGRATION-MODES.md](PKO-MIGRATION-MODES.md) for mode selection
3. Check [USING-PREBUILT-IMAGES.md](USING-PREBUILT-IMAGES.md) if using CI builds

For questions or issues, check phase logs in `logs/` directory.
