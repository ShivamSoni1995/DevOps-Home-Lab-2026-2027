# Network Policy Interview Guide

Use this as a high-value reference for Kubernetes NetworkPolicy interview rounds (screening, system design, and troubleshooting).

## 1) 30-Second Interview Pitch

"I use Kubernetes NetworkPolicies to enforce least-privilege east-west traffic. I start with default-deny (ingress and egress), then allow only required app paths like frontend -> backend, backend -> database/cache, and DNS egress. I validate policies with active traffic tests, monitor for drops/timeouts, and iterate safely using policy-as-code and staged rollouts."

## 2) Core Concepts Interviewers Expect

1. `NetworkPolicy` controls pod traffic at L3/L4 (IP + port/protocol), not L7.
2. Policies are allow-lists. There is no explicit `deny` rule.
3. A pod becomes isolated for ingress/egress only when selected by a policy with that `policyTypes` direction.
4. `podSelector` in `spec` chooses target pods (the pods being protected).
5. `from`/`to` choose allowed peers; `ports` choose allowed destination ports.
6. `namespaceSelector` and `podSelector` in the same peer entry are ANDed.
7. A CNI plugin must support NetworkPolicy (Calico, Cilium, Antrea, etc.).
8. Service traffic is ultimately pod-to-pod; policy enforcement happens at pod network interface level.

## 3) How Network Policy Is Implemented In This Project

Source of truth: `k8s/network-policies.yaml`

1. `frontend-network-policy`
- Target: pods with `app=frontend`
- Ingress: allow TCP/80
- Egress: allow `backend:3001` and DNS (53 TCP/UDP)

2. `backend-network-policy`
- Target: `app=backend`
- Ingress: allow from `app=frontend` on TCP/3001
- Egress: allow to `app=postgres:5432`, `app=redis:6379`, and DNS

3. `database-network-policy`
- Target: `app=postgres`
- Ingress: allow only `app=backend` on 5432
- Egress: DNS only

4. `redis-network-policy`
- Target: `app=redis`
- Ingress: allow only `app=backend` on 6379
- Egress: DNS only

Apply path in automation: `Makefile` target that runs:
`kubectl apply -f k8s/network-policies.yaml`

## 4) Strong Interview Narrative for This Repo

Use this structure:

1. Problem
- "Without policy, any compromised pod can laterally move to DB/Redis."

2. Design
- "I segmented by app role and allowed only required flows."

3. Execution
- "I wrote four role-based policies (frontend/backend/postgres/redis)."

4. Validation
- "I tested expected allow and deny paths with in-cluster curl/nc pods."

5. Outcome
- "Blast radius reduced; accidental cross-service access blocked."

## 5) Practical Commands You Should Remember

```bash
# List policies
kubectl get networkpolicy -n humor-game

# Inspect one policy
kubectl describe networkpolicy backend-network-policy -n humor-game

# Temporary debug pod
kubectl run netshoot -n humor-game --rm -it \
  --image=nicolaka/netshoot -- /bin/bash

# Test allowed path (example)
nc -zv backend 3001

# Test denied path (example)
nc -zv postgres 5432   # from frontend/debug pod should fail unless allowed
```

## 6) High-Impact Interview Q&A

### Q1: What is the difference between ingress and egress policies?
Ingress controls inbound traffic to selected pods; egress controls outbound traffic from selected pods.

### Q2: How do you create default deny?
Select pods and set `policyTypes: [Ingress, Egress]` with no allow rules (or separate default-deny policies).

### Q3: Why does traffic still flow even after creating a policy?
Likely reasons: target pods not selected by `podSelector`, missing `policyTypes`, unsupported CNI, or traffic path not actually matching tested assumption.

### Q4: Do NetworkPolicies secure NodePort/hostNetwork traffic?
Not reliably for all host-network paths. They primarily govern pod interfaces; host-level controls may also be required.

### Q5: How do you allow same-namespace app-to-app only?
Use `podSelector` peer rules and avoid broad `namespaceSelector: {}` unless needed.

