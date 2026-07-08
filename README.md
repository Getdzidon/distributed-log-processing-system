# Distributed Log Processing System

## 🎯 Overview

Production-ready, modular log-processing system for multiple sensor types with enterprise observability, multi-region HA, and extensibility.

**Key Features:**
- Modular sensor processors (Temperature, Humidity, Pressure)
- Kubernetes autoscaling (KEDA)
- Multi-region deployment (eu-central-1, eu-west-1)
- OpenTelemetry observability
- Infrastructure as Code (Terraform)
- CI/CD with GitHub Actions (OIDC)

## 🚀 Quick Start

```bash
# Deploy infrastructure
cd infrastructure/terraform
terraform init
terraform apply -var-file=environments/dev.tfvars

# Deploy application
helm install log-processor infrastructure/helm/log-processor \
  --values infrastructure/helm/log-processor/values-dev.yaml

# Test
QUEUE_URL=<url> ./scripts/send_test_messages.sh
```

## 📁 Structure

```
src/
├── processors/          # Sensor processors
├── common/             # Shared utilities
└── main.py            # Entry point

infrastructure/
├── terraform/         # AWS resources
└── helm/             # Kubernetes manifests

.github/workflows/    # CI/CD pipelines

tests/               # Unit tests

docs/                # Documentation

scripts/
├── setup.sh               # Complete automated deployment script (read notes on script for more details)
├── send_test_messages.sh  # Send sample sensor data to SQS
└── load_test.sh           # Performance testing script
```

## 📊 Observability

- **Metrics**: Prometheus (processing rate, latency, errors)
- **Logs**: Loki (structured JSON with trace correlation)
- **Traces**: Tempo (distributed tracing)
- **Dashboards**: Grafana (system overview, SLO compliance)

## 🔧 Adding New Sensors

1. Create processor: `src/processors/new_sensor.py`
2. Register in `src/main.py`
3. Add tests: `tests/test_new_sensor.py`
4. Deploy: `git push origin dev`

See [docs/ADDING_SENSORS.md](docs/ADDING_SENSORS.md)

## 📝 CI/CD

**Workflows:**
- `pr-checks.yml` - Test PRs
- `reusable-build.yml` - Shared build workflow for dev and Prod
- `dev.yml` - Deploy to dev (auto)
- `production.yml` - Deploy to production (manual approval)
- `terraform.yml` - Infrastructure deployment

See [docs/CICD.md](docs/CICD.md)

## 🌍 Multi-Region

- Primary: eu-central-1
- Secondary: eu-west-1
- RPO: <1 min, RTO: <5 min (Recovery Point Objective - max data loss <1 min, Recovery Time Objective - recovery time <5 min)

## 📚 Documentation

- [DEPLOYMENT.md](docs/DEPLOYMENT.md) - Deployment guide
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - System design
- [ADDING_SENSORS.md](docs/ADDING_SENSORS.md) - Extensibility
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Problem resolution

## 👤 Author
Dzissah, Donatus Dziedzorm
