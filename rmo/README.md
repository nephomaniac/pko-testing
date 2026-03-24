# RMO PKO Migration Testing

Route Monitor Operator (RMO) migration from OLM to PKO.

## Setup

1. Copy config from CAMO as template:
   ```bash
   cp ../camo/config/pko-test-config.example config/pko-test-config
   nano config/pko-test-config
   ```

2. Update operator-specific values:
   - IMAGE_NAME=route-monitor-operator
   - OPERATOR_NAMESPACE=openshift-route-monitor-operator  
   - Update CRD and resource names

3. Set RMO repository path:
   ```bash
   export RMO_REPO=/path/to/route-monitor-operator
   ```

4. Run migration:
   ```bash
   ../common/run-all-phases.sh
   ```

## Status

🚧 **Under Development** - Scripts are being adapted for RMO.

See [../camo/](../camo/) for working example.
