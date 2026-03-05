## Kubernetes Troubleshooting Cheat Sheet


| Issue / Symptom                                 | Likely Resource / Layer            | Commands to Investigate                                                              |
| ----------------------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------ |
| Pod stuck in **Pending**                        | Scheduler / Node capacity / Taints | `kubectl get pods`  `kubectl describe pod <pod>`  `kubectl get nodes`                |
| **CrashLoopBackOff**                            | Application crash / bad config     | `kubectl logs <pod>`  `kubectl logs --previous <pod>`  `kubectl describe pod`        |
| **ImagePullBackOff**                            | Container image / registry auth    | `kubectl describe pod`  `kubectl get secrets`                                        |
| Pod stuck in **ContainerCreating**              | Volume mount / CNI / image pull    | `kubectl describe pod`                                                               |
| Pod **OOMKilled**                               | Memory limits too low              | `kubectl describe pod`  `kubectl top pod`                                            |
| Pod restarting frequently                       | Application issue / liveness probe | `kubectl logs`  `kubectl describe pod`                                               |
| Pod **Running but service unreachable**         | Service / networking               | `kubectl get svc`  `kubectl get endpoints`                                           |
| Service has **no endpoints**                    | Label mismatch                     | `kubectl get svc`  `kubectl get pods --show-labels`                                  |
| DNS resolution failing                          | CoreDNS                            | `kubectl get pods -n kube-system`  `kubectl logs -n kube-system -l k8s-app=kube-dns` |
| Pod cannot reach another pod                    | CNI / Network policy               | `kubectl get networkpolicy`                                                          |
| External traffic not reaching cluster           | Ingress / Load balancer            | `kubectl get ingress`  `kubectl describe ingress`                                    |
| Node **NotReady**                               | Kubelet / resource pressure        | `kubectl describe node`                                                              |
| Node under **MemoryPressure**                   | Resource exhaustion                | `kubectl top nodes`                                                                  |
| Node under **DiskPressure**                     | Disk full                          | `df -h` on node                                                                      |
| Scheduling failure: **Insufficient CPU/memory** | Cluster capacity                   | `kubectl describe pod`  `kubectl top nodes`                                          |
| Deployment rollout stuck                        | ReplicaSet / readiness probe       | `kubectl rollout status deployment`                                                  |
| Pod failing **readiness probe**                 | Application health check           | `kubectl describe pod`                                                               |
| PVC stuck in **Pending**                        | StorageClass / volume provisioner  | `kubectl get pvc`  `kubectl describe pvc`                                            |
| Persistent volume mount failure                 | Storage backend                    | `kubectl describe pod`                                                               |
| High cluster CPU usage                          | Noisy pod / workload spike         | `kubectl top pods -A`                                                                |
| API calls slow                                  | API server / etcd                  | `kubectl get componentstatuses`                                                      |
| Cluster DNS slow                                | CoreDNS overloaded                 | `kubectl top pod -n kube-system`                                                     |
| Pod network latency                             | CNI plugin issue                   | `kubectl get pods -n kube-system`                                                    |
| Container cannot reach internet                 | NAT / egress rules                 | Test via debug pod                                                                   |


## Troubleshooting Flow

```
User request
↓
Ingress
↓
Service
↓
Pod
↓
Container
↓
Node
↓
Network
↓
Control Plane
↓
Cloud Infrastructure
```

Below is a **Principal/Senior SRE Kubernetes Troubleshooting Matrix**. This is the kind of **structured mental model** engineers at companies like Google, Meta, and Netflix use during incidents.

It maps **production symptoms → probable root cause → commands to confirm**.

---

# Principal SRE Kubernetes Troubleshooting Matrix

