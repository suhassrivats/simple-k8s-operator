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

### How Your Operators Use etcd

```
You create CR → API Server → etcd → Operator watches → Reconciles → Creates resources → etcd
```

Your operators watch:
- `/registry/demo.mycompany.com/configmapapps/`
- `/registry/demo.mycompany.com/simpleapps/`

When you create or update a custom resource:
1. Change is written to etcd
2. Operator receives watch event
3. Operator reconciles desired state
4. Operator creates/updates Deployments, ConfigMaps, etc.
5. Those resources also stored in etcd

## 📚 Learn More

For comprehensive documentation, tutorials, and advanced topics, see the `docs/` directory (to be added).

## 🛠️ Troubleshooting

### Operator not responding?
```bash
# 1. Check if change reached etcd
./scripts/etcd-explorer.sh custom

# 2. Watch for events  
./scripts/etcd-explorer.sh watch /registry/demo.mycompany.com

# 3. Check operator logs
kubectl logs <operator-pod>
```

### Resource not found?
```bash
# Search for it
./scripts/etcd-explorer.sh search <resource-name>
```

## 📖 Help

```bash
./scripts/etcd-explorer.sh help
```

---

*These tools help you understand the deep internals of Kubernetes and how operators interact with etcd.*
