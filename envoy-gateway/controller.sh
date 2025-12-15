#!/bin/bash

# Envoy Gateway Controller Setup/Teardown Script
# Usage: ./controller.sh [setup|teardown]

set -e

ENVOY_GATEWAY_VERSION="v1.6.1"
NAMESPACE="envoy-gateway-system"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_usage() {
  echo "Usage: $0 [setup|teardown]"
  echo ""
  echo "Commands:"
  echo "  setup     Install Gateway API CRDs and Envoy Gateway controller"
  echo "  teardown  Remove Envoy Gateway controller and all Gateway API CRDs"
  echo ""
  echo "Examples:"
  echo "  $0 setup      # Install everything"
  echo "  $0 teardown   # Remove everything"
}

setup() {
  echo "=========================================="
  echo "Envoy Gateway Controller Setup"
  echo "=========================================="
  echo ""
  echo "Version: $ENVOY_GATEWAY_VERSION"
  echo ""

  echo -e "${YELLOW}Step 1: Install Gateway API CRDs + Envoy Gateway CRDs...${NC}"
  helm template eg oci://docker.io/envoyproxy/gateway-crds-helm \
    --version $ENVOY_GATEWAY_VERSION \
    --set crds.gatewayAPI.enabled=true \
    --set crds.gatewayAPI.channel=standard \
    --set crds.envoyGateway.enabled=true \
    | kubectl apply --server-side -f -
  echo -e "${GREEN}✅ Gateway API + Envoy Gateway CRDs installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 2: Install TLSRoute CRD (experimental)...${NC}"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
  echo -e "${GREEN}✅ TLSRoute CRD installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 3: Install Envoy Gateway controller...${NC}"
  helm install eg oci://docker.io/envoyproxy/gateway-helm \
    --version $ENVOY_GATEWAY_VERSION \
    -n $NAMESPACE \
    --create-namespace \
    --set config.envoyGateway.extensionApis.enableBackend=true \
    --set config.envoyGateway.provider.kubernetes.deploy.type=GatewayNamespace \
    --skip-crds
  echo -e "${GREEN}✅ Envoy Gateway controller installed${NC}"
  echo ""

  echo -e "${YELLOW}Step 4: Create GatewayClass...${NC}"
  cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
  echo -e "${GREEN}✅ GatewayClass 'eg' created${NC}"
  echo ""

  echo -e "${YELLOW}Step 5: Wait for controller to be ready...${NC}"
  kubectl rollout status deployment/envoy-gateway -n $NAMESPACE --timeout=120s
  echo -e "${GREEN}✅ Envoy Gateway controller ready${NC}"
  echo ""

  echo "=========================================="
  echo -e "${GREEN}✅ Envoy Gateway setup complete!${NC}"
  echo "=========================================="
  echo ""
  echo "Verify installation:"
  echo "  kubectl get pods -n $NAMESPACE"
  echo "  kubectl get gatewayclass"
  echo "  kubectl get crds | grep -E 'gateway|envoyproxy'"
}

teardown() {
  echo "=========================================="
  echo "Envoy Gateway Controller Teardown"
  echo "=========================================="
  echo ""
  echo -e "${RED}WARNING: This will remove:${NC}"
  echo "  - Envoy Gateway controller"
  echo "  - Envoy Gateway CRDs"
  echo "  - Gateway API CRDs (including TLSRoute)"
  echo ""
  echo "All Gateway, HTTPRoute, TLSRoute, SecurityPolicy, etc. resources will be deleted!"
  echo ""

  read -p "Are you sure you want to continue? (yes/no): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi

  echo ""
  echo -e "${YELLOW}Step 1: Delete GatewayClass...${NC}"
  kubectl delete gatewayclass eg --ignore-not-found=true 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found"

  echo ""
  echo -e "${YELLOW}Step 2: Uninstall Envoy Gateway controller...${NC}"
  helm uninstall eg -n $NAMESPACE 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found or already uninstalled"

  echo ""
  echo -e "${YELLOW}Step 3: Delete Envoy Gateway namespace...${NC}"
  kubectl delete namespace $NAMESPACE --ignore-not-found=true && echo -e "${GREEN}✅ Done${NC}"

  echo ""
  echo -e "${YELLOW}Step 4: Delete Envoy Gateway CRDs...${NC}"
  kubectl get crds -o name | grep -E "gateway\.envoyproxy\.io" | xargs -r kubectl delete 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  No Envoy Gateway CRDs found"

  echo ""
  echo -e "${YELLOW}Step 5: Delete TLSRoute CRD (experimental)...${NC}"
  kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml --ignore-not-found=true 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found"

  echo ""
  echo -e "${YELLOW}Step 6: Delete Gateway API CRDs...${NC}"
  helm template eg oci://docker.io/envoyproxy/gateway-crds-helm \
    --version $ENVOY_GATEWAY_VERSION \
    --set crds.gatewayAPI.enabled=true \
    --set crds.gatewayAPI.channel=standard \
    --set crds.envoyGateway.enabled=true \
    2>/dev/null | kubectl delete --ignore-not-found=true -f - 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  Not found"

  echo ""
  echo -e "${YELLOW}Step 7: Delete any remaining Gateway API CRDs...${NC}"
  kubectl get crds -o name | grep -E "gateway\.networking\.k8s\.io" | xargs -r kubectl delete 2>/dev/null && echo -e "${GREEN}✅ Done${NC}" || echo "  No remaining CRDs"

  echo ""
  echo "=========================================="
  echo -e "${GREEN}✅ Envoy Gateway teardown complete!${NC}"
  echo "=========================================="
  echo ""
  echo "Verify no CRDs remain:"
  echo "  kubectl get crds | grep -E 'gateway|envoyproxy'"
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
