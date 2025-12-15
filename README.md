# ingress2keg 🍺

<h3 align="center">NGINX Ingress → <b>K</b>Gateway + <b>E</b>nvoy <b>G</b>ateway</h3>

<p align="center">
  <b>Battle-tested configurations for migrating from NGINX Ingress Controller to Kubernetes Gateway API</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Gateway%20API-v1.4.1-orange" alt="Gateway API">
  <img src="https://img.shields.io/badge/KGateway-v2.2.0--main-blue" alt="KGateway">
  <img src="https://img.shields.io/badge/Envoy%20Gateway-v1.6.1-purple" alt="Envoy Gateway">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Features%20Tested-27-brightgreen" alt="Features">
  <img src="https://img.shields.io/badge/KGateway-26%20tests-blue" alt="KGateway Tests">
  <img src="https://img.shields.io/badge/Envoy%20Gateway-28%20tests-purple" alt="Envoy Gateway Tests">
  <img src="https://img.shields.io/badge/License-Apache%202.0-green" alt="License">
</p>

---

## 🎯 What is this?

A comprehensive reference for mapping **NGINX Ingress annotations** to their **Gateway API equivalents**. Each mapping includes tested configurations for both KGateway and Envoy Gateway.

**Why "KEG"? 🍺**
> **K**Gateway + **E**nvoy **G**ateway = **KEG**

