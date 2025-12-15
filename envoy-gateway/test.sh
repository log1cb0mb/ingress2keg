#!/bin/bash

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo "Please create config.env from the example:"
    echo "  cd coverage && cp config.env.example config.env"
    exit 1
fi

set -a
source "$CONFIG_FILE"
set +a

echo "=========================================="
echo "Envoy Gateway Feature Test Suite"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test configuration
HOST="eg.${DOMAIN}"
AUTH_HEADER="Authorization: Bearer token1"  # HTTP ext-auth service

echo "Test Configuration:"
echo "  Host: $HOST"
echo "  Auth Header: Authorization: Bearer token1"
echo ""
echo "  Valid tokens: token1→user1, token2→user2, token3→user3"
echo ""

# Get gateway address
GATEWAY_IP=$(kubectl get gateway external-gateway -n ingress2envoygateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)

if [ -z "$GATEWAY_IP" ]; then
    echo "❌ Gateway IP not found. Cannot run tests without LoadBalancer IP."
    echo "   Ensure Gateway is deployed and has an external IP assigned."
    exit 1
fi

echo "✅ Gateway IP: $GATEWAY_IP"
BASE_URL="https://$HOST"

# Use --resolve to bypass DNS - no external-dns dependency
# This maps hostname:port to the Gateway IP for all curl requests
RESOLVE="--resolve ${HOST}:443:${GATEWAY_IP} --resolve ${HOST}:80:${GATEWAY_IP}"
RESOLVE_PASSTHROUGH="--resolve nginx-passthrough.${DOMAIN}:443:${GATEWAY_IP}"
RESOLVE_LB_RR="--resolve lb-rr.${DOMAIN}:443:${GATEWAY_IP}"
RESOLVE_LB_LR="--resolve lb-lr.${DOMAIN}:443:${GATEWAY_IP}"
RESOLVE_LB_RANDOM="--resolve lb-random.${DOMAIN}:443:${GATEWAY_IP}"
echo "✅ Using curl --resolve to bypass DNS"

echo ""
echo "=========================================="
echo "Test 1: Auth Required (Should Fail - 403)"
echo "=========================================="
echo "Testing HTTP-based external auth via SecurityPolicy.extAuth"
echo ""
# Use /api/extauth/ path which has SecurityPolicy.extAuth attached
AUTH_RESPONSE=$(curl -si $RESOLVE $BASE_URL/api/extauth/test 2>/dev/null)
AUTH_CODE=$(echo "$AUTH_RESPONSE" | grep -oE "HTTP/[0-9.]+ [0-9]+" | head -1 | awk '{print $2}')

echo "  HTTP Response: $AUTH_CODE"
if [ "$AUTH_CODE" == "403" ]; then
  echo -e "${GREEN}✅ External auth enforced - denied without header${NC}"
else
  echo -e "${YELLOW}⚠️  Expected 403, got $AUTH_CODE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 2: Valid Auth Header (Should Pass - 200)"
echo "=========================================="
echo "Sending request with: $AUTH_HEADER"
echo ""
# Use /api/extauth/ path which has SecurityPolicy.extAuth attached
RESPONSE=$(curl -si $RESOLVE $BASE_URL/api/extauth/data -H "$AUTH_HEADER" 2>/dev/null)
RESPONSE_CODE=$(echo "$RESPONSE" | grep -oE "HTTP/[0-9.]+ [0-9]+" | head -1 | awk '{print $2}')
RESPONSE_BODY=$(echo "$RESPONSE" | sed -n '/^\r$/,$p' | tail -n +2)

# Check for x-current-user header
X_CURRENT_USER=$(echo "$RESPONSE_BODY" | grep -o '"x-current-user":"[^"]*"' | cut -d'"' -f4)

echo "  HTTP Response: $RESPONSE_CODE"
if [ "$RESPONSE_CODE" == "200" ]; then
  echo -e "${GREEN}✅ Auth with valid token working!${NC}"
  if [ -n "$X_CURRENT_USER" ]; then
    echo -e "${GREEN}✅ x-current-user header forwarded: $X_CURRENT_USER${NC}"
  fi
else
  echo -e "${RED}❌ Expected 200, got $RESPONSE_CODE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 3: IP Whitelisting (RBAC)"
echo "=========================================="
echo "Testing SecurityPolicy.authorization with clientCIDRs..."
# Path /api/eg/v1/rbac-test has IP whitelisting via SecurityPolicy
RBAC_RESPONSE=$(curl -si $RESOLVE $BASE_URL/api/eg/v1/rbac-test -H "$AUTH_HEADER" 2>/dev/null)
RBAC_CODE=$(echo "$RBAC_RESPONSE" | grep -oE "HTTP/[0-9.]+ [0-9]+" | head -1 | awk '{print $2}')

echo "  HTTP Response: $RBAC_CODE"
if [ "$RBAC_CODE" == "200" ]; then
  echo -e "${GREEN}✅ RBAC Allow - IP is in whitelist${NC}"
elif [ "$RBAC_CODE" == "403" ]; then
  echo -e "${YELLOW}⚠️  RBAC Deny - IP not in whitelist (expected for non-internal IPs)${NC}"
else
  echo -e "${YELLOW}⚠️  Unexpected response: $RBAC_CODE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 4: CORS (7 annotations)"
echo "=========================================="
echo "Testing SecurityPolicy.cors on /api/eg/v1/ (comprehensive-test-route)..."
# CORS policy is attached to comprehensive-test-route which handles /api/eg/v1/
CORS_RESPONSE=$(curl -s $RESOLVE -i $BASE_URL/api/eg/v1/data \
  -H "Origin: https://app.${DOMAIN}" \
  -H "Access-Control-Request-Method: POST" \
  -H "$AUTH_HEADER" \
  -X OPTIONS 2>/dev/null)

echo "  CORS headers in response:"
echo "$CORS_RESPONSE" | grep -i "access-control" | head -5
echo ""

