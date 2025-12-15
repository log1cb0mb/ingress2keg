#!/bin/bash

echo "=========================================="
echo "KGateway Implementation Cleanup"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "⚠️  This will delete:"
echo "  - Namespace: ingress2kgateway (echo-server + ext-authz)"
echo "  - Gateway: external-gateway (ingress2kgateway)"
echo "  - GatewayExtension: ext-auth-http (ingress2kgateway)"
echo "  - BackendConfigPolicy: session-affinity-policy, session-affinity-policy-canary"
echo "  - HTTPRoutes: http-to-https-redirect, comprehensive-test-route, regex-rewrite-test-route, single-capture-test-route"
echo "  - TrafficPolicy: comprehensive-test-policy, regex-rewrite-test-policy, single-capture-test-policy"
echo "  - ReferenceGrant: allow-kgateway-to-apps"
echo ""

read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo ""
echo "🧹 Starting cleanup (reverse order)..."
echo ""

# Delete in reverse order of creation
echo "Step 1: Deleting HTTPRoutes and TrafficPolicy..."
kubectl delete httproute comprehensive-test-route -n ingress2kgateway --ignore-not-found=true
kubectl delete httproute regex-rewrite-test-route -n ingress2kgateway --ignore-not-found=true
kubectl delete httproute single-capture-test-route -n ingress2kgateway --ignore-not-found=true
kubectl delete httproute http-to-https-redirect -n ingress2kgateway --ignore-not-found=true
kubectl delete trafficpolicy comprehensive-test-policy -n ingress2kgateway --ignore-not-found=true
kubectl delete trafficpolicy regex-rewrite-test-policy -n ingress2kgateway --ignore-not-found=true
kubectl delete trafficpolicy single-capture-test-policy -n ingress2kgateway --ignore-not-found=true
echo -e "${GREEN}✅ Routes deleted${NC}"
echo ""

echo "Step 2: Deleting KGateway Extensions..."
kubectl delete gatewayextension ext-auth-http -n ingress2kgateway --ignore-not-found=true
kubectl delete backendconfigpolicy -n ingress2kgateway --all --ignore-not-found=true
echo -e "${GREEN}✅ Extensions deleted${NC}"
echo ""

echo "Step 3: Deleting Gateway API Resources..."
kubectl delete gateway external-gateway -n ingress2kgateway --ignore-not-found=true
kubectl delete referencegrant allow-kgateway-to-apps -n ingress2kgateway --ignore-not-found=true
echo -e "${GREEN}✅ Gateway resources deleted${NC}"
echo ""

echo "Step 4: Deleting Apps and Namespace..."
kubectl delete namespace ingress2kgateway --ignore-not-found=true
echo -e "${YELLOW}⏳ Waiting for namespace deletion...${NC}"

# Wait for namespace to be fully deleted
for i in {1..60}; do
    if ! kubectl get namespace ingress2kgateway &>/dev/null; then
        echo -e "${GREEN}✅ Namespace deleted${NC}"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

echo ""
echo "=========================================="
echo "✅ Cleanup Complete!"
echo "=========================================="
echo ""

# Verification
echo "Verification:"
echo ""

echo "Namespaces:"
kubectl get namespace ingress2kgateway 2>&1 | grep -E "ingress2kgateway|NotFound" || echo "  ✅ ingress2kgateway not found (cleaned up)"
echo ""

echo "Gateway:"
kubectl get gateway external-gateway -n ingress2kgateway 2>&1 | grep -E "external-gateway|NotFound" || echo "  ✅ external-gateway not found (cleaned up)"
echo ""

echo "GatewayExtension:"
kubectl get gatewayextension -n ingress2kgateway 2>&1 | grep -E "ext-auth|NotFound|No resources" || echo "  ✅ GatewayExtensions cleaned up"
echo ""

echo "=========================================="
echo "✅ Ready for fresh deployment!"
echo "=========================================="
echo ""
echo "Run ./deploy.sh to redeploy"
