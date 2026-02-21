# Grafana Observability Setup

## Overview

Grafana is deployed automatically via Helm as part of the observability stack in the `observability` namespace. It connects to:
- **Prometheus** - Application metrics (Prometheus client in Python app)
- **Loki** - Application logs (stdout/stderr from pods)
- **CloudWatch** - AWS infrastructure metrics (optional)

## Deployment Method

**Automated via Helm** - Deployed once per EKS cluster after infrastructure is ready.

### When to Deploy

Deploy Grafana **after** EKS cluster is created but **before** deploying the log-processor application.

**Deployment order:**
1. Bootstrap infrastructure (S3, DynamoDB, OIDC)
2. Main infrastructure (VPC, EKS, SQS, S3, DynamoDB)
3. **Observability stack (Grafana, Prometheus, Loki)** ← You are here
4. Log-processor application

---

## Installation

### Step 1: Deploy Observability Stack

```bash
# Add Helm repo
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki stack (includes Grafana + Prometheus + Loki)
helm install loki grafana/loki-stack \
  --namespace observability \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set prometheus.server.persistentVolume.enabled=true \
  --set prometheus.server.persistentVolume.size=20Gi \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=5Gi \
  --set grafana.adminPassword=admin123 \
  --wait

# Verify deployment
kubectl get pods -n observability
```

**What gets deployed:**
- Grafana (UI for dashboards and visualization)
- Prometheus (metrics collection and storage)
- Loki (log aggregation)
- Promtail (log shipper - collects logs from all pods)

### Step 2: Get Grafana Credentials

```bash
# Get admin password (if not set during install)
kubectl get secret loki-grafana -n observability \
  -o jsonpath="{.data.admin-password}" | base64 --decode && echo

# Username: admin
# Password: (output from above command)
```

### Step 3: Access Grafana

**Option A: Port Forward (for testing)**
```bash
kubectl port-forward -n observability svc/loki-grafana 3000:80

# Access at http://localhost:3000
```

**Option B: LoadBalancer (for production)**
```bash
kubectl patch svc loki-grafana -n observability -p '{"spec": {"type": "LoadBalancer"}}'

# Get external URL
kubectl get svc loki-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## Application Integration

### How Grafana Connects to Log-Processor

**1. Prometheus Metrics (Automatic)**

The log-processor application exposes metrics at `/metrics` endpoint:

```python
# src/metrics.py already configured
from prometheus_client import Counter, Histogram, start_http_server

# Metrics exposed on port 8000
start_http_server(8000)
```

Prometheus automatically discovers and scrapes these metrics via Kubernetes service discovery.

**2. Loki Logs (Automatic)**

Promtail (deployed with Loki stack) automatically collects logs from all pods in the cluster:
- Reads stdout/stderr from log-processor pods
- Adds Kubernetes labels (namespace, pod, container)
- Ships to Loki for storage

**No application code changes needed** - just use Python logging:

```python
import logging
logger = logging.getLogger(__name__)
logger.info("Processing message", extra={"sensor_type": "temperature"})
```

**3. CloudWatch (Optional)**

For AWS infrastructure metrics, add CloudWatch data source manually (see Configuration section).

---

## Configuration

### Step 1: Verify Data Sources

Login to Grafana and check pre-configured data sources:

**Prometheus:**
- URL: `http://loki-prometheus-server.observability.svc.cluster.local`
- Already configured by Helm chart

**Loki:**
- URL: `http://loki.observability.svc.cluster.local:3100`
- Already configured by Helm chart

### Step 2: Add CloudWatch Data Source (Optional)

1. Go to **Configuration** → **Data Sources** → **Add data source**
2. Select **CloudWatch**
3. Configure:
   - **Auth Provider**: AWS SDK Default
   - **Default Region**: eu-central-1
   - **Namespaces**: AWS/SQS, AWS/DynamoDB, AWS/S3, AWS/EKS
4. Click **Save & Test**

