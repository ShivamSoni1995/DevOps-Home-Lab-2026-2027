# GKE Migration — Validation Checklist

Run these checks in order after bootstrap and after the first CI push.

---

## 1. Infrastructure

```bash
# Cluster is reachable
kubectl cluster-info

# ingress-nginx controller is Running and has an external IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# cert-manager is Ready
kubectl get pods -n cert-manager

# ArgoCD server is Running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
```

---

## 2. Artifact Registry — Image Published

After the first successful CI run on `main`:

```bash
# List images in AR — you should see backend and frontend with a 7-char SHA tag
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/${GCP_PROJECT}/humor-game \
  --include-tags

# Confirm the tag matches the latest commit
git rev-parse --short HEAD
```

---

## 3. GitOps Manifest Updated

```bash
# Check kustomization.yaml was updated by CI with the new tag
grep newTag gitops-safe/overlays/gke/kustomization.yaml

# Should show something like:
#   newTag: a1b2c3d
#   newTag: a1b2c3d
```

---

## 4. ArgoCD Synced

```bash
# Application should be Healthy + Synced
kubectl get application humor-game-gke -n argocd

# Detailed sync status
kubectl describe application humor-game-gke -n argocd | grep -A5 "Status:"

# Or via ArgoCD UI — port-forward and open browser:
kubectl port-forward svc/argocd-server -n argocd 8090:443
# → https://localhost:8090  (admin / password from argocd-initial-admin-secret)
```

---

## 5. Pods Healthy

```bash
# All pods Running (2 backend, 2 frontend, 1 postgres, 1 redis)
kubectl get pods -n humor-game

# No OOMKilled or CrashLoopBackOff
kubectl get pods -n humor-game -o wide

# Backend health endpoint (from inside the cluster)
kubectl exec -n humor-game \
  $(kubectl get pod -n humor-game -l app=backend -o jsonpath='{.items[0].metadata.name}') \
  -- wget -qO- http://localhost:3001/health
```

---

## 6. Ingress Working + TLS

```bash
# Ingress exists and shows the correct host and IP
kubectl get ingress -n humor-game

# TLS certificate issued by Let's Encrypt (may take 1-2 min)
kubectl get certificate -n humor-game
kubectl describe certificate humor-game-tls -n humor-game

# Full end-to-end smoke test (replace with your domain)
curl -I https://${APP_DOMAIN}/
curl -I https://${APP_DOMAIN}/api/health
```

Expected:
- `HTTP/2 200` on `/`
- `{"status":"ok",...}` body on `/api/health`

---

## 7. HPA Registered

```bash
kubectl get hpa -n humor-game
# Should show backend-hpa and frontend-hpa with current/target metrics
```

---

## 8. Rollback Path

**Via Git revert (preferred):**
```bash
# Revert the manifest commit that introduced the bad tag
git revert <bad-commit-sha>
git push

# ArgoCD detects the new Git state and re-applies within ~3 min (polling interval)
# Or trigger immediately:
argocd app sync humor-game-gke
```

**Via ArgoCD UI:**
- Open Application → History → select previous revision → Rollback

**Manual override (emergency):**
```bash
# Temporarily override the image without touching Git
kubectl set image deployment/backend \
  backend=us-central1-docker.pkg.dev/${GCP_PROJECT}/humor-game/backend:<known-good-tag> \
  -n humor-game

# NOTE: ArgoCD selfHeal will revert this on next sync cycle if automated sync is on.
# Create a proper Git revert immediately after.
```

---

## Common Gotchas

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `ImagePullBackOff` | Nodes can't pull from AR | Verify `roles/artifactregistry.reader` on compute SA (Phase 5 of bootstrap) |
| `0/1 targets` in HPA | Metrics server not installed | `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` — on Autopilot this is auto-installed |
| ArgoCD shows `OutOfSync` after every sync | `commonAnnotations` triggers drift | Add the affected fields to `ignoreDifferences` in argocd-application-gke.yaml |
| TLS cert stuck in `Pending` | DNS not pointed at LB IP yet | Get IP: `kubectl get svc -n ingress-nginx`, update DNS A record |
| Backend CrashLoop | Missing secret | Run `scripts/secrets-bootstrap.sh` |
| `git push` fails in CI | Branch protection requires PR | Store a PAT as `GITOPS_TOKEN` secret and replace `github.token` in ci.yml |