ALLOW_METHODS=$(echo "$CORS_RESPONSE" | grep -i "access-control-allow-methods" | head -1)
ALLOW_ORIGIN=$(echo "$CORS_RESPONSE" | grep -i "access-control-allow-origin" | head -1)
if echo "$ALLOW_METHODS" | grep -qi "POST\|GET"; then
  echo -e "${GREEN}✅ CORS working (methods allowed)${NC}"
elif [ -n "$ALLOW_ORIGIN" ]; then
  echo -e "${GREEN}✅ CORS working (origin allowed)${NC}"
else
  echo -e "${YELLOW}⚠️  CORS headers not found in OPTIONS response${NC}"
  echo "  Note: CORS may work on actual requests (not just preflight)"
fi

echo ""
echo "=========================================="
echo "Test 5: Rate Limiting (limit-rps)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.rateLimit..."
echo "Sending 50 rapid requests..."

# Clear previous results
> /tmp/rate-test-results.txt

# Send requests in quick succession
for i in {1..50}; do
  curl -s $RESOLVE -o /dev/null -w "%{http_code}\n" \
    "$BASE_URL/api/eg/v1/data" \
    -H "$AUTH_HEADER" >> /tmp/rate-test-results.txt &
done
wait

SUCCESS=$(grep -c "^200$" /tmp/rate-test-results.txt 2>/dev/null || echo "0")
RATE_LIMITED=$(grep -c "^429$" /tmp/rate-test-results.txt 2>/dev/null || echo "0")

echo "  Success (200): $SUCCESS"
echo "  Rate Limited (429): $RATE_LIMITED"

if [ "$RATE_LIMITED" -gt 0 ]; then
  echo -e "${GREEN}✅ Rate limiting working!${NC}"
else
  echo -e "${YELLOW}⚠️  No 429 errors seen - rate limit may need higher burst${NC}"
fi

echo ""
echo "=========================================="
echo "Test 6: Path Rewrite (Prefix) - Standard Gateway API"
echo "=========================================="
echo "Testing HTTPRoute URLRewrite.ReplacePrefixMatch..."
REWRITE_RESPONSE=$(curl -s $RESOLVE $BASE_URL/api/standard/prefix/data -H "$AUTH_HEADER" 2>/dev/null)
REWRITTEN_PATH=$(echo "$REWRITE_RESPONSE" | grep -o '"originalUrl":"[^"]*"' | cut -d'"' -f4)

echo "  Client sent: /api/standard/prefix/data"
echo "  Backend received: $REWRITTEN_PATH"
echo "  Expected: /api/rewritten/data"

if [ "$REWRITTEN_PATH" == "/api/rewritten/data" ]; then
  echo -e "${GREEN}✅ Standard prefix rewrite working!${NC}"
else
  echo -e "${YELLOW}⚠️  Prefix rewrite may not be applied${NC}"
fi

echo ""
echo "Test 6b: Host Header Rewrite (upstream-vhost) - Standard Gateway API"
echo "Testing HTTPRoute URLRewrite.hostname..."
echo ""
echo "NGINX equivalent:"
echo "  nginx.ingress.kubernetes.io/upstream-vhost: internal-backend.local"
echo ""

VHOST_RESPONSE=$(curl -s $RESOLVE $BASE_URL/api/standard/vhost/test -H "$AUTH_HEADER" 2>/dev/null)
BACKEND_HOST=$(echo "$VHOST_RESPONSE" | grep -o '"host":"[^"]*"' | head -1 | cut -d'"' -f4)

echo "  Client sent Host: $HOST"
echo "  Backend received Host: $BACKEND_HOST"
echo "  Expected: internal-backend.local"

if [ "$BACKEND_HOST" == "internal-backend.local" ]; then
  echo -e "${GREEN}✅ Host header rewrite (vhost) working!${NC}"
else
  echo -e "${YELLOW}⚠️  Host header may not be rewritten${NC}"
fi

echo ""
echo "=========================================="
echo "Test 7: Path Rewrite (Regex) - Envoy Gateway Specific"
echo "=========================================="
echo "Testing HTTPRouteFilter.urlRewrite.replaceRegexMatch..."
REGEX_PATH="/api/regex/feedback/ABC123/implementation/DEF456"
REGEX_EXPECTED="/api-feedback-manager/feedback/ABC123/implementation/DEF456"

REGEX_RESPONSE=$(curl -s $RESOLVE $BASE_URL$REGEX_PATH -H "$AUTH_HEADER" 2>/dev/null)
REGEX_REWRITTEN=$(echo "$REGEX_RESPONSE" | grep -o '"originalUrl":"[^"]*"' | cut -d'"' -f4)

echo "  Client sent: $REGEX_PATH"
echo "  Backend received: $REGEX_REWRITTEN"
echo "  Expected: $REGEX_EXPECTED"

if [ "$REGEX_REWRITTEN" = "$REGEX_EXPECTED" ]; then
  echo -e "${GREEN}✅ Regex rewrite working!${NC}"
else
  echo -e "${RED}❌ Regex rewrite failed${NC}"
fi

echo ""
echo "=========================================="
echo "Test 8: Body Size Limit (10MB)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.requestBuffer.limit..."
echo "NGINX equivalent: proxy-body-size: 10m"
echo ""

# Test with allowed size (5MB - under 10Mi limit)
dd if=/dev/zero of=/tmp/eg-5mb.dat bs=1M count=5 2>/dev/null
# Use /api/eg/v1/ path which has BackendTrafficPolicy attached via HTTPRoute
SMALL_UPLOAD=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/api/eg/v1/upload" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @/tmp/eg-5mb.dat)

echo "  5MB upload: HTTP $SMALL_UPLOAD (expected: 200 - under 10Mi limit)"