**Note**: Requires IRSA (IAM Role for Service Account) with CloudWatch read permissions.

---

## Dashboards

### Import Pre-Built Dashboards

**1. Kubernetes Cluster Monitoring**
```bash
# Dashboard ID: 15760 (Kubernetes cluster monitoring)
```
1. Go to **Dashboards** → **Import**
2. Enter ID: `15760`
3. Select Prometheus data source
4. Click **Import**

**2. Loki Logs Dashboard**
```bash
# Dashboard ID: 13639 (Loki dashboard)
```
1. Go to **Dashboards** → **Import**
2. Enter ID: `13639`
3. Select Loki data source
4. Click **Import**

### Create Custom Log-Processor Dashboard

1. Go to **Dashboards** → **New Dashboard** → **Add visualization**
2. Select **Prometheus** data source

**Panel 1: Messages Processed (Counter)**
```promql
rate(messages_processed_total[5m])
```
- Visualization: Time series
- Legend: `{{sensor_type}}`

**Panel 2: Processing Duration (Histogram)**
```promql
histogram_quantile(0.95, rate(processing_duration_seconds_bucket[5m]))
```
- Visualization: Time series
- Legend: `{{sensor_type}} - p95`

**Panel 3: Error Rate**
```promql
rate(processing_errors_total[5m]) / rate(messages_processed_total[5m])
```
- Visualization: Stat
- Unit: Percent (0.0-1.0)
- Thresholds: Green < 0.01, Yellow < 0.05, Red >= 0.05

**Panel 4: Validation Errors**
```promql
sum by (sensor_type) (rate(validation_errors_total[5m]))
```
- Visualization: Bar chart
- Legend: `{{sensor_type}}`

**Panel 5: Application Logs**
- Select **Loki** data source
```logql
{namespace="log-processing", app="log-processor"} |= "ERROR"
```
- Visualization: Logs

3. Click **Save dashboard**
4. Name: `Log Processor Metrics`

---

## Alerting

### Configure Alert Rules

**1. High Error Rate Alert**

1. Go to **Alerting** → **Alert rules** → **New alert rule**
2. Configure:
   - **Name**: High Error Rate
   - **Query**: 
     ```promql
     rate(processing_errors_total[5m]) / rate(messages_processed_total[5m]) > 0.05
     ```
   - **Condition**: WHEN last() OF query(A) IS ABOVE 0.05
   - **Evaluate every**: 1m
   - **For**: 5m
3. Add notification channel (see below)

**2. Pod Down Alert**

1. **Query**:
   ```promql
   up{job="log-processor"} == 0
   ```
2. **Condition**: WHEN last() OF query(A) IS BELOW 1
3. **For**: 2m

### Configure Notification Channels

**Slack Integration:**

1. Go to **Alerting** → **Contact points** → **New contact point**
2. Select **Slack**
3. Configure:
   - **Webhook URL**: (your Slack webhook)
   - **Channel**: #alerts
4. Click **Save**

**Email Integration:**

1. Edit Grafana config:
```bash
kubectl edit configmap loki-grafana -n observability
```

2. Add SMTP settings:
```ini
[smtp]
enabled = true
host = smtp.gmail.com:587
user = your-email@gmail.com
password = your-app-password
from_address = grafana@cmg.io
from_name = Grafana
```

3. Restart Grafana:
```bash
kubectl rollout restart deployment loki-grafana -n observability
```

---

## Metrics Reference

### Application Metrics (Prometheus)

Exposed by log-processor application on port 8000:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `messages_processed_total` | Counter | `sensor_type` | Total messages processed |
| `processing_duration_seconds` | Histogram | `sensor_type` | Time to process message |
| `validation_errors_total` | Counter | `sensor_type`, `error_type` | Validation failures |
| `processing_errors_total` | Counter | `sensor_type`, `error_type` | Processing failures |
| `s3_upload_duration_seconds` | Histogram | `sensor_type` | S3 upload time |
| `dynamodb_write_duration_seconds` | Histogram | `sensor_type` | DynamoDB write time |

