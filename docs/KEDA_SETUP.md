# KEDA Setup (Kubernetes Event-Driven Autoscaling)

## Overview

KEDA enables event-driven autoscaling for the log-processor application based on SQS queue depth. It scales pods from 0 to N based on the number of messages waiting in the queue.

**Why KEDA?**
- Scale to zero when queue is empty (cost savings)
- Scale up automatically when messages arrive
- Native SQS integration with AWS authentication
- More responsive than standard HPA (Horizontal Pod Autoscaler)

## Deployment Method

**Automated via Helm** - Deployed once per EKS cluster in the `keda` namespace.

### When to Deploy

Deploy KEDA **after** EKS cluster is created but **before** the log-processor application.

**Deployment order:**
1. Bootstrap infrastructure
2. Main infrastructure (VPC, EKS, SQS, S3, DynamoDB)
3. **KEDA** ← You are here
4. Observability stack (Grafana, Prometheus, Loki)
5. OpenTelemetry Collector
6. Log-processor application

---

## Installation

### Step 1: Deploy KEDA

```bash
# Add Helm repo
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA
helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace \
  --set podIdentity.aws.irsa.enabled=true \
  --set podIdentity.aws.irsa.roleArn="" \
  --set resources.operator.requests.cpu=100m \
  --set resources.operator.requests.memory=128Mi \
  --set resources.operator.limits.cpu=500m \
  --set resources.operator.limits.memory=512Mi \
  --set resources.metricServer.requests.cpu=50m \
  --set resources.metricServer.requests.memory=64Mi \
  --wait

# Verify deployment
kubectl get pods -n keda
```

**Components deployed:**
- **keda-operator**: Manages ScaledObject resources and creates HPA
- **keda-metrics-apiserver**: Exposes external metrics to Kubernetes
- **keda-admission-webhooks**: Validates KEDA resources

### Step 2: Verify Installation

```bash
# Check KEDA version
kubectl get deployment keda-operator -n keda -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check CRDs
kubectl get crd | grep keda

# Expected output:
# scaledobjects.keda.sh
# scaledjobs.keda.sh
# triggerauthentications.keda.sh
```

---

## Application Integration

### How KEDA Scales Log-Processor

KEDA monitors the SQS queue and scales the log-processor deployment based on:
- **Queue depth**: Number of messages in queue
- **Target messages per pod**: Desired messages each pod should handle
- **Scaling formula**: `desiredReplicas = ceil(queueDepth / targetMessagesPerPod)`

**Example:**
- Queue has 100 messages
- Target: 10 messages per pod
- KEDA scales to: 100 / 10 = 10 pods

### ScaledObject Configuration

The ScaledObject is already configured in the Helm chart at `infrastructure/helm/log-processor/templates/scaledobject.yaml`:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ include "log-processor.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  scaleTargetRef:
    name: {{ include "log-processor.fullname" . }}
  
  # Scaling behavior
  minReplicaCount: {{ .Values.autoscaling.minReplicas }}
  maxReplicaCount: {{ .Values.autoscaling.maxReplicas }}
  pollingInterval: 30  # Check queue every 30 seconds
  cooldownPeriod: 300  # Wait 5 minutes before scaling down
  
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: {{ .Values.sqs.queueUrl }}
        queueLength: "{{ .Values.autoscaling.targetQueueLength }}"
        awsRegion: {{ .Values.aws.region }}
        identityOwner: operator  # Use KEDA operator's IRSA role
```

### Helm Values Configuration

**Dev environment** (`values-dev.yaml`):
```yaml
autoscaling:
  enabled: true
  minReplicas: 0  # Scale to zero when queue is empty
  maxReplicas: 10
  targetQueueLength: 10  # Scale up when queue has >10 messages

sqs:
  queueUrl: ""  # Set during deployment from Terraform output

aws:
  region: eu-central-1
```

**Production environment** (`values-production.yaml`):
```yaml
autoscaling:
  enabled: true
  minReplicas: 2  # Always keep 2 pods running
  maxReplicas: 50
  targetQueueLength: 5  # More aggressive scaling

sqs:
  queueUrl: ""

aws:
  region: eu-central-1
```

---

## IAM Permissions for KEDA

### Option 1: Use Application's IRSA Role (Recommended)

KEDA uses the log-processor's service account IRSA role to access SQS. The role already has SQS permissions from Terraform.

**No additional configuration needed** - KEDA automatically uses the pod's IAM role.

### Option 2: Separate KEDA IRSA Role

For stricter separation, create a dedicated IRSA role for KEDA:

```bash
# Get OIDC provider from Terraform
OIDC_PROVIDER=$(cd infrastructure/terraform && terraform output -raw oidc_provider_arn)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create IAM policy
cat > keda-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ],
      "Resource": "arn:aws:sqs:eu-central-1:${ACCOUNT_ID}:cmg-log-processor-*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name keda-sqs-policy \
  --policy-document file://keda-policy.json

