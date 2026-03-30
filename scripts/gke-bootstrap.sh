#!/usr/bin/env bash
# ==============================================================================
# GKE Bootstrap — Humor Memory Game
#
# Provisions everything needed to run the app on GKE with GitHub Actions CI
# and ArgoCD pull-based CD.
#
# Run this ONCE from a workstation that has:
#   - gcloud CLI (authenticated as Owner or Project Editor)
#   - kubectl
#   - helm
#
# Usage:
#   export GCP_PROJECT=my-project-123456
#   export GCP_REGION=us-central1
#   export GITHUB_USERNAME=your-github-username
#   export GITHUB_REPO=DevOps-Home-Lab-2026-2027
#   export APP_DOMAIN=humorgame.shivamsoni.duckdns.org
#   bash scripts/gke-bootstrap.sh
#
# The script is idempotent for most steps — safe to re-run.
# ==============================================================================

set -euo pipefail

# ---- Required env vars -------------------------------------------------------
: "${GCP_PROJECT:?Set GCP_PROJECT (e.g. my-project-123456)}"
: "${GCP_REGION:?Set GCP_REGION (e.g. us-central1)}"
: "${GITHUB_USERNAME:?Set GITHUB_USERNAME (your GitHub username)}"
: "${GITHUB_REPO:?Set GITHUB_REPO (e.g. DevOps-Home-Lab-2026-2027)}"
: "${APP_DOMAIN:?Set APP_DOMAIN (e.g. humorgame.shivamsoni.duckdns.org)}"

CLUSTER_NAME="humor-game-gke"
AR_REPO="humor-game"
GH_SA_NAME="github-actions-sa"
GH_SA_EMAIL="${GH_SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
WIF_POOL="github-pool"
WIF_PROVIDER="github-provider"

echo "============================================================"
echo " GKE Bootstrap: Project=${GCP_PROJECT}  Region=${GCP_REGION}"
echo "============================================================"

# ==============================================================================
# PHASE 1 — Enable Required GCP APIs
# ==============================================================================
echo ""
echo ">>> Phase 1: Enabling GCP APIs..."
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="${GCP_PROJECT}"

# ==============================================================================
# PHASE 2 — Artifact Registry
# ==============================================================================
echo ""
echo ">>> Phase 2: Creating Artifact Registry repository..."
gcloud artifacts repositories create "${AR_REPO}" \
  --repository-format=docker \
  --location="${GCP_REGION}" \
  --description="Humor Memory Game container images" \
  --project="${GCP_PROJECT}" \
  2>/dev/null || echo "  (repository already exists — skipping)"

# ==============================================================================
# PHASE 3 — GKE Autopilot Cluster
# ==============================================================================
# Autopilot chosen over Standard because:
#   - No node pool management (Google manages nodes)
#   - Automatic per-pod bin-packing and scaling
#   - Significantly lower operational overhead for a lab project
#   - Cost-effective: you pay per pod, not per idle node
# Trade-off: slightly less control over node-level configs.
# Switch to Standard if you need DaemonSets, node taints, or custom OS configs.

echo ""
echo ">>> Phase 3: Creating GKE Autopilot cluster '${CLUSTER_NAME}'..."
gcloud container clusters create-auto "${CLUSTER_NAME}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT}" \
  --release-channel=regular \
  2>/dev/null || echo "  (cluster already exists — skipping)"

echo ""
echo ">>> Fetching cluster credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region="${GCP_REGION}" \
  --project="${GCP_PROJECT}"

# ==============================================================================
# PHASE 4 — IAM: Workload Identity Federation for GitHub Actions
# ==============================================================================
# WIF lets GitHub Actions authenticate to GCP without long-lived service account keys.
# How it works:
#   GitHub OIDC token → WIF pool → maps to GCP service account → short-lived access token
# This is the recommended approach over storing a JSON key as a GitHub secret.

echo ""
echo ">>> Phase 4: Setting up Workload Identity Federation..."

# Get project number (needed for the WIF resource name)
PROJECT_NUMBER=$(gcloud projects describe "${GCP_PROJECT}" --format='value(projectNumber)')

# Create the Workload Identity Pool
gcloud iam workload-identity-pools create "${WIF_POOL}" \
  --location=global \
  --display-name="GitHub Actions Pool" \
  --project="${GCP_PROJECT}" \
  2>/dev/null || echo "  (pool already exists — skipping)"

# Create the OIDC Provider for GitHub Actions
gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER}" \
  --location=global \
  --workload-identity-pool="${WIF_POOL}" \
  --display-name="GitHub OIDC Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '${GITHUB_USERNAME}/${GITHUB_REPO}'" \
  --project="${GCP_PROJECT}" \
  2>/dev/null || echo "  (provider already exists — skipping)"

# Create the service account that GitHub Actions impersonates
gcloud iam service-accounts create "${GH_SA_NAME}" \
  --display-name="GitHub Actions CI/CD" \
  --project="${GCP_PROJECT}" \
  2>/dev/null || echo "  (service account already exists — skipping)"

# Grant the service account permission to push to Artifact Registry
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${GH_SA_EMAIL}" \
  --role="roles/artifactregistry.writer"

# Allow the GitHub Actions OIDC token to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding "${GH_SA_EMAIL}" \
  --project="${GCP_PROJECT}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_USERNAME}/${GITHUB_REPO}"

# Print the values needed as GitHub Secrets
WIF_PROVIDER_FULL="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"

