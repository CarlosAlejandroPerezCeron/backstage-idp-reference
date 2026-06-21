#!/usr/bin/env bash
# bootstrap.sh — First-time IDP platform setup
# Usage: ./scripts/bootstrap.sh --env production --cluster idp-platform --region us-east-1
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENV="production"
CLUSTER_NAME="idp-platform"
AWS_REGION="us-east-1"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env)      ENV="$2";          shift 2 ;;
    --cluster)  CLUSTER_NAME="$2"; shift 2 ;;
    --region)   AWS_REGION="$2";   shift 2 ;;
    *)          fail "Unknown argument: $1" ;;
  esac
done

check_deps() {
  log "Checking dependencies..."
  local deps=("aws" "kubectl" "helm" "terraform" "node" "yarn" "argocd")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      fail "Required tool not found: $dep"
    fi
  done
  ok "All dependencies present"
}

configure_kubectl() {
  log "Configuring kubectl for cluster ${CLUSTER_NAME}..."
  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --alias "${CLUSTER_NAME}"
  kubectl cluster-info
  ok "kubectl configured"
}

install_cert_manager() {
  log "Installing cert-manager..."
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --version v1.14.0 \
    --set installCRDs=true \
    --wait --timeout 5m
  ok "cert-manager installed"
}

install_external_secrets() {
  log "Installing External Secrets Operator..."
  helm repo add external-secrets https://charts.external-secrets.io --force-update
  helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --version 0.9.13 \
    --wait --timeout 5m
  ok "External Secrets Operator installed"
}

install_argocd() {
  log "Installing ArgoCD..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
  kubectl -n argocd wait deploy/argocd-server --for=condition=Available --timeout=5m
  ok "ArgoCD installed"

  log "Retrieving initial ArgoCD admin password..."
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
  warn "ArgoCD admin password: ${ARGOCD_PASSWORD} — change immediately!"
}

install_backstage() {
  log "Creating backstage namespace..."
  kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -

  log "Applying External Secrets for Backstage..."
  kubectl apply -f kubernetes/external-secrets.yaml -n backstage

  log "Deploying Backstage..."
  kubectl apply -f kubernetes/ -n backstage
  kubectl -n backstage rollout status deployment/backstage --timeout=5m
  ok "Backstage deployed"
}

verify() {
  log "Running health checks..."
  ./scripts/health-check.sh
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   Backstage IDP Bootstrap — ${ENV}        "
echo "╚═══════════════════════════════════════════╝"
echo ""

check_deps
configure_kubectl
install_cert_manager
install_external_secrets
install_argocd
install_backstage
verify

ok "Bootstrap complete. Backstage IDP is running."
echo ""
echo "  Portal:  https://idp.infravix.io"
echo "  ArgoCD:  https://argocd.infravix.io"
echo ""
