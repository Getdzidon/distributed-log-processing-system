#!/bin/bash
# Complete setup script for CMG Log Processor
#
# This script automates the complete deployment process:
#   1. Deploy infrastructure with Terraform
#   2. Configure kubectl for EKS access
#   3. Install KEDA for autoscaling
#   4. Install observability stack (Grafana, Prometheus, Loki)
#   5. Build and push Docker image to ECR
#   6. Deploy application with Helm
#   7. Verify deployment and send test message
#
# Use cases:
#   - Quick manual deployments from your local machine
#   - Testing infrastructure changes before committing
#   - Disaster recovery scenarios
#   - Environments without CI/CD access
#
# Note: For production, GitHub Actions workflows are recommended.
#       See docs/CICD.md for automated CI/CD setup.

set -e

echo "=========================================="
echo "CMG Log Processor - Complete Setup"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "AWS CLI not found. Install it first."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found. Install it first."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Helm not found. Install it first."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Terraform not found. Install it first."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker not found. Install it first."; exit 1; }

echo "✓ All prerequisites found"
echo ""

# Configuration
ENVIRONMENT=${ENVIRONMENT:-"dev"}
AWS_REGION=${AWS_REGION:-"eu-central-1"}

echo "Configuration:"
echo "  Environment: $ENVIRONMENT"
echo "  AWS Region: $AWS_REGION"
echo ""

read -p "Continue with setup? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Step 1: Deploy Infrastructure
echo ""
echo "Step 1/7: Deploying Infrastructure..."
cd infrastructure/terraform

terraform init
terraform workspace new $ENVIRONMENT 2>/dev/null || terraform workspace select $ENVIRONMENT
terraform apply -var-file=environments/${ENVIRONMENT}.tfvars -auto-approve

# Save outputs
terraform output -json > outputs.json
echo "✓ Infrastructure deployed"

# Step 2: Configure kubectl
echo ""
echo "Step 2/7: Configuring kubectl..."
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
echo "✓ kubectl configured"

# Step 3: Install KEDA
echo ""
echo "Step 3/7: Installing KEDA..."
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update
helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --wait
echo "✓ KEDA installed"

# Step 4: Install Observability Stack
echo ""
echo "Step 4/7: Installing Observability Stack..."
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update
helm upgrade --install loki grafana/loki-stack \
  --namespace observability \
  --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set prometheus.alertmanager.enabled=true \
  --wait
echo "✓ Observability stack installed"

# Get Grafana password
GRAFANA_PASSWORD=$(kubectl get secret --namespace observability loki-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
echo "  Grafana admin password: $GRAFANA_PASSWORD"

# Step 5: Build and Push Image
echo ""
echo "Step 5/7: Building and pushing Docker image..."
cd ../..
ECR_REPO=$(cd infrastructure/terraform && terraform output -raw ecr_repository_url)

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REPO

docker build -t log-processor:latest .
docker tag log-processor:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
echo "✓ Image built and pushed"

# Step 6: Deploy Application
echo ""
echo "Step 6/7: Deploying application..."
cd infrastructure/terraform
QUEUE_URL=$(terraform output -raw sqs_queue_url)
S3_BUCKET=$(terraform output -raw s3_bucket_name)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name)
ROLE_ARN=$(terraform output -raw service_account_role_arn)

cd ../..
helm upgrade --install log-processor \
  infrastructure/helm/log-processor \
  --namespace log-processing \
  --create-namespace \
  --values infrastructure/helm/log-processor/values-${ENVIRONMENT}.yaml \
  --set image.repository=$ECR_REPO \
  --set image.tag=latest \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --set env[0].name=QUEUE_URL \
  --set env[0].value=$QUEUE_URL \
  --set env[1].name=RAW_LOGS_BUCKET \
  --set env[1].value=$S3_BUCKET \
  --set env[2].name=PROCESSED_METRICS_TABLE \
  --set env[2].value=$DYNAMODB_TABLE \
  --wait
echo "✓ Application deployed"

# Step 7: Verify Deployment
echo ""
echo "Step 7/7: Verifying deployment..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=log-processor -n log-processing --timeout=300s
echo "✓ Deployment verified"

# Send test message
echo ""
echo "Sending test message..."
aws sqs send-message \
  --queue-url $QUEUE_URL \
  --message-body '{
    "sensor_type": "temperature",
    "sensor_id": "temp-001",
    "timestamp": "2024-01-15T10:00:00Z",
    "value": 22.5,
    "unit": "celsius",
    "location": "test"
  }' >/dev/null

sleep 5
echo "✓ Test message sent"

# Summary
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Resources:"
echo "  EKS Cluster: $CLUSTER_NAME"
echo "  SQS Queue: $QUEUE_URL"
echo "  S3 Bucket: $S3_BUCKET"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n observability svc/loki-grafana 3000:80"
echo "  URL: http://localhost:3000"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASSWORD"
echo ""
echo "View logs:"
echo "  kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f"
echo ""
echo "Send test messages:"
echo "  QUEUE_URL=$QUEUE_URL ./scripts/send_test_messages.sh"
echo ""
echo "Next steps:"
echo "  - Review docs/ARCHITECTURE.md"
echo "  - Set up CI/CD with GitHub Actions"
echo "  - Configure alerts in Grafana"
echo ""