### Infrastructure Metrics (CloudWatch)

Available via CloudWatch data source:

| Metric | Namespace | Description |
|--------|-----------|-------------|
| `ApproximateNumberOfMessagesVisible` | AWS/SQS | Messages in queue |
| `NumberOfMessagesSent` | AWS/SQS | Messages sent to queue |
| `ConsumedReadCapacityUnits` | AWS/DynamoDB | DynamoDB read usage |
| `ConsumedWriteCapacityUnits` | AWS/DynamoDB | DynamoDB write usage |
| `BucketSizeBytes` | AWS/S3 | S3 bucket size |

---

## Log Queries (Loki)

### Useful LogQL Queries

**All logs from log-processor:**
```logql
{namespace="log-processing", app="log-processor"}
```

**Error logs only:**
```logql
{namespace="log-processing"} |= "ERROR"
```

**Logs for specific sensor type:**
```logql
{namespace="log-processing"} | json | sensor_type="temperature"
```

**Count errors per minute:**
```logql
sum(count_over_time({namespace="log-processing"} |= "ERROR" [1m]))
```

**Slow processing (>1s):**
```logql
{namespace="log-processing"} | json | duration > 1
```

---

## Troubleshooting

### Grafana Not Accessible

```bash
# Check pod status
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

# Check logs
kubectl logs -n observability -l app.kubernetes.io/name=grafana

# Check service
kubectl get svc loki-grafana -n observability
```

### No Metrics Showing

```bash
# Verify Prometheus is scraping
kubectl port-forward -n observability svc/loki-prometheus-server 9090:80

# Open http://localhost:9090/targets
# Check if log-processor target is UP

# Verify app metrics endpoint
kubectl port-forward -n log-processing svc/log-processor 8000:8000
curl http://localhost:8000/metrics
```

### No Logs in Loki

```bash
# Check Promtail is running
kubectl get pods -n observability -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n observability -l app.kubernetes.io/name=promtail

# Verify Loki is receiving logs
kubectl port-forward -n observability svc/loki 3100:3100
curl http://localhost:3100/ready
```

### Data Source Connection Failed

```bash
# Test from Grafana pod
kubectl exec -n observability -it deployment/loki-grafana -- /bin/sh

# Test Prometheus
wget -O- http://loki-prometheus-server.observability.svc.cluster.local

# Test Loki
wget -O- http://loki.observability.svc.cluster.local:3100/ready
```

---

## Production Considerations

### High Availability

For production, deploy Grafana with HA:

```bash
helm upgrade loki grafana/loki-stack \
  --namespace observability \
  --set grafana.replicas=2 \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.storageClassName=gp3 \
  --set prometheus.server.replicaCount=2 \
  --reuse-values
```

### Backup Dashboards

```bash
# Export all dashboards
kubectl exec -n observability deployment/loki-grafana -- \
  grafana-cli admin export-dashboard > dashboards-backup.json

# Store in S3
aws s3 cp dashboards-backup.json s3://cmg-terraform-state/grafana-backups/
```

### Resource Limits

Update values for production workloads:

```bash
helm upgrade loki grafana/loki-stack \
  --namespace observability \
  --set grafana.resources.requests.memory=256Mi \
  --set grafana.resources.requests.cpu=100m \
  --set grafana.resources.limits.memory=512Mi \
  --set grafana.resources.limits.cpu=500m \
  --set prometheus.server.resources.requests.memory=2Gi \
  --set prometheus.server.resources.requests.cpu=500m \
  --reuse-values
```

---

## Next Steps

1. Deploy observability stack to dev environment
2. Deploy log-processor application
3. Import pre-built dashboards
4. Create custom log-processor dashboard
5. Configure alerting rules
6. Set up notification channels
7. Test with sample messages
8. Repeat for production environment