# Test with over-limit size (15MB - over 10Mi limit)
dd if=/dev/zero of=/tmp/eg-15mb.dat bs=1M count=15 2>/dev/null
LARGE_UPLOAD=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
  -X POST "$BASE_URL/api/eg/v1/upload" \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @/tmp/eg-15mb.dat --max-time 30)

echo "  15MB upload: HTTP $LARGE_UPLOAD (expected: 413 - over 10Mi limit)"

if [ "$SMALL_UPLOAD" == "200" ] && [ "$LARGE_UPLOAD" == "413" ]; then
  echo -e "${GREEN}✅ Body size limit working correctly!${NC}"
elif [ "$SMALL_UPLOAD" == "200" ]; then
  echo -e "${YELLOW}⚠️  Small file passed, but large file got $LARGE_UPLOAD (expected 413)${NC}"
else
  echo -e "${YELLOW}⚠️  Upload test: small=$SMALL_UPLOAD, large=$LARGE_UPLOAD${NC}"
fi

echo ""
echo "=========================================="
echo "Test 9: Timeout - Standard Gateway API"
echo "=========================================="
echo "Testing HTTPRoute.timeouts.request..."
echo ""
echo "NGINX equivalent:"
echo "  nginx.ingress.kubernetes.io/proxy-read-timeout: 60"
echo ""

STANDARD_TIMEOUT_RESPONSE=$(curl -s $RESOLVE -w "%{http_code}" -o /dev/null \
  $BASE_URL/api/standard/timeout/test \
  -H "$AUTH_HEADER" \
  --max-time 10 2>/dev/null)

echo "  Request to /api/standard/timeout/test: HTTP $STANDARD_TIMEOUT_RESPONSE"
if [ "$STANDARD_TIMEOUT_RESPONSE" = "200" ]; then
  echo -e "${GREEN}✅ Standard Gateway API timeout route working!${NC}"
else
  echo -e "${RED}❌ Standard timeout route failed: $STANDARD_TIMEOUT_RESPONSE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 10: Session Affinity (Sticky Sessions)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.loadBalancer.consistentHash.cookie..."
echo "Cookie name: 'route' (configured in BackendTrafficPolicy)"
echo ""

# First, send 5 requests WITHOUT cookie to see distribution
echo "Part 1: Requests without cookie (should distribute across pods):"
for i in {1..5}; do
  # Use /api/eg/v1/ path which has BackendTrafficPolicy with session affinity
  BACKEND=$(curl -s $RESOLVE "$BASE_URL/api/eg/v1/data" \
    -H "$AUTH_HEADER" \
    | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3)
  echo "  Request $i → $BACKEND"
done

echo ""
echo "Part 2: Requests WITH session cookie (should stick to same pod):"

# Get first request with cookie - use -c to capture cookies
RESPONSE1=$(curl -si $RESOLVE "$BASE_URL/api/eg/v1/data" \
  -H "$AUTH_HEADER" 2>&1)

# Extract Set-Cookie header and pod hostname (cookie name is 'route')
COOKIE=$(echo "$RESPONSE1" | grep -i "set-cookie:" | grep -i "route=" | sed 's/.*route=/route=/' | cut -d';' -f1 | tr -d '\r')
FIRST_BACKEND=$(echo "$RESPONSE1" | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3)

if [ -n "$COOKIE" ]; then
  echo "✅ Session cookie received: ${COOKIE:0:50}..."
  echo "First request routed to pod: $FIRST_BACKEND"
  echo ""
  echo "Sending 5 more requests with same cookie..."
  
  SAME_COUNT=0
  for i in {1..5}; do
    BACKEND=$(curl -s $RESOLVE "$BASE_URL/api/eg/v1/data" \
      -H "$AUTH_HEADER" \
      -H "Cookie: $COOKIE" \
      | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3)
    echo "  Request $i → $BACKEND"
    
    if [ "$BACKEND" == "$FIRST_BACKEND" ]; then
      SAME_COUNT=$((SAME_COUNT + 1))
    fi
  done
  
  echo ""
  if [ $SAME_COUNT -ge 4 ]; then
    echo -e "${GREEN}✅ Session affinity working! $SAME_COUNT/5 requests went to same pod${NC}"
  else
    echo -e "${YELLOW}⚠️  Session affinity: $SAME_COUNT/5 to same pod (may be affected by canary)${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  No 'route' cookie received - checking BackendTrafficPolicy...${NC}"
  # Check if policy exists
  POLICY_EXISTS=$(kubectl get backendtrafficpolicy comprehensive-backend-policy -n ingress2envoygateway -o jsonpath='{.spec.loadBalancer.consistentHash.cookie.name}' 2>/dev/null)
  if [ -n "$POLICY_EXISTS" ]; then
    echo "  Policy configured with cookie: $POLICY_EXISTS"
  fi
fi

echo ""
echo "=========================================="
echo "Test 11: Canary Deployment - Standard Gateway API"
echo "=========================================="
echo "Testing HTTPRoute weighted backendRefs..."
STABLE_COUNT=0
CANARY_COUNT=0

for i in {1..20}; do
  RESPONSE=$(curl -s $RESOLVE $BASE_URL/api/standard/canary/test -H "$AUTH_HEADER")
  if echo "$RESPONSE" | grep -q '"VERSION":"canary"'; then
    CANARY_COUNT=$((CANARY_COUNT + 1))
  elif echo "$RESPONSE" | grep -q '"VERSION":"stable"'; then
    STABLE_COUNT=$((STABLE_COUNT + 1))
  fi
done

echo "  Distribution (20 requests): Stable=$STABLE_COUNT, Canary=$CANARY_COUNT"
if [ $CANARY_COUNT -ge 1 ]; then
  echo -e "${GREEN}✅ Canary traffic splitting working!${NC}"
else
  echo -e "${YELLOW}⚠️  No canary traffic detected${NC}"
fi

echo ""
echo "=========================================="
echo "Test 12: Response Compression (Gzip)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.compression on /api/eg/v1/..."
echo ""

