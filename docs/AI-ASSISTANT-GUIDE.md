# AI Assistant Guide - PKO Testing Framework

This guide is specifically for AI assistants (like Claude) helping users work with the PKO testing framework. It provides context, common patterns, and best practices for assisting with OLM→PKO migration testing.

## Framework Overview

### Purpose
The PKO testing framework enables local testing of Kubernetes operator migrations from OLM (Operator Lifecycle Manager) to PKO (Package Operator) deployment methods. It supports multiple testing scenarios ranging from simple PKO deployments to production-like OLM→PKO migrations.

### Repository Structure
```
pko-testing/
├── common/              # Shared scripts used by all operators
│   ├── scenario-selector.sh        # NEW: Intelligent scenario selection
│   ├── deploy-olm-from-quay.sh     # NEW: Production OLM deployment
│   ├── install-via-olm.sh          # Simulated OLM deployment
│   ├── phase0-setup.sh             # Interactive setup menu
│   ├── phase1-build-images.sh      # Build operator + PKO images
│   ├── phase2-push-images.sh       # Push to registry
│   ├── phase3-prepare-cluster.sh   # Cluster preparation
│   ├── phase4-prepare-migration.sh # PKO migration prep
│   ├── phase5-deploy-pko.sh        # PKO deployment
│   ├── phase6-monitor-deployment.sh # Monitoring
│   ├── phase7-functional-test.sh   # Testing
│   └── load-config.sh              # Configuration loader
├── camo/                # configure-alertmanager-operator config
├── ome/                 # osd-metrics-exporter config
├── rmo/                 # route-monitor-operator config
└── docs/                # Documentation
    ├── SCENARIO-SELECTOR.md        # NEW: Scenario workflow guide
    └── AI-ASSISTANT-GUIDE.md       # This file
```

### Key Concepts

**Testing Scenarios:**
1. **Fresh PKO** - Direct PKO deployment (no OLM)
2. **OLM→PKO (Local)** - Full migration with locally-built images
3. **OLM→PKO (Production)** - Migration with quay.io production images
4. **Cleanup Only** - Test migration with existing OLM deployment

**Configuration Files:**
- `config/user-config` - User-specific settings (cluster, registry, images)
- `config/operator-config` - Operator-specific constants (names, paths, etc.)
- `config/runtime-state` - Execution state and scenario flags

**Workflow Flags:**
Set by `scenario-selector.sh` in `runtime-state`:
- `SKIP_BUILD_OPERATOR` - Don't build operator image
- `SKIP_BUILD_PKO` - Don't build PKO package
- `SKIP_OLM_DEPLOYMENT` - Skip OLM deployment phases
- `USE_PRODUCTION_OLM` - Use deploy-olm-from-quay.sh
- `USE_SIMULATED_OLM` - Use install-via-olm.sh

## Common User Requests and How to Help

### "I want to test PKO migration for [operator]"

**Recommended Approach:**
1. Check if they have the testing framework: `ls -la ~/sandbox/pko-testing`
2. If not, help them set it up or direct to existing installation
3. Navigate to operator directory: `cd ~/sandbox/pko-testing/[operator]`
4. Run scenario selector: `../common/scenario-selector.sh`
5. Follow the suggested workflow from scenario selector output

**Example:**
```bash
cd ~/sandbox/pko-testing/ome
../common/scenario-selector.sh
# User selects scenario, then follow printed next steps
```

### "I want to test with production images from quay.io"

**This is Scenario 3 - Production OLM→PKO Migration**

**Steps to help:**
1. Ensure `config/operator-config` has OLM image fields configured
2. Run scenario selector and choose scenario 3
3. Walk through the workflow:
   - deploy-olm-from-quay.sh (deploys production OLM)
   - phase1-build-images.sh (builds PKO package only)
   - phase2-push-images.sh (pushes PKO image)
   - phase4-prepare-migration.sh (preps cleanup)
   - phase5-deploy-pko.sh (migrates to PKO)

**Check OLM configuration:**
```bash
grep -E "OLM_REGISTRY_IMAGE|OLM_TEMPLATE_PATH|OLM_CHANNEL" config/operator-config
```

