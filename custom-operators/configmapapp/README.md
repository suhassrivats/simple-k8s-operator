# ConfigMapApp Operator

A Kubernetes operator that manages applications requiring configuration data stored in ConfigMaps.

## What It Does

When you create a `ConfigMapApp` custom resource, this operator automatically:
1. Creates a **ConfigMap** with your configuration data
2. Creates a **Deployment** with the specified image and replicas
3. Mounts the ConfigMap into the deployment pods
4. Updates all resources when you modify the CR

## Custom Resource Definition

```yaml
apiVersion: demo.mycompany.com/v1
kind: ConfigMapApp
metadata:
  name: my-app
spec:
  image: nginx                    # Container image
  replicas: 3                     # Number of replicas
  configData:                     # Configuration key-value pairs
    app.conf: "server { listen 80; }"
    database.conf: "host=localhost"
```

## Quick Start

### 1. Install the CRD

```bash
kubectl apply -f crd.yml
```

### 2. Run the Operator

```bash
# Make sure you have dependencies installed
pip install kopf kubernetes

# Run the operator
kopf run operator.py
```

### 3. Create a ConfigMapApp

```bash
kubectl apply -f examples/sample-cr.yml
```

### 4. Verify

```bash
# Check the custom resource
kubectl get configmapapp

# Check created resources
kubectl get deployments
kubectl get configmaps
kubectl get pods
```

## How It Works

### Architecture

```
┌─────────────────────────┐
│  ConfigMapApp CR        │
│  (Your desired state)   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  Operator watches       │
│  (kopf framework)       │
└───────────┬─────────────┘
            │
            ├──────────────────────┐
            ▼                      ▼
┌─────────────────────┐  ┌──────────────────┐
│  ConfigMap          │  │  Deployment      │
│  (config data)      │  │  (app replicas)  │
└──────────┬──────────┘  └────────┬─────────┘
           │                      │
           └──────────┬───────────┘
                      ▼
              ┌──────────────┐
              │    Pods      │
              │  (running)   │
              └──────────────┘
```

### Event Handlers

The operator uses kopf decorators to handle events:

- **`@kopf.on.create`**: When a ConfigMapApp is created
  - Creates ConfigMap with configuration data
  - Creates Deployment with the ConfigMap mounted
  
- **`@kopf.on.update`**: When a ConfigMapApp is modified
  - Updates ConfigMap if `configData` changed
  - Updates Deployment if `image` or `replicas` changed
  
- **`@kopf.on.delete`**: When a ConfigMapApp is deleted
  - Resources auto-deleted via owner references

## Examples

### Basic Nginx App

```yaml
apiVersion: demo.mycompany.com/v1
kind: ConfigMapApp
metadata:
  name: my-nginx
spec:
  image: nginx
  replicas: 2
  configData:
    nginx.conf: |
      server {
        listen 80;
        location / {
          return 200 "Hello from ConfigMapApp!";
        }
      }
```

### Python App with Multiple Configs

```yaml
apiVersion: demo.mycompany.com/v1
kind: ConfigMapApp
metadata:
  name: python-api
spec:
  image: python:3.9
  replicas: 3
  configData:
    app.py: |
      from flask import Flask
      app = Flask(__name__)
      
      @app.route('/')
      def hello():
          return "Hello World!"
    config.json: |
      {
        "database": "postgresql://localhost:5432/mydb",
        "debug": false
      }
```

## Configuration

### ConfigMap Naming

The operator creates a ConfigMap with the name:
```
<configmapapp-name>-configmap
```

Example: `my-nginx` → `my-nginx-configmap`

### Deployment Naming

The operator creates a Deployment with the name:
```
<configmapapp-name>-deployment
```

Example: `my-nginx` → `my-nginx-deployment`

### Volume Mount

The ConfigMap is mounted at `/config` inside the pods:
```
/config/
  ├── nginx.conf
  ├── config.json
  └── ... (all keys from configData)
```

## Updating Resources

### Change Replicas

```bash
kubectl patch configmapapp my-nginx -p '{"spec":{"replicas":5}}'
```

The operator will update the Deployment automatically.

### Change Configuration

```bash
kubectl edit configmapapp my-nginx
# Modify configData section
```

The operator will update the ConfigMap. **Note**: Pods may need restart to pick up new config.

### Change Image

```bash
kubectl patch configmapapp my-nginx -p '{"spec":{"image":"nginx:alpine"}}'
```

The operator will update the Deployment, triggering a rolling update.

## Debugging

### Check Operator Logs

The operator runs in your terminal, showing all events:
```
[2024-02-09 12:34:56] ConfigMapApp my-nginx created
[2024-02-09 12:34:56] Creating ConfigMap my-nginx-configmap
[2024-02-09 12:34:56] Creating Deployment my-nginx-deployment
```

### Check Custom Resource

```bash
kubectl get configmapapp my-nginx -o yaml
kubectl describe configmapapp my-nginx
```

### Check Created Resources

```bash
# ConfigMap
kubectl get configmap my-nginx-configmap -o yaml

# Deployment
kubectl get deployment my-nginx-deployment -o yaml

# Pods
kubectl get pods -l app=my-nginx
```

### Explore in etcd

```bash
# See how it's stored in etcd
cd ../../etcd-deep-dive
./scripts/etcd-explorer.sh get /registry/demo.mycompany.com/configmapapps/default/my-nginx

# Watch changes in real-time
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com/configmapapps
```

## Cleanup

### Delete a ConfigMapApp

```bash
kubectl delete configmapapp my-nginx
```

This automatically deletes the ConfigMap and Deployment (via owner references).

### Uninstall the CRD

```bash
kubectl delete -f crd.yml
```

**Warning**: This deletes all ConfigMapApp resources in the cluster.

## Code Structure

```python
@kopf.on.create('demo.mycompany.com', 'v1', 'configmapapps')
def create_fn(spec, name, namespace, **kwargs):
    # Create ConfigMap
    # Create Deployment
    # Set owner references

@kopf.on.update('demo.mycompany.com', 'v1', 'configmapapps')
def update_fn(spec, name, namespace, **kwargs):
    # Update ConfigMap if changed
    # Update Deployment if changed

@kopf.on.delete('demo.mycompany.com', 'v1', 'configmapapps')
def delete_fn(spec, name, namespace, **kwargs):
    # Cleanup handled by owner references
```

## Requirements

- Python 3.7+
- kopf
- kubernetes

```bash
pip install kopf kubernetes
```

## Limitations

- ConfigMap mounted at fixed path `/config`
- No support for secrets (use ConfigMaps only)
- No support for environment variables from ConfigMap
- Pods don't automatically restart when ConfigMap changes

## Future Enhancements

- [ ] Support for Secrets
- [ ] Configurable mount path
- [ ] Environment variables from ConfigMap
- [ ] Automatic pod restart on config changes
- [ ] Service creation
- [ ] Ingress support

## Learn More

- [Kopf Documentation](https://kopf.readthedocs.io/)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

---

*Part of the simple-k8s-operator project*
