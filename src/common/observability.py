"""OpenTelemetry observability configuration.

Sets up:
- Distributed tracing with OTLP exporter
- Metrics collection and export
- Structured logging with trace correlation
"""

import os
from opentelemetry import trace, metrics as otel_metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.resources import Resource
import logging

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","message":"%(message)s"}',
    datefmt='%Y-%m-%dT%H:%M:%S'
)

class ObservabilityManager:
    """Centralized observability configuration"""
    
    def __init__(self):
        self.service_name = os.getenv("SERVICE_NAME", "log-processor")
        self.environment = os.getenv("ENVIRONMENT", "development")
        self.otlp_endpoint = os.getenv("OTLP_ENDPOINT", "localhost:4317")
        
        self._setup_tracing()
        self._setup_metrics()
        
    def _setup_tracing(self):
        """Configure OpenTelemetry tracing"""
        resource = Resource.create({
            "service.name": self.service_name,
            "service.version": os.getenv("VERSION", "1.0.0"),
            "deployment.environment": self.environment
        })
        
        provider = TracerProvider(resource=resource)
        processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=self.otlp_endpoint, insecure=True))
        provider.add_span_processor(processor)
        trace.set_tracer_provider(provider)
        
    def _setup_metrics(self):
        """Configure OpenTelemetry metrics"""
        resource = Resource.create({
            "service.name": self.service_name,
            "deployment.environment": self.environment
        })
        
        reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(endpoint=self.otlp_endpoint, insecure=True)
        )
        provider = MeterProvider(resource=resource, metric_readers=[reader])
        otel_metrics.set_meter_provider(provider)

class MetricsCollector:
    """Simplified metrics collection"""
    
    def __init__(self):
        self.meter = otel_metrics.get_meter(__name__)
        self.counters = {}
        self.histograms = {}
        
    def increment_counter(self, name: str, labels: dict = None):
        """Increment a counter metric"""
        if name not in self.counters:
            self.counters[name] = self.meter.create_counter(name)
        self.counters[name].add(1, labels or {})
        
    def record_histogram(self, name: str, value: float, labels: dict = None):
        """Record histogram value"""
        if name not in self.histograms:
            self.histograms[name] = self.meter.create_histogram(name)
        self.histograms[name].record(value, labels or {})

# Global instances
observability = ObservabilityManager()
tracer = trace.get_tracer(__name__)
metrics = MetricsCollector()