If missing, help them add:
```bash
OLM_REGISTRY_IMAGE="quay.io/app-sre/[operator]-registry@sha256:..."
OLM_CHANNEL="staging"
OLM_TEMPLATE_PATH="hack/olm-registry/olm-artifacts-template.yaml"
```

### "The OLM deployment isn't working"

**Troubleshooting Steps:**

1. **Verify cluster connectivity:**
   ```bash
   oc whoami
   oc get nodes
   ```

2. **Check if template exists:**
   ```bash
   ls -la $OME_REPO/hack/olm-registry/olm-artifacts-template.yaml
   # Or wherever OLM_TEMPLATE_PATH points
   ```

3. **Check OLM resources:**
   ```bash
   oc get catalogsource,subscription,csv -n $OPERATOR_NAMESPACE
   oc describe catalogsource $CATALOGSOURCE_NAME -n $OPERATOR_NAMESPACE
   ```

4. **Check operator pod:**
   ```bash
   oc get pods -n $OPERATOR_NAMESPACE
   oc logs -n $OPERATOR_NAMESPACE [pod-name]
   ```

5. **Check events:**
   ```bash
   oc get events -n $OPERATOR_NAMESPACE --sort-by='.lastTimestamp'
   ```

**Common Issues:**
- **CatalogSource image pull fails** - Verify quay.io image exists and is public
- **CSV stays in "Installing"** - Check operator image pull, RBAC, resource limits
- **Template not found** - Verify OLM_TEMPLATE_PATH in operator-config
- **Parameter substitution fails** - Ensure OLM_REGISTRY_IMAGE includes digest

### "I want to test my code changes"

**This is Scenario 2 - Local Image Migration**

**Steps:**
1. Ensure their code changes are in the operator repo
2. Run scenario selector, choose scenario 2
3. This will:
   - Build operator image from local code
   - Build PKO package from local code
   - Deploy via simulated OLM
   - Test migration

**Important:**
- Scenario 2 uses `install-via-olm.sh` which creates mock OLM resources
- Good for development, not for production validation
- If they want to test against real OLM template, use scenario 3 with locally-built images

### "How do I clean up after testing?"

**PKO Cleanup:**
```bash
oc delete clusterpackage $CLUSTERPACKAGE_NAME
```

**OLM Cleanup:**
```bash
oc delete csv -n $OPERATOR_NAMESPACE --all
oc delete subscription $SUBSCRIPTION_NAME -n $OPERATOR_NAMESPACE
oc delete catalogsource $CATALOGSOURCE_NAME -n $OPERATOR_NAMESPACE
oc delete namespace $OPERATOR_NAMESPACE
```

**Or use the cleanup script:**
```bash
../common/phase8-cleanup.sh
```

### "Scenario selector detects wrong state"

**Common Causes:**
1. **Both OLM and PKO detected** - Leftover resources from previous test
2. **Hive still active** - They forgot to pause Hive
3. **Wrong namespace** - Check OPERATOR_NAMESPACE in config

**Solutions:**
- Clean up existing deployments first
- Verify cluster state manually: `oc get clusterpackage,csv -A`
- Re-run scenario selector after cleanup

## Helping with Configuration

### Checking Configuration Status

**Always check config before running phases:**
```bash
cd ~/sandbox/pko-testing/[operator]
cat config/user-config
cat config/operator-config
cat config/runtime-state  # If exists
```

### Required user-config Fields

**For all scenarios:**
- `CLUSTER_ID` - Cluster identifier
- `CLUSTER_SERVER` - API server URL
- `CLUSTER_USER` - Username for login
- `OPERATOR_NAMESPACE` - Where operator deploys

**For image building (scenarios 1, 2):**
- `IMAGE_REGISTRY` - e.g., quay.io
- `IMAGE_REPOSITORY` - User's quay.io username
- `[OPERATOR]_REPO` - Path to operator git repository

**For production OLM (scenario 3):**
- Check `operator-config` has OLM fields configured

### Required operator-config Fields

**Standard fields (all operators):**
- `OPERATOR_NAME` - Deployment name
- `OPERATOR_NAMESPACE` - Namespace
- `CSV_NAME_PATTERN` - For grep matching CSVs
- `SUBSCRIPTION_NAME` - OLM subscription name
- `CATALOGSOURCE_NAME` - CatalogSource name
- `CLUSTERPACKAGE_NAME` - PKO package name
- `CLUSTERPACKAGE_TEMPLATE_PATH` - Path to template in operator repo