**Two implementations compared:**
- **[KGateway](https://kgateway.dev/)** - Open-source Envoy-based gateway by Solo.io
- **[Envoy Gateway](https://gateway.envoyproxy.io/)** - CNCF project for Envoy-based ingress

---

## 💡 The Approach

```
┌─────────────────────────────────────────────────────────────┐
│                    NGINX Ingress Annotations                │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Gateway API                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Gateway   │  │  HTTPRoute  │  │      TLSRoute       │  │
│  │ (Listeners) │  │  (L7 Rules) │  │   (L4 Passthrough)  │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              ▼
┌──────────────────────────┬──────────────────────────────────┐
│        KGateway          │         Envoy Gateway            │
├──────────────────────────┼──────────────────────────────────┤
│  • TrafficPolicy         │  • SecurityPolicy                │
│  • BackendConfigPolicy   │  • BackendTrafficPolicy          │
│  • GatewayExtension      │  • ClientTrafficPolicy           │
│  • ListenerPolicy        │  • HTTPRouteFilter               │
└──────────────────────────┴──────────────────────────────────┘
```

---

## ✨ Feature Coverage Matrix

This project validates **27 common NGINX Ingress features** covering the most widely-used annotations and configuration patterns. See the [Complete Annotation Reference](#complete-annotation-reference) below for detailed annotation mappings.

| # | Feature | Standard | KGateway | Envoy Gateway |
|---|---------|:--------:|:--------:|:-------------:|
| 1 | External Auth (deny) | ❌ | ✅ | ✅ |
| 2 | External Auth (headers) | ❌ | ✅ | ✅ |
| 3 | IP Whitelisting | ❌ | ✅ | ✅ |
| 4 | CORS | 🧪 | ✅ | ✅ |
| 5 | Rate Limiting | ❌ | ✅ | ✅ |
| 6 | Prefix Rewrite | ✅ | ✅ | ✅ |
| 7 | Regex Rewrite | ❌ | ✅ | ✅ |
| 8 | Body Size Limit | ❌ | ✅ | ✅ |
| 9 | Timeouts | ✅ | ✅ | ✅ |
| 10 | Session Affinity | 🧪 | ✅ | ✅ |
| 11 | Canary / Traffic Split | ✅ | ✅ | ✅ |
| 12 | Gzip Compression | ❌ | ✅ | ✅ |
| 13 | Request Header Mod | ✅ | ✅ | ✅ |
| 14 | Response Header Mod | ✅ | ✅ | ✅ |
| 15 | Connection Timeout | ❌ | ✅ | ✅ |
| 16 | SSL Redirect | ✅ | ✅ | ✅ |
| 17 | Backend TLS | ✅ | ✅ | ✅ |
| 18 | TLS Passthrough | 🧪 | ✅ | ✅ |
| 19 | Method Whitelisting | ✅ | ✅ | ✅ |
| 20 | Basic Auth | ❌ | ✅ | ✅ |
| 21 | Retry Policy | ❌ | ✅ | ✅ |
| 22 | OAuth2/OIDC | ❌ | ✅ | ✅ |
| 23 | App Root Redirect | ✅ | ✅ | ✅ |
| 24 | Load Balancing | ❌ | ✅ | ✅ |
| 25 | Direct Response | ❌ | ✅ | ✅ |
| 26 | JWT Authentication | ❌ | ✅ | ✅ |
| 27 | Custom HTTP Errors | ❌ | ❌ | ✅ |

**Legend:**
- ✅ = Supported
- 🧪 = Experimental (Gateway API feature, may change)
- ❌ = Not supported (see [Known Limitations](#known-limitations))

---

## 🚀 Quick Start

### Prerequisites

- Kubernetes cluster with **LoadBalancer** support
- **cert-manager** installed with a working `ClusterIssuer`

> **Note:** No `external-dns` required - tests use `curl --resolve` to bypass DNS resolution.

### 1. Configure Environment

```bash
cp config.env.example config.env

# Edit config.env with your values:
# - DOMAIN: Your cluster's domain suffix (e.g., "my-cluster.example.com")
# - CLUSTER_ISSUER: cert-manager ClusterIssuer name (e.g., "letsencrypt-production")
```

### 2. Deploy and Test

```bash
# KGateway
cd kgateway
./controller.sh setup    # Install controller
./deploy.sh              # Deploy resources
./test.sh                # Run 26 tests
./cleanup.sh             # Cleanup (when done)

# Envoy Gateway
cd envoy-gateway
./controller.sh setup    # Install controller
./deploy.sh              # Deploy resources
./test.sh                # Run 28 tests
./cleanup.sh             # Cleanup (when done)
```

---

## 📋 Complete Annotation Reference

| Category | NGINX Annotation | Test # | Notes |
|----------|------------------|--------|-------|
| **External Auth** | `auth-url` | 1, 22 | HTTP ext-auth or OAuth2 flow |
| | `auth-response-headers` | 2 | Forward auth headers to backend |
| | `auth-signin` | 22 | OAuth2 redirect URL |
| | `auth-type` | 20 | `basic` for htpasswd auth |
| | `auth-secret` | 20 | Secret containing `.htpasswd` |
| | `auth-realm` | 20 | Cosmetic (browser popup) - not supported |
| | `enable-global-auth` | - | Documented: TrafficPolicy → Gateway |
| **JWT** | N/A (NGINX Plus only) | 26 | Native JWT validation (no external service) |
| **CORS** | `enable-cors` | 4 | Enable CORS handling |
| | `cors-allow-origin` | 4 | Allowed origins (wildcard supported) |
| | `cors-allow-methods` | 4 | Allowed HTTP methods |
| | `cors-allow-headers` | 4 | Allowed request headers |
| | `cors-allow-credentials` | 4 | Allow credentials |
| | `cors-expose-headers` | 4 | Headers exposed to JS |
| | `cors-max-age` | 4 | Preflight cache duration |
| **Path Rewrite** | `rewrite-target` | 6, 7 | Prefix or regex rewrite |
| | `use-regex` | 7 | Enable regex path matching |
| **Rate Limiting** | `limit-rps` | 5 | Requests per second |
| | `limit-rpm` | 5 | Requests per minute |
| | `limit-burst-multiplier` | 5 | Burst capacity multiplier |
| **Timeouts** | `proxy-read-timeout` | 9 | Request timeout |
| | `proxy-send-timeout` | 9 | Stream idle timeout |
| | `proxy-connect-timeout` | 9, 15 | TCP connection timeout |
| **Body Size** | `proxy-body-size` | 8 | Max request body size |
| **Session Affinity** | `affinity` | 10 | `cookie` for sticky sessions |
| | `affinity-mode` | 10 | `balanced` or `persistent` |
| | `session-cookie-name` | 10 | Cookie name |
| | `session-cookie-max-age` | 10 | Cookie TTL |
| | `session-cookie-expires` | 10 | Cookie expiration |
| **Canary** | `canary` | 11 | Enable canary routing |
| | `canary-weight` | 11 | Traffic percentage (0-100) |
| **SSL/TLS** | `ssl-redirect` | 16 | Redirect HTTP to HTTPS |
| | `force-ssl-redirect` | 16 | Force HTTPS redirect |
| | `ssl-passthrough` | 18 | L4 TLS passthrough |
| **Backend TLS** | `proxy-ssl-secret` | 17 | Client cert for mTLS |
| | `backend-protocol` | 17 | `HTTPS`, `GRPC`, `GRPCS` |
| **Headers** | `configuration-snippet` (gzip) | 12 | Response compression |
| | `configuration-snippet` (more_set_input_headers) | 13 | Request header modification |
| | `configuration-snippet` (more_set_headers) | 14 | Response header modification |
| | `configuration-snippet` (proxy_ssl_name) | 17 | Backend SNI hostname |
| **Routing** | `whitelist-source-range` | 3 | IP-based access control |
| | `whitelist-methods` | 19 | Allowed HTTP methods |
| | `app-root` | 23 | Root path redirect |
| | `load-balance` | 24 | Load balancing algorithm |
| **Advanced** | `proxy-next-upstream-tries` | 21 | Retry attempts |
| | `server-snippet` | 25 | Custom NGINX config (mapped to DirectResponse) |
| | `custom-http-errors` | 27 | Error page interception |
| | `upstream-vhost` | 6b/6c | `URLRewrite.hostname` - Rewrite Host header to backend |

---

## ⚠️ Known Limitations

### Annotation Limitations

| Annotation | KGateway | Envoy Gateway | Workaround |
|------------|----------|---------------|------------|
| `custom-http-errors` | ❌ (Gloo Gateway ✅) | ✅ | Handle in backend |
| `auth-cache-key` | ❌ | ❌ | Implement in auth service (Redis) |
| `auth-cache-duration` | ❌ | ❌ | Implement in auth service (Redis) |
| `auth-realm` | ❌ | ❌ | Cosmetic only (browser popup message) |

### Both Implementations

| Limitation | Workaround |
|------------|------------|
| Auth response caching | Implement in auth service (Redis) |
| Negative lookahead regex `(?!...)` | Use route ordering (RE2 limitation) |
| Dynamic headers (`$request_uri`) | Use `x-envoy-original-path` (auto-added on rewrite) |

### KGateway OSS Specific

| Feature | Status | Alternative |
|---------|--------|-------------|
| `custom-http-errors` | ❌ Not supported | Handle in backend, or use Gloo Gateway |
| `auth-cache-key/duration` | ❌ Not supported | Implement in auth service, or use Gloo Gateway |

### Envoy Gateway Specific

| Feature | Status | Alternative |
|---------|--------|-------------|
| `auth-cache-key/duration` | ❌ Not supported | Implement in auth service |

---

## 🔄 CRD Comparison

### Gateway API (Standard - Portable)

| Resource | Purpose |
|----------|---------|
| `Gateway` | Ingress entry point (listeners, TLS termination) |
| `HTTPRoute` | HTTP routing, path matching, rewrites, redirects |
| `TLSRoute` | L4 TLS routing (passthrough) 🧪 |
| `GRPCRoute` | gRPC-specific routing |
| `BackendTLSPolicy` | TLS configuration for backend connections (mTLS via [GEP-3155](https://gateway-api.sigs.k8s.io/geps/gep-3155/) 🧪) |
| `ReferenceGrant` | Cross-namespace reference authorization |

### KGateway Extension CRDs

| CRD | Purpose | NGINX Equivalent |
|-----|---------|------------------|
| `GatewayParameters` | Service configuration (externalTrafficPolicy, annotations) | N/A |
| `GatewayExtension` | External auth, OAuth2/OIDC | `auth-url`, `auth-signin` |
| `TrafficPolicy` | CORS, rate limit, timeout, buffer, compression, headers, RBAC, retry, basic auth | Multiple annotations |
| `BackendConfigPolicy` | Session affinity, connection timeout, load balancing, mTLS | `affinity`, `proxy-connect-timeout`, `load-balance`, `proxy-ssl-secret` |
| `DirectResponse` | Static responses (HTTP rejection) | `server-snippet` |

### Envoy Gateway Extension CRDs

| CRD | Purpose | NGINX Equivalent |
|-----|---------|------------------|
| `EnvoyProxy` | Service configuration (externalTrafficPolicy, annotations) | N/A |
| `SecurityPolicy` | External auth, OIDC, CORS, basic auth, IP authorization | `auth-url`, `auth-signin`, `enable-cors`, `auth-type`, `whitelist-source-range` |
| `BackendTrafficPolicy` | Rate limit, timeout, retry, load balancing, compression, body size, response override | `limit-rps`, `proxy-*-timeout`, `proxy-next-upstream-tries`, `load-balance`, `proxy-body-size`, `custom-http-errors` |
| `ClientTrafficPolicy` | Client connection settings, client IP detection | (Gateway-level settings) |
| `HTTPRouteFilter` | Regex rewrite, direct response | `use-regex`, `server-snippet` |
| `Backend` | External backends, mTLS configuration | `proxy-ssl-secret` |

---

## 🔀 Architecture Comparison

### NGINX Ingress Architecture

```
Client → Ingress Controller → Ingress Resource → Service → Pods
                                    ↑
                              Annotations
                         (all config in one place)
```

### Gateway API Architecture

```
Client → Gateway → HTTPRoute → Service → Pods
            ↑           ↑
     GatewayClass    Policies
            ↑       (attached)
    Implementation
       Config
```

**Key Differences:**
1. **Separation of Concerns** - Gateway (infra) vs HTTPRoute (app) vs Policies (features)
2. **Policy Attachment** - Features attach to resources rather than inline annotations
3. **Cross-namespace** - Routes can reference backends in other namespaces (via ReferenceGrant)
4. **Portability** - Standard features work across implementations

---

## 📁 Repository Structure

```
├── config.env.example           # Environment configuration template
├── kgateway/                    # KGateway implementation
│   ├── 01-apps-and-namespace/   # Namespace, echo-server, ext-authz, nginx-tls backend
│   ├── 02-gateway/              # Gateway, Certificate, ReferenceGrant, GatewayParameters
│   ├── 03-kgateway-policies/    # GatewayExtension, TrafficPolicy, BackendConfigPolicy, BackendTLSPolicy
│   ├── 04-routing/              # HTTPRoutes, TLSRoute, route-attached TrafficPolicies
│   ├── controller.sh            # Controller setup/teardown
│   ├── deploy.sh                # Deploy all resources
│   ├── cleanup.sh               # Remove all resources
│   ├── test.sh                  # Automated test suite (26 tests)
│   └── README.md                # Quick start guide
│
├── envoy-gateway/               # Envoy Gateway implementation
│   ├── 01-apps-and-namespace/   # Namespace, echo-server, ext-authz, nginx-tls backend
│   ├── 02-gateway/              # Gateway, Certificate, ReferenceGrant, EnvoyProxy
│   ├── 03-envoy-gateway-policies/  # SecurityPolicy, BackendTrafficPolicy, HTTPRouteFilter
│   ├── 04-routing/              # HTTPRoutes, TLSRoute, route-attached policies
│   ├── controller.sh            # Controller setup/teardown
│   ├── deploy.sh                # Deploy all resources
│   ├── cleanup.sh               # Remove all resources
│   ├── test.sh                  # Automated test suite (28 tests)
│   └── README.md                # Quick start guide
│
└── samples/                     # Reference NGINX Ingress samples
```

All resource files contain detailed comments explaining the NGINX annotation mapping and configuration options.

---

## ⚙️ Controller Installation

### KGateway

```bash
cd kgateway
./controller.sh setup
```

This installs:
1. Gateway API CRDs (v1.4.1 standard + TLSRoute experimental)
2. KGateway CRDs (v2.2.0)
3. KGateway controller

**Manual installation:**
```bash
# Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

# KGateway CRDs
helm upgrade -i --create-namespace --namespace kgateway-system \
  --version v2.2.0-main \
  kgateway-crds oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds

# KGateway controller
helm upgrade -i -n kgateway-system kgateway \
  oci://cr.kgateway.dev/kgateway-dev/charts/kgateway \
  --version v2.2.0-main
```

### Envoy Gateway

```bash
cd envoy-gateway
./controller.sh setup
```

This installs:
1. Gateway API CRDs (bundled with Envoy Gateway)
2. TLSRoute experimental CRD
3. Envoy Gateway CRDs and controller (v1.6.1)
4. GatewayClass `eg`

**Manual installation:**
```bash
# Install CRDs (Gateway API + Envoy Gateway)
helm template eg oci://docker.io/envoyproxy/gateway-crds-helm \
  --version v1.6.1 \
  --set crds.gatewayAPI.enabled=true \
  --set crds.gatewayAPI.channel=standard \
  --set crds.envoyGateway.enabled=true \
  | kubectl apply --server-side -f -

# TLSRoute experimental CRD
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/refs/heads/main/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

# Envoy Gateway controller
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.6.1 \
  -n envoy-gateway-system \
  --create-namespace \
  --set config.envoyGateway.extensionApis.enableBackend=true \
  --set config.envoyGateway.provider.kubernetes.deploy.type=GatewayNamespace \
  --skip-crds

# Create GatewayClass
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
EOF
```

### Teardown

```bash
# KGateway
cd kgateway && ./controller.sh teardown

# Envoy Gateway
cd envoy-gateway && ./controller.sh teardown
```

---

## 📦 Deployment Order

For both implementations, resources should be deployed in order:

1. **Namespace & Apps** (`01-apps-and-namespace/`)
   - Namespace, test backends (echo-server), auth services, TLS backends

2. **Gateway** (`02-gateway/`)
   - Gateway, Certificate, ReferenceGrant, controller-specific infra config

3. **Extension Policies** (`03-*/`)
   - Implementation-specific policies (auth, CORS, rate limit, etc.)

4. **Routing** (`04-routing/`)
   - HTTPRoutes, TLSRoutes, and route-attached policies

---

## 📝 Implementation-Specific Notes

### Preserving Client IP

Both implementations require `externalTrafficPolicy: Local` for IP-based features:

**KGateway:**
```yaml
apiVersion: gateway.kgateway.dev/v1alpha1
kind: GatewayParameters
spec:
  kube:
    service:
      externalTrafficPolicy: Local
```

**Envoy Gateway:**
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
spec:
  provider:
    kubernetes:
      envoyService:
        externalTrafficPolicy: Local
```

### TLS Passthrough

Both use Standard Gateway API on port 443 with SNI-based routing:

```yaml
# Gateway listener
- name: tls-passthrough
  protocol: TLS
  port: 443
  hostname: "passthrough.example.com"  # SNI for routing
  tls:
    mode: Passthrough
  allowedRoutes:
    kinds:
    - kind: TLSRoute
```

**Note:** L7 policies (CORS, rate limit, auth) cannot be applied to passthrough traffic.

### OAuth2/OIDC

Both implementations support native OAuth2/OIDC without requiring oauth2-proxy:

**KGateway:** Uses `GatewayExtension.oauth2` with direct IdP integration  
**Envoy Gateway:** Uses `SecurityPolicy.oidc` with similar capabilities

Both require the same OIDC client secret named `oidc-client-secret`.

---

## 📈 Coverage Summary

| Metric | KGateway | Envoy Gateway |
|--------|----------|---------------|
| Standard Gateway API features | 11/27 | 11/27 |
| Implementation-specific features | 15/27 | 16/27 |
| Not supported | 1/27* | 0/27 |
| **Test count** | **26 tests** | **28 tests** |

*KGateway OSS lacks `custom-http-errors` (available in Gloo Gateway)

---

## ✅ Test Results

### KGateway: 26/26 Tests Passing ✅

All planned features validated including:
- External authentication (HTTP)
- OAuth2/OIDC (native, no oauth2-proxy)
- JWT authentication (native, `GatewayExtension type: JWT`)
- Backend TLS (simple + mTLS)
- TLS passthrough
- Regex path rewrite with capture groups
- Session affinity with cookies
- All standard Gateway API features

### Envoy Gateway: 28/28 Tests Passing ✅

All planned features validated including:
- External authentication
- OAuth2/OIDC (SecurityPolicy.oidc)
- JWT authentication (native, `SecurityPolicy.jwt`)
- Per-IP rate limiting (`sourceCIDR.type: Distinct`)
- Backend TLS (simple + mTLS via Backend resource)
- TLS passthrough
- Regex path rewrite (HTTPRouteFilter)
- Custom HTTP error responses (responseOverride)
- All standard Gateway API features

---

## 📊 Implementation Comparison

Based on our testing of 27 features, here's an objective comparison:

### Feature Parity

Both implementations successfully validated all common NGINX Ingress patterns:

| Capability | KGateway | Envoy Gateway |
|------------|----------|---------------|
| Native OAuth2/OIDC | ✅ `GatewayExtension.oauth2` | ✅ `SecurityPolicy.oidc` |
| Native JWT Auth | ✅ `GatewayExtension type: JWT` | ✅ `SecurityPolicy.jwt` |
| External Auth | ✅ `GatewayExtension.extAuth` | ✅ `SecurityPolicy.extAuth` |
| TLS Passthrough | ✅ Standard `TLSRoute` | ✅ Standard `TLSRoute` |
| Backend TLS (simple) | ✅ Standard `BackendTLSPolicy` | ✅ Standard `BackendTLSPolicy` |
| Backend mTLS | 🧪 GEP-3155 (Experimental) | 🧪 GEP-3155 (Experimental) |
| Regex Path Rewrite | ✅ `TrafficPolicy.urlRewrite` | ✅ `HTTPRouteFilter.urlRewrite` |
| Rate Limiting | ✅ `TrafficPolicy.rateLimit` | ✅ `BackendTrafficPolicy.rateLimit` |
| Per-IP Rate Limiting | ❌ | ✅ `sourceCIDR.type: Distinct` |
| Custom HTTP Errors | ❌ (Gloo Gateway ✅) | ✅ `responseOverride` |

### Key Differences

| Aspect | KGateway | Envoy Gateway |
|--------|----------|---------------|
| **Feature coverage** | 26/27 features | 27/27 features |
| **Missing feature** | `custom-http-errors` | None |
| **JWT config** | `GatewayExtension type: JWT` + `Backend` + `BackendTLSPolicy` | `SecurityPolicy.jwt` (simpler, auto TLS) |
| **IP whitelisting** | CEL expressions (`source.address.startsWith()`) | CIDR-based (`clientCIDRs`) |
| **Per-IP rate limiting** | ❌ Not supported | ✅ `sourceCIDR.type: Distinct` |
| **Policy organization** | `TrafficPolicy` (L7) + `BackendConfigPolicy` (backend) | `SecurityPolicy` + `BackendTrafficPolicy` + `ClientTrafficPolicy` |
| **Infrastructure config** | `GatewayParameters` | `EnvoyProxy` |
| **Enterprise path** | Gloo Gateway (Solo.io) | N/A (CNCF project) |

### Both Implementations Support

- Gateway API resources (HTTPRoute, TLSRoute*, BackendTLSPolicy)
- Native OAuth2/OIDC without oauth2-proxy
- Weighted traffic splitting (canary deployments)
- Session affinity via consistent hashing
- Request/response header modification
- Gzip compression
- Retry policies with backoff
- Multiple load balancing algorithms

*TLSRoute is experimental. Backend mTLS is covered by [GEP-3155](https://gateway-api.sigs.k8s.io/geps/gep-3155/) (Experimental).

---

## 📚 References

### Gateway API
- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [Gateway API GEPs](https://gateway-api.sigs.k8s.io/geps/overview/)

### KGateway
- [KGateway Documentation](https://kgateway.dev/docs/latest/)
- [KGateway GitHub](https://github.com/kgateway-dev/kgateway)

### Envoy Gateway
- [Envoy Gateway Documentation](https://gateway.envoyproxy.io/)
- [Envoy Gateway GitHub](https://github.com/envoyproxy/gateway)

---

## 🎯 Conclusion

Both KGateway and Envoy Gateway successfully demonstrate that **NGINX Ingress migrations to Gateway API are production-viable**. The majority of common NGINX annotations map directly to either:

1. **Standard Gateway API** resources (11 features) - Portable across implementations
2. **Implementation-specific CRDs** (15-16 features) - Advanced functionality with vendor lock-in trade-off

For teams migrating from NGINX Ingress:
- Start with **Standard Gateway API features** for maximum portability
- Use **implementation-specific CRDs** when needed for advanced features
- Plan for **auth caching** if using external authentication at scale
- Review **regex patterns** for RE2 compatibility

The complete resource configurations with detailed comments are available in the respective implementation directories.

---

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Kubernetes Gateway API SIG](https://gateway-api.sigs.k8s.io/)
- [Solo.io](https://www.solo.io/) for KGateway
- [Envoy Proxy](https://www.envoyproxy.io/) community

---

<p align="center">
  <b>Found this useful? Give it a ⭐!</b>
</p>
