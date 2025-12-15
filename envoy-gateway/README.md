# Envoy Gateway Feature Coverage

Coverage testing for migrating from NGINX Ingress to Gateway API using **Envoy Gateway** (CNCF project).

📖 **Full Documentation:** [Main README](../README.md)

---

## Quick Commands

```bash
# Controller
./controller.sh setup      # Install Envoy Gateway + Gateway API CRDs
./controller.sh teardown   # Remove controller + CRDs

# Resources
./deploy.sh                # Deploy test resources
./test.sh                  # Run 28 tests
./cleanup.sh               # Remove resources
```

---

## Test Environment

| Setting | Value |
|---------|-------|
| Envoy Gateway Version | v1.6.1 |
| GatewayClass | `eg` |
| Test Hostname | `eg.<your-domain>` |
| Namespace | `ingress2envoygateway` |

> **Note:** Configure `DOMAIN` and `CLUSTER_ISSUER` in `../config.env` before deploying.
