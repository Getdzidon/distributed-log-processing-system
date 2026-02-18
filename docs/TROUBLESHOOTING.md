# Troubleshooting Guide

## Common Issues and Solutions

### 1. Pods Not Starting

**Symptoms**
```
kubectl get pods -n log-processing
NAME                             READY   STATUS             RESTARTS   AGE
log-processor-xxx                0/1     CrashLoopBackOff   5          5m
```

**Diagnosis**
```bash
# Check pod events
kubectl describe pod -n log-processing log-processor-xxx

# Check logs
kubectl logs -n log-processing log-processor-xxx

# Check service account
kubectl get sa log-processor -n log-processing -o yaml
```

**Common Causes**
- Missing environment variables
- IAM role not attached to service account
- Invalid AWS credentials
- Missing secrets

**Solutions**
```bash
# Verify secrets exist
kubectl get secrets -n log-processing

# Check IAM role annotation
kubectl describe sa log-processor -n log-processing | grep role-arn

# Recreate secrets
kubectl delete secret log-processor-secrets -n log-processing
kubectl create secret generic log-processor-secrets \
  --from-literal=queue-url=$QUEUE_URL \
  --from-literal=s3-bucket=$S3_BUCKET \
  --from-literal=dynamodb-table=$DYNAMODB_TABLE
```

### 2. Messages Not Processing

**Symptoms**
- SQS queue depth increasing
- No logs showing message processing
- Pods running but idle

**Diagnosis**
```bash
# Check queue attributes
aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names All

# Check pod logs
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f

# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn $ROLE_ARN \
  --action-names sqs:ReceiveMessage \
  --resource-arns $QUEUE_ARN
```

**Common Causes**
- Incorrect queue URL
- IAM permissions missing
- Network connectivity issues
- Message format errors

**Solutions**
```bash
# Verify queue URL
kubectl exec -n log-processing log-processor-xxx -- env | grep QUEUE_URL

# Test SQS access from pod
kubectl exec -n log-processing log-processor-xxx -- \
  aws sqs receive-message --queue-url $QUEUE_URL --max-number-of-messages 1

# Check IAM role policy
aws iam get-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME
```

### 3. KEDA Autoscaling Not Working

**Symptoms**
- Pods not scaling despite queue depth
- ScaledObject shows errors

**Diagnosis**
```bash
# Check ScaledObject status
kubectl describe scaledobject -n log-processing

# Check KEDA operator logs
kubectl logs -n keda -l app.kubernetes.io/name=keda-operator

# Check HPA
kubectl get hpa -n log-processing
```

**Common Causes**
- KEDA not installed
- Incorrect queue URL in ScaledObject
- IAM permissions for KEDA operator
- Metrics not available

**Solutions**
```bash
# Verify KEDA installation
kubectl get pods -n keda

# Reinstall KEDA if needed
helm upgrade --install keda kedacore/keda --namespace keda --create-namespace

# Check ScaledObject configuration
kubectl get scaledobject -n log-processing -o yaml

# Manual scale test
kubectl scale deployment log-processor -n log-processing --replicas=5
```

### 4. High Error Rate

**Symptoms**
- Many messages in DLQ
- Error logs in pods
- Validation failures

**Diagnosis**
```bash
# Check DLQ
aws sqs get-queue-attributes \
  --queue-url $DLQ_URL \
  --attribute-names ApproximateNumberOfMessages

# Sample DLQ messages
aws sqs receive-message --queue-url $DLQ_URL --max-number-of-messages 10

# Check error metrics
kubectl port-forward -n observability svc/loki-grafana 3000:80
# View error dashboard
```

**Common Causes**
- Invalid message format
- Data validation failures
- Storage errors (S3/DynamoDB)
- Transient AWS service issues

**Solutions**
```bash
# Validate message format
aws sqs receive-message --queue-url $DLQ_URL | jq '.Messages[0].Body'

# Check S3 permissions
aws s3 ls s3://$S3_BUCKET/

# Check DynamoDB permissions
aws dynamodb describe-table --table-name $DYNAMODB_TABLE

# Redrive DLQ messages
aws sqs start-message-move-task \
  --source-arn $DLQ_ARN \
  --destination-arn $QUEUE_ARN
```

### 5. High Latency

**Symptoms**
- P95 latency > 500ms
- Slow message processing
- Queue backlog growing

