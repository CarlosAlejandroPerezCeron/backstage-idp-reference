# Architecture — Backstage IDP Reference

## Design Principles

**Self-service over tickets.** Any engineer can provision a new service, database, or topic without opening a ticket. The IDP enforces standards via templates, not gatekeeping.

**GitOps as the source of truth.** No manual `kubectl apply` in production. Every state change goes through ArgoCD. Catalog state is reconstructible from GitHub at any time.

**Security baked in, not bolted on.** Scaffolder templates produce services that are already compliant: image signing, SBOM, SAST, OPA policies, IRSA, and Datadog APM are defaults — not optional add-ons.

**Cost visibility at the service level.** Every provisioned resource is tagged at creation time with team, system, and environment. Cost allocation is automatic.

---

## Component Decisions

### Why Backstage?

Evaluated Cortex, Port, and OpsLevel. Backstage wins on extensibility and open-source ecosystem. The plugin API lets us integrate every internal tool without vendor dependency. The tradeoff is operational overhead — Backstage requires a dedicated team to maintain.

### Why EKS over ECS?

Backstage's plugin ecosystem assumes Kubernetes-native tooling (ArgoCD, Prometheus, External Secrets). Running on ECS would require wrapping every Kubernetes-native tool, which adds more complexity than it saves.

### Why External Secrets Operator over mounting Secrets Manager directly?

ESO gives us a Kubernetes-native reconciliation loop with auditable sync status. Direct Secrets Manager mounting via the AWS provider is simpler but loses the centralized visibility and rotation tracking that ESO provides.

### Database: RDS vs Aurora

Using RDS PostgreSQL t3.medium Multi-AZ. Aurora Serverless v2 was considered but the cold-start behavior on low-traffic periods (nights/weekends) made Backstage startup time unpredictable. RDS with a stable instance is $30/month more but eliminates that variance.

---

## Scaling Model

| Dimension | Behavior |
|---|---|
| Backstage pods | HPA: 2–8 replicas on CPU/memory |
| Node capacity | Karpenter: auto-provisions nodes on demand |
| Catalog processing | Linear with repo count — ~10ms per entity |
| Scaffolder concurrency | 10 parallel task runners (configurable) |
| TechDocs build | Offloaded to CI — no impact on portal |

At 500+ catalog entities and 30+ teams, Backstage comfortably runs on 3 replicas with 2 vCPU / 2 GB RAM each. Plan for 5–6 replicas at 1,000+ entities.

---

## Security Controls

| Control | Implementation |
|---|---|
| Auth | GitHub OAuth + group-based authorization |
| Secrets | External Secrets Operator from AWS Secrets Manager |
| Network | Private cluster + ALB ingress with WAF |
| Image security | Trivy scan in CI, Cosign signing, ECR image scanning |
| IRSA | Backstage SA bound to IAM role via OIDC |
| Audit | GitHub App integration for auditable catalog writes |
| Encryption | KMS for EKS secrets, RDS, S3 (TechDocs) |

---

## Operational Runbooks

- [Backstage restart procedure](https://runbooks.infravix.io/backstage/restart)
- [Database failover](https://runbooks.infravix.io/backstage/db-failover)
- [ArgoCD app out of sync](https://runbooks.infravix.io/argocd/out-of-sync)
- [Certificate renewal](https://runbooks.infravix.io/backstage/certs)
- [Catalog entity missing](https://runbooks.infravix.io/backstage/catalog-missing)