# Create trust policy
cat > keda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-central-1.amazonaws.com/id/XXXXX:sub": "system:serviceaccount:keda:keda-operator"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name keda-operator-role \
  --assume-role-policy-document file://keda-trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name keda-operator-role \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/keda-sqs-policy

# Update KEDA with role ARN
helm upgrade keda kedacore/keda \
  --namespace keda \
  --set podIdentity.aws.irsa.roleArn=arn:aws:iam::${ACCOUNT_ID}:role/keda-operator-role \
  --reuse-values
```

---

## Deployment with KEDA

### Deploy Log-Processor with Autoscaling

```bash
# Get SQS queue URL from Terraform
QUEUE_URL=$(cd infrastructure/terraform && terraform output -raw sqs_queue_url)
ROLE_ARN=$(cd infrastructure/terraform && terraform output -raw service_account_role_arn)

# Deploy with KEDA enabled
helm upgrade --install log-processor \
  infrastructure/helm/log-processor \
  --namespace log-processing \
  --create-namespace \
  --values infrastructure/helm/log-processor/values-dev.yaml \
  --set sqs.queueUrl=$QUEUE_URL \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ROLE_ARN \
  --set autoscaling.enabled=true \
  --wait

# Verify ScaledObject
kubectl get scaledobject -n log-processing
kubectl describe scaledobject -n log-processing
```

---

## Testing Autoscaling

### Test Scale-Up

```bash
# Send 100 messages to queue
QUEUE_URL=$(cd infrastructure/terraform && terraform output -raw sqs_queue_url)

for i in {1..100}; do
  aws sqs send-message \
    --queue-url $QUEUE_URL \
    --message-body "{
      \"sensor_type\": \"temperature\",
      \"sensor_id\": \"temp-$i\",
      \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
      \"value\": $((20 + RANDOM % 10)),
      \"unit\": \"celsius\",
      \"location\": \"test\"
    }"
done

# Watch pods scale up
kubectl get pods -n log-processing -w

# Check HPA created by KEDA
kubectl get hpa -n log-processing

# Check ScaledObject status
kubectl get scaledobject -n log-processing -o yaml
```

**Expected behavior:**
1. Queue receives 100 messages
2. KEDA detects queue depth
3. Calculates: 100 messages / 10 target = 10 pods
4. Creates HPA to scale deployment to 10 replicas
5. Pods start processing messages
6. Queue empties
7. After cooldown (5 min), scales back to minReplicas

### Test Scale-to-Zero

```bash
# Ensure queue is empty
aws sqs purge-queue --queue-url $QUEUE_URL

# Wait for cooldown period (5 minutes)
# Watch pods scale down
kubectl get pods -n log-processing -w

# After cooldown, should scale to 0 (dev) or 2 (production)
```

---

## Monitoring KEDA

### KEDA Metrics

KEDA exposes Prometheus metrics on port 8080:

```bash
# Port forward to KEDA operator
kubectl port-forward -n keda deployment/keda-operator 8080:8080

# Access metrics
curl http://localhost:8080/metrics
```

**Key metrics:**
```promql
# Scaler errors
keda_scaler_errors_total

# Scaler activity
keda_scaler_active

# Scaled object errors
keda_scaled_object_errors_total

# Trigger authentication errors
keda_trigger_authentication_errors_total
```

### Create Grafana Dashboard

**Panel 1: Current Replicas**
```promql
kube_deployment_status_replicas{deployment="log-processor", namespace="log-processing"}
```

**Panel 2: Desired Replicas**
```promql
kube_deployment_spec_replicas{deployment="log-processor", namespace="log-processing"}
```

**Panel 3: Queue Depth**
```promql
# From CloudWatch data source
aws_sqs_approximate_number_of_messages_visible_average{queue_name="cmg-log-processor-dev-queue"}
```

**Panel 4: Scaling Events**
```promql
rate(keda_scaler_active[5m])
```

---

## Advanced Configuration

### Custom Scaling Behavior

Add advanced scaling behavior to ScaledObject:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: log-processor
spec:
  scaleTargetRef:
    name: log-processor
  
  minReplicaCount: 0
  maxReplicaCount: 50
  pollingInterval: 30
  cooldownPeriod: 300
  
  # Advanced scaling behavior
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Percent
              value: 50
              periodSeconds: 60
        scaleUp:
          stabilizationWindowSeconds: 0
          policies:
            - type: Percent
              value: 100
              periodSeconds: 15
            - type: Pods
              value: 4
              periodSeconds: 15
          selectPolicy: Max
  
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: "https://sqs.eu-central-1.amazonaws.com/123456789012/queue-name"
        queueLength: "10"
        awsRegion: eu-central-1
        identityOwner: operator
```