echo ""
echo "============================================================"
echo " ADD THESE AS GITHUB REPOSITORY SECRETS:"
echo "   Settings → Secrets and variables → Actions → New secret"
echo ""
echo "  GCP_PROJECT_ID = ${GCP_PROJECT}"
echo "  WIF_PROVIDER   = ${WIF_PROVIDER_FULL}"
echo "  WIF_SERVICE_ACCOUNT = ${GH_SA_EMAIL}"
echo "============================================================"

# ==============================================================================
# PHASE 5 — Allow GKE nodes to pull from Artifact Registry
# ==============================================================================
# For GKE Autopilot, pods pull images using the default compute service account
# of the node pool. Grant it Artifact Registry reader access so no imagePullSecrets
# are needed in the manifests.

echo ""
echo ">>> Phase 5: Granting GKE node SA Artifact Registry reader..."
DEFAULT_COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${DEFAULT_COMPUTE_SA}" \
  --role="roles/artifactregistry.reader"

# ==============================================================================
# PHASE 6 — Install ingress-nginx via Helm
# ==============================================================================
# Keeping ingress-nginx (same as local setup) instead of GKE-native ingress because:
#   - Identical Ingress YAML works in both local k3d and GKE — no manifest changes
#   - Fine-grained annotation control (proxy-body-size, CORS, etc.)
#   - GKE-native ingress provisions a separate L7 LB per Ingress, which is slower/costlier
# Trade-off: one extra Deployment to manage.

echo ""
echo ">>> Phase 6: Installing ingress-nginx..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.replicaCount=1 \
  --wait

echo ""
echo ">>> Ingress-nginx external IP (may take 60-90s to provision):"
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true
echo ""
echo "  → Point your DNS A record for ${APP_DOMAIN} at the IP above."

# ==============================================================================
# PHASE 7 — Install cert-manager (TLS via Let's Encrypt)
# ==============================================================================
echo ""
echo ">>> Phase 7: Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait

# ClusterIssuer for Let's Encrypt production
# Replace the email address with your real email before running.
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com   # <-- CHANGE THIS
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# ==============================================================================
# PHASE 8 — Install ArgoCD
# ==============================================================================
echo ""
echo ">>> Phase 8: Installing ArgoCD..."
kubectl create namespace argocd 2>/dev/null || true

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "  Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# ==============================================================================
# PHASE 9 — Substitute placeholders and bootstrap ArgoCD resources
# ==============================================================================
echo ""
echo ">>> Phase 9: Substituting placeholders and applying ArgoCD resources..."

# Replace GitHub username in ArgoCD manifests (in-place, only if not already done)
if grep -q "YOUR_GITHUB_USERNAME" gitops-safe/argocd-project.yaml; then
  sed -i "s|YOUR_GITHUB_USERNAME|${GITHUB_USERNAME}|g" gitops-safe/argocd-project.yaml
  sed -i "s|YOUR_GITHUB_USERNAME|${GITHUB_USERNAME}|g" gitops-safe/argocd-application-gke.yaml
  echo "  Replaced YOUR_GITHUB_USERNAME with ${GITHUB_USERNAME}"
fi

# Replace domain placeholder in GKE overlay
if grep -q "YOUR_DOMAIN.com" gitops-safe/overlays/gke/kustomization.yaml; then
  sed -i "s|YOUR_DOMAIN\.com|${APP_DOMAIN}|g" gitops-safe/overlays/gke/kustomization.yaml
  sed -i "s|YOUR_DOMAIN\.com|${APP_DOMAIN}|g" gitops-safe/overlays/gke/ingress.yaml
  echo "  Replaced YOUR_DOMAIN.com with ${APP_DOMAIN}"
fi

# Replace project ID in GKE overlay image references
if grep -q "YOUR_PROJECT_ID" gitops-safe/overlays/gke/kustomization.yaml; then
  sed -i "s|YOUR_PROJECT_ID|${GCP_PROJECT}|g" gitops-safe/overlays/gke/kustomization.yaml
  echo "  Replaced YOUR_PROJECT_ID with ${GCP_PROJECT}"
fi

echo ""
echo "  Commit these changes before applying ArgoCD resources!"
echo "  Run: git add gitops-safe/ && git commit -m 'chore: set GKE bootstrap placeholders' && git push"
echo ""
echo "  Then apply ArgoCD project and application:"
echo "  kubectl apply -f gitops-safe/argocd-project.yaml -n argocd"
echo "  kubectl apply -f gitops-safe/argocd-application-gke.yaml -n argocd"

# ==============================================================================
# PHASE 10 — Create humor-game namespace (ArgoCD handles this, but just in case)
# ==============================================================================
echo ""
echo ">>> Phase 10: Creating app namespace..."
kubectl create namespace humor-game 2>/dev/null || echo "  (namespace already exists)"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo "============================================================"
echo " Bootstrap COMPLETE"
echo ""
echo " Next steps:"
echo " 1. Add GitHub Secrets (printed above in Phase 4)"
echo " 2. Create Kubernetes secret for app credentials:"
echo "      bash scripts/secrets-bootstrap.sh"
echo " 3. Commit and push placeholder changes (from Phase 9)"
echo " 4. Apply ArgoCD project + application (from Phase 9)"
echo " 5. Get ArgoCD initial admin password:"
echo "      kubectl get secret argocd-initial-admin-secret -n argocd \\"
echo "        -o jsonpath='{.data.password}' | base64 -d && echo"
echo " 6. Push any code change to main to trigger first CI run"
echo " 7. Watch ArgoCD sync: kubectl get app humor-game-gke -n argocd -w"
echo "============================================================"
