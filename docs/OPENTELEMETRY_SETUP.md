# OpenTelemetry Setup

## Overview

OpenTelemetry Collector is deployed to provide unified observability by collecting, processing, and exporting traces, metrics, and logs. It acts as a central pipeline between the log-processor application and observability backends (Prometheus, Loki, Jaeger).

**Why OpenTelemetry?**
- Vendor-neutral observability standard
- Single agent for traces, metrics, and logs
- Advanced processing (sampling, filtering, batching)
- Future-proof (industry standard)

## Deployment Method

**Automated via Helm** - Deployed once per EKS cluster in the `observability` namespace.

### When to Deploy

Deploy OpenTelemetry Collector **after** Grafana/Prometheus/Loki but **before** the log-processor application.

**Deployment order:**
1. Bootstrap infrastructure
2. Main infrastructure (VPC, EKS, SQS, S3, DynamoDB)
3. Observability stack (Grafana, Prometheus, Loki)
4. **OpenTelemetry Collector** ← You are here
5. Log-processor application

---

## Installation

### Step 1: Deploy OpenTelemetry Collector

```bash
# Add Helm repo
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Install collector
helm install opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --set mode=deployment \
  --set replicaCount=2 \
  --set resources.requests.memory=256Mi \
  --set resources.requests.cpu=100m \
  --set resources.limits.memory=512Mi \
  --set resources.limits.cpu=500m \
  --wait

# Verify deployment
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector
```

### Step 2: Configure Collector

Create custom configuration:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: observability
data:
  config.yaml: |
    receivers:
      # Receive OTLP traces and metrics from application
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      
      # Receive Prometheus metrics
      prometheus:
        config:
          scrape_configs:
            - job_name: 'log-processor'
              kubernetes_sd_configs:
                - role: pod
                  namespaces:
                    names:
                      - log-processing
              relabel_configs:
                - source_labels: [__meta_kubernetes_pod_label_app]
                  action: keep
                  regex: log-processor
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                  action: keep
                  regex: true
                - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
                  action: replace
                  target_label: __address__
                  regex: ([^:]+)(?::\d+)?;(\d+)
                  replacement: \$1:\$2
    
    processors:
      # Batch telemetry for efficiency
      batch:
        timeout: 10s
        send_batch_size: 1024
      
      # Add resource attributes
      resource:
        attributes:
          - key: service.name
            value: log-processor
            action: upsert
          - key: deployment.environment
            from_attribute: k8s.namespace.name
            action: insert
      
      # Memory limiter to prevent OOM
      memory_limiter:
        check_interval: 1s
        limit_mib: 400
        spike_limit_mib: 100
      
      # Sample traces (keep 10% in dev, 1% in production)
      probabilistic_sampler:
        sampling_percentage: 10
    
    exporters:
      # Export metrics to Prometheus
      prometheus:
        endpoint: "0.0.0.0:8889"
        namespace: otel
      
      # Export to Prometheus remote write
      prometheusremotewrite:
        endpoint: http://loki-prometheus-server.observability.svc.cluster.local/api/v1/write
        tls:
          insecure: true
      
      # Export logs to Loki
      loki:
        endpoint: http://loki.observability.svc.cluster.local:3100/loki/api/v1/push
        labels:
          resource:
            service.name: "service_name"
            deployment.environment: "environment"
      
      # Export traces to Jaeger (optional)
      jaeger:
        endpoint: jaeger-collector.observability.svc.cluster.local:14250
        tls:
          insecure: true
      
      # Debug exporter (disable in production)
      logging:
        loglevel: info
    
    service:
      pipelines:
        # Traces pipeline
        traces:
          receivers: [otlp]
          processors: [memory_limiter, batch, resource, probabilistic_sampler]
          exporters: [jaeger, logging]
        
        # Metrics pipeline
        metrics:
          receivers: [otlp, prometheus]
          processors: [memory_limiter, batch, resource]
          exporters: [prometheusremotewrite, prometheus]
        
        # Logs pipeline
        logs:
          receivers: [otlp]
          processors: [memory_limiter, batch, resource]
          exporters: [loki, logging]
EOF

