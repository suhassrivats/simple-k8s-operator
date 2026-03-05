# Kubernetes CPU and Memory Optimization Guide

Optimizing **CPU and memory in Kubernetes** is a continuous process of balancing **application performance, cluster utilization, and infrastructure cost**.

The goal is to **right-size resource allocations** so workloads receive enough resources to perform well while avoiding wasted capacity.

---

# Core Resource Management Concepts

Kubernetes manages compute resources at the container level using **Resource Requests** and **Resource Limits**.

| Concept               | Description                                      | Behavior                                                |
| --------------------- | ------------------------------------------------ | ------------------------------------------------------- |
| **Resource Requests** | Minimum CPU or memory guaranteed for a container | Used by the **kube-scheduler** to place pods on nodes   |
| **Resource Limits**   | Maximum CPU or memory a container can use        | Prevents a container from consuming excessive resources |

Example configuration:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "1"
    memory: "1Gi"
```

---

# CPU vs Memory Behavior

CPU and memory behave very differently when limits are exceeded.

| Resource   | Behavior When Limit Exceeded                                                   |
| ---------- | ------------------------------------------------------------------------------ |
| **CPU**    | Container is **throttled** (performance slows but container continues running) |
| **Memory** | Container is **OOMKilled** (terminated immediately)                            |

Example OOMKilled message:

```bash
kubectl describe pod <pod>
```

Output:

```
Last State: Terminated
Reason: OOMKilled
```

---

# Key Optimization Strategies

## 1. Monitor Actual Resource Usage

Before tuning resources, you must observe real workload behavior.

Common monitoring stack:

* **Prometheus**
* **Grafana**

Important metrics:

| Metric                                      | Purpose               |
| ------------------------------------------- | --------------------- |
| `container_cpu_usage_seconds_total`         | CPU utilization       |
| `container_memory_working_set_bytes`        | Actual memory usage   |
| `container_cpu_cfs_throttled_seconds_total` | Detect CPU throttling |

Example:

```bash
kubectl top pods
kubectl top nodes
```

---

# 2. Rightsize Resource Requests and Limits

Many Kubernetes clusters suffer from **severe over-provisioning**.

Studies show:

> Nearly **50% of containers use less than one-third of their requested resources**.

Rightsizing improves:

* cluster utilization
* scheduling efficiency
* infrastructure cost

### CPU Best Practices

| Strategy                                        | Explanation             |
| ----------------------------------------------- | ----------------------- |
| Set accurate **CPU requests**                   | Ensures fair scheduling |
| Avoid CPU limits for latency-sensitive services | Prevents CPU throttling |
| Use monitoring data to tune requests            | Avoid wasted capacity   |

Example:

```yaml
resources:
  requests:
    cpu: "500m"
  limits:
    cpu: "1000m"
```

Some teams intentionally **remove CPU limits** for latency-critical APIs.

---

### Memory Best Practices

Memory should be configured more carefully because exceeding limits kills the container.

| Strategy                                   | Explanation                      |
| ------------------------------------------ | -------------------------------- |
| Set **requests ≈ limits**                  | Prevent node memory pressure     |
| Avoid large gaps between request and limit | Reduces unpredictable scheduling |
| Watch for memory leaks                     | Use heap profiling               |

Example:

```yaml
resources:
  requests:
    memory: "1Gi"
  limits:
    memory: "1Gi"
```

This creates **Guaranteed QoS** in Kubernetes.

---

# 3. Horizontal Pod Autoscaler (HPA)

HPA scales **number of pod replicas** based on metrics such as CPU or request rate.

Example:

```bash
kubectl autoscale deployment api \
  --cpu-percent=75 \
  --min=3 \
  --max=10
```

Behavior:

| CPU Usage | Action          |
| --------- | --------------- |
| >75%      | Scale up pods   |
| <75%      | Scale down pods |

HPA works best for:

* stateless APIs
* web services
* request-driven workloads

---

# 4. Vertical Pod Autoscaler (VPA)

VPA automatically adjusts **CPU and memory requests/limits** based on historical usage.

Modes:

| Mode        | Behavior                      |
| ----------- | ----------------------------- |
| **Off**     | Only provides recommendations |
| **Initial** | Sets resources at pod startup |
| **Auto**    | Dynamically adjusts resources |

Example VPA output:

```
Recommended CPU: 800m
Recommended Memory: 1.2Gi
```

Many production environments run VPA in **recommendation mode** and apply changes manually.

---

# Using HPA and VPA Together

Using both on the **same metric (CPU)** can cause instability.

Example conflict:

| Component | Action                     |
| --------- | -------------------------- |
| HPA       | Adds pods when CPU is high |
| VPA       | Increases CPU per pod      |

This creates a **feedback loop**.

### Recommended Approach

| Autoscaler | Responsibility                     |
| ---------- | ---------------------------------- |
| **HPA**    | Scale replicas (CPU, traffic, QPS) |
| **VPA**    | Manage memory sizing               |

Example best practice:

```
HPA → CPU scaling
VPA → Memory recommendations
```

---

# 5. Container Image Optimization

Large container images increase:

* startup time
* memory footprint
* network usage

Best practices:

| Technique                  | Benefit                |
| -------------------------- | ---------------------- |
| Use minimal base images    | lower memory usage     |
| Remove unused dependencies | smaller images         |
| Multi-stage builds         | smaller runtime images |

Example base images:

* `alpine`
* `distroless`

---

# 6. Namespace Resource Governance

Prevent resource abuse using namespace-level controls.

### ResourceQuota

Limits total resources per namespace.

Example:

```yaml
apiVersion: v1
kind: ResourceQuota
```

Example limits:

| Resource | Limit     |
| -------- | --------- |
| CPU      | 100 cores |
| Memory   | 200Gi     |
| Pods     | 200       |

---

### LimitRange

Defines default container resource limits.

Example:

```yaml
kind: LimitRange
```

Ensures every container has resource requests.

---

# 7. Iterative Performance Tuning

Resource optimization is **not a one-time task**.

Typical tuning workflow:

1. Deploy application with conservative resource requests
2. Monitor usage over time
3. Identify peak utilization
4. Adjust requests and limits
5. Repeat periodically

Special attention:

* JVM startup memory spikes
* batch workloads
* traffic bursts

---

# Key Best Practices Summary

| Best Practice                                    | Reason                       |
| ------------------------------------------------ | ---------------------------- |
| Monitor real usage with Prometheus/Grafana       | understand workload patterns |
| Rightsize CPU and memory requests                | improve cluster utilization  |
| Avoid CPU limits for latency-sensitive workloads | prevent throttling           |
| Keep memory request close to limit               | prevent OOM kills            |
| Use HPA for scaling replicas                     | handle traffic spikes        |
| Use VPA for resource recommendations             | automate rightsizing         |
| Use ResourceQuota and LimitRange                 | enforce fairness             |
| Optimize container images                        | reduce memory footprint      |

---

# Example Target Cluster Utilization

A well-optimized cluster should aim for:

| Resource           | Target Utilization |
| ------------------ | ------------------ |
| CPU                | 60–80%             |
| Memory             | 70–80%             |
| Node idle capacity | minimal            |

