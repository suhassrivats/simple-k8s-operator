# etcd Deep Dive

Comprehensive resources for understanding how etcd works in your Kubernetes cluster and how your operators interact with it.

## 🚀 Quick Start

```bash
# Check cluster health
./scripts/etcd-explorer.sh status

# List your custom resources
./scripts/etcd-explorer.sh custom

# Watch changes in real-time
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com
```

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

---

*These tools help you understand the deep internals of Kubernetes and how operators interact with etcd.*