**New OLM fields (for scenario 3):**
- `OLM_REGISTRY_IMAGE` - CatalogSource image with digest
- `OLM_TEMPLATE_PATH` - Path to OLM template
- `OLM_CHANNEL` - Channel name (e.g., "staging")

## Understanding Workflow Flags

When `scenario-selector.sh` runs, it writes flags to `config/runtime-state`. Phase scripts check these flags to determine behavior.

### Flag Decision Tree

```
Scenario 1 (Fresh PKO):
  SKIP_BUILD_OPERATOR=false
  SKIP_BUILD_PKO=false
  SKIP_OLM_DEPLOYMENT=true
  → Builds both images, skips OLM, deploys PKO directly

Scenario 2 (Local OLM→PKO):
  SKIP_BUILD_OPERATOR=false
  SKIP_BUILD_PKO=false
  USE_SIMULATED_OLM=true
  → Builds both images, uses install-via-olm.sh, migrates

Scenario 3 (Production OLM→PKO):
  SKIP_BUILD_OPERATOR=true
  SKIP_BUILD_PKO=false
  USE_PRODUCTION_OLM=true
  → Skips operator build, uses deploy-olm-from-quay.sh, migrates

Scenario 4 (Cleanup Only):
  SKIP_BUILD_OPERATOR=true
  SKIP_BUILD_PKO=false
  SKIP_OLM_DEPLOYMENT=true
  → Skips operator build, OLM already exists, migrates
```

### How Phase Scripts Use Flags

**phase1-build-images.sh:**
```bash
if [ "$SKIP_BUILD_OPERATOR" = "true" ]; then
    echo "Skipping operator image build"
else
    # Build operator image
fi

if [ "$SKIP_BUILD_PKO" = "true" ]; then
    echo "Skipping PKO image build"
else
    # Build PKO package image
fi
```

**phase3-prepare-cluster.sh:**
```bash
if [ "$USE_PRODUCTION_OLM" = "true" ]; then
    ../common/deploy-olm-from-quay.sh
elif [ "$USE_SIMULATED_OLM" = "true" ]; then
    ../common/install-via-olm.sh
elif [ "$SKIP_OLM_DEPLOYMENT" = "true" ]; then
    echo "Skipping OLM deployment"
fi
```

## Best Practices for AI Assistance

### 1. Always Start with Scenario Selector

Don't jump straight to phase scripts. The scenario selector:
- Detects current cluster state
- Recommends appropriate scenario
- Sets correct workflow flags
- Provides clear next steps

**DON'T:**
```bash
# Don't immediately run phases without configuration
cd ~/sandbox/pko-testing/ome
../common/phase1-build-images.sh  # May fail or do wrong thing
```

**DO:**
```bash
# Always run scenario selector first
cd ~/sandbox/pko-testing/ome
../common/scenario-selector.sh
# Then follow the printed next steps
```

### 2. Validate Configuration Before Running Phases

Always check that required config exists and is correct:
```bash
# Check user config
cat config/user-config | grep -E "IMAGE_REGISTRY|CLUSTER_ID|OPERATOR_NAMESPACE"

# Check operator config
cat config/operator-config | grep -E "OPERATOR_NAME|CLUSTERPACKAGE_NAME"

# Check runtime state (if scenario selector ran)
cat config/runtime-state | grep -E "TESTING_SCENARIO|SKIP_BUILD"
```

### 3. Understand the User's Goal

Ask clarifying questions:
- "Are you testing your own code changes or production images?"
- "Do you want to test the full OLM→PKO migration or just PKO deployment?"
- "Is OLM already deployed on your cluster?"

This helps you recommend the correct scenario.

### 4. Provide Context for Errors

When a script fails, help the user understand:
- **What** failed (which phase, which command)
- **Why** it failed (missing config, cluster issue, image pull)
- **How** to fix it (specific commands to run)