# Update collector to use custom config
helm upgrade opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --set mode=deployment \
  --set configMap.create=false \
  --set configMap.existingName=otel-collector-config \
  --reuse-values
```

### Step 3: Verify Collector

```bash
# Check collector logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector

# Port forward to check metrics
kubectl port-forward -n observability svc/opentelemetry-collector 8889:8889

# Access metrics at http://localhost:8889/metrics
```

---

## Application Integration

### How Log-Processor Connects to OpenTelemetry

The application sends telemetry to the OpenTelemetry Collector using the OTLP protocol.

**Connection details:**
- **Endpoint**: `opentelemetry-collector.observability.svc.cluster.local:4317` (gRPC)
- **Protocol**: OTLP (OpenTelemetry Protocol)
- **Data sent**: Traces, metrics, logs

### Update Application Code

**1. Add OpenTelemetry Dependencies**

Update `requirements.txt`:
```txt
opentelemetry-api==1.21.0
opentelemetry-sdk==1.21.0
opentelemetry-instrumentation==0.42b0
opentelemetry-exporter-otlp==1.21.0
opentelemetry-instrumentation-boto3==0.42b0
opentelemetry-instrumentation-logging==0.42b0
```

**2. Initialize OpenTelemetry in Application**

Create `src/telemetry.py`:
```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.boto3 import Boto3Instrumentor
import os

def init_telemetry():
    """Initialize OpenTelemetry with OTLP exporters"""
    
    # Get collector endpoint from environment
    otel_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", 
                              "opentelemetry-collector.observability.svc.cluster.local:4317")
    
    # Define service resource
    resource = Resource.create({
        "service.name": "log-processor",
        "service.version": os.getenv("APP_VERSION", "1.0.0"),
        "deployment.environment": os.getenv("ENVIRONMENT", "dev"),
    })
    
    # Configure tracing
    trace_provider = TracerProvider(resource=resource)
    otlp_trace_exporter = OTLPSpanExporter(endpoint=otel_endpoint, insecure=True)
    trace_provider.add_span_processor(BatchSpanProcessor(otlp_trace_exporter))
    trace.set_tracer_provider(trace_provider)
    
    # Configure metrics
    otlp_metric_exporter = OTLPMetricExporter(endpoint=otel_endpoint, insecure=True)
    metric_reader = PeriodicExportingMetricReader(otlp_metric_exporter, export_interval_millis=60000)
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)
    
    # Auto-instrument boto3 (AWS SDK)
    Boto3Instrumentor().instrument()
    
    return trace.get_tracer(__name__), metrics.get_meter(__name__)
```

**3. Update Main Application**

Update `src/main.py`:
```python
from telemetry import init_telemetry
from opentelemetry import trace

# Initialize telemetry at startup
tracer, meter = init_telemetry()

# Create custom metrics
messages_counter = meter.create_counter(
    "messages.processed",
    description="Number of messages processed",
    unit="1"
)

processing_histogram = meter.create_histogram(
    "processing.duration",
    description="Message processing duration",
    unit="ms"
)

def process_message(message):
    """Process message with tracing"""
    
    # Create span for tracing
    with tracer.start_as_current_span("process_message") as span:
        span.set_attribute("sensor_type", message.get("sensor_type"))
        span.set_attribute("sensor_id", message.get("sensor_id"))
        
        start_time = time.time()
        
        try:
            # Validate message
            with tracer.start_as_current_span("validate_message"):
                validate(message)
            
            # Store in S3
            with tracer.start_as_current_span("store_s3"):
                store_s3(message)
            
            # Store in DynamoDB
            with tracer.start_as_current_span("store_dynamodb"):
                store_dynamodb(message)
            
            # Record metrics
            duration = (time.time() - start_time) * 1000
            messages_counter.add(1, {"sensor_type": message["sensor_type"]})
            processing_histogram.record(duration, {"sensor_type": message["sensor_type"]})
            
            span.set_status(trace.Status(trace.StatusCode.OK))
            
        except Exception as e:
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            span.record_exception(e)
            raise
