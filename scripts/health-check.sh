#!/usr/bin/env bash
# health-check.sh — Validates Backstage IDP platform health
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

check() {
  local name="$1"; shift
  if "$@" &>/dev/null; then
    echo -e "${GREEN}✓${NC} ${name}"
    ((PASS++))
  else
    echo -e "${RED}✗${NC} ${name}"
    ((FAIL++))
  fi
}

warn_check() {
  local name="$1"; shift
  if "$@" &>/dev/null; then
    echo -e "${GREEN}✓${NC} ${name}"
  else
    echo -e "${YELLOW}⚠${NC} ${name} (non-blocking)"
  fi
}

echo "═══════════════════════════════════════"
echo " Backstage IDP — Health Check"
echo "═══════════════════════════════════════"
echo ""

echo "── Kubernetes ──────────────────────────"
check "backstage namespace"       kubectl get namespace backstage
check "deployment ready"          kubectl -n backstage rollout status deployment/backstage --timeout=30s
check "replicas >= 2"             bash -c '[[ $(kubectl -n backstage get deploy backstage -o jsonpath="{.status.readyReplicas}") -ge 2 ]]'
check "PDB configured"            kubectl -n backstage get pdb backstage-pdb
check "HPA configured"            kubectl -n backstage get hpa backstage-hpa
check "IRSA service account"      kubectl -n backstage get sa backstage

echo ""
echo "── Supporting Services ─────────────────"
check "cert-manager"              kubectl -n cert-manager rollout status deploy/cert-manager --timeout=30s
check "external-secrets"         kubectl -n external-secrets rollout status deploy/external-secrets --timeout=30s
check "argocd-server"            kubectl -n argocd rollout status deploy/argocd-server --timeout=30s

echo ""
echo "── Backstage API ───────────────────────"
BACKSTAGE_URL="${BACKSTAGE_URL:-http://localhost:7007}"
warn_check "healthcheck endpoint"   curl -sf "${BACKSTAGE_URL}/healthcheck"
warn_check "catalog API"            curl -sf "${BACKSTAGE_URL}/api/catalog/entities?limit=1"

echo ""
echo "═══════════════════════════════════════"
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}All checks passed (${PASS}/${PASS})${NC}"
else
  echo -e "${RED}${FAIL} check(s) failed${NC}"
  exit 1
fi
