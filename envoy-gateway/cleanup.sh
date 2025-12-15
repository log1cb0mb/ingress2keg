#!/bin/bash

echo "=========================================="
echo "Envoy Gateway Implementation Cleanup"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "⚠️  This will delete ALL resources in ingress2envoygateway namespace."
echo ""
read -p "Are you sure? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "🗑️ Deleting HTTPRoutes..."
kubectl delete -f 04-routing/ --ignore-not-found=true

echo ""
echo "🗑️ Deleting Envoy Gateway Policies..."
kubectl delete -f 03-envoy-gateway-policies/ --ignore-not-found=true

echo ""
echo "🗑️ Deleting Gateway API Resources..."
kubectl delete -f 02-gateway/ --ignore-not-found=true

echo ""
echo "🗑️ Deleting Apps & Namespace..."
kubectl delete -f 01-apps-and-namespace/ --ignore-not-found=true

echo ""
echo "⏳ Waiting for namespace deletion..."
kubectl wait --for=delete namespace/ingress2envoygateway --timeout=120s 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Cleanup Complete!"
echo "=========================================="
echo ""
echo "Note: Namespace 'ingress2envoygateway' may take a moment to terminate."
echo "Check status with: kubectl get ns ingress2envoygateway"
echo ""
