# OLM to PKO RBAC Migration - How It Works

## How OLM Defines and Creates RBAC

### 1. OLM CSV Structure

In OLM, operator permissions are defined in the ClusterServiceVersion (CSV) manifest under `spec.install.spec`:

```yaml
spec:
  install:
    spec:
      clusterPermissions:    # Cluster-scoped RBAC
        - serviceAccountName: configure-alertmanager-operator
          rules:
            - apiGroups: [""]
              resources: [nodes]
              verbs: [get, list]
            - apiGroups: [config.openshift.io]
              resources: [clusterversions, proxies, infrastructures]
              verbs: [get, list, watch]
        - serviceAccountName: configure-alertmanager-operator
          rules:
            - apiGroups: [""]
              resources: [secrets, configmaps]
              verbs: [get, list, watch, patch, update]
            - apiGroups: [batch]
              resources: [jobs]
              verbs: [get, list, watch]

      permissions:            # Namespace-scoped RBAC
        - serviceAccountName: configure-alertmanager-operator
          rules:
            - apiGroups: [""]
              resources: [pods, services, endpoints, configmaps, secrets]
              verbs: ["*"]
            - apiGroups: [apps]
              resources: [deployments, daemonsets, replicasets, statefulsets]
              verbs: ["*"]
            # ... more namespace rules
```

### 2. How OLM Creates Resources

When OLM installs an operator from a CSV:

**A. Namespace-Scoped RBAC (`permissions`):**
- Creates a **Role** in the operator's namespace
- Creates a **RoleBinding** linking the Role to the ServiceAccount
- Role name: Same as ServiceAccount name (`configure-alertmanager-operator`)

**B. Cluster-Scoped RBAC (`clusterPermissions`):**
- OLM has TWO approaches depending on the CSV structure:

#### Approach 1: Single ClusterRole (Standard)
If there's one `clusterPermissions` block:
- Creates **ClusterRole** with same name as ServiceAccount
- Creates **ClusterRoleBinding** linking to ServiceAccount

#### Approach 2: Multiple ClusterRoles (CAMO's Case)
If there are multiple `clusterPermissions` blocks (like CAMO), OLM generates **unique** names:
- Creates **ClusterRole** with generated name (e.g., `<csv-name>-<hash>-view`)
- Creates **ClusterRoleBinding** with matching name
- The naming is controlled by the permissions defined, not explicit names

### 3. CAMO's Actual Implementation

CAMO took a different approach in its repository. Instead of relying on OLM's auto-generated ClusterRoles, it pre-defined them in `deploy/01_role.yaml`:

```yaml
# deploy/01_role.yaml contains THREE resources:

1. Role: configure-alertmanager-operator (namespace-scoped)
2. ClusterRole: configure-alertmanager-operator-view
3. ClusterRole: configure-alertmanager-operator-edit
```

**Why two ClusterRoles?**
- **`-view`**: Contains read-only cluster permissions (nodes, clusterversions, proxies, infrastructures)
- **`-edit`**: Contains write/update cluster permissions (secrets, configmaps, jobs)

**The naming is misleading!**
- These are NOT for end-users (despite names suggesting view/edit)
- These are the **operator's own cluster permissions**
- The operator ServiceAccount is bound to BOTH ClusterRoles

## Why PKO Migration Created the "Right" RBAC

When migrating to PKO, the migration looked at `deploy/01_role.yaml` (not the CSV) and correctly created:

**Created in deploy_pko/:**
```
Role-configure-alertmanager-operator.yaml.gotmpl
RoleBinding-configure-alertmanager-operator.yaml.gotmpl
ClusterRole-configure-alertmanager-operator-view.yaml.gotmpl
ClusterRole-configure-alertmanager-operator-edit.yaml.gotmpl
ClusterRoleBinding-configure-alertmanager-operator-view.yaml.gotmpl
ClusterRoleBinding-configure-alertmanager-operator-edit.yaml.gotmpl
```

