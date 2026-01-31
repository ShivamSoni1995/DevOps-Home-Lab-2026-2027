# Copilot Instructions for DevOps Home Lab

## Project Overview
Production-grade Kubernetes tutorial project deploying a "Humor Memory Game" web app through a complete DevOps pipeline: Docker → k3d Kubernetes → Monitoring → GitOps → Global CDN.

## Architecture
```
Frontend (Vanilla JS + Nginx:80) → Backend (Node.js Express:3001) → PostgreSQL:5432 + Redis:6379
                                         ↓
                                  Prometheus:9090 → Grafana:3000
```

**Namespaces**: `humor-game` (app), `monitoring` (Prometheus/Grafana), `argocd` (GitOps), `ingress-nginx`

## Key Commands
```bash
# Full deployment (creates k3d cluster + all components)
make deploy-all

# Individual components
make setup-cluster      # k3d cluster with port 8080→80, 8443→443
make deploy-app         # Applies k8s/*.yaml in order
make deploy-monitoring  # Prometheus + Grafana stack
make deploy-gitops      # ArgoCD from gitops-safe/

# Verification
make verify             # All pods, ingress, HPA status
make test-endpoints     # curl /api/health with Host: gameapp.local

# Access services (port-forward)
make port-forward-grafana    # localhost:3000
make port-forward-prometheus # localhost:9090
make port-forward-argocd     # localhost:8090
```

## Service Communication Pattern
- **Ingress routing**: `/api/*`, `/health`, `/metrics` → backend:3001; `/` → frontend:80
- **Internal DNS**: `backend.humor-game.svc.cluster.local`, `postgres`, `redis`
- **Hosts**: `gameapp.local` (local), `shivamsoni.duckdns.org` (production)

## Configuration Locations
| Purpose | File(s) |
|---------|---------|
| App config | [k8s/configmap.yaml](k8s/configmap.yaml), [env/env.example](env/env.example) |
| Secrets | [k8s/secrets.template.yaml](k8s/secrets.template.yaml) (DB_PASSWORD, REDIS_PASSWORD, JWT_SECRET) |
| GitOps base | [gitops-safe/base/kustomization.yaml](gitops-safe/base/kustomization.yaml) |
| Prometheus scrape | [k8s/monitoring.yaml](k8s/monitoring.yaml) - static targets + kubernetes_sd |

## Backend Patterns
- **Metrics**: Prometheus via `prom-client` at `/metrics` - see [backend/middleware/metrics.js](backend/middleware/metrics.js)
- **Database**: Pool in [backend/models/database.js](backend/models/database.js), init SQL in [database/combined-init.sql](database/combined-init.sql)
- **Routes**: `/api/game/*`, `/api/scores/*`, `/api/leaderboard/*` in [backend/routes/](backend/routes/)
- **Health check**: `/health` returns DB + Redis status

## Kubernetes Conventions
- All app resources use `namespace: humor-game`
- ConfigMaps/Secrets referenced via `valueFrom.configMapKeyRef`/`secretKeyRef`
- Images use `imagePullPolicy: Never` (local k3d registry)
- Backend pods have `prometheus.io/scrape: "true"` annotations

## GitOps Structure (Kustomize)
```
gitops-safe/
├── base/           # Core resources (postgres, redis, backend, frontend)
├── overlays/dev/   # Dev-specific patches
├── argocd-application.yaml   # Points to gitops-safe/overlays/dev
└── argocd-project.yaml       # humor-game-safe project
```

## Network Policies
[k8s/network-policies.yaml](k8s/network-policies.yaml) enforces:
- Frontend → backend:3001 only
- Backend → postgres:5432, redis:6379 only
- All pods allow DNS (UDP/TCP 53)

## Local Development
```bash
# Docker Compose (bypasses k8s)
docker-compose up -d
curl http://localhost:3001/api/health

# Backend dev mode
cd backend && npm run dev  # nodemon watches server.js
```

## Adding New Features
1. **New API endpoint**: Add route in [backend/routes/](backend/routes/), register in [backend/server.js](backend/server.js)
2. **New K8s resource**: Add to [k8s/](k8s/), update `make deploy-app` order if dependencies exist
3. **GitOps resource**: Add to [gitops-safe/base/](gitops-safe/base/), list in kustomization.yaml

## Troubleshooting
- Check pod logs: `kubectl logs -l app=backend -n humor-game`
- Verify scrape targets: Prometheus UI → Status → Targets
- ArgoCD password: `kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d`
