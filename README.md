# backstage-idp-reference

**Production-grade Internal Developer Platform built with Backstage, deployed on EKS.**

This reference architecture implements a full IDP used to serve 30+ product teams — enabling self-service infrastructure provisioning, standardized CI/CD workflows, and developer autonomy at scale. Reduced onboarding time by 60%+ and eliminated manual provisioning bottlenecks in production.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DEVELOPER PORTAL                          │
│                    Backstage (EKS / Fargate)                     │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
│  │ Software     │  │ Scaffolder   │  │ TechDocs           │    │
│  │ Catalog      │  │ Templates    │  │ (S3 backend)       │    │
│  └──────┬───────┘  └──────┬───────┘  └────────────────────┘    │
│         │                 │                                      │
│  ┌──────▼───────┐  ┌──────▼───────┐  ┌────────────────────┐    │
│  │ GitHub       │  │ Terraform    │  │ ArgoCD Integration │    │
│  │ Integration  │  │ Cloud Control│  │ (GitOps sync)      │    │
│  └──────────────┘  └──────────────┘  └────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
         │                   │                    │
         ▼                   ▼                    ▼
┌─────────────┐    ┌──────────────────┐  ┌──────────────────┐
│   GitHub    │    │   AWS (EKS,      │  │   ArgoCD         │
│   Actions   │    │   RDS, S3, ECR)  │  │   (GitOps)       │
└─────────────┘    └──────────────────┘  └──────────────────┘
```

---

## Stack

| Layer | Technology |
|---|---|
| Platform | Backstage 1.26, Node.js 20 |
| Infrastructure | Terraform 1.7, AWS EKS 1.29 |
| GitOps | ArgoCD 2.10, GitHub Actions |
| Container Registry | AWS ECR |
| Secrets | AWS Secrets Manager + External Secrets Operator |
| Observability | Datadog, OpenTelemetry |
| Auth | GitHub OAuth + AWS IAM OIDC |
| TechDocs | MkDocs + S3 backend |

---

## Repository Structure

```
backstage-idp-reference/
├── app-config.yaml                    # Base Backstage config
├── app-config.production.yaml         # Production overrides
├── catalog/
│   ├── components/                    # Service entity definitions
│   ├── systems/                       # System groupings
│   └── templates/                     # Scaffolder templates
│       ├── eks-service-template.yaml  # New service on EKS
│       └── terraform-module-template.yaml
├── terraform/
│   ├── eks-cluster/                   # EKS cluster for Backstage
│   └── backstage-infra/               # RDS, S3, ECR, IAM
├── kubernetes/
│   ├── backstage-deployment.yaml
│   ├── backstage-service.yaml
│   └── ingress.yaml
├── .github/workflows/
│   ├── build-push.yaml                # Build & push to ECR
│   └── deploy.yaml                    # ArgoCD sync trigger
├── scripts/
│   ├── bootstrap.sh                   # First-time setup
│   └── health-check.sh
└── docs/
    ├── architecture.md
    └── onboarding.md
```

---

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.7
- kubectl
- Node.js 20+
- Helm 3

### 1. Provision Infrastructure

```bash
# EKS cluster
cd terraform/eks-cluster
terraform init
terraform apply -var="cluster_name=idp-platform" -var="environment=production"

# Backstage supporting infra (RDS, S3, ECR, IAM)
cd ../backstage-infra
terraform init
terraform apply
```

### 2. Bootstrap Backstage

```bash
# Install dependencies
yarn install

# Configure secrets
aws secretsmanager create-secret \
  --name /backstage/production/github-token \
  --secret-string "ghp_yourtoken"

# Apply Kubernetes manifests
kubectl apply -f kubernetes/

# Verify
./scripts/health-check.sh
```

### 3. Load the Software Catalog

```bash
# Import catalog entities
kubectl exec -n backstage deploy/backstage -- \
  node packages/backend/dist/index.js catalog:import \
  --file /catalog
```

---

## Scaffolder Templates

### EKS Service Template

Creates a new microservice with:
- GitHub repository with branch protection
- EKS deployment + HPA + PodDisruptionBudget
- Datadog APM + structured logging
- ArgoCD Application manifest
- Standardized Dockerfile
- GitHub Actions CI pipeline

```yaml
# Trigger via Backstage UI or API
POST /api/scaffolder/v2/tasks
{
  "templateRef": "template:default/eks-service-template",
  "values": {
    "name": "payment-processor",
    "owner": "team-payments",
    "system": "payment-platform",
    "replicaCount": 2,
    "resources": { "cpu": "500m", "memory": "512Mi" }
  }
}
```

### Terraform Module Template

Creates a new Terraform module with:
- Standard module structure
- Pre-wired Atlantis config
- OPA policy tests
- Automated documentation via `terraform-docs`

---

## Software Catalog Structure

Entities follow the [Backstage descriptor format](https://backstage.io/docs/features/software-catalog/descriptor-format):

```
Components → owned by Teams → grouped in Systems → part of Domains
```

Example:

```yaml
# catalog/systems/payment-platform.yaml
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: payment-platform
  annotations:
    backstage.io/techdocs-ref: dir:.
spec:
  owner: team-payments
  domain: fintech
```

---

## Production Considerations

**High Availability:** Backstage runs with 3 replicas across 3 AZs. PodDisruptionBudget ensures at least 2 are always available during node upgrades.

**Database:** PostgreSQL on RDS Multi-AZ. Backstage catalog state is fully reconstructible from GitHub, so RDS is not a critical recovery path — but it enables fast startup.

**Auth:** GitHub OAuth for portal access. Catalog ingestion uses a dedicated GitHub App (not personal token) for auditability and rate limit headroom.

**Secrets:** External Secrets Operator syncs from AWS Secrets Manager to Kubernetes Secrets. No secrets in environment variables or ConfigMaps.

**Cost:** Backstage on Fargate with 2 vCPU / 4GB RAM runs ~$80–120/month. RDS t3.medium Multi-AZ ~$130/month. Total IDP infrastructure: ~$250/month for a 30-team org.

---

## Key Metrics (Production Reference)

| Metric | Result |
|---|---|
| Developer onboarding time | 60%+ reduction |
| Manual provisioning incidents | Eliminated |
| Service creation time | < 8 minutes end-to-end |
| Catalog coverage | 500+ components |
| Template adoption | 95% of new services |

---

## Related Repos

- [`argocd-multi-env-gitops`](https://github.com/CarlosAlejandroPerezCeron/argocd-multi-env-gitops) — GitOps delivery used by scaffolder templates
- [`devsecops-supply-chain-pipeline`](https://github.com/CarlosAlejandroPerezCeron/devsecops-supply-chain-pipeline) — Security controls integrated into scaffolder CI

---

## Author

**Carlos Alejandro Perez Ceron**  
Senior Principal Engineer · Platform Engineering · Cloud Architecture  
[LinkedIn](https://linkedin.com/in/carlos-alejandro-perez-ceron-a3b0b6213) · [infravix.io](https://infravix.io)