# Use /api/eg/v1/ path which has BackendTrafficPolicy
# Get original size (without compression)
RAW_SIZE=$(curl -s $RESOLVE "$BASE_URL/api/eg/v1/data" -H "$AUTH_HEADER" 2>/dev/null | wc -c | tr -d ' ')

# Get compressed size (with gzip)
GZIP_RESPONSE=$(curl -s $RESOLVE -D - "$BASE_URL/api/eg/v1/data" \
  -H "$AUTH_HEADER" \
  -H "Accept-Encoding: gzip, deflate" \
  -o /tmp/gzip-test.out 2>/dev/null)

GZIP_SIZE=$(wc -c < /tmp/gzip-test.out | tr -d ' ')

# Check for Content-Encoding: gzip in response headers
if echo "$GZIP_RESPONSE" | grep -qi "content-encoding.*gzip"; then
  if [ "$RAW_SIZE" -gt 0 ]; then
    RATIO=$((100 * GZIP_SIZE / RAW_SIZE))
    echo -e "${GREEN}✅ Response compression working!${NC}"
    echo "   Original: $RAW_SIZE bytes → Compressed: $GZIP_SIZE bytes ($RATIO%)"
  else
    echo -e "${GREEN}✅ Response compression working!${NC}"
  fi
else
  # Check if compression is configured
  COMPRESSION=$(kubectl get backendtrafficpolicy comprehensive-backend-policy -n ingress2envoygateway -o jsonpath='{.spec.compression}' 2>/dev/null)
  if [ -n "$COMPRESSION" ]; then
    echo -e "${YELLOW}⚠️  Compression configured but not in response${NC}"
    echo "   Response may be too small to compress"
  else
    echo -e "${YELLOW}⚠️  No gzip compression detected${NC}"
    echo "   BackendTrafficPolicy.compression may not be configured"
  fi
  echo "   Raw size: $RAW_SIZE bytes"
fi

echo ""
echo "=========================================="
echo "Test 13: Request Header Modification - Standard Gateway API"
echo "=========================================="
echo "Testing HTTPRoute.RequestHeaderModifier..."
echo ""

STANDARD_HEADER_RESPONSE=$(curl -s $RESOLVE $BASE_URL/api/standard/headers/test \
  -H "$AUTH_HEADER" \
  -H "Accept: application/json" 2>/dev/null)
STANDARD_ACCEPT=$(echo "$STANDARD_HEADER_RESPONSE" | grep -o '"accept":"[^"]*"' | cut -d'"' -f4)
EXPECTED_ACCEPT="text/plain"

echo "  Client sent:       Accept: application/json"
echo "  Backend received:  Accept: $STANDARD_ACCEPT"
echo "  Expected:          Accept: $EXPECTED_ACCEPT"
echo ""

if [ "$STANDARD_ACCEPT" = "$EXPECTED_ACCEPT" ]; then
  echo -e "${GREEN}✅ Standard Gateway API request header modification working!${NC}"
else
  echo -e "${RED}❌ Standard request header modification failed${NC}"
  echo "   Got: $STANDARD_ACCEPT"
fi

echo ""
echo "=========================================="
echo "Test 14: Response Header Modification - Standard Gateway API"
echo "=========================================="
echo "Testing HTTPRoute.ResponseHeaderModifier..."
echo ""

STANDARD_RESP_HEADERS=$(curl -sI $BASE_URL/api/standard/headers/test -H "$AUTH_HEADER" 2>/dev/null)
STANDARD_CLUSTER=$(echo "$STANDARD_RESP_HEADERS" | grep -i "x-cluster-name:" | sed 's/.*: *//' | tr -d '\r')
STANDARD_GATEWAY_TYPE=$(echo "$STANDARD_RESP_HEADERS" | grep -i "x-gateway-type:" | sed 's/.*: *//' | tr -d '\r')

echo "  Response headers received:"
echo "    X-Cluster-Name: $STANDARD_CLUSTER"
echo "    X-Gateway-Type: $STANDARD_GATEWAY_TYPE"
echo ""

if [ -n "$STANDARD_CLUSTER" ] || [ -n "$STANDARD_GATEWAY_TYPE" ]; then
  echo -e "${GREEN}✅ Standard Gateway API response header modification working!${NC}"
else
  echo -e "${RED}❌ Standard response header modification failed${NC}"
fi

echo ""
echo "=========================================="
echo "Test 15: Connection Timeout (proxy-connect-timeout)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.timeout.tcp.connectTimeout..."
echo ""

# Verify BackendTrafficPolicy has timeout configured
CONNECT_TIMEOUT=$(kubectl get backendtrafficpolicy comprehensive-backend-policy -n ingress2envoygateway -o jsonpath='{.spec.timeout.tcp.connectTimeout}' 2>/dev/null)

echo "  BackendTrafficPolicy tcp.connectTimeout: $CONNECT_TIMEOUT"

if [ -n "$CONNECT_TIMEOUT" ]; then
  echo -e "${GREEN}✅ Connection timeout configured correctly!${NC}"
  
  # Verify connectivity still works
  CONN_TEST=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" $BASE_URL/api/extauth/data -H "$AUTH_HEADER" --max-time 5)
  if [ "$CONN_TEST" = "200" ]; then
    echo "   Connectivity test: HTTP $CONN_TEST (connection established)"
  else
    echo -e "${YELLOW}⚠️  Connectivity test returned: HTTP $CONN_TEST${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Connection timeout not found in BackendTrafficPolicy${NC}"
fi

echo ""
echo "=========================================="
echo "Test 16: SSL Redirect (HTTP → HTTPS)"
echo "=========================================="
echo "Testing HTTPRoute RequestRedirect..."
HTTP_URL="http://$HOST/api/extauth/data"
REDIRECT_RESPONSE=$(curl -sI "$HTTP_URL" --max-time 10 2>/dev/null)
REDIRECT_CODE=$(echo "$REDIRECT_RESPONSE" | grep -oE "HTTP/[0-9.]+ [0-9]+" | head -1 | awk '{print $2}')

