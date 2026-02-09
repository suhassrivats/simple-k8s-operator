# etcd Deep Dive

Comprehensive resources for understanding how etcd works in your Kubernetes cluster and how your operators interact with it.

## 📑 Table of Contents

- [Quick Start](#-quick-start) - Get started in 30 seconds
- [Common Commands](#-common-commands) - etcd-explorer.sh usage
- [Understanding etcd](#-understanding-etcd) - Core concepts
  - [Revision System Deep Dive](#deep-dive-etcds-revision-system) - Counters explained
  - [Update Mechanism](#what-happens-during-an-update) - Step-by-step trace
  - [MVCC in Action](#mvcc-in-action) - Time travel and history
- [Direct etcd Access](#-accessing-etcd-directly) - Using etcdctl
- [Inspecting Revisions](#-inspecting-revisions-and-versions) - Hands-on experiments
- [Troubleshooting](#️-troubleshooting) - Debug like a pro
- [Quick Reference](#-quick-reference-card) - Cheat sheet

## 🚀 Quick Start

```bash
# Check cluster health
./scripts/etcd-explorer.sh status

# List your custom resources
./scripts/etcd-explorer.sh custom

# Watch changes in real-time
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com
```

## 📁 What You'll Learn

This guide covers:
- ✅ **etcd fundamentals** - How Kubernetes stores all its state
- ✅ **Revision system** - Understanding version counters and MVCC
- ✅ **Direct access** - Using etcdctl for advanced debugging
- ✅ **Operator integration** - How your custom operators interact with etcd
- ✅ **Troubleshooting** - Debug issues using revision tracking
- ✅ **Practical examples** - Hands-on experiments and real-world scenarios

## 📁 Structure

```
etcd-deep-dive/
├── scripts/           # Interactive exploration tools
│   └── etcd-explorer.sh
└── docs/              # Documentation (to be added)
```

## 🔍 Common Commands

### Cluster Information
```bash
./scripts/etcd-explorer.sh status      # Health and status
./scripts/etcd-explorer.sh members     # Cluster members
./scripts/etcd-explorer.sh size        # Database size
```

### Data Exploration
```bash
./scripts/etcd-explorer.sh list        # List all keys
./scripts/etcd-explorer.sh count       # Count by type
./scripts/etcd-explorer.sh get <key>   # Get specific key
./scripts/etcd-explorer.sh search <pattern>  # Search keys
```

### Custom Resources
```bash
./scripts/etcd-explorer.sh custom              # All custom resources
./scripts/etcd-explorer.sh custom configmapapps  # Specific type
```

### Real-Time Watching
```bash
# Terminal 1: Watch for changes
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com/configmapapps

# Terminal 2: Make a change
kubectl patch configmapapp my-nginx-app -p '{"spec":{"replicas":5}}'
# → See it appear instantly in Terminal 1!
```

## 💡 Understanding etcd

**etcd** is Kubernetes' distributed key-value store that serves as the source of truth for all cluster state.

### Key Concepts

1. **Storage Location**: All resources stored at `/registry/<type>/<namespace>/<name>`
2. **Watch Mechanism**: Operators subscribe to changes via watches
3. **MVCC**: Multi-Version Concurrency Control tracks all changes
4. **Raft Consensus**: Ensures distributed consistency

### Deep Dive: etcd's Revision System

etcd uses a sophisticated versioning system to track every change in the cluster. Understanding this is crucial for debugging and monitoring.

#### The Three Counters

Every key in etcd has three important version numbers:

1. **Cluster Revision (Global Counter)**
   - A global, monotonically increasing counter for the **entire etcd cluster**
   - Increments by 1 for **every write operation** (create, update, delete)
   - Never resets (except during compaction)
   - Used by watches to resume from a specific point in history
   - Example: If cluster revision is 1000, the next write makes it 1001

2. **ModRevision (Key's Last Modified Revision)**
   - The cluster revision when this specific key was **last modified**
   - Updates every time the key changes
   - Used to detect if a key has changed since you last read it
   - Example: Key created at revision 100, updated at 500 → ModRevision = 500

3. **Version (Key's Update Counter)**
   - How many times **this specific key** has been updated
   - Starts at 1 when key is created
   - Increments by 1 for each update to this key
   - Resets to 1 if key is deleted and recreated
   - Example: Key created (v1), updated twice (v2, v3) → Version = 3

#### What Happens During an Update

Let's trace what happens when you update a Kubernetes resource:

```bash
kubectl patch configmapapp my-app -p '{"spec":{"replicas":5}}'
```

**Step-by-step process:**

1. **API Server receives request**
   - Validates the patch
   - Checks authentication/authorization
   - Retrieves current state from etcd

2. **Read current state from etcd**
   ```
   Key: /registry/demo.mycompany.com/configmapapps/default/my-app
   Value: <serialized object>
   ModRevision: 1234
   Version: 3
   Cluster Revision: 5000
   ```

3. **API Server applies patch**
   - Merges patch with current object
   - Increments `resourceVersion` in the object metadata
   - Validates the result

4. **Write back to etcd (Compare-and-Swap)**
   - etcd receives the write
   - Increments **Cluster Revision**: 5000 → 5001
   - Updates **ModRevision**: 1234 → 5001
   - Increments **Version**: 3 → 4
   - Commits to Raft log and replicates to cluster

5. **Trigger Watch Events**
   ```
   Event Type: PUT
   Key: /registry/demo.mycompany.com/configmapapps/default/my-app
   Value: <new serialized object>
   ModRevision: 5001
   Version: 4
   ```

6. **Operator receives event**
   - Sees the change at revision 5001
   - Extracts new desired state
   - Reconciles: creates/updates child resources

7. **Child resources created**
   - Each child resource write increments cluster revision
   - Deployment created: Cluster Revision → 5002
   - ConfigMap created: Cluster Revision → 5003
   - Service created: Cluster Revision → 5004

#### MVCC in Action

**Multi-Version Concurrency Control** means etcd keeps a history of all changes:

```
Cluster Rev 100: Key "my-app" created, Version 1, Value "replicas: 3"
Cluster Rev 250: Key "my-app" updated, Version 2, Value "replicas: 5"
Cluster Rev 400: Key "my-app" updated, Version 3, Value "replicas: 7"
Cluster Rev 600: Key "my-app" updated, Version 4, Value "replicas: 10"
```

**Benefits:**
- **Time Travel**: You can query etcd at any past revision
  ```bash
  # Get value as it was at revision 250
  etcdctl get /registry/... --rev=250
  ```
- **Watch Resume**: If operator crashes, it can resume watching from its last seen revision
  ```bash
  # Start watching from revision 400 onwards
  etcdctl watch /registry/... --rev=400
  ```
- **Conflict Detection**: Compare ModRevision to detect concurrent modifications
- **Audit Trail**: See complete history of changes

#### Compaction and History

etcd doesn't keep history forever:

```bash
# Before compaction
Revisions: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 (current)
           ↑__________________|  (can access all)

# After compaction at revision 5
Revisions: [compacted] → 5 → 6 → 7 → 8 (current)
                         ↑________|  (can only access 5+)
```

- **Automatic Compaction**: Kubernetes API server compacts old revisions
- **Default**: Keep 5 minutes of history or 30000 revisions
- **Why**: Save disk space and improve performance
- **Impact**: Can't query revisions older than compaction point

#### Practical Examples

**Example 1: Detecting Stale Reads**
```bash
# Read 1: Get current state
ModRevision: 1000, Version: 5

# Someone else updates the key
# Cluster revision now 1001

# Read 2: Try to update based on stale data
# etcd will reject if you provide old ModRevision
```

**Example 2: Watch Continuity**
```bash
# Operator watching from revision 500
# Operator crashes after processing revision 550
# Operator restarts and resumes from 551
# No events missed!
```

**Example 3: Debugging "Resource Not Found"**
```bash
# Check if resource was deleted recently
./scripts/etcd-explorer.sh watch /registry/.../my-resource --rev=<old-revision>
# You might see it existed in the past
```

### How Your Operators Use etcd

```
You create CR → API Server → etcd → Operator watches → Reconciles → Creates resources → etcd
```

Your operators watch:
- `/registry/demo.mycompany.com/configmapapps/`
- `/registry/demo.mycompany.com/simpleapps/`

When you create or update a custom resource:
1. **Change written to etcd**
   - Cluster revision increments (e.g., 1000 → 1001)
   - Key's ModRevision set to new cluster revision
   - Key's Version increments (e.g., 3 → 4)

2. **Operator receives watch event**
   - Event includes ModRevision (1001) and new state
   - Operator stores this revision for crash recovery
   - Extracts desired state from the event

3. **Operator reconciles desired state**
   - Compares desired state with actual state
   - Determines what needs to change
   - May use ModRevision for optimistic locking

4. **Operator creates/updates child resources**
   - Each operation increments cluster revision
   - Example: Deployment (1002), ConfigMap (1003), Service (1004)
   - All changes are atomic and tracked

5. **Resources stored in etcd with full versioning**
   - Each resource has its own Version counter
   - All tied together by cluster revision timeline
   - Operator can watch child resources for their changes too

**Key Benefits for Operators:**
- **Reliability**: Can resume watching from last processed revision
- **Consistency**: ModRevision prevents race conditions
- **Debugging**: Full audit trail of what changed and when
- **Performance**: Only notified of actual changes via watches

## 📚 Learn More

For comprehensive documentation, tutorials, and advanced topics, see the `docs/` directory (to be added).

## 🔌 Accessing etcd Directly

While the `etcd-explorer.sh` script provides convenience, you can also access etcd directly using `etcdctl`. This is useful for advanced debugging and understanding the raw data.

### Prerequisites

etcd in Kubernetes requires TLS authentication. You'll need:
- CA certificate
- Client certificate  
- Client key

### Access etcd Pod

```bash
# Find etcd pod (for kubeadm clusters)
kubectl get pods -n kube-system | grep etcd

# Shell into etcd pod
kubectl exec -it -n kube-system etcd-<node-name> -- sh

# Or for single-node clusters
kubectl exec -it -n kube-system $(kubectl get pods -n kube-system -l component=etcd -o name | head -1) -- sh
```

### Set etcdctl Environment Variables

```bash
# Inside etcd pod, set these variables
export ETCDCTL_API=3
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379

# Or set them inline (if not in pod)
alias etcdctl='kubectl exec -it -n kube-system <etcd-pod> -- etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  --endpoints=https://127.0.0.1:2379'
```

### Basic etcdctl Commands

#### Cluster Health and Status
```bash
# Check cluster health
etcdctl endpoint health
# Output: 127.0.0.1:2379 is healthy: successfully committed proposal

# Get cluster status
etcdctl endpoint status --write-out=table
# Shows: Endpoint, ID, Version, DB Size, Leader, Raft Term, Raft Index

# List cluster members
etcdctl member list --write-out=table
```

#### Reading Keys

```bash
# Get a specific key
etcdctl get /registry/configmaps/default/my-configmap

# Get with metadata (shows ModRevision, Version, etc.)
etcdctl get /registry/configmaps/default/my-configmap -w json | jq

# Get all keys with a prefix
etcdctl get /registry/configmaps/ --prefix

# Get only keys (not values)
etcdctl get /registry/configmaps/ --prefix --keys-only

# Count keys with prefix
etcdctl get /registry/configmaps/ --prefix --keys-only | wc -l

# Get key at specific revision (time travel!)
etcdctl get /registry/configmaps/default/my-configmap --rev=1000
```

#### Listing and Searching

```bash
# List all keys in Kubernetes registry
etcdctl get /registry/ --prefix --keys-only

# Search for specific resource
etcdctl get /registry/ --prefix --keys-only | grep "my-resource"

# List all custom resources
etcdctl get /registry/demo.mycompany.com/ --prefix --keys-only

# Count resources by type
etcdctl get /registry/deployments/ --prefix --keys-only | wc -l
etcdctl get /registry/pods/ --prefix --keys-only | wc -l
etcdctl get /registry/configmaps/ --prefix --keys-only | wc -l
```

#### Watching for Changes

```bash
# Watch a specific key
etcdctl watch /registry/configmaps/default/my-configmap

# Watch all keys with prefix
etcdctl watch /registry/demo.mycompany.com/configmapapps/ --prefix

# Watch from specific revision
etcdctl watch /registry/configmaps/ --prefix --rev=5000

# Watch with JSON output for parsing
etcdctl watch /registry/configmaps/ --prefix -w json

# Interactive watch (shows PUT/DELETE events in real-time)
etcdctl watch /registry/ --prefix
```

#### Revision and Version Information

```bash
# Get current cluster revision
etcdctl endpoint status --write-out=table | awk 'NR==2 {print $5}'

# Get key with full metadata
etcdctl get /registry/configmaps/default/my-cm -w json | jq '{
  key: .kvs[0].key | @base64d,
  create_revision: .kvs[0].create_revision,
  mod_revision: .kvs[0].mod_revision,
  version: .kvs[0].version,
  lease: .kvs[0].lease
}'

# Get multiple keys with metadata
etcdctl get /registry/configmaps/ --prefix --limit=5 -w json | jq -r '
  .kvs[] | "\(.key | @base64d) | Rev:\(.mod_revision) | Ver:\(.version)"
'
```

#### Database Management

```bash
# Check database size
etcdctl endpoint status --write-out=table

# Get detailed DB size
du -sh /var/lib/etcd

# Check compaction revision
etcdctl endpoint status -w json | jq '.[] | .Status.dbSize, .Status.raftAppliedIndex'

# Compact to specific revision (careful!)
# This removes history before revision 5000
etcdctl compact 5000

# Defragment database (reclaim space after compaction)
etcdctl defrag

# Check alarm status (disk space issues)
etcdctl alarm list
```

#### Advanced Queries

```bash
# Get all pods in a namespace
etcdctl get /registry/pods/default/ --prefix --keys-only

# Get all resources of a specific API group
etcdctl get /registry/demo.mycompany.com/ --prefix --keys-only

# Watch for deletions only
etcdctl watch /registry/configmaps/ --prefix | grep DELETE

# Get key range
etcdctl get /registry/configmaps/default/a /registry/configmaps/default/z

# Get last N keys
etcdctl get /registry/configmaps/ --prefix --limit=10 --order=DESCEND --sort-by=MODIFY

# Get keys modified after specific revision
etcdctl get /registry/ --prefix --rev=5000 | \
  etcdctl get /registry/ --prefix --rev=5100 | diff - -
```

### Decode Kubernetes Objects

etcd stores Kubernetes objects in protobuf format. To decode:

```bash
# Get raw value
etcdctl get /registry/configmaps/default/my-cm --print-value-only > /tmp/cm.pb

# Kubernetes API server can decode it, but raw etcd data is protobuf
# For human-readable output, use kubectl instead:
kubectl get configmap my-cm -o yaml

# Or decode using protoc (if you have proto definitions)
protoc --decode_raw < /tmp/cm.pb
```

### Practical Examples

#### Example 1: Find Who's Using Disk Space
```bash
# Count keys by resource type
for type in pods deployments configmaps secrets services; do
  count=$(etcdctl get /registry/$type/ --prefix --keys-only 2>/dev/null | wc -l)
  echo "$type: $count"
done
```

#### Example 2: Track Operator's Resource Creation
```bash
# Watch custom resources and their children
etcdctl watch /registry/demo.mycompany.com/configmapapps/ --prefix &
etcdctl watch /registry/deployments/default/ --prefix &
etcdctl watch /registry/configmaps/default/ --prefix &

# Now create a custom resource and see the cascade
```

#### Example 3: Debug Stale Reads
```bash
# Get current revision
CURRENT_REV=$(etcdctl endpoint status -w json | jq -r '.[0].Status.header.revision')
echo "Current revision: $CURRENT_REV"

# Get resource at current revision
etcdctl get /registry/configmaps/default/my-cm --rev=$CURRENT_REV

# Get resource at older revision
OLD_REV=$((CURRENT_REV - 100))
etcdctl get /registry/configmaps/default/my-cm --rev=$OLD_REV
```

#### Example 4: Monitor Cluster Activity
```bash
# Check how fast revisions are growing
REV1=$(etcdctl endpoint status -w json | jq -r '.[0].Status.header.revision')
sleep 60
REV2=$(etcdctl endpoint status -w json | jq -r '.[0].Status.header.revision')
echo "Revisions per minute: $((REV2 - REV1))"
```

### ⚠️ WARNING: Write Operations

**DO NOT** perform write operations on etcd directly unless you know exactly what you're doing!

```bash
# ❌ DANGEROUS - Don't do this!
etcdctl put /registry/configmaps/default/my-cm "..."

# ❌ DANGEROUS - Can corrupt cluster state!
etcdctl del /registry/pods/default/my-pod

# ✅ SAFE - Always use kubectl for modifications
kubectl delete pod my-pod
kubectl apply -f resource.yaml
```

Writing directly to etcd bypasses:
- Kubernetes validation
- Admission webhooks
- RBAC authorization
- Audit logging
- API server logic

**Only use writes for:**
- Disaster recovery (with expert guidance)
- Removing stuck finalizers (as last resort)
- Advanced debugging (development clusters only)

### Remote Access (Outside Cluster)

```bash
# Port-forward etcd (be careful with this!)
kubectl port-forward -n kube-system etcd-<node-name> 2379:2379

# In another terminal, use etcdctl locally (requires certs)
etcdctl --endpoints=https://localhost:2379 \
  --cacert=./ca.crt \
  --cert=./client.crt \
  --key=./client.key \
  get /registry/configmaps/default/my-cm
```

## 🔬 Inspecting Revisions and Versions

Want to see these counters in action? Here's how:

### View Revision Information
```bash
# Get a key with full metadata
./scripts/etcd-explorer.sh get /registry/demo.mycompany.com/configmapapps/default/my-app

# Output includes:
# - Cluster Revision (current global counter)
# - ModRevision (when this key was last modified)
# - Version (how many times this key was updated)
```

### Watch Changes with Revisions
```bash
# Watch and see revisions increment in real-time
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com/configmapapps/

# Each event shows:
# - Event type (PUT/DELETE)
# - Key path
# - ModRevision (new revision number)
# - Version (key's version counter)
```

### Understanding resourceVersion in Kubernetes
```bash
# In Kubernetes, resourceVersion maps to etcd's ModRevision
kubectl get configmapapp my-app -o yaml | grep resourceVersion

# This is the ModRevision from etcd!
# resourceVersion: "5001" means ModRevision: 5001
```

### Practical Experiment

Try this to see revisions in action:

```bash
# Terminal 1: Watch the etcd changes
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com/configmapapps/

# Terminal 2: Make changes and observe
kubectl patch configmapapp my-app -p '{"spec":{"replicas":3}}'
# → See cluster revision increment, Version increment

kubectl patch configmapapp my-app -p '{"spec":{"replicas":5}}'  
# → See cluster revision increment again, Version increment again

kubectl patch configmapapp my-app -p '{"spec":{"replicas":5}}'
# → Even though value is same, still creates an event!
# → Cluster revision still increments
```

## 🛠️ Troubleshooting

### Operator not responding?
```bash
# 1. Check if change reached etcd
./scripts/etcd-explorer.sh custom

# 2. Verify the resource version changed
./scripts/etcd-explorer.sh get /registry/.../my-resource
# Look at ModRevision - did it update?

# 3. Watch for events  
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com
# Are watch events being generated?

# 4. Check operator logs
kubectl logs <operator-pod>
# Look for: "Reconciling at revision X"
```

### Resource not found?
```bash
# Search for it
./scripts/etcd-explorer.sh search <resource-name>

# Check if it was recently deleted
# (if you know an old revision number)
./scripts/etcd-explorer.sh get <key> --rev=<old-revision>
```

### Changes not taking effect?
```bash
# Compare versions to see if resource is actually changing
# Before change:
kubectl get configmapapp my-app -o yaml | grep resourceVersion
# resourceVersion: "1000"

# After change:
kubectl get configmapapp my-app -o yaml | grep resourceVersion  
# resourceVersion: "1000"  ← SAME? Change didn't go through!
# resourceVersion: "1005"  ← DIFFERENT? Change was written!
```

### Detecting Race Conditions
```bash
# Two operators updating same resource?
# Watch the ModRevision and Version counters

./scripts/etcd-explorer.sh watch /registry/.../my-resource

# If Version increments faster than expected:
# Version 1 → 2 → 3 → 4 (in seconds)
# Multiple controllers might be fighting over the same resource!
```

## 📖 Help

```bash
./scripts/etcd-explorer.sh help
```

## 📋 Quick Reference Card

### etcdctl Cheat Sheet

```bash
# === CLUSTER STATUS ===
etcdctl endpoint health                    # Check health
etcdctl endpoint status -w table          # Cluster status
etcdctl member list -w table              # List members

# === READ OPERATIONS ===
etcdctl get <key>                         # Get specific key
etcdctl get <key> -w json                 # Get with metadata
etcdctl get <key> --rev=1000              # Get at revision 1000
etcdctl get <prefix> --prefix             # Get all with prefix
etcdctl get <prefix> --prefix --keys-only # List keys only
etcdctl get <prefix> --prefix --limit=10  # Limit results

# === WATCH OPERATIONS ===
etcdctl watch <key>                       # Watch key
etcdctl watch <prefix> --prefix           # Watch prefix
etcdctl watch <prefix> --prefix --rev=100 # Watch from revision

# === DATABASE INFO ===
etcdctl endpoint status -w table          # DB size & revision
etcdctl compact <revision>                # Compact to revision
etcdctl defrag                            # Defragment DB
etcdctl alarm list                        # Check alarms

# === COMMON KUBERNETES PATHS ===
/registry/pods/<namespace>/<name>
/registry/deployments/<namespace>/<name>
/registry/configmaps/<namespace>/<name>
/registry/secrets/<namespace>/<name>
/registry/services/<namespace>/<name>
/registry/<apigroup>/<resource>/<namespace>/<name>
```

### Environment Setup

```bash
# Copy-paste this block when accessing etcd pod:
export ETCDCTL_API=3
export ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt
export ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt
export ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key
export ETCDCTL_ENDPOINTS=https://127.0.0.1:2379
```

### One-Liners

```bash
# Current cluster revision
etcdctl endpoint status -w json | jq -r '.[0].Status.header.revision'

# Count all keys
etcdctl get / --prefix --keys-only | wc -l

# Count pods
etcdctl get /registry/pods/ --prefix --keys-only | wc -l

# Database size in MB
etcdctl endpoint status -w json | jq -r '.[0].Status.dbSize / 1024 / 1024'

# List all namespaces
etcdctl get /registry/namespaces/ --prefix --keys-only | sed 's|/registry/namespaces/||'

# Watch all changes (live feed)
etcdctl watch / --prefix

# Get latest modified keys
etcdctl get / --prefix --limit=10 --order=DESCEND --sort-by=MODIFY --keys-only
```

---

*These tools help you understand the deep internals of Kubernetes and how operators interact with etcd.*
