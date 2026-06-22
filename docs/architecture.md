# Architecture — Backstage IDP Reference

## Design Principles

**Self-service over tickets.** Any engineer can provision a new service, database, or topic without opening a ticket. The IDP enforces standards via templates, not gatekeeping.

**GitOps as the source of truth.** No manual kubectl apply in production. Every state change goes through ArgoCD. Catalog state is reconstructible from GitHub at any time.

**Security baked in, not bolted on.** Scaffolder templates produce services that are already compliant: image signing, SBOM, SAST, OPA policies, IRSA, and Datadog APM are defaults — not optional add-ons.

**Cost visibility at the service level.** Every provisioned resource is tagged at creation time with team, system, and environment. Cost allocation is automatic.

## Component Decisions

### Why Backstage?
Evaluated Cortex, Port, and OpsLevel. Backstage wins on extensibility and open-source ecosystem. The plugin API lets us integrate every internal tool without vendor dependency. The tradeoff is operational overhead — Backstage requires a dedicated team to maintain.

### Why EKS over ECS?
Backstage's plugin ecosystem assumes Kubernetes-native tooling (ArgoCD, Prometheus, External Secrets). Running on ECS would require wrapping every Kubernetes-native tool.

### Why External Secrets Operator?
ESO gives us a Kubernetes-native reconciliation loop with auditable sync status. Rotation tracking and centralized visibility that direct Secrets Manager mounting doesn't provide.

### Database: RDS vs Aurora
Using RDS PostgreSQL t3.medium Multi-AZ. Aurora Serverless v2 cold-start behavior on low-traffic periods made Backstage startup time unpredictable. RDS is $30/month more but eliminates that variance.

## Scaling Model

| Dimension | Behavior |
|---|---|
| Backstage pods | HPA: 2–8 replicas on CPU/memory |
| Node capacity | Karpenter: auto-provisions nodes on demand |
| Catalog processing | ~10ms per entity |
| Scaffolder concurrency | 10 parallel task runners |

## Security Controls

| Control | Implementation |
|---|---|
| Auth | GitHub OAuth + group-based authorization |
| Secrets | External Secrets Operator from AWS Secrets Manager |
| Network | Private cluster + ALB ingress with WAF |
| Image security | Trivy scan in CI, Cosign signing |
| IRSA | Backstage SA bound to IAM role via OIDC |
| Encryption | KMS for EKS secrets, RDS, S3 |
