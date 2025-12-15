#!/bin/bash

# KGateway Controller Setup/Teardown Script
# Usage: ./controller.sh [setup|teardown]

set -e

KGATEWAY_VERSION="v2.2.0-main"
GATEWAY_API_VERSION="v1.4.1"
NAMESPACE="kgateway-system"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_usage() {
  echo "Usage: $0 [setup|teardown]"
  echo ""
  echo "Commands:"
  echo "  setup     Install Gateway API CRDs and KGateway controller"
  echo "  teardown  Remove KGateway controller and all Gateway API CRDs"
  echo ""
  echo "Examples:"
  echo "  $0 setup      # Install everything"
  echo "  $0 teardown   # Remove everything"
}

setup() {
  echo "=========================================="
  echo "KGateway Controller Setup"
  echo "=========================================="
  echo ""
  echo "Versions:"
  echo "  KGateway: $KGATEWAY_VERSION"
  echo "  Gateway API: $GATEWAY_API_VERSION"
  echo ""

  echo -e "${YELLOW}Step 1: Install Gateway API CRDs (standard)...${NC}"
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
  echo -e "${GREEN}✅ Gateway API CRDs installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 2: Install TLSRoute CRD (experimental)...${NC}"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
  echo -e "${GREEN}✅ TLSRoute CRD installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 3: Install KGateway CRDs...${NC}"
  helm upgrade -i --create-namespace --namespace $NAMESPACE \
    --version $KGATEWAY_VERSION \
    kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds
  echo -e "${GREEN}✅ KGateway CRDs installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 4: Install KGateway controller...${NC}"
  helm upgrade -i -n $NAMESPACE kgateway \
    oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
    --version $KGATEWAY_VERSION \
    --set controller.image.pullPolicy=Always
  echo -e "${GREEN}✅ KGateway controller installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 5: Wait for controller to be ready...${NC}"
  kubectl rollout status deployment/kgateway -n $NAMESPACE --timeout=120s
  echo -e "${GREEN}✅ KGateway controller ready${NC}"
  echo ""

  echo "=========================================="
  echo -e "${GREEN}✅ KGateway setup complete!${NC}"
  echo "=========================================="
  echo ""
  echo "Verify installation:"
  echo "  kubectl get pods -n $NAMESPACE"
  echo "  kubectl get gatewayclass"
  echo "  kubectl get crds | grep -E 'gateway|kgateway'"
}

teardown() {
  echo "=========================================="
  echo "KGateway Controller Teardown"
  echo "=========================================="
  echo ""
  echo -e "${RED}WARNING: This will remove:${NC}"
  echo "  - KGateway controller"
  echo "  - KGateway CRDs"
  echo "  - Gateway API CRDs (including TLSRoute)"
  echo ""
  echo "All Gateway, HTTPRoute, TLSRoute, etc. resources will be deleted!"
  echo ""

  read -p "Are you sure you want to continue? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""
  echo -e "${YELLOW}Step 1: Uninstall KGateway controller...${NC}"
  helm uninstall kgateway -n $NAMESPACE 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found or already uninstalled"

  echo ""
  echo -e "${YELLOW}Step 2: Uninstall KGateway CRDs...${NC}"
  helm uninstall kgateway-crds -n $NAMESPACE 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found or already uninstalled"

  echo ""
  echo -e "${YELLOW}Step 3: Delete KGateway namespace...${NC}"
  kubectl delete namespace $NAMESPACE --ignore-not-found=true && echo -e "${GREEN}✅ Done${NC}"

  echo ""
  echo -e "${YELLOW}Step 4: Delete remaining KGateway CRDs...${NC}"
  kubectl get crds -o name | grep -E "kgateway\.dev|gloo\.solo\.io" | xargs -r kubectl delete 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  No KGateway CRDs found"

  echo ""
  echo -e "${YELLOW}Step 5: Delete TLSRoute CRD (experimental)...${NC}"
  kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml --ignore-not-found=true 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found"

  echo ""
  echo -e "${YELLOW}Step 6: Delete Gateway API CRDs (standard)...${NC}"
  kubectl delete -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" --ignore-not-found=true 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found"

  echo ""
  echo "=========================================="
  echo -e "${GREEN}✅ KGateway teardown complete!${NC}"
  echo "=========================================="
  echo ""
  echo "Verify no CRDs remain:"
  echo "  kubectl get crds | grep -E 'gateway|kgateway|gloo'"
}

# Main
case "${1:-}" in
  setup)
    setup
    ;;
  teardown)
    teardown
    ;;
  *)
    show_usage
    exit 1
    ;;
esac