```

**4. Update Helm Values**

Add OpenTelemetry configuration to `infrastructure/helm/log-processor/values-dev.yaml`:
```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "opentelemetry-collector.observability.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "log-processor"
  - name: ENVIRONMENT
    value: "dev"
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # Sample 10% of traces
```

---

## Distributed Tracing with Jaeger (Optional)

### Install Jaeger

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo update

helm install jaeger jaegertracing/jaeger \
  --namespace observability \
  --set provisionDataStore.cassandra=false \
  --set allInOne.enabled=true \
  --set storage.type=memory \
  --set agent.enabled=false \
  --set collector.enabled=false \
  --set query.enabled=false
```

### Access Jaeger UI

```bash
kubectl port-forward -n observability svc/jaeger-query 16686:16686

# Open http://localhost:16686
```

### View Traces

1. Select **Service**: log-processor
2. Click **Find Traces**
3. View trace details showing:
   - Message processing flow
   - S3 upload duration
   - DynamoDB write duration
   - Error details

---

## Monitoring OpenTelemetry Collector

### Key Metrics

```promql
# Collector metrics received
otelcol_receiver_accepted_spans
otelcol_receiver_accepted_metric_points

# Collector metrics exported
otelcol_exporter_sent_spans
otelcol_exporter_sent_metric_points

# Collector errors
rate(otelcol_exporter_send_failed_spans[5m])
rate(otelcol_exporter_send_failed_metric_points[5m])

# Collector queue size
otelcol_exporter_queue_size
```

### Create Grafana Dashboard

1. Go to **Dashboards** → **Import**
2. Enter ID: `15983` (OpenTelemetry Collector dashboard)
3. Select Prometheus data source
4. Click **Import**

---

## Troubleshooting

### Application Not Sending Telemetry

```bash
# Check application logs
kubectl logs -n log-processing -l app=log-processor | grep -i otel

# Verify collector endpoint is reachable
kubectl exec -n log-processing deployment/log-processor -- \
  nc -zv opentelemetry-collector.observability.svc.cluster.local 4317
```

### Collector Not Receiving Data

```bash
# Check collector logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector

# Check receiver status
kubectl port-forward -n observability svc/opentelemetry-collector 13133:13133
curl http://localhost:13133/
```

### Traces Not Appearing in Jaeger

```bash
# Verify collector is exporting to Jaeger
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector | grep jaeger

# Check Jaeger collector
kubectl logs -n observability -l app.kubernetes.io/name=jaeger
```

### High Memory Usage

```bash
# Check collector memory
kubectl top pod -n observability -l app.kubernetes.io/name=opentelemetry-collector

# Adjust memory limiter in config
# Update memory_limiter.limit_mib value
```

---

## Production Considerations

### Sampling Strategy

**Dev environment**: Sample 10% of traces
```yaml
probabilistic_sampler:
  sampling_percentage: 10
```

**Production**: Sample 1% of traces, always sample errors
```yaml
tail_sampling:
  policies:
    - name: error-traces
      type: status_code
      status_code:
        status_codes: [ERROR]
    - name: slow-traces
      type: latency
      latency:
        threshold_ms: 1000
    - name: random-sample
      type: probabilistic
      probabilistic:
        sampling_percentage: 1
```

### High Availability

Deploy collector as DaemonSet for better performance:

```bash
helm upgrade opentelemetry-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  --set mode=daemonset \
  --set presets.kubernetesAttributes.enabled=true \
  --reuse-values
```

### Resource Limits

For production workloads:

```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 200m
  limits:
    memory: 1Gi
    cpu: 1000m
```

---

## Benefits of OpenTelemetry

**Before OpenTelemetry:**
- Prometheus client for metrics
- Python logging for logs
- No distributed tracing
- Multiple agents/exporters

**After OpenTelemetry:**
- Single SDK for all telemetry
- Distributed tracing across services
- Automatic instrumentation (boto3, requests)
- Centralized configuration
- Vendor-neutral (can switch backends easily)

---

## Next Steps

1. Deploy OpenTelemetry Collector
2. Update application code with OpenTelemetry SDK
3. Deploy updated application
4. Verify telemetry in Grafana/Jaeger
5. Create custom dashboards
6. Configure sampling for production
7. Set up alerting on collector metrics
