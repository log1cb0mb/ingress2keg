# KGateway Feature Coverage

Coverage testing for migrating from NGINX Ingress to Gateway API using **KGateway** (OSS by Solo.io).

📖 **Full Documentation:** [Main README](../README.md)

---

## Quick Commands

```bash
# Controller
./controller.sh setup      # Install KGateway + Gateway API CRDs
./controller.sh teardown   # Remove controller + CRDs

# Resources
./deploy.sh                # Deploy test resources
./test.sh                  # Run 26 tests
./cleanup.sh               # Remove resources
```

---

## Test Environment

| Setting | Value |
|---------|-------|
| KGateway Version | v2.2.0 |
| Test Hostname | `i2g.<your-domain>` |
| Namespace | `ingress2kgateway` |

> **Note:** Configure `DOMAIN` and `CLUSTER_ISSUER` in `../config.env` before deploying.