| Symptom                               | Likely Layer     | Possible Root Cause               | Commands to Check                                   |
| ------------------------------------- | ---------------- | --------------------------------- | --------------------------------------------------- |
| Pod stuck **Pending**                 | Scheduler / Node | Insufficient CPU or memory        | `kubectl describe pod`                              |
| Pod stuck **Pending**                 | Scheduler        | Node selector mismatch            | `kubectl get nodes --show-labels`                   |
| Pod stuck **Pending**                 | Scheduler        | Taints without tolerations        | `kubectl describe node`                             |
| Pod stuck **ContainerCreating**       | Storage          | Volume mount failure              | `kubectl describe pod`                              |
| Pod stuck **ContainerCreating**       | Network          | CNI initialization delay          | `kubectl get pods -n kube-system`                   |
| **CrashLoopBackOff**                  | Application      | App crashing on startup           | `kubectl logs`                                      |
| **CrashLoopBackOff**                  | Config           | Missing environment variables     | `kubectl describe pod`                              |
| **ImagePullBackOff**                  | Registry         | Wrong image name or tag           | `kubectl describe pod`                              |
| **ImagePullBackOff**                  | Registry         | Registry authentication issue     | `kubectl get secrets`                               |
| Pod restarting frequently             | Application      | Bad liveness probe                | `kubectl describe pod`                              |
| Pod running but **not ready**         | Readiness probe  | Service dependency not ready      | `kubectl describe pod`                              |
| Service unreachable                   | Service          | Selector mismatch                 | `kubectl get svc`, `kubectl get pods --show-labels` |
| Service unreachable                   | Service          | Endpoints not created             | `kubectl get endpoints`                             |
| Pod cannot reach another pod          | Networking       | Network policy blocking traffic   | `kubectl get networkpolicy`                         |
| DNS lookup failing                    | DNS              | CoreDNS down                      | `kubectl get pods -n kube-system`                   |
| DNS lookup failing                    | DNS              | CoreDNS misconfiguration          | `kubectl logs -n kube-system -l k8s-app=kube-dns`   |
| External traffic not reaching service | Ingress          | Ingress misconfiguration          | `kubectl describe ingress`                          |
| External traffic failing              | Load Balancer    | Cloud LB provisioning issue       | `kubectl get svc`                                   |
| Node becomes **NotReady**             | Node             | kubelet crashed                   | `systemctl status kubelet`                          |
| Node becomes **NotReady**             | Node             | Network failure                   | `kubectl describe node`                             |
| Node under **MemoryPressure**         | Node             | Memory exhaustion                 | `kubectl top nodes`                                 |
| Node under **DiskPressure**           | Node             | Disk full                         | `df -h`                                             |
| Pods getting **OOMKilled**            | Resource         | Memory limit too low              | `kubectl describe pod`                              |
| High pod CPU                          | Application      | Infinite loop or workload spike   | `kubectl top pods`                                  |
| Deployment rollout stuck              | Deployment       | Readiness probe failing           | `kubectl rollout status deployment`                 |
| Deployment stuck                      | ReplicaSet       | ReplicaSet not scaling            | `kubectl get rs`                                    |
| PVC stuck **Pending**                 | Storage          | StorageClass missing              | `kubectl get storageclass`                          |
| PVC stuck **Pending**                 | Storage          | Cloud volume provisioning failure | `kubectl describe pvc`                              |
| Pod network latency                   | CNI              | CNI plugin failure                | `kubectl get pods -n kube-system`                   |
| Cluster API slow                      | Control Plane    | API server overloaded             | `kubectl get componentstatuses`                     |
| Cluster API errors                    | Control Plane    | etcd latency                      | `etcdctl endpoint health`                           |
| Cluster-wide DNS slow                 | DNS              | CoreDNS CPU saturation            | `kubectl top pods -n kube-system`                   |
| Pod cannot access internet            | Networking       | NAT / egress rules                | test via debug pod                                  |
| Random pod communication failures     | Networking       | MTU mismatch                      | packet capture                                      |

---

# Critical Debugging Commands

### Cluster health

```bash
kubectl get nodes
kubectl get pods -A
```

### Pod debugging

```bash
kubectl describe pod <pod>
kubectl logs <pod>
kubectl logs --previous <pod>
```

### Networking debugging

```bash
kubectl get svc
kubectl get endpoints
kubectl get networkpolicy
```

### Resource debugging

```bash
kubectl top nodes
kubectl top pods -A
```

### Deployment debugging

```bash
kubectl rollout status deployment <name>
kubectl get rs
```

### Storage debugging

```bash
kubectl get pvc
kubectl describe pvc
```

---

# Debug Pod (Extremely Useful)

Create a temporary pod to test networking.

```bash
kubectl run debug --rm -it --image=nicolaka/netshoot -- bash
```

Tools available:

```
curl
dig
nslookup
tcpdump
ping
traceroute
netstat
```

---

# Senior SRE Troubleshooting Strategy

| Layer         | What to Check            |
| ------------- | ------------------------ |
| User          | Request latency / errors |
| Ingress       | Routing                  |
| Service       | Endpoints                |
| Pod           | Status / logs            |
| Container     | Application              |
| Node          | CPU / memory / disk      |
| Network       | CNI / policies           |
| Control Plane | API server / etcd        |