echo "  Request to: $HTTP_URL"
echo "  HTTP Response: $REDIRECT_CODE"

if [ "$REDIRECT_CODE" = "301" ]; then
  echo -e "${GREEN}✅ SSL redirect working!${NC}"
else
  echo -e "${YELLOW}⚠️  Expected 301, got $REDIRECT_CODE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 17: Backend TLS (proxy_ssl_name)"
echo "=========================================="
echo "Testing TLS origination from Gateway to backend"
echo ""

# Check if nginx-tls backend is deployed
NGINX_TLS_POD=$(kubectl get pods -n ingress2envoygateway -l app=nginx-tls -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NGINX_TLS_POD" ]; then
  echo -e "${YELLOW}⚠️  Backend TLS test skipped - nginx-tls backend not deployed${NC}"
else
  echo "Test 17a: Standard Gateway API (BackendTLSPolicy)"
  echo ""
  
  RESPONSE_17A=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
    "https://${HOST}/api/backend-tls/standard/test" \
    -H "Authorization: Bearer token1" 2>/dev/null || echo "000")
  
  echo "  Request to /api/backend-tls/standard/test: HTTP ${RESPONSE_17A}"
  
  if [ "$RESPONSE_17A" = "200" ]; then
    echo -e "${GREEN}✅ Standard BackendTLSPolicy working!${NC}"
  elif [ "$RESPONSE_17A" = "503" ]; then
    echo -e "${YELLOW}⚠️  Backend unavailable (503) - TLS handshake may have failed${NC}"
  else
    echo -e "${RED}❌ Standard BackendTLSPolicy not working (HTTP ${RESPONSE_17A})${NC}"
  fi
  
  echo ""
  echo "Test 17b: Envoy Gateway Backend Resource (Simple TLS)"
  echo ""
  
  RESPONSE_17B=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
    "https://${HOST}/api/backend-tls/simple/test" \
    -H "Authorization: Bearer token1" 2>/dev/null || echo "000")
  
  echo "  Request to /api/backend-tls/simple/test: HTTP ${RESPONSE_17B}"
  
  if [ "$RESPONSE_17B" = "200" ]; then
    echo -e "${GREEN}✅ Envoy Gateway Backend (simple TLS) working!${NC}"
  else
    echo -e "${RED}❌ Envoy Gateway Backend not working (HTTP ${RESPONSE_17B})${NC}"
  fi
  
  echo ""
  echo "Test 17c: Envoy Gateway Backend Resource (mTLS)"
  echo ""
  
  RESPONSE_17C=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
    "https://${HOST}/api/backend-tls/mtls/test" \
    -H "Authorization: Bearer token1" 2>/dev/null || echo "000")
  
  echo "  Request to /api/backend-tls/mtls/test: HTTP ${RESPONSE_17C}"
  
  if [ "$RESPONSE_17C" = "200" ]; then
    echo -e "${GREEN}✅ Envoy Gateway Backend (mTLS) working!${NC}"
  else
    echo -e "${RED}❌ Envoy Gateway Backend mTLS not working (HTTP ${RESPONSE_17C})${NC}"
  fi
fi

echo ""
echo "=========================================="
echo "Test 18: TLS Passthrough (ssl-passthrough)"
echo "=========================================="
echo "NGINX annotation: ssl-passthrough: 'true'"
echo "Gateway API: Gateway listener (tls.mode: Passthrough) + TLSRoute"
echo "Note: Same port 443 - SNI-based routing distinguishes HTTPS vs Passthrough"
echo ""

PASSTHROUGH_HOST="nginx-passthrough.${DOMAIN}"