### Q6: Why allow DNS egress?
Apps often need DNS for service discovery or outbound name resolution. Blocking DNS causes hidden failures/timeouts.

### Q7: How do you handle monitoring and health checks?
Explicitly allow required paths/ports from monitoring namespaces or probes as needed.

### Q8: Can NetworkPolicy filter HTTP methods or URLs?
No. Use service mesh/WAF/API gateway for L7 controls.

### Q9: How do you safely roll out stricter policies?
Stage in non-prod, baseline flows, introduce default deny in phases, and validate with synthetic tests.

### Q10: How do you prove policy effectiveness?
Show before/after connectivity matrix, blocked test cases, and incident risk reduction narrative.

## 7) Common Mistakes (Interview Gold)

1. Forgetting CNI support for NetworkPolicy.
2. Applying egress restrictions without DNS allow.
3. Over-broad selectors (`namespaceSelector: {}`) that allow too much.
4. Assuming Services bypass policy.
5. Missing policy for newly added workloads.
6. Relying on comments/documentation but not runtime validation.

## 8) Connectivity Matrix Template (Use in Interviews)

| Source | Destination | Port | Expected |
|---|---|---:|---|
| frontend | backend | 3001 | Allow |
| frontend | postgres | 5432 | Deny |
| backend | postgres | 5432 | Allow |
| backend | redis | 6379 | Allow |
| backend | internet arbitrary | any | Deny (unless explicitly allowed) |
| postgres | backend | 3001 | Deny |

Bring this table into design interviews. It shows structured security thinking.

## 9) Advanced Follow-Ups (Senior Rounds)

1. How to enforce policy governance?
- Use OPA Gatekeeper/Kyverno policies to require default-deny and block wildcard peers.

2. How to version and test policies?
- Keep in GitOps, add CI checks, run ephemeral namespace connectivity tests.

3. How to observe denied flows?
- CNI observability (e.g., Cilium Hubble / Calico flow logs), plus app timeout/error dashboards.

4. How to combine with zero trust?
- NetworkPolicy (L3/L4) + mTLS identity + workload IAM + secret rotation + runtime detection.

## 10) Whiteboard Answer: "Design Network Policy for 3-tier app"

1. Create namespace-scoped default deny ingress+egress.
2. Allow ingress to frontend only from ingress controller.
3. Allow frontend egress only to backend service port.
4. Allow backend ingress only from frontend.
5. Allow backend egress only to DB/cache + DNS.
6. Allow DB/cache ingress only from backend.
7. Add explicit monitoring/metrics exceptions.
8. Validate with connectivity tests and observability.

## 11) Scenario-Based Answers You Can Reuse

### Scenario A: "Users get 504 after policy rollout"
Response:
1. Check policy selectors match pod labels.
2. Verify backend ingress from frontend is present.
3. Validate backend egress to DB/Redis and DNS.
4. Run in-pod connectivity tests (`nc`, `dig`).
5. Roll back last policy change if SLA impact persists.

### Scenario B: "Security asks for tighter egress"
Response:
1. Inventory required outbound endpoints.
2. Introduce least-privilege egress in stages.
3. Add DNS and approved external CIDRs/FQDN controls (via CNI/service mesh capabilities).
4. Measure breakage and iterate.

### Scenario C: "New microservice added"
Response:
1. Update connectivity matrix first.
2. Add service-specific policy in same PR.
3. Add CI verification tests.
4. Deploy canary and monitor denied-flow telemetry.

## 12) Fast Revision Checklist (Before Interview)

1. I can explain default-deny mechanics clearly.
2. I can explain selector logic (`podSelector`, `namespaceSelector`).
3. I can describe at least one real policy from this project.
4. I can troubleshoot a broken policy rollout end-to-end.
5. I can articulate L3/L4 limit and L7 complementary controls.
6. I can discuss safe rollout and validation strategy.

## 13) One-Liner Summary

NetworkPolicy in this project is implemented as role-based, least-privilege segmentation in `k8s/network-policies.yaml`, enforced via Kubernetes selectors and explicit ingress/egress allow rules, then applied through deployment automation for repeatable security posture.
