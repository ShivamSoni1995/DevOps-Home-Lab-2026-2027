# 📚 DevOps Home Lab — Documentation

*Learn production DevOps by building and deploying the Humor Memory Game: Docker → Kubernetes → GitOps → GKE*

[![Live App](https://img.shields.io/badge/Live_App-GKE-blue?style=for-the-badge)](http://34.44.151.3)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-orange?style=for-the-badge)](./argocd-deep-dive.md)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-black?style=for-the-badge)](./ci-cd-pipeline.md)

## 🎮 **Application Preview**

![Humor Memory Game Interface](../assets/images/hga.jpg)

*The Humor Memory Game — a 4×4 card memory game with leaderboard, scoring, and stats. Running live on GKE Autopilot at `http://34.44.151.3`.*

---

## 🗺️ Learning Path

Two tracks depending on your goal:

### Track A — Local Development (Learn the concepts)

| Step | Guide | What You'll Learn | Time |
|------|-------|-------------------|------|
| 0 | [Overview](00-overview.md) | Architecture and full roadmap | 15 min |
| 1 | [Prerequisites](01-prereqs.md) | Docker, kubectl, local tooling | 30 min |
| 2 | [Docker Compose](02-compose.md) | Multi-container local dev | 45 min |
| 3 | [Kubernetes Basics](03-k8s-basics.md) | Deploy on local k3d cluster | 60 min |
| 4 | [Ingress & Networking](04-ingress.md) | Route traffic into your cluster | 45 min |
| 5 | [Observability](05-observability.md) | Prometheus + Grafana monitoring | 90 min |
| 6 | [GitOps](06-gitops.md) | ArgoCD automated deployments | 60 min |

### Track B — GKE Production (What's actually running)

| Step | Guide | What You'll Learn | Time |
|------|-------|-------------------|------|
| 1 | [GKE Setup](gke-setup.md) | Bootstrap GCP infra, WIF, Artifact Registry, cluster | 60 min |
| 2 | [CI/CD Pipeline](ci-cd-pipeline.md) | GitHub Actions → build → push → ArgoCD sync | 30 min |
| 3 | [GKE Validation](gke-migration-validation.md) | Verify the full stack is healthy | 20 min |
| 4 | [GitOps Deep Dive](argocd-deep-dive.md) | How ArgoCD manages the live cluster | 30 min |

---

## 🔧 Reference

### Core Reference
- [Troubleshooting Guide](08-troubleshooting.md) — common issues including GKE Autopilot gotchas
- [GitOps Troubleshooting](gitops-troubleshooting.md) — ArgoCD sync problems and merge conflicts
- [FAQ](09-faq.md) — quick answers
- [Glossary](10-glossary.md) — terms and definitions
- [Architecture Decisions](11-decision-notes.md) — why we chose each technology

### Deep Dives
- [ArgoCD Deep Dive](argocd-deep-dive.md) — GitOps internals and sync mechanics
- [Network Policy Interview Guide](network-policy-interview-guide.md) — K8s NP for interviews
- [Security Contexts Guide](security-contexts-guide.md) — container security hardening

---

## 🚀 Quick Start (GKE — already running)

```bash
# Check live app
curl http://34.44.151.3/api/health

# Check cluster state
export USE_GKE_GCLOUD_AUTH_PLUGIN=True
kubectl get pods -n humor-game
kubectl get applications -n argocd

# Deploy a change (triggers full CI/CD pipeline)
git checkout -b feature/my-change
# ... make code changes in backend/ or frontend/ ...
git push -u origin feature/my-change
# Open PR → merge to main → CI builds → ArgoCD syncs automatically
```

---

## ✅ Current Production State

| Component | Status | Details |
|-----------|--------|---------|
| GKE Autopilot cluster | ✅ Running | `humor-game-gke`, us-central1 |
| Backend (×2 pods) | ✅ Healthy | Node.js Express, HPA min=2 |
| Frontend (×2 pods) | ✅ Healthy | Nginx + Vanilla JS, HPA min=2 |
| PostgreSQL | ✅ Healthy | Persistent volume, `standard-rwo` |
| Redis | ✅ Healthy | In-memory cache |
| ingress-nginx | ✅ Healthy | LoadBalancer IP `34.44.151.3` |
| ArgoCD | ✅ Synced / Healthy | Auto-sync + selfHeal on |
| CI Pipeline | ✅ Active | Builds on push to `main` |

---

## 📞 Getting Help

- **Pods won't start** → [Troubleshooting: Pod Issues](08-troubleshooting.md#pod-issues)
- **ArgoCD OutOfSync** → [GitOps Troubleshooting](gitops-troubleshooting.md)
- **GKE-specific issues** → [Troubleshooting: GKE Autopilot](08-troubleshooting.md#gke-autopilot-issues)
- **Pipeline not running** → [CI/CD Pipeline Guide](ci-cd-pipeline.md)
- **GitHub Issues** → [ShivamSoni1995/DevOps-Home-Lab-2026-2027](https://github.com/ShivamSoni1995/DevOps-Home-Lab-2026-2027/issues)