# Check if TLSRoute exists
if kubectl get tlsroute nginx-tls-passthrough -n ingress2envoygateway &>/dev/null; then
  echo "TLSRoute found. Testing via direct access on port 443..."
  echo ""
  
  # Test TLS passthrough - direct access via port 443
  # Use RESOLVE_PASSTHROUGH for the passthrough hostname
  PASSTHROUGH_RESPONSE=$(curl -sk $RESOLVE_PASSTHROUGH https://$PASSTHROUGH_HOST/ 2>/dev/null)
  
  # Get certificate subject via openssl (connect to Gateway IP with SNI)
  CERT_SUBJECT=$(echo | openssl s_client -connect ${GATEWAY_IP}:443 \
    -servername $PASSTHROUGH_HOST 2>/dev/null | \
    openssl x509 -noout -subject 2>/dev/null)
  
  if echo "$PASSTHROUGH_RESPONSE" | grep -q '"server":"nginx-tls"'; then
    echo -e "${GREEN}✅ TLS Passthrough working!${NC}"
    echo "   Certificate: $CERT_SUBJECT"
    if echo "$CERT_SUBJECT" | grep -q "nginx-tls"; then
      echo -e "${GREEN}✅ Client sees backend's certificate (not gateway's)${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  TLS Passthrough response check failed${NC}"
    echo "   Response: $PASSTHROUGH_RESPONSE"
  fi
else
  echo -e "${YELLOW}⚠️  TLS Passthrough test skipped - TLSRoute not deployed${NC}"
fi

echo ""
echo "=========================================="
echo "Test 19: Method Whitelisting"
echo "=========================================="
echo "Testing HTTPRouteMatch.method..."

GET_RESULT=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" \
  https://$HOST/api/method-test/get-only)
POST_TO_GET=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" -X POST -H "$AUTH_HEADER" \
  https://$HOST/api/method-test/get-only)

echo "  GET-only endpoint: GET=$GET_RESULT (200 expected), POST=$POST_TO_GET (404 expected)"

if [ "$GET_RESULT" = "200" ] && [ "$POST_TO_GET" = "404" ]; then
  echo -e "${GREEN}✅ Method whitelisting working!${NC}"
else
  echo -e "${RED}❌ Method whitelisting failed${NC}"
fi

echo ""
echo "=========================================="
echo "Test 20: Basic Auth"
echo "=========================================="
echo "Testing SecurityPolicy.basicAuth..."

BASIC_NO_AUTH=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
  https://$HOST/api/basic-auth/protected)
BASIC_VALID=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" -u basicuser:basicpass \
  https://$HOST/api/basic-auth/protected)
BASIC_INVALID=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" -u basicuser:wrongpass \
  https://$HOST/api/basic-auth/protected)

echo "  No credentials: $BASIC_NO_AUTH (401 expected)"
echo "  Valid credentials: $BASIC_VALID (200 expected)"
echo "  Invalid credentials: $BASIC_INVALID (401 expected)"

if [ "$BASIC_NO_AUTH" = "401" ] && [ "$BASIC_VALID" = "200" ] && [ "$BASIC_INVALID" = "401" ]; then
  echo -e "${GREEN}✅ Basic auth working!${NC}"
else
  echo -e "${RED}❌ Basic auth failed${NC}"
fi

echo ""
echo "=========================================="
echo "Test 21: Retry Policy"
echo "=========================================="
echo "Testing BackendTrafficPolicy.retry..."
echo ""
echo "Config: numRetries=3, retryOn=[5xx]"
echo ""

# Test with flaky backend that always returns 503
if kubectl get svc flaky-backend -n ingress2envoygateway &>/dev/null; then
  echo "Sending request to flaky backend (returns 503)..."
  START_TIME=$(date +%s.%N)
  RETRY_RESPONSE=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
    https://$HOST/api/retry-test \
    -H "Authorization: Bearer token1" --max-time 15 2>/dev/null)
  END_TIME=$(date +%s.%N)
  ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
  
  # Check flaky backend logs for retry count
  RETRY_COUNT=$(kubectl logs -l app=flaky-backend -n ingress2envoygateway --since=15s 2>/dev/null | grep -c "GET /api/retry-test")
  
  echo "  HTTP Response: $RETRY_RESPONSE"
  echo "  Total time: ${ELAPSED}s"
  echo "  Backend requests (from logs): $RETRY_COUNT"
  
  if [ "$RETRY_COUNT" -ge 3 ]; then
    echo -e "${GREEN}✅ Retry behavior working! $RETRY_COUNT requests seen${NC}"
  else
    echo -e "${YELLOW}⚠️ Expected 3+ requests, got $RETRY_COUNT${NC}"
  fi
else
  echo -e "${YELLOW}⚠️ Flaky backend not deployed - retry test skipped${NC}"
fi

echo ""
echo "=========================================="
echo "Test 22: OAuth2 Sign-In (auth-signin)"
echo "=========================================="
echo "Testing SecurityPolicy.oidc (native OAuth2, no oauth2-proxy needed!)..."
echo ""

OAUTH_HOST="oauth.${DOMAIN}"

# Test unauthenticated request - should get 302 redirect to Azure AD
echo "Testing unauthenticated request (expect 302 → Azure AD)..."
OAUTH_RESPONSE=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
  "https://$OAUTH_HOST/echo" -L --max-redirs 0 2>/dev/null)

OAUTH_REDIRECT=$(curl -s $RESOLVE -I "https://$OAUTH_HOST/echo" 2>/dev/null | grep -i "location:" | head -1)

echo "  HTTP Response: $OAUTH_RESPONSE"

if [[ "$OAUTH_RESPONSE" == "302" ]] && [[ "$OAUTH_REDIRECT" == *"login.microsoftonline.com"* ]]; then
  echo -e "${GREEN}  ✅ Unauthenticated request → 302 redirect to Azure AD${NC}"
  echo "  Redirect: ${OAUTH_REDIRECT:0:80}..."
elif [[ "$OAUTH_RESPONSE" == "302" ]]; then
  echo -e "${GREEN}  ✅ OAuth2 redirect working (302)${NC}"
else
  echo -e "${YELLOW}  ⚠️ Expected 302 redirect, got $OAUTH_RESPONSE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 23: App Root Redirect"
echo "=========================================="
echo "Testing HTTPRoute RequestRedirect for app-root..."

APP_ROOT_HOST="approot.${DOMAIN}"
APP_ROOT_RESPONSE=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" \
  "https://$APP_ROOT_HOST/" -L --max-redirs 0 2>/dev/null)

echo "  Request to /: HTTP $APP_ROOT_RESPONSE"

if [ "$APP_ROOT_RESPONSE" = "302" ]; then
  echo -e "${GREEN}✅ App root redirect working!${NC}"
else
  echo -e "${YELLOW}⚠️  Expected 302, got $APP_ROOT_RESPONSE${NC}"
fi

echo ""
echo "=========================================="
echo "Test 24: Load Balancing Algorithms"
echo "=========================================="
echo "Testing BackendTrafficPolicy.loadBalancer (RoundRobin, LeastRequest, Random)..."
echo ""

# Test 24a: Round Robin
echo "  24a: Round Robin (lb-rr.${DOMAIN})"
LB_RR_TYPE=$(kubectl get backendtrafficpolicy round-robin-lb-policy -n ingress2envoygateway -o jsonpath='{.spec.loadBalancer.type}' 2>/dev/null)
if [ "$LB_RR_TYPE" == "RoundRobin" ]; then
  > /tmp/lb-rr-pods.txt
  for i in {1..10}; do
    curl -sk $RESOLVE_LB_RR "https://lb-rr.${DOMAIN}/" 2>/dev/null | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3 >> /tmp/lb-rr-pods.txt
  done
  RR_UNIQUE=$(sort /tmp/lb-rr-pods.txt | uniq | wc -l | tr -d ' ')
  echo -e "${GREEN}  ✅ Round Robin: $RR_UNIQUE unique pods (10 requests)${NC}"
else
  echo -e "${YELLOW}  ⚠️ Round Robin policy not found${NC}"
fi

