# GKE Setup Guide

*How to bootstrap the Humor Memory Game on Google Kubernetes Engine from scratch*

## Prerequisites

| Tool | Install | Purpose |
|------|---------|---------|
| `gcloud` CLI | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) | GCP auth + cluster management |
| `gke-gcloud-auth-plugin` | `gcloud components install gke-gcloud-auth-plugin` | Required for `kubectl` to auth against GKE |
| `kubectl` | via gcloud: `gcloud components install kubectl` | Cluster operations |
| `helm` | [helm.sh](https://helm.sh/docs/intro/install/) | Install ingress-nginx, cert-manager |

After installing the auth plugin, add to your shell profile:

```bash
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
# Also add gke-gcloud-auth-plugin to PATH if installed locally:
export PATH="$HOME/.local/bin:$PATH"
```

## Overview

The bootstrap is 10 phases, all captured in `scripts/gke-bootstrap.sh`. You can run the script, or follow this guide step by step to understand what each phase does.

```
Phase 1  — Enable GCP APIs
Phase 2  — Create Artifact Registry repository
Phase 3  — Create GKE Autopilot cluster
Phase 4  — Workload Identity Federation (WIF) for GitHub Actions
Phase 5  — Grant GKE nodes Artifact Registry reader access
Phase 6  — Install ingress-nginx (LoadBalancer)
Phase 7  — Install cert-manager (TLS / Let's Encrypt)
Phase 8  — Install ArgoCD
Phase 9  — Substitute placeholders, apply ArgoCD project + application
Phase 10 — Create humor-game namespace
```

## Running the bootstrap

```bash
# Set required variables
export GCP_PROJECT=gke-project-491822       # your GCP project ID
export GCP_REGION=us-central1
export GITHUB_USERNAME=ShivamSoni1995
export GITHUB_REPO=DevOps-Home-Lab-2026-2027
export APP_DOMAIN=your-domain.example.com   # or leave blank if using raw IP

# Authenticate first
gcloud auth login
gcloud config set project $GCP_PROJECT

# Run
bash scripts/gke-bootstrap.sh
```

The script is idempotent — safe to re-run if a phase fails halfway.

---

## Phase-by-Phase Breakdown

### Phase 1 — Enable GCP APIs

```bash
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${GCP_PROJECT}"
```

These APIs are disabled by default on new projects. `container.googleapis.com` covers GKE; `artifactregistry` is the image registry; the IAM APIs are needed for Workload Identity Federation.

---

### Phase 2 — Artifact Registry

```bash
gcloud artifacts repositories create humor-game \
  --repository-format=docker \
  --location=us-central1 \
  --project="${GCP_PROJECT}"
```

Images are stored at: `us-central1-docker.pkg.dev/${GCP_PROJECT}/humor-game/backend:TAG`

**Why Artifact Registry instead of Docker Hub?** GKE nodes can pull from AR without credentials (using node's default compute SA). No imagePullSecrets needed in manifests.

---

### Phase 3 — GKE Autopilot Cluster

```bash
gcloud container clusters create-auto humor-game-gke \
  --region=us-central1 \
  --project="${GCP_PROJECT}" \
  --release-channel=regular
```

**Why Autopilot?**
- No node pool management — Google manages nodes automatically
- You pay per pod, not per idle node
- Automatic bin-packing and scaling

**Trade-offs to know:**
- Autopilot mutating webhook injects `ephemeral-storage` into every pod spec → requires ArgoCD `ignoreDifferences` (see [Troubleshooting](08-troubleshooting.md#gke-autopilot-issues))
- Autopilot Dataplane V2 (eBPF/Antrea) evaluates `NetworkPolicy` egress rules before DNAT → pod-selector-based egress rules silently drop ClusterIP traffic
- SSD quota: each Autopilot node uses ~100GB SSD. Default quota is 250GB → max ~2 nodes before quota increase is needed

After cluster creation, fetch credentials:
```bash
gcloud container clusters get-credentials humor-game-gke \
  --region=us-central1 \
  --project="${GCP_PROJECT}"
```

---

### Phase 4 — Workload Identity Federation (WIF)

WIF lets GitHub Actions authenticate to GCP using short-lived OIDC tokens instead of long-lived service account JSON keys.

```
GitHub push → GitHub OIDC token issued → WIF pool validates token
→ Maps to GCP service account → Short-lived GCP access token returned
→ gcloud / docker authenticated without any stored credentials
```

```bash
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')

# Create identity pool
gcloud iam workload-identity-pools create github-pool \
  --location=global --project="${GCP_PROJECT}"

# Create OIDC provider scoped to your repo only
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --workload-identity-pool=github-pool \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${GITHUB_USERNAME}/${GITHUB_REPO}'" \
  --location=global --project="${GCP_PROJECT}"

# Create service account for CI
gcloud iam service-accounts create github-actions-sa \
  --display-name="GitHub Actions CI/CD" --project="${GCP_PROJECT}"

# Grant SA permission to push images
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:github-actions-sa@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.writer"

# Allow GitHub OIDC token to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding \
  github-actions-sa@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/${GITHUB_USERNAME}/${GITHUB_REPO}" \
  --project="${GCP_PROJECT}"
```

After this phase, add three GitHub repository secrets (Settings → Secrets and variables → Actions):

| Secret name | Value |
|-------------|-------|
| `GCP_PROJECT_ID` | your project ID e.g. `gke-project-491822` |
| `WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `WIF_SERVICE_ACCOUNT` | `github-actions-sa@YOUR_PROJECT.iam.gserviceaccount.com` |

---

### Phase 5 — GKE Node Artifact Registry Access

```bash
DEFAULT_COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${DEFAULT_COMPUTE_SA}" \
  --role="roles/artifactregistry.reader"
```

GKE Autopilot nodes pull images as the default compute service account. This grants them read access to AR so no `imagePullSecrets` are needed.

---

### Phase 6 — ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.replicaCount=1 --wait
```

After install, get the external IP:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

This IP is how all traffic enters the cluster. Point your DNS A record at it (or use it directly). **Current IP: `34.44.151.3`**

**Why ingress-nginx instead of GKE native ingress?**
- Same Ingress YAML works in both local k3d and GKE — no manifest changes needed across environments
- GKE-native ingress provisions a separate L7 LB per Ingress resource, which costs more and provisions slower

---

### Phase 7 — cert-manager

```bash
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true --wait
```

Then apply the ClusterIssuer for Let's Encrypt (see `k8s/cluster-issuer.yaml`). TLS is not yet active in this deployment since we're using a raw IP — cert-manager is installed and ready for when a domain is added.

---

### Phase 8 — ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

Get the initial admin password:
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

Access ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8090:443
# → https://localhost:8090  (username: admin)
```

**Note on resource constraints:** On a 2-node Autopilot cluster, reduce ArgoCD component requests before deploying app workloads:
```bash
kubectl patch deployment argocd-server -n argocd \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","resources":{"requests":{"cpu":"100m"}}}]}}}}'
```

---

### Phase 9 — ArgoCD Project and Application

```bash
# Apply the project (defines allowed sources and destinations)
kubectl apply -f gitops-safe/argocd-project.yaml -n argocd

# Apply the application (points ArgoCD at the GKE overlay)
kubectl apply -f gitops-safe/argocd-application-gke.yaml -n argocd
```

ArgoCD will immediately begin syncing. Watch:
```bash
kubectl get applications -n argocd -w
```

Expected final state: `Synced / Healthy`

---

### Phase 10 — App Secrets

ArgoCD manages all Kubernetes resources except secrets (never store secrets in git). Bootstrap them manually:

```bash
bash scripts/secrets-bootstrap.sh
# Creates the humor-game-secrets Secret with DB_PASSWORD, REDIS_PASSWORD, JWT_SECRET
```

Or manually:
```bash
kubectl create secret generic humor-game-secrets -n humor-game \
  --from-literal=DB_PASSWORD=your-secure-password \
  --from-literal=REDIS_PASSWORD=your-redis-password \
  --from-literal=JWT_SECRET=your-jwt-secret
```

---

## Verifying the Setup

See [gke-migration-validation.md](gke-migration-validation.md) for the full checklist. Quick version:

```bash
# All pods Running
kubectl get pods -n humor-game

# ArgoCD status
kubectl get applications -n argocd

# App responds
curl http://34.44.151.3/api/health
# Expected: {"status":"healthy","database":"connected","redis":"connected"}
```

---

## Current Project Values

| Value | Setting |
|-------|---------|
| GCP Project | `gke-project-491822` |
| Region | `us-central1` |
| Cluster | `humor-game-gke` (Autopilot) |
| Artifact Registry | `us-central1-docker.pkg.dev/gke-project-491822/humor-game` |
| External IP | `34.44.151.3` |
| kube-dns ClusterIP | `34.118.224.10` (needed for nginx resolver) |
| ArgoCD app name | `humor-game-gke` |