**Current State on Cluster (verified):**
```bash
$ oc get clusterrole | grep configure-alertmanager
configure-alertmanager-operator-edit    # ✓ Exists
configure-alertmanager-operator-view    # ✓ Exists

$ oc get clusterrolebinding | grep configure-alertmanager
configure-alertmanager-operator-edit    # ✓ Bound to operator SA
configure-alertmanager-operator-view    # ✓ Bound to operator SA
```

## So Why Is The Operator Failing?

The RBAC **is actually complete and correct**. The error message is misleading:

```
ERROR: failed to determine if *v1.ClusterVersion is namespaced:
       failed to get restmapping:
       failed to get server groups:
       the server has asked for the client to provide credentials
```

This error says "the server has asked for the client to provide credentials" - this is an **authentication** error, not an **authorization** (RBAC) error.

### Possible Causes:

1. **ServiceAccount Token Not Being Read**
   - The operator might not be using in-cluster authentication correctly
   - Controller-runtime client might not be picking up the SA token

2. **API Discovery Permissions**
   - The error happens during API discovery (`failed to get server groups`)
   - This is when controller-runtime queries `/apis` to discover available resources
   - This typically requires `system:discovery` ClusterRole, which is normally granted to all authenticated users

3. **Client Configuration Issue**
   - The operator might be trying to use a kubeconfig file instead of in-cluster config
   - Environment variables might be directing it to wrong auth method

### Verification That RBAC Is Correct:

```bash
# Operator SA CAN access ClusterVersion
$ oc auth can-i get clusterversions.config.openshift.io \
    --as=system:serviceaccount:openshift-monitoring:configure-alertmanager-operator
yes

# Both ClusterRoles exist and have correct rules
$ oc get clusterrole configure-alertmanager-operator-view -o yaml
# Shows: nodes, clusterversions, proxies, infrastructures permissions ✓

$ oc get clusterrole configure-alertmanager-operator-edit -o yaml
# Shows: secrets, configmaps, jobs permissions ✓

# Both ClusterRoleBindings correctly bind to operator SA
$ oc get clusterrolebinding configure-alertmanager-operator-view -o yaml
subjects:
- kind: ServiceAccount
  name: configure-alertmanager-operator
  namespace: openshift-monitoring  ✓

$ oc get clusterrolebinding configure-alertmanager-operator-edit -o yaml
subjects:
- kind: ServiceAccount
  name: configure-alertmanager-operator
  namespace: openshift-monitoring  ✓
```

## What's Actually Missing?

After thorough investigation: **Nothing is missing from RBAC perspective.**

The issue is likely:
1. **API Discovery ClusterRoleBinding** - The operator SA might not have system:discovery or system:basic-user
2. **Client Auth Configuration** - The operator code might have an issue with how it's reading the SA token
3. **API Server Connection** - There might be a network/connection issue to the API server

### Next Debugging Steps:

1. Check if operator SA has basic authenticated user permissions:
   ```bash
   oc get clusterrolebinding system:basic-user -o yaml | grep -A5 subjects
   ```

2. Verify the operator is using in-cluster config (not looking for kubeconfig file)

3. Check operator code's client initialization (main.go around line 118)

4. Test if operator can access discovery endpoints:
   ```bash
   # Create a debug pod with same SA
   oc debug deployment/configure-alertmanager-operator \
     --as-user=1001 -- curl -k -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     https://kubernetes.default.svc/apis
   ```

## Summary

- ✅ **Role and RoleBinding**: Created correctly in openshift-monitoring namespace
- ✅ **ClusterRole `-view`**: Created with correct permissions (nodes, clusterversions, proxies, infrastructures)
- ✅ **ClusterRole `-edit`**: Created with correct permissions (secrets, configmaps, jobs)
- ✅ **ClusterRoleBinding `-view`**: Correctly binds `-view` ClusterRole to operator SA
- ✅ **ClusterRoleBinding `-edit`**: Correctly binds `-edit` ClusterRole to operator SA
- ❌ **Operator Authentication**: Something wrong with how operator authenticates to API server (not RBAC)

The PKO migration did **exactly what it should have** - it migrated the RBAC correctly from deploy/01_role.yaml. The operator failure is due to an authentication issue, not missing RBAC resources.