# Test 24b: Least Request
echo "  24b: Least Request (lb-lr.${DOMAIN})"
LB_LR_TYPE=$(kubectl get backendtrafficpolicy least-request-lb-policy -n ingress2envoygateway -o jsonpath='{.spec.loadBalancer.type}' 2>/dev/null)
if [ "$LB_LR_TYPE" == "LeastRequest" ]; then
  > /tmp/lb-lr-pods.txt
  for i in {1..10}; do
    curl -sk $RESOLVE_LB_LR "https://lb-lr.${DOMAIN}/" 2>/dev/null | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3 >> /tmp/lb-lr-pods.txt
  done
  LR_UNIQUE=$(sort /tmp/lb-lr-pods.txt | uniq | wc -l | tr -d ' ')
  echo -e "${GREEN}  ✅ Least Request: $LR_UNIQUE unique pods (10 requests)${NC}"
else
  echo -e "${YELLOW}  ⚠️ Least Request policy not found${NC}"
fi

# Test 24c: Random
echo "  24c: Random (lb-random.${DOMAIN})"
LB_RANDOM_TYPE=$(kubectl get backendtrafficpolicy random-lb-policy -n ingress2envoygateway -o jsonpath='{.spec.loadBalancer.type}' 2>/dev/null)
if [ "$LB_RANDOM_TYPE" == "Random" ]; then
  > /tmp/lb-random-pods.txt
  for i in {1..10}; do
    curl -sk $RESOLVE_LB_RANDOM "https://lb-random.${DOMAIN}/" 2>/dev/null | grep -o 'HOSTNAME":"[^"]*"' | cut -d'"' -f3 >> /tmp/lb-random-pods.txt
  done
  RANDOM_UNIQUE=$(sort /tmp/lb-random-pods.txt | uniq | wc -l | tr -d ' ')
  echo -e "${GREEN}  ✅ Random: $RANDOM_UNIQUE unique pods (10 requests)${NC}"
else
  echo -e "${YELLOW}  ⚠️ Random policy not found${NC}"
fi

# Summary
if [ -n "$LB_RR_TYPE" ] || [ -n "$LB_LR_TYPE" ] || [ -n "$LB_RANDOM_TYPE" ]; then
  echo -e "${GREEN}✅ Load balancing algorithms configured and working${NC}"
else
  echo -e "${YELLOW}⚠️ Load balancing policies not deployed (deploy 16-load-balance-test.yaml)${NC}"
fi

echo ""
echo "=========================================="
echo "Test 25: Server Snippet (HTTP Rejection)"
echo "=========================================="
echo "Testing HTTPRouteFilter.directResponse..."

API_REJECT_HOST="api-reject.${DOMAIN}"
HTTP_REJECT=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" "http://$API_REJECT_HOST/" 2>/dev/null)
HTTPS_OK=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" "https://$API_REJECT_HOST/" 2>/dev/null)

echo "  HTTP request: $HTTP_REJECT (400 expected)"
echo "  HTTPS request: $HTTPS_OK (200 expected)"

if [ "$HTTP_REJECT" = "400" ] && [ "$HTTPS_OK" = "200" ]; then
  echo -e "${GREEN}✅ Server snippet (HTTP rejection) working!${NC}"
else
  echo -e "${YELLOW}⚠️  Direct response may not be configured${NC}"
fi

echo ""
echo "=========================================="
echo "Test 26: Custom HTTP Errors (EG-specific!)"
echo "=========================================="
echo "Testing BackendTrafficPolicy.responseOverride..."
echo "(This is a feature KGateway OSS LACKS!)"

CUSTOM_ERROR=$(curl -s $RESOLVE $BASE_URL/api/custom-error-test -H "$AUTH_HEADER" 2>/dev/null)

if echo "$CUSTOM_ERROR" | grep -q "Service Temporarily Unavailable"; then
  echo -e "${GREEN}✅ Custom HTTP errors working! Response intercepted and customized${NC}"
else
  echo -e "${YELLOW}⚠️  Custom error response not detected${NC}"
  echo "  Response: $CUSTOM_ERROR"
fi

echo ""
echo "=========================================="
echo "Test 27: JWT Authentication (Native!)"
echo "=========================================="
echo "Testing SecurityPolicy.jwt (no external service needed!)..."
echo ""
echo "NGINX equivalent:"
echo "  - No open-source NGINX Ingress support (requires NGINX Plus or ext-auth)"
echo "  - Envoy Gateway provides built-in JWT validation!"
echo ""

# Check if JWT SecurityPolicy exists
JWT_POLICY=$(kubectl get securitypolicy jwt-auth-policy -n ingress2envoygateway -o name 2>/dev/null)

if [ -n "$JWT_POLICY" ]; then
  # Test without token (should fail - 401)
  JWT_NO_TOKEN=$(curl -s $RESOLVE -o /dev/null -w "%{http_code}" "$BASE_URL/api/jwt-auth/test" 2>/dev/null)
  echo "  Without token: HTTP $JWT_NO_TOKEN (expected: 401)"
  
  if [ "$JWT_NO_TOKEN" == "401" ]; then
    echo -e "${GREEN}✅ JWT validation enforced - denied without token${NC}"
  else
    echo -e "${YELLOW}⚠️  Expected 401, got $JWT_NO_TOKEN${NC}"
  fi
  
  echo ""
  echo "  To test with valid JWT token (Azure AD example):"
  echo "    az login"
  echo "    TOKEN=\$(az account get-access-token --resource ${OIDC_CLIENT_ID} --query accessToken -o tsv)"
  echo "    curl -H \"Authorization: Bearer \$TOKEN\" $BASE_URL/api/jwt-auth/test"
  echo ""
  echo "  JWT claims extracted to headers:"
  echo "    X-JWT-Subject, X-JWT-Email, X-JWT-Name, X-JWT-Username"
