#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo ""
    echo "Please create config.env from the example:"
    echo "  cd coverage && cp config.env.example config.env"
    echo "  # Edit config.env with your environment values"
    exit 1
fi

set -a
source "$CONFIG_FILE"
set +a

# Validate required variables
if [[ -z "$DOMAIN" || "$DOMAIN" == "your-cluster.your-domain.com" ]]; then
    echo "❌ DOMAIN not configured in config.env"
    exit 1
fi

echo "=========================================="
echo "Envoy Gateway Implementation Deployment"
echo "Domain: $DOMAIN"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Helper function to apply YAML with variable substitution
apply_yaml_dir() {
    local dir="$1"
    for file in "$dir"/*.yaml "$dir"/*.yml; do
        [[ -f "$file" ]] || continue
        echo "  📄 Applying: $(basename "$file")"
        # Include OIDC variables for OIDC/JWT authentication (optional)
        envsubst '${DOMAIN} ${CLUSTER_ISSUER} ${OIDC_ISSUER_URL} ${OIDC_CLIENT_ID} ${OIDC_JWKS_URL}' < "$file" | kubectl apply -f -
    done
}

echo "📋 Deployment Order:"
echo "  1. Apps & Namespace (namespace, echo-server, ext-authz)"
echo "  2. Gateway API (EnvoyProxy, Gateway, ClientTrafficPolicy)"
echo "  3. Envoy Gateway Policies (SecurityPolicy, BackendTrafficPolicy, HTTPRouteFilter)"
echo "  4. HTTPRoutes (redirect + comprehensive-test + policies)"
echo ""
read -p "Press Enter to begin deployment..."

echo ""
echo "=========================================="
echo "Step 1: Apps & Namespace..."
echo "=========================================="
apply_yaml_dir 01-apps-and-namespace

echo ""
echo "Waiting for pods..."
kubectl wait --for=condition=ready pod -l app=echo-server,version=stable -n ingress2envoygateway --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=echo-server,version=canary -n ingress2envoygateway --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=ext-authz -n ingress2envoygateway --timeout=120s || true

# Check if nginx-tls backend was deployed (for Backend TLS testing)
if kubectl get deployment nginx-tls -n ingress2envoygateway &>/dev/null; then
  echo ""
  echo "🔐 Backend TLS: Setting up certificates..."
  
  # Wait for cert-manager to create CA secret
  echo "  Waiting for cert-manager to create CA certificate..."
  for i in {1..30}; do
    if kubectl get secret nginx-tls-ca-secret -n ingress2envoygateway &>/dev/null; then
      echo -e "  ${GREEN}✅ CA secret created${NC}"
      break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
  done
  
  # Note: BackendTLSPolicy uses Secret directly (nginx-tls-ca-secret)
  # No ConfigMap conversion needed - Envoy Gateway supports Secret references
  
  # Wait for NGINX TLS pod
  echo "  Waiting for NGINX TLS backend..."
  kubectl wait --for=condition=ready pod -l app=nginx-tls -n ingress2envoygateway --timeout=120s || true
fi

echo ""
echo "📦 Deployed:"
kubectl get namespace ingress2envoygateway
kubectl get pods,svc -n ingress2envoygateway -o wide
echo ""
read -p "Press Enter to continue to Step 2..."

echo ""
echo "=========================================="
echo "Step 2: Gateway API Resources..."
echo "=========================================="
apply_yaml_dir 02-gateway

echo ""
echo "Waiting for Gateway..."
sleep 10
kubectl wait --for=condition=Programmed gateway/external-gateway -n ingress2envoygateway --timeout=120s || true

echo ""
echo "🌐 Gateway:"
kubectl get gateway external-gateway -n ingress2envoygateway
echo ""
echo "🔧 Envoy Proxy Pod (GatewayNamespace mode):"
kubectl get pods -n ingress2envoygateway -l gateway.envoyproxy.io/owning-gateway-name=external-gateway
echo ""
echo "📜 ClientTrafficPolicy:"
kubectl get clienttrafficpolicy -n ingress2envoygateway
echo ""
echo "🏗️ EnvoyProxy (Infrastructure Config):"
kubectl get envoyproxy -n ingress2envoygateway
echo ""
read -p "Press Enter to continue to Step 3..."

echo ""
echo "=========================================="
echo "Step 3: Envoy Gateway Policies..."
echo "=========================================="
apply_yaml_dir 03-envoy-gateway-policies

echo ""
echo "🔐 SecurityPolicy:"
kubectl get securitypolicy -n ingress2envoygateway
echo ""
echo "🔄 BackendTrafficPolicy:"
kubectl get backendtrafficpolicy -n ingress2envoygateway
echo ""
echo "🛠️ HTTPRouteFilter:"
kubectl get httproutefilter -n ingress2envoygateway
echo ""
read -p "Press Enter to continue to Step 4..."

echo ""
echo "=========================================="
echo "Step 4: HTTPRoutes..."
echo "=========================================="
apply_yaml_dir 04-routing

echo ""
echo "Waiting for routes..."
sleep 5

echo ""
echo "📍 HTTPRoutes:"
kubectl get httproute -n ingress2envoygateway
echo ""
echo "🔒 TLSRoute:"
kubectl get tlsroute -n ingress2envoygateway
echo ""
read -p "Press Enter to view final summary..."

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""

echo "📊 Resource Status:"
echo ""
echo "Namespace: ingress2envoygateway"
kubectl get pods -n ingress2envoygateway
echo ""

echo "Gateway:"
kubectl get gateway external-gateway -n ingress2envoygateway
echo ""

echo "SecurityPolicy:"
kubectl get securitypolicy -n ingress2envoygateway
echo ""

echo "BackendTrafficPolicy:"
kubectl get backendtrafficpolicy -n ingress2envoygateway
echo ""

echo "ClientTrafficPolicy:"
kubectl get clienttrafficpolicy -n ingress2envoygateway
echo ""

echo "EnvoyProxy (Infrastructure: externalTrafficPolicy, annotations):"
kubectl get envoyproxy -n ingress2envoygateway
echo ""

echo "HTTPRouteFilter:"
kubectl get httproutefilter -n ingress2envoygateway
echo ""

echo "HTTPRoutes:"
kubectl get httproute -n ingress2envoygateway
echo ""

echo "TLSRoute:"
kubectl get tlsroute -n ingress2envoygateway
echo ""

# Show Backend TLS resources if deployed
if kubectl get deployment nginx-tls -n ingress2envoygateway &>/dev/null; then
  echo "Backend TLS (Test 17):"
  kubectl get backendtlspolicy -n ingress2envoygateway 2>/dev/null || echo "  (no BackendTLSPolicy found)"
  echo ""
  echo "CA Secret (for BackendTLSPolicy):"
  kubectl get secret nginx-tls-ca-secret -n ingress2envoygateway 2>/dev/null || echo "  (waiting for cert-manager)"
  echo ""
fi

echo "=========================================="
echo "🧪 Ready for Testing!"
echo "=========================================="
echo ""
echo "Gateway Address:"
GATEWAY_ADDRESS=$(kubectl get gateway external-gateway -n ingress2envoygateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "Not ready yet")
echo "  $GATEWAY_ADDRESS"
echo ""
echo "Test hostname: eg.${DOMAIN}"
echo ""
echo "Run tests:"
echo "  ./test.sh"
echo ""