**Diagnosis**
```bash
# Check pod resources
kubectl top pods -n log-processing

# Check node resources
kubectl top nodes

# View traces in Grafana Tempo
kubectl port-forward -n observability svc/tempo 3100:3100
```

**Common Causes**
- Insufficient pod resources
- Node resource constraints
- DynamoDB throttling
- S3 rate limiting

**Solutions**
```bash
# Increase pod resources
helm upgrade log-processor infrastructure/helm/log-processor \
  --set resources.requests.cpu=500m \
  --set resources.requests.memory=512Mi

# Scale horizontally
kubectl scale deployment log-processor -n log-processing --replicas=10

# Check DynamoDB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=$DYNAMODB_TABLE \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### 6. Storage Issues

**Symptoms**
- S3 upload failures
- DynamoDB write errors
- Storage costs increasing rapidly

**Diagnosis**
```bash
# Check S3 bucket
aws s3 ls s3://$S3_BUCKET/raw/ --recursive --summarize

# Check DynamoDB table
aws dynamodb describe-table --table-name $DYNAMODB_TABLE

# Check storage metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BucketSizeBytes \
  --dimensions Name=BucketName,Value=$S3_BUCKET
```

**Solutions**
```bash
# Verify lifecycle policies
aws s3api get-bucket-lifecycle-configuration --bucket $S3_BUCKET

# Check DynamoDB TTL
aws dynamodb describe-time-to-live --table-name $DYNAMODB_TABLE

# Enable S3 lifecycle if missing
aws s3api put-bucket-lifecycle-configuration \
  --bucket $S3_BUCKET \
  --lifecycle-configuration file://lifecycle.json
```

### 7. Observability Issues

**Symptoms**
- No metrics in Grafana
- Missing logs in Loki
- Traces not appearing

**Diagnosis**
```bash
# Check OTLP collector
kubectl get pods -n observability

# Check collector logs
kubectl logs -n observability opentelemetry-collector-xxx

# Verify Prometheus targets
kubectl port-forward -n observability svc/loki-prometheus-server 9090:80
# Navigate to http://localhost:9090/targets
```

**Solutions**
```bash
# Restart OTLP collector
kubectl rollout restart deployment -n observability opentelemetry-collector

# Verify pod annotations
kubectl get pods -n log-processing -o yaml | grep prometheus

# Check service monitor
kubectl get servicemonitor -n log-processing
```

### 8. Multi-Region Failover Issues

**Symptoms**
- Failover not happening
- Route53 health checks failing
- Data not replicating

**Diagnosis**
```bash
# Check Route53 health checks
aws route53 get-health-check-status --health-check-id $HEALTH_CHECK_ID

# Check S3 replication
aws s3api get-bucket-replication --bucket $S3_BUCKET

# Check DynamoDB global table
aws dynamodb describe-global-table --global-table-name $DYNAMODB_TABLE
```

**Solutions**
```bash
# Manually trigger failover
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch file://failover.json

# Verify replication status
aws s3api get-bucket-replication --bucket $S3_BUCKET | jq '.ReplicationConfiguration.Rules[].Status'

# Check global table status
aws dynamodb describe-global-table --global-table-name $DYNAMODB_TABLE | jq '.GlobalTableDescription.ReplicationGroup[].ReplicaStatus'
```

## Emergency Procedures

### Complete System Restart

```bash
# 1. Scale down to zero
kubectl scale deployment log-processor -n log-processing --replicas=0

# 2. Clear any stuck resources
kubectl delete pods -n log-processing --all --force --grace-period=0

# 3. Verify queue is stable
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All

# 4. Scale back up
kubectl scale deployment log-processor -n log-processing --replicas=3

# 5. Monitor recovery
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f
```

### Rollback Deployment

```bash
# List releases
helm history log-processor -n log-processing

# Rollback to previous
helm rollback log-processor -n log-processing

# Rollback to specific version
helm rollback log-processor 5 -n log-processing
```

### Drain DLQ

```bash
# Move messages back to main queue
aws sqs start-message-move-task \
  --source-arn $DLQ_ARN \
  --destination-arn $QUEUE_ARN

# Or purge DLQ (destructive)
aws sqs purge-queue --queue-url $DLQ_URL
```

## Getting Help

1. Check logs: `kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor`
2. Check metrics: Grafana dashboards
3. Check traces: Tempo/Jaeger
4. Review AWS CloudWatch
5. Check GitHub Issues
6. Contact SRE team