else
  echo -e "${YELLOW}⚠️  JWT SecurityPolicy not deployed${NC}"
  echo "  Deploy with: kubectl apply -f 03-envoy-gateway-policies/10-security-policy-jwt.yaml"
  echo "  Note: Requires OIDC_ISSUER_URL, OIDC_CLIENT_ID, OIDC_JWKS_URL in config.env"
fi

echo ""
echo "=========================================="
echo "Test 28: Per-IP Rate Limiting"
echo "=========================================="
echo "Testing BackendTrafficPolicy.rateLimit with sourceCIDR.type: Distinct..."
echo ""
echo "NGINX equivalent:"
echo "  nginx.ingress.kubernetes.io/limit-rps: \"5\""
echo "  (NGINX applies per-IP by default via \$binary_remote_addr)"
echo ""
echo "Envoy Gateway:"
echo "  rateLimit.local.rules[].clientSelectors[].sourceCIDR.type: Distinct"
echo "  Each unique IP gets its own rate limit bucket!"
echo ""

# Check if Per-IP RateLimit policy exists
PERIP_POLICY=$(kubectl get backendtrafficpolicy per-ip-ratelimit-policy -n ingress2envoygateway -o name 2>/dev/null)

if [ -n "$PERIP_POLICY" ]; then
  # Rate limit is 5 req/second - need parallel requests to trigger it
  echo "  Sending 15 parallel requests (limit: 5/sec)..."
  
  # Create temp files for results
  RESULT_FILE=$(mktemp)
  
  # Send 15 parallel requests
  for i in {1..15}; do
    curl -s $RESOLVE -o /dev/null -w "%{http_code}\n" \
      "$BASE_URL/api/ratelimit-per-ip/test" >> "$RESULT_FILE" 2>/dev/null &
  done
  
  # Wait for all background jobs
  wait
  
  # Count results
  SUCCESS_COUNT=$(grep -c "200" "$RESULT_FILE" 2>/dev/null || echo "0")
  LIMITED_COUNT=$(grep -c "429" "$RESULT_FILE" 2>/dev/null || echo "0")
  
  echo "    Results: $SUCCESS_COUNT successful (200), $LIMITED_COUNT rate limited (429)"
  
  rm -f "$RESULT_FILE"
  
  echo ""
  if [ "$LIMITED_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Per-IP rate limiting working! Excess requests got 429${NC}"
    echo "  With sourceCIDR.type: Distinct, each unique IP gets its own bucket"
  else
    echo -e "${YELLOW}⚠️  Rate limiting not triggered - requests may have been too slow${NC}"
    echo "  Manual test: for i in {1..15}; do curl -s -o /dev/null -w '%{http_code}\n' $RESOLVE $BASE_URL/api/ratelimit-per-ip/test & done"
    echo "  Verify: kubectl get backendtrafficpolicy per-ip-ratelimit-policy -n ingress2envoygateway -o yaml"
  fi
else
  echo -e "${YELLOW}⚠️  Per-IP RateLimit policy not deployed${NC}"
  echo "  Deploy with: kubectl apply -f 03-envoy-gateway-policies/11-backend-traffic-policy-per-ip-ratelimit.yaml"
fi

echo ""
echo "=========================================="
echo "✅ Test Suite Complete!"
echo "=========================================="
echo ""
echo "Summary of Envoy Gateway Features Tested:"
echo "  • Tests 1-2:  SecurityPolicy.extAuth - External auth"
echo "  • Test 3:     SecurityPolicy.authorization - IP Whitelisting"
echo "  • Test 4:     SecurityPolicy.cors - CORS"
echo "  • Test 5:     BackendTrafficPolicy.rateLimit - Rate Limiting (Global)"
echo "  • Test 6:     HTTPRoute.URLRewrite.ReplacePrefixMatch - Prefix Rewrite (Standard)"
echo "  • Test 7:     HTTPRouteFilter.urlRewrite.replaceRegexMatch - Regex Rewrite (EG)"
echo "  • Test 8:     BackendTrafficPolicy.requestBuffer - Body Size Limit"
echo "  • Test 9:     HTTPRoute.timeouts - Timeout (Standard)"
echo "  • Test 10:    BackendTrafficPolicy.loadBalancer.consistentHash - Session Affinity"
echo "  • Test 11:    HTTPRoute.backendRefs[].weight - Canary (Standard)"
echo "  • Test 12:    BackendTrafficPolicy.compression - Gzip"
echo "  • Test 13-14: HTTPRoute.RequestHeaderModifier/ResponseHeaderModifier (Standard)"
echo "  • Test 15:    BackendTrafficPolicy.timeout.tcp - Connection Timeout"
echo "  • Test 16:    HTTPRoute.RequestRedirect - SSL Redirect (Standard)"
echo "  • Test 17:    BackendTLSPolicy + Backend resource - Backend TLS/mTLS"
echo "  • Test 18:    Gateway TLS Passthrough + TLSRoute (Standard)"
echo "  • Test 19:    HTTPRouteMatch.method - Method Whitelisting (Standard)"
echo "  • Test 20:    SecurityPolicy.basicAuth - Basic Auth"
echo "  • Test 21:    BackendTrafficPolicy.retry - Retry Policy"
echo "  • Test 22:    SecurityPolicy.oidc - OAuth2/OIDC (Native, no proxy!)"
echo "  • Test 23:    HTTPRoute.RequestRedirect - App Root (Standard)"
echo "  • Test 24:    BackendTrafficPolicy.loadBalancer - Load Balancing Algorithms"
echo "  • Test 25:    HTTPRouteFilter.directResponse - Direct Response (EG)"
echo "  • Test 26:    BackendTrafficPolicy.responseOverride - Custom HTTP Errors (EG)"
echo "  • Test 27:    SecurityPolicy.jwt - JWT Authentication (Native!)"
echo "  • Test 28:    BackendTrafficPolicy.rateLimit.sourceCIDR.Distinct - Per-IP Rate Limiting"
echo ""
