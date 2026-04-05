# CI/CD Pipeline Guide

*How code changes flow from your laptop to the live GKE cluster*

## Architecture

```
Developer pushes code
        │
        ▼
┌─────────────────────────────────────────────┐
│  GitHub Actions (.github/workflows/ci.yml)  │
│                                             │
│  Trigger: push to main / pull_request       │
│  Path filter: backend/** frontend/** ci.yml │
│                                             │
│  Job 1 — test (all PRs and main)            │
│    • npm ci && npm test (backend)           │
│    • npm run lint (backend + frontend)      │
│                                             │
│  Job 2 — build-and-push (main only)         │
│    • Authenticate via WIF (keyless)         │
│    • docker buildx build backend + frontend │
│    • Push to Artifact Registry              │
│    • Tag = first 7 chars of commit SHA      │
│                                             │
│  Job 3 — update-manifests (main only)       │
│    • kustomize edit set image <new-tag>     │
│    • git commit [skip ci] + push to main   │
└─────────────────────────────────────────────┘
        │  (git push triggers ArgoCD poll)
        ▼
┌─────────────────────────────────────────────┐
│  ArgoCD (CD)  — watches git every ~3 min   │
│    • Detects new image tag in kustomization │
│    • Applies updated Deployment to GKE      │
│    • Rolling update: new pods, then old die │
│    • selfHeal ON: reverts manual changes    │
└─────────────────────────────────────────────┘
        │
        ▼
   Live at http://34.44.151.3
```

---

## Branching Strategy

| Branch | What happens | Deploys? |
|--------|-------------|---------|
| `feature/*` or any branch | Only Job 1 (tests) runs on push | ❌ No |
| Pull Request to `main` | Job 1 runs; shows pass/fail on PR | ❌ No |
| Merge to `main` | All 3 jobs run → new images → GKE updated | ✅ Yes |

**The rule:** nothing reaches production without passing tests and going through `main`.

---

## Job Details

### Job 1 — Test & Lint

Runs on every push and every PR. If this fails, Jobs 2 and 3 are blocked.

```yaml
- name: Install and test backend
  run: cd backend && npm ci && npm test

- name: Lint backend
  run: cd backend && npm run lint

- name: Install and lint frontend
  run: cd frontend && npm ci && npm run lint
```

Tests live in `backend/tests/`. Run them locally before pushing:
```bash
cd backend && npm test
```

### Job 2 — Build & Push Images

Only runs on push to `main` (not on PRs). Authenticates to GCP using Workload Identity Federation — no keys stored anywhere.

**Image tag** = first 7 characters of the git commit SHA:
```bash
echo "tag=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
# e.g. tag=26ea967
```

Both images get two tags: the SHA tag and `latest`.

Images are pushed to:
```
us-central1-docker.pkg.dev/gke-project-491822/humor-game/backend:26ea967
us-central1-docker.pkg.dev/gke-project-491822/humor-game/backend:latest
us-central1-docker.pkg.dev/gke-project-491822/humor-game/frontend:26ea967
us-central1-docker.pkg.dev/gke-project-491822/humor-game/frontend:latest
```

Docker layer caching is enabled via GitHub Actions cache (scoped per image) — rebuilds only changed layers.

### Job 3 — Update GitOps Manifests

Runs after Job 2. Updates `gitops-safe/overlays/gke/kustomization.yaml` with the new image tag and commits it back to `main`:

```bash
cd gitops-safe/overlays/gke
kustomize edit set image \
  "humor-game-backend=us-central1-docker.pkg.dev/gke-project-491822/humor-game/backend:${IMAGE_TAG}" \
  "humor-game-frontend=us-central1-docker.pkg.dev/gke-project-491822/humor-game/frontend:${IMAGE_TAG}"

git commit -m "ci: update GKE images to ${IMAGE_TAG} [skip ci]"
git push
```

The `[skip ci]` in the commit message prevents this push from re-triggering the pipeline (which would create an infinite loop).

---

## Making a Code Change

### Option A — Direct to main (small fixes)

```bash
# Make your change
vim backend/server.js

# Test locally first
cd backend && npm test

# Commit and push
git add backend/server.js
git commit -m "fix: improve health endpoint response"
git push origin main
```

Watch the pipeline: https://github.com/ShivamSoni1995/DevOps-Home-Lab-2026-2027/actions

### Option B — Feature branch + PR (recommended)

```bash
# Create a branch
git checkout -b feature/better-health-response

# Make changes, test, commit
vim backend/server.js
cd backend && npm test
git add -A && git commit -m "feat: add version info to health endpoint"
git push -u origin feature/better-health-response

# Open a PR on GitHub
# → CI runs tests only (no deploy)
# → Merge when ready → full pipeline fires
```

### Watching the Deploy

After merge to main, the pipeline takes ~3-5 minutes total:

```bash
# 1. Watch pods rolling out (new pods start before old terminate)
kubectl get pods -n humor-game -w

# 2. Check image tag in kustomization (after Job 3 commits)
grep newTag gitops-safe/overlays/gke/kustomization.yaml

# 3. Check ArgoCD detected and applied the change
kubectl get applications -n argocd

# 4. Verify new code is live
curl http://34.44.151.3/api/health
```

---

## Rollback

### Option 1 — Git revert (preferred, GitOps way)

```bash
# Find the bad commit
git log gitops-safe/overlays/gke/kustomization.yaml

# Revert it — this triggers a new CI run that updates the image tag back
git revert <bad-commit-sha>
git push

# ArgoCD detects the change within 3 minutes and re-applies the old image
```

### Option 2 — Manual override (emergency)

```bash
# Force ArgoCD to sync to a specific git revision
kubectl patch application humor-game-gke -n argocd \
  -p '{"spec":{"source":{"targetRevision":"<good-commit-sha>"}}}' \
  --type=merge

# Reset to main once the bad commit is reverted
kubectl patch application humor-game-gke -n argocd \
  -p '{"spec":{"source":{"targetRevision":"main"}}}' \
  --type=merge
```

> ⚠️ `kubectl set image` won't stick — ArgoCD selfHeal will revert it on the next sync cycle.

---

## Pipeline Failures

### "Tests failed" — Job 1 blocked

```bash
# Run tests locally to reproduce
cd backend && npm test

# Common causes
# - Missing dependency: npm ci (not npm install)
# - Port conflict in test: check backend/tests/ for hardcoded ports
```

### "Push rejected" — Job 3 can't push

The CI uses `GITHUB_TOKEN` to push. If branch protection requires PRs, this push will fail.

Fix: Store a Personal Access Token as `GITOPS_TOKEN` secret and reference it in the workflow:
```yaml
token: ${{ secrets.GITOPS_TOKEN }}  # instead of secrets.GITHUB_TOKEN
```

### "ImagePullBackOff" after deploy

```bash
kubectl describe pod <pod-name> -n humor-game | grep -A5 "Events"
# Look for: "unauthorized" or "not found"

# Verify the image tag exists in AR
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/gke-project-491822/humor-game \
  --include-tags | grep <tag>

# Verify GKE node SA has AR reader access (Phase 5 of gke-setup.md)
```

---

## Required GitHub Secrets

| Secret | Where to get it | Used by |
|--------|----------------|---------|
| `GCP_PROJECT_ID` | GCP Console → Project ID | Job 2: image path |
| `WIF_PROVIDER` | Output from `gke-bootstrap.sh` Phase 4 | Job 2: GCP auth |
| `WIF_SERVICE_ACCOUNT` | Output from `gke-bootstrap.sh` Phase 4 | Job 2: GCP auth |

Set at: Repository → Settings → Secrets and variables → Actions → New repository secret