**Behavior explained:**
- **Scale up**: Immediately add 100% more pods or 4 pods (whichever is higher)
- **Scale down**: Wait 5 minutes, then reduce by 50% per minute

### Multiple Triggers

Scale based on multiple metrics:

```yaml
triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: "https://sqs.eu-central-1.amazonaws.com/123456789012/queue-name"
      queueLength: "10"
      awsRegion: eu-central-1
  
  - type: prometheus
    metadata:
      serverAddress: http://loki-prometheus-server.observability.svc.cluster.local
      metricName: processing_duration_seconds
      threshold: "0.5"
      query: histogram_quantile(0.95, rate(processing_duration_seconds_bucket[5m]))
```

---

## Troubleshooting

### Pods Not Scaling

```bash
# Check KEDA operator logs
kubectl logs -n keda deployment/keda-operator

# Check ScaledObject status
kubectl describe scaledobject -n log-processing

# Check HPA created by KEDA
kubectl get hpa -n log-processing
kubectl describe hpa -n log-processing

# Verify SQS permissions
kubectl logs -n log-processing deployment/log-processor | grep -i sqs
```

### Authentication Errors

```bash
# Check service account annotations
kubectl get sa log-processor -n log-processing -o yaml

# Verify IRSA role has SQS permissions
aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>

# Test SQS access from pod
kubectl exec -n log-processing deployment/log-processor -- \
  aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All
```

### Scaling Too Slow

```bash
# Reduce polling interval
kubectl patch scaledobject log-processor -n log-processing --type merge -p '
{
  "spec": {
    "pollingInterval": 10
  }
}'

# Reduce target queue length (more aggressive scaling)
kubectl patch scaledobject log-processor -n log-processing --type merge -p '
{
  "spec": {
    "triggers": [
      {
        "type": "aws-sqs-queue",
        "metadata": {
          "queueLength": "5"
        }
      }
    ]
  }
}'
```

### Scaling Too Aggressive

```bash
# Increase cooldown period
kubectl patch scaledobject log-processor -n log-processing --type merge -p '
{
  "spec": {
    "cooldownPeriod": 600
  }
}'

# Increase target queue length
kubectl patch scaledobject log-processor -n log-processing --type merge -p '
{
  "spec": {
    "triggers": [
      {
        "type": "aws-sqs-queue",
        "metadata": {
          "queueLength": "20"
        }
      }
    ]
  }
}'
```

---

## Production Considerations

### Scaling Limits

**Dev environment:**
- minReplicas: 0 (cost savings)
- maxReplicas: 10 (limited load)
- targetQueueLength: 10

**Production environment:**
- minReplicas: 2 (always available)
- maxReplicas: 50 (handle spikes)
- targetQueueLength: 5 (faster response)

### Cost Optimization

**Scale to zero in dev:**
```yaml
minReplicaCount: 0
```
- Saves compute costs when queue is empty
- Cold start delay (~30 seconds) acceptable for dev

**Keep minimum replicas in production:**
```yaml
minReplicaCount: 2
```
- No cold start delay
- Always ready to process messages
- Higher cost but better performance

### Monitoring Alerts

Create alerts for KEDA issues:

**Alert 1: KEDA Scaler Errors**
```promql
rate(keda_scaler_errors_total[5m]) > 0
```

**Alert 2: Max Replicas Reached**
```promql
kube_deployment_status_replicas{deployment="log-processor"} >= 50
```

**Alert 3: Scaling Lag**
```promql
aws_sqs_approximate_number_of_messages_visible_average > 100
AND
kube_deployment_status_replicas{deployment="log-processor"} < 10
```

---

## Benefits of KEDA

**Before KEDA:**
- Manual scaling or static replica count
- Wasted resources when queue is empty
- Slow response to traffic spikes
- Complex custom autoscaling logic

**After KEDA:**
- Automatic event-driven scaling
- Scale to zero for cost savings
- Fast response to queue depth changes
- Native AWS integration with IRSA
- No custom code needed

---

## Next Steps

1. Deploy KEDA to EKS cluster
2. Deploy log-processor with autoscaling enabled
3. Test scaling with sample messages
4. Monitor scaling behavior in Grafana
5. Tune scaling parameters for your workload
6. Set up alerts for scaling issues
7. Document scaling behavior for your team