**Example:**
```
The deploy-olm-from-quay.sh script failed because:
- OLM_TEMPLATE_PATH points to: hack/olm-registry/olm-artifacts-template.yaml
- But this file doesn't exist in your operator repo

Fix:
1. Check if the template is at a different path:
   ls -la $OME_REPO/hack/
   ls -la $OME_REPO/build/templates/

2. Update operator-config with correct path:
   OLM_TEMPLATE_PATH="build/templates/olm-artifacts-template.yaml.tmpl"
```

### 5. Be Aware of Operator Differences

Different operators have different:
- Template paths (some use `hack/`, others `build/templates/`)
- Template formats (some are OpenShift Templates, others are plain YAML)
- OLM resource structures (some have extra RBAC, others don't)
- Namespace patterns (CAMO uses `openshift-monitoring`, OME uses `openshift-osd-metrics`)

Always check the operator-specific config and respect differences.

### 6. Help Interpret Cluster State

When scenario selector shows state, help user understand:

**"Hive is ACTIVE"**
- Means Hive might reconcile and override manual changes
- Suggest pausing Hive: `oc scale deployment hive-operator -n hive --replicas=0`

**"Both OLM and PKO detected"**
- Likely leftover from previous test
- Offer to clean up before starting new test

**"OLM CSV phase: Installing"**
- Normal during initial deployment
- Check again after 30 seconds
- If stuck, investigate with `oc describe csv` and `oc get events`

## Common Pitfalls to Avoid

### 1. Don't Mix Scenarios

If user runs scenario selector for scenario 3, then manually runs phase1 with operator build, they'll have mismatched config.

**Solution:** Re-run scenario selector if changing approach mid-test.

### 2. Don't Assume Template Format

Some operators use OpenShift Template format (`kind: Template`), others use plain YAML lists. The `deploy-olm-from-quay.sh` script handles both, but be aware when troubleshooting.

### 3. Don't Skip Scenario Selector

Even if you think you know which scenario the user needs, run scenario selector. It validates cluster state and may reveal issues.

### 4. Don't Ignore runtime-state

If `config/runtime-state` exists, check it before suggesting commands. The flags set there control what phases do.

### 5. Don't Assume OLM Template Location

Check `OLM_TEMPLATE_PATH` in operator-config. Don't assume all operators use the same path.

## Quick Reference Commands

### Check Everything
```bash
cd ~/sandbox/pko-testing/[operator]

# Configuration
cat config/user-config
cat config/operator-config
cat config/runtime-state

# Cluster state
oc whoami
oc get clusterpackage,csv -A | grep [operator-name]

# Hive status
oc get deployment hive-operator -n hive -o jsonpath='{.spec.replicas}'
```

### Start Fresh Test
```bash
cd ~/sandbox/pko-testing/[operator]
../common/scenario-selector.sh
# Follow printed next steps
```

### Deploy Production OLM
```bash
cd ~/sandbox/pko-testing/[operator]
../common/deploy-olm-from-quay.sh
```

### Clean Up
```bash
# PKO
oc delete clusterpackage [name]

# OLM
oc delete csv,subscription,catalogsource -n [namespace] --all

# Full cleanup
../common/phase8-cleanup.sh
```

## When to Escalate or Ask User

**Ask the user if:**
- You're unsure which scenario fits their needs
- Configuration is missing and you don't know the correct values
- Multiple operators could match (they said "operator" but not which one)
- You need credentials or sensitive information

**Suggest reading docs if:**
- Question is complex and covered in SCENARIO-SELECTOR.md
- User wants to understand workflow in depth
- Issue requires understanding of PKO concepts

**Troubleshoot yourself if:**
- Error message is clear and fix is obvious
- Configuration is missing but defaults are safe
- Issue is a known pitfall with documented solution

## Summary

The PKO testing framework with scenario selector makes testing operator migrations much easier. As an AI assistant:

1. **Always start with scenario selector** - It sets everything up correctly
2. **Validate configuration** - Check config files before running phases
3. **Understand the user's goal** - Ask which scenario fits their needs
4. **Provide context for errors** - Explain what failed and how to fix
5. **Respect operator differences** - Check operator-config for specifics
6. **Use the docs** - SCENARIO-SELECTOR.md has comprehensive examples

The scenario-based approach eliminates guesswork and provides clear workflows for different testing needs. Help users leverage this by always starting with scenario selection.
