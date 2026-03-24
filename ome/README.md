# OME PKO Migration Testing

OSD Metrics Exporter (OME) migration from OLM to PKO.

## Setup

1. Copy config from CAMO as template:
   ```bash
   cp ../camo/config/pko-test-config.example config/pko-test-config
   nano config/pko-test-config
   ```

2. Update operator-specific values:
   - IMAGE_NAME=osd-metrics-exporter
   - OPERATOR_NAMESPACE=openshift-osd-metrics-exporter
   - Update CRD and resource names

3. Set OME repository path:
   ```bash
   export OME_REPO=/path/to/osd-metrics-exporter
   ```

4. Run migration:
   ```bash
   ../common/run-all-phases.sh
   ```

## Status

🚧 **Under Development** - Scripts are being adapted for OME.

See [../camo/](../camo/) for working example.
