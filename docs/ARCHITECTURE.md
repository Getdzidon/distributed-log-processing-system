# Architecture Overview

## System Design

### High-Level Architecture

```
┌─────────────────┐
│  Sensor Devices │
└────────┬────────┘
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│   AWS SQS       │────▶│  Log Processor   │
│   (Queue)       │      │  (EKS Pods)      │
└─────────────────┘      └────────┬─────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
            ┌──────────┐  ┌──────────┐  ┌──────────┐
            │   S3     │  │ DynamoDB │  │  OTLP    │
            │ Raw Logs │  │ Metrics  │  │Collector │
            └──────────┘  └──────────┘  └──────────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │ Grafana Stack    │
                                    │ (Loki/Prometheus)│
                                    └──────────────────┘
```

## Component Details

### 1. Message Ingestion (SQS)
- **Purpose**: Decouple sensor data ingestion from processing
- **Configuration**: 
  - Visibility timeout: 300s
  - Message retention: 14 days
  - Dead Letter Queue for failed messages
- **Scaling**: Queue depth triggers KEDA autoscaling

### 2. Log Processor (EKS)
- **Language**: Python 3.11
- **Architecture**: Modular processor pattern
- **Processors**:
  - `TemperatureProcessor`: Handles temperature sensors (C/F conversion)
  - `HumidityProcessor`: Handles humidity sensors (0-100%)
  - `PressureProcessor`: Handles pressure sensors (hPa/PSI conversion)
- **Extensibility**: Add new processors by extending `BaseProcessor`

### 3. Storage Layer

#### S3 (Raw Logs)
- **Structure**: `raw/{sensor_type}/{year}/{month}/{day}/{timestamp}.json`
- **Lifecycle**: 
  - Standard: 0-90 days
  - Glacier: 90-365 days
  - Expiration: 365 days
- **Replication**: Cross-region to us-west-2 (production)

#### DynamoDB (Processed Metrics)
- **Schema**:
  - Partition Key: `sensor_id`
  - Sort Key: `timestamp`
  - GSI: `sensor_type-timestamp-index`
- **Features**:
  - TTL: 90 days
  - Point-in-time recovery
  - Global tables (multi-region)

### 4. Observability Stack

#### OpenTelemetry
- **Traces**: Distributed tracing across all components
- **Metrics**: Custom business metrics + system metrics
- **Logs**: Structured JSON logs with trace correlation

#### Prometheus
- **Metrics Collection**: Scrapes OTLP collector
- **Retention**: 15 days
- **Alerting**: AlertManager integration

#### Grafana
- **Dashboards**:
  - System Overview
  - Sensor-specific metrics
  - SLO compliance
  - Cost optimization
- **Data Sources**: Prometheus, Loki, Tempo

#### Loki
- **Log Aggregation**: Centralized log storage
- **Retention**: 30 days
- **Indexing**: By namespace, pod, sensor_type

## Multi-Region Architecture

### Active-Active Configuration

```
┌─────────────────────────────────────────────────────┐
│                    Route53                          │
│              (Health Check + Failover)              │
└──────────────┬──────────────────────┬───────────────┘
               │                      │
               ▼                      ▼
    ┌──────────────────┐   ┌──────────────────┐
    │   us-east-1      │   │   us-west-2      │
    │   (Primary)      │   │   (Secondary)    │
    ├──────────────────┤   ├──────────────────┤
    │ EKS Cluster      │   │ EKS Cluster      │
    │ SQS Queue        │   │ SQS Queue        │
    │ S3 Bucket        │◄──┤ S3 Bucket        │
    │ DynamoDB Table   │◄─►│ DynamoDB Table   │
    └──────────────────┘   └──────────────────┘
         (Replication)      (Global Tables)
```

### Disaster Recovery

- **RPO**: < 1 minute (continuous replication)
- **RTO**: < 5 minutes (automated failover)
- **Failover Triggers**:
  - EKS cluster health check failure
  - SQS queue unavailability
  - Regional AWS outage

## Security Architecture

### Network Security
- **VPC**: Isolated per environment
- **Subnets**: Public (NAT/LB) + Private (EKS nodes)
- **Security Groups**: Least privilege access
- **Network Policies**: Pod-to-pod communication restrictions

### IAM & Authentication
- **IRSA**: IAM Roles for Service Accounts
- **Least Privilege**: Scoped permissions per service
- **No Long-lived Credentials**: Temporary STS tokens

### Data Security
- **Encryption at Rest**: 
  - S3: AES-256
  - DynamoDB: AWS managed keys
- **Encryption in Transit**: TLS 1.3
- **Secrets Management**: AWS Secrets Manager

## Scalability Design

### Horizontal Scaling
- **KEDA**: Queue-based autoscaling
- **Target**: 10 messages per pod
- **Limits**: Min 2, Max 50 pods
- **Scale-down**: Gradual (5 min cooldown)

### Vertical Scaling
- **Resource Requests**: 250m CPU, 256Mi RAM
- **Resource Limits**: 500m CPU, 512Mi RAM
- **VPA**: Disabled (horizontal scaling preferred)

### Cost Optimization
- **Spot Instances**: 50% of node capacity
- **S3 Lifecycle**: Automatic archival
- **DynamoDB**: On-demand pricing
- **Right-sizing**: Based on P95 metrics

## Monitoring & Alerting

### SLIs (Service Level Indicators)
1. **Availability**: Successful requests / Total requests
2. **Latency**: P95 processing time
3. **Throughput**: Messages processed per second
4. **Error Rate**: Failed messages / Total messages

### SLOs (Service Level Objectives)
1. **Availability**: 99.9% (43 min downtime/month)
2. **Latency**: P95 < 500ms
3. **Error Rate**: < 0.1%

### Alerts
- **Critical**: 
  - Error rate > 1%
  - Availability < 99%
  - DLQ depth > 100
- **Warning**:
  - Latency P95 > 500ms
  - Queue depth > 1000
  - Pod crash loops

## Deployment Strategy

### GitOps Workflow
1. **Code Push**: Developer pushes to GitHub
2. **CI Pipeline**: Tests, lint, security scan
3. **Build**: Docker image built and pushed to ECR
4. **Staging Deploy**: Automatic deployment to staging
5. **Integration Tests**: Smoke tests run
6. **Production Deploy**: Manual approval required
7. **Multi-Region**: Sequential deployment (us-east-1 → us-west-2)

### Rollback Strategy
- **Helm Rollback**: `helm rollback log-processor`
- **Automatic**: On health check failure
- **Manual**: Via GitHub Actions workflow

## Future Enhancements

1. **Additional Sensors**: Vibration, motion, light
2. **Real-time Analytics**: Kinesis Data Analytics
3. **ML Anomaly Detection**: SageMaker integration
4. **Multi-cloud**: Azure/GCP support
5. **Edge Processing**: AWS IoT Greengrass
