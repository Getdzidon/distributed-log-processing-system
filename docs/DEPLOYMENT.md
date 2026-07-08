# Deployment Guide

> **Note**: For automated CI/CD deployments, see [CICD.md](CICD.md). This guide covers manual deployment and initial setup.

## Prerequisites

### Required Tools
```bash
aws --version        # >= 2.0
kubectl version      # >= 1.28
helm version         # >= 3.12
terraform version    # >= 1.5
docker --version     # >= 24.0
```

### AWS Authentication
Configure AWS CLI with your credentials:
```bash
aws configure
# Region: eu-central-1
```

---

## One-Time Setup

### Step 1: Create Terraform Backend (Required First!)

**This must be done before running any Terraform commands.**

```bash
# Create S3 bucket for Terraform state
aws s3 mb s3://dlps-terraform-state --region eu-central-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket dlps-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-central-1
```

### Step 2: Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name log-processor \
  --region eu-central-1
```

---

## Infrastructure Deployment

### Deploy to Dev

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Create and select dev workspace
terraform workspace new dev
terraform workspace select dev

# Deploy
terraform apply -var-file=environments/dev.tfvars

# Save outputs
terraform output -json > outputs.json
```

### Deploy to Production

```bash
# Select production workspace
terraform workspace new production
terraform workspace select production

# Deploy with multi-region
terraform apply -var-file=environments/production.tfvars

# Save outputs
terraform output -json > outputs.json
```

---

## Kubernetes Setup

### Configure kubectl

```bash
# Get cluster name from Terraform
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)

# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region eu-central-1

# Verify
kubectl get nodes
```

### Install KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace
```

### Install Observability Stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki stack (includes Grafana, Prometheus)
helm install loki grafana/loki-stack \
  --namespace observability \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true

# Get Grafana password
kubectl get secret --namespace observability loki-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Install OpenTelemetry Collector

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --set mode=deployment
```

---

## Application Deployment

### Build and Push Image

```bash
# Get ECR URL
ECR_REPO=$(cd infrastructure/terraform && terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build and push
docker build -t log-processor:latest .
docker tag log-processor:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### Deploy with Helm

```bash
# Get Terraform outputs
cd infrastructure/terraform
ROLE_ARN=$(terraform output -raw service_account_role_arn)

# Deploy to dev
cd ../..
helm upgrade --install log-processor \
  infrastructure/helm/log-processor \
  --namespace log-processing \
  --create-namespace \
  --values infrastructure/helm/log-processor/values-dev.yaml \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --wait

# Verify
kubectl get pods -n log-processing
```

---

## Verification

### Send Test Message

```bash
QUEUE_URL=$(cd infrastructure/terraform && terraform output -raw sqs_queue_url)

aws sqs send-message \
  --queue-url $QUEUE_URL \
  --message-body '{
    "sensor_type": "temperature",
    "sensor_id": "temp-001",
    "timestamp": "2024-01-15T10:00:00Z",
    "value": 22.5,
    "unit": "celsius",
    "location": "test"
  }'

# Check logs
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor --tail=20
```

### Verify Storage

```bash
S3_BUCKET=$(cd infrastructure/terraform && terraform output -raw s3_bucket_name)
DYNAMODB_TABLE=$(cd infrastructure/terraform && terraform output -raw dynamodb_table_name)

# Check S3
aws s3 ls s3://$S3_BUCKET/raw/temperature/ --recursive

# Check DynamoDB
aws dynamodb scan --table-name $DYNAMODB_TABLE --limit 10
```

### Access Grafana

```bash
# Port forward
kubectl port-forward -n observability svc/loki-grafana 3000:80

# Open http://localhost:3000
# Username: admin
# Password: (from earlier step)

# Create dashboards using these metrics:
# - messages_processed_total{sensor_type}
# - processing_duration_seconds{sensor_type}
# - validation_errors_total{sensor_type}
# - processing_errors_total{sensor_type}
```

---

## Multi-Region Production

### Deploy to Both Regions

```bash
# Primary region (eu-central-1)
aws eks update-kubeconfig --name dlps-log-processor-prod-eu-central-1 --region eu-central-1
helm upgrade --install log-processor infrastructure/helm/log-processor \
  --namespace log-processing --create-namespace \
  --values infrastructure/helm/log-processor/values-production.yaml --wait

# Secondary region (eu-west-1)
aws eks update-kubeconfig --name dlps-log-processor-prod-eu-west-1 --region eu-west-1
helm upgrade --install log-processor infrastructure/helm/log-processor \
  --namespace log-processing --create-namespace \
  --values infrastructure/helm/log-processor/values-production.yaml --wait
```

---

## Troubleshooting

### Pods Not Starting

```bash
kubectl describe pod -n log-processing <pod-name>
kubectl logs -n log-processing <pod-name>
kubectl get sa log-processor -n log-processing -o yaml
```

### Messages Not Processing

```bash
# Check queue
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All

# Check logs
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f

# Check KEDA
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator
```

### Scaling Issues

```bash
kubectl describe scaledobject -n log-processing
kubectl get hpa -n log-processing
```

---

## Rollback

### Application

```bash
helm history log-processor -n log-processing
helm rollback log-processor -n log-processing
```

### Infrastructure

```bash
git checkout <previous-commit>
cd infrastructure/terraform
terraform plan
terraform apply
```

---

## Cleanup

### Remove Application

```bash
helm uninstall log-processor -n log-processing
kubectl delete namespace log-processing
```

### Destroy Infrastructure

```bash
cd infrastructure/terraform
terraform workspace select dev
terraform destroy -var-file=environments/dev.tfvars
```

---

## Next Steps

- Set up automated deployments: [CICD.md](CICD.md)
- Configure OIDC authentication: [OIDC_SETUP.md](OIDC_SETUP.md)
- Add new sensors: [ADDING_SENSORS.md](ADDING_SENSORS.md)
