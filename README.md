# Kubernetes Operator Examples

This repository contains example Kubernetes Operators built with Python and Kopf framework to demonstrate CRD, CR, Operator, and Controller concepts.

## Table of Contents
- [Core Concepts](#core-concepts)
- [Examples](#examples)
- [Getting Started](#getting-started)
- [Key Learnings](#key-learnings)

---

## Core Concepts

### 1. CustomResourceDefinition (CRD)

A **CRD** extends Kubernetes API to create custom resource types. It's the **schema/blueprint** that defines a new kind of resource.

**Key Points:**
- Defines the structure and validation rules for custom resources
- Must be installed before creating custom resources
- Name format: `<plural>.<group>` (e.g., `simpleapps.demo.mycompany.com`)

**CRD Structure:**
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: <plural>.<group>    # e.g., simpleapps.demo.mycompany.com
spec:
  group: <group>             # API group (e.g., demo.mycompany.com)
  scope: Namespaced          # or Cluster
  names:
    plural: <plural>         # e.g., simpleapps
    singular: <singular>     # e.g., simpleapp
    kind: <Kind>            # e.g., SimpleApp
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:      # Validation schema
        type: object
        properties:
          spec:             # Your custom fields here
            type: object
            properties:
              # Define your custom fields
```

**Mandatory vs Custom Parts:**

| Component | Type | Description |
|-----------|------|-------------|
| `apiVersion`, `kind` | Mandatory | Identifies this as a CRD |
| `metadata.name` | Mandatory | Must be `<plural>.<group>` |
| `spec.group` | Mandatory | API group for resource |
| `spec.scope` | Mandatory | `Namespaced` or `Cluster` |
| `spec.names` | Mandatory | Plural, singular, kind names |
| `spec.versions` | Mandatory | At least one version required |
| `openAPIV3Schema` | Mandatory | Validation schema (required in v1) |
| `spec.properties.*` | **Custom** | Your application-specific fields |

### 2. Custom Resource (CR)

A **CR** is an **instance** of a CRD - an actual object you create using the custom type.

**Key Points:**
- Must match a CRD's schema
- `metadata.name` should be descriptive of THIS specific instance
- Can create multiple CRs from one CRD

**CR Structure:**
```yaml
apiVersion: <group>/<version>  # From CRD
kind: <Kind>                   # From CRD
metadata:
  name: my-app                 # Descriptive instance name (NOT the CRD name!)
spec:
  # Your custom fields as defined in CRD
```

**Important:** CR name should **NOT** match CRD name!
- ❌ Bad: `name: simpleapps.demo.mycompany.com` (looks like the CRD)
- ✅ Good: `name: my-nginx-app` (describes this instance)

### 3. API Group

An **API Group** is a collection of related resources that provides namespacing and versioning.

**Key Points:**
- Format: Reverse DNS (e.g., `demo.mycompany.com`)
- Prevents naming conflicts globally
- Allows independent versioning
- Part of the full API path: `<group>/<version>/<resource>`

**Example:**
```
demo.mycompany.com/v1/simpleapps
       ↓              ↓      ↓
     group        version  resource
```

**Why Required:**
1. **Conflict Prevention**: Two companies can both have an "App" resource
   - Company A: `apps.companyA.com/v1/App`
   - Company B: `apps.companyB.com/v1/App`
2. **Organization**: Groups related resources together
3. **Versioning**: Independent version management (`v1`, `v2`, `v1beta1`)

### 4. Controller

A **Controller** is a control loop that watches resources and reconciles actual state with desired state.

**Key Points:**
- Watches for resource changes (create, update, delete)
- Implements the "reconciliation loop"
- Core pattern: Observe → Diff → Act
- Built-in examples: Deployment Controller, ReplicaSet Controller

**Reconciliation Loop:**
```
┌─────────────────────────────────────┐
│  Watch Custom Resources (CR)        │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  Read Desired State (CR spec)       │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  Read Actual State (K8s resources)  │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  Calculate Diff                     │
└──────────┬──────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  Reconcile (Create/Update/Delete)   │
└──────────┬──────────────────────────┘
           │
           └───────→ (loop continues)
```

### 5. Operator

An **Operator** is a **Controller + Domain Knowledge**. It automates operational tasks using custom resources.

**Key Points:**
- Controller that understands application-specific logic
- Packages operational knowledge into code
- Uses CRDs to expose application configuration
- Automates Day 1 (installation) and Day 2 (updates, backups, scaling) operations

**Operator = Controller + Domain Logic**

| Component | Responsibility |
|-----------|----------------|
| **Controller** | Watch resources, reconcile state |
| **+ Domain Logic** | Application-specific knowledge (backup strategy, scaling logic, etc.) |
| **= Operator** | Automated operations for an application |

### 6. Labels vs Annotations

Both are key-value pairs attached to resources, but serve different purposes:

| Aspect | Labels | Annotations |
|--------|--------|-------------|
| **Purpose** | Identify and select resources | Store metadata |
| **Queryable** | ✅ Yes (`kubectl get -l app=nginx`) | ❌ No |
| **Selection** | Used by Services, Controllers | Not used for selection |
| **Size Limit** | 63 characters | 256KB total |
| **Use Cases** | Filtering, grouping, selection | Config, docs, tool metadata |

**Labels Example:**
```yaml
metadata:
  labels:
    app: frontend           # For selection
    tier: web              # For filtering
    environment: prod      # For grouping
```

**Annotations Example:**
```yaml
metadata:
  annotations:
    description: "Main web frontend"           # Documentation
    prometheus.io/scrape: "true"               # Tool config
    buildInfo: '{"commit": "abc123"}'          # Metadata
```

**Rule of Thumb:**
- Need to **find/select** resources? → Use **labels**
- Need to **store information about** resources? → Use **annotations**

---

## Examples

### Example 1: SimpleApp Operator

A basic operator that creates Kubernetes Deployments from a simplified custom resource.

**Files:**
- `simpleapp-crd.yml` - CRD definition
- `simpleapp-cr.yml` - Custom resource instance
- `simpleapp-operator.py` - Operator code

**What it does:**
1. You create a `SimpleApp` CR with image and replica count
2. Operator automatically creates a Kubernetes Deployment
3. Updates to the CR update the Deployment

**Custom Resource:**
```yaml
apiVersion: demo.mycompany.com/v1
kind: SimpleApp
metadata:
  name: nginx-app
spec:
  image: nginx
  replicas: 3
```

**Result:** Creates `nginx-app-deployment` with 3 nginx replicas

### Example 2: ConfigMapApp Operator

An advanced operator that creates both ConfigMaps and Deployments with volume mounts.

**Files:**
- `configmapapp-crd.yml` - CRD definition
- `configmapapp-cr.yml` - Custom resource instance
- `configmapapp-operator.py` - Operator code

**What it does:**
1. You create a `ConfigMapApp` CR with image, replicas, and config data
2. Operator creates a ConfigMap with your data
3. Operator creates a Deployment that mounts the ConfigMap at `/etc/config`
4. Updates to config data are reflected in new pods

**Custom Resource:**
```yaml
apiVersion: demo.mycompany.com/v1
kind: ConfigMapApp
metadata:
  name: my-nginx-app
spec:
  image: nginx
  replicas: 2
  configData:
    app.conf: "server { listen 80; }"
    database.conf: "host=localhost"
```

**Result:** 
- Creates ConfigMap with `app.conf` and `database.conf`
- Creates Deployment with configs mounted at `/etc/config/app.conf` and `/etc/config/database.conf`

---

## Getting Started

### Prerequisites

```bash
# Install Python dependencies
pip install kopf kubernetes

# Ensure you have a running Kubernetes cluster
kubectl cluster-info

# Ensure you have minikube or similar cluster
minikube start
```

### Running Example 1: SimpleApp

```bash
# 1. Apply the CRD
kubectl apply -f simpleapp-crd.yml

# 2. Verify CRD is created
kubectl get crds | grep simpleapps

# 3. Run the operator (in a separate terminal)
kopf run simpleapp-operator.py --all-namespaces

# 4. Create a SimpleApp instance
kubectl apply -f simpleapp-cr.yml

# 5. Verify resources
kubectl get simpleapps
kubectl get deployments
kubectl get pods
```

### Running Example 2: ConfigMapApp

```bash
# 1. Apply the CRD
kubectl apply -f configmapapp-crd.yml

# 2. Verify CRD is created
kubectl get crds | grep configmapapps

# 3. Run the operator (in a separate terminal)
kopf run configmapapp-operator.py --all-namespaces

# 4. Create a ConfigMapApp instance
kubectl apply -f configmapapp-cr.yml

# 5. Verify resources
kubectl get configmapapps
kubectl get deployments
kubectl get configmaps
kubectl get pods

# 6. Verify config is mounted
POD_NAME=$(kubectl get pods -l app=my-nginx-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -- ls -la /etc/config
kubectl exec $POD_NAME -- cat /etc/config/key1
```

### Testing Updates

```bash
# Edit the CR
kubectl edit configmapapp my-nginx-app

# Or apply updated yaml
kubectl apply -f configmapapp-cr.yml

# Watch the operator logs to see reconciliation
# Check updated resources
kubectl get deployments
kubectl get configmaps -o yaml
```

### Cleanup

```bash
# Delete custom resources
kubectl delete -f simpleapp-cr.yml
kubectl delete -f configmapapp-cr.yml

# Delete CRDs (this also deletes all CRs)
kubectl delete -f simpleapp-crd.yml
kubectl delete -f configmapapp-crd.yml

# Stop the operators (Ctrl+C in their terminals)
```

---

## Key Learnings

### 1. Naming Conventions

**CRD Name:**
- Format: `<plural>.<group>`
- Example: `simpleapps.demo.mycompany.com`
- Defines the resource TYPE

**CR Name:**
- Format: Descriptive instance name
- Example: `nginx-frontend`, `api-backend`
- Names a specific INSTANCE
- Should **NOT** match CRD name

### 2. Operator Patterns

**Kopf Decorators:**
```python
@kopf.on.create('demo.mycompany.com', 'v1', 'simpleapps')
@kopf.on.update('demo.mycompany.com', 'v1', 'simpleapps')
def reconcile(spec, name, namespace, body, **kwargs):
    # spec: CR spec fields
    # name: CR metadata.name
    # namespace: CR namespace
    # body: Full CR object
    pass
```

**Error Handling:**
```python
try:
    # Try to create resource
    api.create_namespaced_deployment(...)
except client.exceptions.ApiException as e:
    if e.status == 409:  # Conflict - resource exists
        # Update instead
        api.patch_namespaced_deployment(...)
    else:
        raise  # Re-raise other errors
```

### 3. Volume Mounts Pattern

To mount ConfigMaps in Deployments:

```python
deployment = client.V1Deployment(
    spec=client.V1DeploymentSpec(
        template=client.V1PodTemplateSpec(
            spec=client.V1PodSpec(
                # Define volumes
                volumes=[
                    client.V1Volume(
                        name="config-volume",
                        config_map=client.V1ConfigMapVolumeSource(
                            name="my-configmap"
                        )
                    )
                ],
                containers=[
                    client.V1Container(
                        name="app",
                        image="nginx",
                        # Mount volumes
                        volume_mounts=[
                            client.V1VolumeMount(
                                name="config-volume",
                                mount_path="/etc/config"
                            )
                        ]
                    )
                ]
            )
        )
    )
)
```

### 4. CRD Schema Best Practices

**For Simple Key-Value Maps:**
```yaml
configData:
  type: object
  additionalProperties:
    type: string
```

**For Arrays of Objects:**
```yaml
items:
  type: array
  items:
    type: object
    properties:
      key:
        type: string
      value:
        type: string
```

### 5. Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Operator not triggering | Wrong plural in decorator | Use CRD's `spec.names.plural` |
| ConfigMap not found | Name mismatch | Ensure ConfigMap name matches volume reference |
| Field not found in spec | Wrong camelCase/snake_case | Match exact field name from CR |
| CRD validation fails | Schema mismatch | Update CRD schema to match CR structure |

### 6. Testing Checklist

- [ ] CRD applies successfully
- [ ] Operator starts without errors
- [ ] CR creates expected resources
- [ ] Resources have correct configuration
- [ ] Updates to CR trigger reconciliation
- [ ] Resources are updated correctly
- [ ] Deletion cleans up resources (if delete handler exists)

---

## Resources

- [Kopf Documentation](https://kopf.readthedocs.io/)
- [Kubernetes Python Client](https://github.com/kubernetes-client/python)
- [Kubernetes CRD Documentation](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/)
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

---

## Project Structure

```
simple-operator/
├── README.md                      # This file
├── simpleapp-crd.yml             # SimpleApp CRD definition
├── simpleapp-cr.yml              # SimpleApp instance example
├── simpleapp-operator.py         # SimpleApp operator code
├── configmapapp-crd.yml          # ConfigMapApp CRD definition
├── configmapapp-cr.yml           # ConfigMapApp instance example
└── configmapapp-operator.py      # ConfigMapApp operator code
```

---

## Next Steps

1. **Add Delete Handlers**: Implement `@kopf.on.delete` to clean up resources
2. **Add Status Fields**: Update CR status to show deployment health
3. **Add Validation**: Implement admission webhooks for validation
4. **Add Finalizers**: Ensure proper cleanup before CR deletion
5. **Package as Container**: Containerize operators for production deployment

---

**Happy Operating!** 🚀
