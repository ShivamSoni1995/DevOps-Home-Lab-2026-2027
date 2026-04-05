# Troubleshooting Guide

*Quick reference for common issues and their solutions*

## 🚨 Quick Reference

| Issue | Quick Fix | More Info |
|-------|-----------|-----------|
| **Cluster won't start** | `k3d cluster delete homelab && k3d cluster create homelab` | [Cluster Issues](#cluster-issues) |
| **Pods stuck in Pending** | `kubectl describe pod <pod-name> -n humor-game` | [Pod Issues](#pod-issues) |
| **Services not accessible** | `kubectl port-forward -n humor-game service/humor-game-frontend 8080:80` | [Service Issues](#service-issues) |
| **Database connection failed** | Check PostgreSQL pod logs: `kubectl logs -n humor-game humor-game-postgres` | [Database Issues](#database-issues) |
| **Ingress not working** | Verify ingress controller: `kubectl get pods -n ingress-nginx` | [Ingress Issues](#ingress-issues) |

## 🔍 Diagnostic Commands

### **Cluster Health Check**
```bash
# Check cluster status
kubectl cluster-info

# Check nodes
kubectl get nodes -o wide

# Check all namespaces
kubectl get namespaces

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

### **Namespace Status**
```bash
# Check specific namespace
kubectl get all -n humor-game

# Check namespace events
kubectl get events -n humor-game --sort-by='.lastTimestamp'

# Check namespace resource quotas
kubectl get resourcequota -n humor-game
```

### **Pod Diagnostics**
```bash
# Get pod details
kubectl describe pod <pod-name> -n humor-game

# Check pod logs
kubectl logs <pod-name> -n humor-game

# Check pod resources
kubectl top pod <pod-name> -n humor-game

# Execute into pod
kubectl exec -it <pod-name> -n humor-game -- /bin/bash
```

### **Service Diagnostics**
```bash
# Check service endpoints
kubectl get endpoints -n humor-game

# Test service connectivity
kubectl port-forward -n humor-game service/humor-game-backend 3001:3001

# Check service configuration
kubectl describe service <service-name> -n humor-game
```

---

## 🚨 Common Issues by Milestone

### **Milestone 1: Docker Compose Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **Docker Compose fails to start** | Port conflicts or Docker not running | `docker ps` | Start Docker Desktop, check port 3001/8080 availability |
| **Database connection refused** | PostgreSQL container not ready | `docker logs postgres` | Wait for container to fully start, check depends_on in docker-compose.yml |
| **Frontend shows "Cannot connect to API"** | Backend service not responding | `curl http://localhost:3001/health` | Check backend logs: `docker logs humor-game-backend` |
| **Redis connection failed** | Redis container not running | `docker ps \| grep redis` | Restart Redis: `docker restart redis` |

### **Milestone 2: Kubernetes Basics Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **k3d cluster creation fails** | Insufficient resources or Docker issues | `docker system df` | Free up Docker resources, ensure 4GB+ RAM available |
| **kubectl connection refused** | Cluster not running or context wrong | `k3d cluster list` | Start cluster: `k3d cluster start homelab` |
| **Pods stuck in Pending** | Insufficient cluster resources | `kubectl describe pod <pod-name> -n humor-game` | Increase cluster resources: `k3d cluster create homelab --servers 1 --agents 2 --k3s-arg "--kube-apiserver-arg=--max-pods=100"` |
| **Image pull errors** | Image not built or wrong tag | `kubectl describe pod <pod-name> -n humor-game` | Build and import images: `docker build -t humor-game-backend:latest backend/` |

### **Milestone 3: Ingress Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **Ingress controller not found** | Ingress controller not installed | `kubectl get pods -n ingress-nginx` | Install ingress: `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml` |
| **Domain not resolving** | /etc/hosts not configured | `cat /etc/hosts \| grep gameapp` | Add entry: `127.0.0.1 gameapp.local` |
| **Ingress shows 404** | Service selector mismatch | `kubectl get ingress -n humor-game -o yaml` | Check service names and ports in ingress.yaml |
| **TLS certificate errors** | cert-manager not installed | `kubectl get pods -n cert-manager` | Install cert-manager for Let's Encrypt certificates |

### **Milestone 4: Monitoring Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **Prometheus not collecting metrics** | ServiceMonitor not configured | `kubectl get servicemonitor -n monitoring` | Create ServiceMonitor for humor-game-backend |
| **Grafana dashboard empty** | Prometheus data source not configured | `kubectl get configmap grafana-datasources -n monitoring -o yaml` | Check Prometheus URL in Grafana config |
| **Metrics endpoint not accessible** | Backend metrics not enabled | `curl http://localhost:3001/metrics` | Ensure metrics middleware is enabled in backend |
| **Alerts not firing** | Prometheus rules not loaded | `kubectl get prometheusrule -n monitoring` | Check PrometheusRule configuration |

### **Milestone 5: GitOps Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **ArgoCD not syncing** | Git repository access issues | `kubectl logs -n argocd deployment/argocd-server` | Check Git credentials and repository permissions |
| **Application shows OutOfSync** | Configuration drift detected | `kubectl get application -n argocd` | Force sync: `kubectl patch application <app-name> -n argocd -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' --type=merge` |
| **ArgoCD health check failed** | Target resources not healthy | `kubectl get application <app-name> -n argocd -o yaml` | Check target namespace and resource health |
| **GitOps conflicts** | Multiple controllers managing same resources | `kubectl get application -n argocd -o wide` | Ensure only ArgoCD manages production resources |

### **Milestone 6: Production Issues**

| Symptom | Cause | Command to Confirm | Fix |
|---------|-------|-------------------|-----|
| **Pods being evicted** | Resource limits too low | `kubectl describe pod <pod-name> -n humor-game` | Increase resource limits in deployment.yaml |
| **Network policies blocking traffic** | Overly restrictive policies | `kubectl get networkpolicy -n humor-game` | Review and adjust network policy rules |
| **Security context violations** | Container trying to run as root | `kubectl describe pod <pod-name> -n humor-game` | Check security context in deployment.yaml |
| **HPA not scaling** | Metrics not available or thresholds too high | `kubectl get hpa -n humor-game` | Check HPA configuration and metrics availability |

---

## 🛠️ Advanced Troubleshooting

### **Resource Cleanup**

```bash
# Clean up stuck resources
kubectl delete pod --field-selector=status.phase=Failed --all-namespaces
kubectl delete pod --field-selector=status.phase=Succeeded --all-namespaces

# Clean up completed jobs
kubectl delete job --all-namespaces --field-selector=status.successful=1

# Clean up old PVCs
kubectl get pvc --all-namespaces | grep Bound | awk '{print $1, $2}' | xargs -I {} kubectl delete pvc {} -n {}

# Reset cluster (nuclear option)
k3d cluster delete homelab
k3d cluster create homelab
```

### **Performance Issues**

```bash
# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Check for resource pressure
kubectl describe node | grep -A 10 "Conditions:"

# Check for OOM kills
kubectl get events --all-namespaces | grep -i "oom"

# Check for throttling
kubectl describe pod <pod-name> -n humor-game | grep -A 5 "Last State"
```

### **Network Issues**

```bash
# Check network policies
kubectl get networkpolicy --all-namespaces

# Test pod-to-pod communication
kubectl exec -it <pod1> -n humor-game -- ping <pod2-ip>

# Check DNS resolution
kubectl exec -it <pod-name> -n humor-game -- nslookup kubernetes.default

# Check service endpoints
kubectl get endpoints --all-namespaces
```

### **Storage Issues**

```bash
# Check PVC status
kubectl get pvc --all-namespaces

# Check PV status
kubectl get pv

# Check storage class
kubectl get storageclass

# Check for storage events
kubectl get events --all-namespaces | grep -i "volume\|storage"
```

---

## 📞 Getting Help

### **When to Ask for Help**

- ✅ **You've tried the troubleshooting steps above**
- ✅ **You've checked the logs and error messages**
- ✅ **You've verified your configuration matches the examples**
- ✅ **You've searched existing issues and documentation**

### **Information to Include**

1. **Your environment**: OS, Docker version, kubectl version, k3d version
2. **What you're trying to do**: Specific milestone and step
3. **What happened**: Exact error messages and behavior
4. **What you've tried**: Commands run and their output
5. **Relevant logs**: `kubectl logs` and `kubectl describe` output

### **Useful Commands for Debugging**

```bash
# Get comprehensive cluster info
kubectl cluster-info dump > cluster-dump.yaml

# Get all resources in a namespace
kubectl get all -n humor-game -o yaml > humor-game-resources.yaml

# Get events for debugging
kubectl get events --all-namespaces --sort-by='.lastTimestamp' > events.yaml

# Check API server logs (if accessible)
kubectl logs -n kube-system deployment/kube-apiserver
```

---

## 🎯 Prevention Tips

### **Best Practices**

1. **Always use the verification script**: Run `./scripts/verify.sh` after each milestone
2. **Check resource requirements**: Ensure your system meets the 4GB+ RAM requirement
3. **Use consistent naming**: Follow the exact names from `docs/name-map.md`
4. **Test incrementally**: Verify each step before moving to the next
5. **Keep backups**: Export your working configurations before making changes

### **Common Pitfalls**

- ❌ **Skipping prerequisites**: Install all required tools first
- ❌ **Changing names**: Use exact values from the documentation
- ❌ **Rushing through**: Take time to understand each step
- ❌ **Ignoring errors**: Address issues before proceeding
- ❌ **Not checking logs**: Always check logs when things go wrong

---

*This troubleshooting guide covers the most common issues. For specific errors, check the logs and use the diagnostic commands above to gather more information.*

---

## ☁️ GKE Autopilot Issues {#gke-autopilot-issues}

These are real issues hit during the GKE Autopilot deployment of this project. None of them appear in standard Kubernetes docs.

---

### **Network policies silently drop ClusterIP traffic**

**Symptom:** Backend CrashLoopBackOff with "Connection terminated due to connection timeout". Postgres logs show **zero** connection attempts despite backend retrying.

**Root cause:** GKE Autopilot uses Dataplane V2 (Antrea eBPF). It evaluates `podSelector` egress rules **before DNAT** on ClusterIP traffic. The SYN packet matches the NP egress rule against the ClusterIP address, not the pod IP — so it gets dropped before it's translated to a pod IP.

**Fix:** Remove `NetworkPolicy` resources from the GKE overlay. GKE VPC firewalls provide perimeter security. Do not re-add pod-selector-based egress rules without testing.

```bash
# Verify NPs are gone
kubectl get networkpolicies -n humor-game
# Should return: No resources found

# Verify backend connects
kubectl logs -l app=backend -n humor-game | grep -i "postgres\|redis\|connect"
```

---

### **ArgoCD permanently OutOfSync — ephemeral-storage / memory**

**Symptom:** `kubectl get applications -n argocd` shows `OutOfSync` even after a successful sync. Diff shows `ephemeral-storage` or memory values that don't exist in git.

**Root cause:** GKE Autopilot's mutating admission webhook automatically injects:
- `ephemeral-storage` requests and limits into every container spec
- Bumped memory requests to meet Autopilot per-container minimums (e.g. 64Mi → 103Mi)

None of these are in git, so ArgoCD always sees a diff.

**Fix:** Add `ignoreDifferences` with `jqPathExpressions` to `gitops-safe/argocd-application-gke.yaml`:

```yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jsonPointers:
  - /spec/replicas                          # HPA manages this
  - /spec/template/metadata/annotations/deployment.kubernetes.io~1revision
  jqPathExpressions:
  - .spec.template.spec.containers[].resources.requests["ephemeral-storage"]
  - .spec.template.spec.containers[].resources.limits["ephemeral-storage"]
  - .spec.template.spec.initContainers[].resources.requests["ephemeral-storage"]
  - .spec.template.spec.initContainers[].resources.limits["ephemeral-storage"]
  - .spec.template.spec.containers[].resources.requests["memory"]
  - .spec.template.spec.initContainers[].resources.requests["memory"]
```

```bash
kubectl apply -f gitops-safe/argocd-application-gke.yaml -n argocd
kubectl annotate application humor-game-gke -n argocd \
  argocd.argoproj.io/refresh=normal --overwrite
```

---

### **Postgres fails to start — "directory not empty"**

**Symptom:** `postgres` pod in CrashLoopBackOff. Logs show:
```
initdb: error: directory "/var/lib/postgresql/data" exists but is not empty
If you want to create a new database system, either remove or empty
the directory "/var/lib/postgresql/data" or run initdb with an argument
other than "/var/lib/postgresql/data".
```

**Root cause:** GKE Autopilot PVCs mount at the root of the filesystem path. A `lost+found` directory is created by the ext4 filesystem at the mount root, making postgres think the data directory is pre-populated.

**Fix:** Set `PGDATA` to a subdirectory inside the mount point:

```yaml
# In postgres-deployment.yaml
env:
- name: PGDATA
  value: /var/lib/postgresql/data/pgdata
```

The PVC still mounts at `/var/lib/postgresql/data`, but postgres initialises inside the `pgdata/` subdir which is empty.

---

### **Frontend nginx fails at startup — "host not found in upstream"**

**Symptom:** `frontend` pod in CrashLoopBackOff. Logs show:
```
nginx: [emerg] host not found in upstream "backend" in /etc/nginx/conf.d/default.conf:10
```

**Root cause:** nginx resolves upstream hostnames at startup, not at request time. If the `backend` service isn't fully ready when nginx starts, DNS lookup fails and nginx refuses to start.

**Fix:** Use a `resolver` directive with the kube-dns ClusterIP and assign the upstream to a variable. nginx only resolves variables at request time.

```nginx
# frontend-nginx-config ConfigMap (gitops-safe/overlays/gke/frontend-nginx-config.yaml)
resolver 34.118.224.10 valid=10s;   # kube-dns ClusterIP for this cluster

location /api/ {
    set $backend_url http://backend.humor-game.svc.cluster.local:3001;
    proxy_pass $backend_url;
}
```

To find your kube-dns ClusterIP:
```bash
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}'
```

---

### **ArgoCD vs HPA replica drift**

**Symptom:** Deployments show `OutOfSync`. Diff shows `replicas: 1` in git vs `replicas: 2` in cluster.

**Root cause:** HPA has `minReplicas: 2`, but the kustomization patch was setting `replicas: 1`. ArgoCD's selfHeal kept forcing it back to 1, fighting the HPA.

**Fix:** Two-part:
1. Remove any `replicas` patches from kustomization that conflict with HPA's `minReplicas`
2. Add `/spec/replicas` to ArgoCD `ignoreDifferences` — this is the standard pattern for any deployment managed by an HPA

```yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jsonPointers:
  - /spec/replicas
```

---

### **Pods stuck Pending — CPU/memory requests at 99%**

**Symptom:** New pods remain in `Pending` state. `kubectl describe pod` shows `Insufficient cpu`.

**Root cause:** GKE Autopilot accounts for system pod requests against node capacity. Even with 2 nodes, Autopilot system pods can consume 60–70% of the request budget, leaving little room for workloads.

**Fix:** Reduce CPU/memory requests to the minimum needed:
- ArgoCD components: reduce from 500m → 100m CPU
- Postgres: reduce from 250m → 50m CPU  
- Backend/Frontend: reduce from 100m → 50m CPU

Autopilot will still scale nodes if actual usage grows. Requests only govern scheduling, not actual limits.

```bash
# Check what's consuming request budget
kubectl describe nodes | grep -A 20 "Allocated resources"
```
