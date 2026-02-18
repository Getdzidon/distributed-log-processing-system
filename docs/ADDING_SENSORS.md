# Adding New Sensor Types

This guide explains how to extend the log processing system to support new sensor types.

## Overview

The system uses a modular processor architecture where each sensor type has its own processor class. Adding a new sensor type requires:

1. Creating a new processor class
2. Registering the processor
3. Deploying the updated application

## Step-by-Step Guide

### 1. Create Processor Class

Create a new file in `src/processors/` for your sensor type:

```python
# src/processors/vibration.py

from typing import Dict, Any
from common.base_processor import BaseProcessor

class VibrationProcessor(BaseProcessor):
    """Processor for vibration sensor data"""
    
    def __init__(self):
        super().__init__("vibration")
        
    def validate(self, data: Dict[str, Any]) -> bool:
        """Validate vibration sensor data"""
        required_fields = ['sensor_id', 'timestamp', 'value', 'unit']
        
        # Check required fields
        if not all(field in data for field in required_fields):
            return False
        
        # Validate value range (0-100 Hz for example)
        if data['unit'] == 'hz':
            return 0 <= float(data['value']) <= 100
        
        return False
        
    def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Transform vibration data to standard format"""
        return {
            'sensor_id': data['sensor_id'],
            'timestamp': data['timestamp'],
            'value': round(float(data['value']), 2),
            'unit': 'hz',
            'location': data.get('location', 'unknown'),
            'axis': data.get('axis', 'xyz')  # Custom field for vibration
        }
```

### 2. Register Processor

Update `src/main.py` to register the new processor:

```python
# Add import at the top
from processors.vibration import VibrationProcessor

# Add to PROCESSORS dictionary
PROCESSORS: Dict[str, object] = {
    'temperature': TemperatureProcessor(),
    'humidity': HumidityProcessor(),
    'pressure': PressureProcessor(),
    'vibration': VibrationProcessor(),  # New processor
}
```

### 3. Create Unit Tests

Create test file `tests/test_vibration_processor.py`:

```python
import pytest
from src.processors.vibration import VibrationProcessor

class TestVibrationProcessor:
    
    def setup_method(self):
        self.processor = VibrationProcessor()
        
    def test_validate_valid_data(self):
        data = {
            'sensor_id': 'vib-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 45.5,
            'unit': 'hz'
        }
        assert self.processor.validate(data) is True
        
    def test_validate_out_of_range(self):
        data = {
            'sensor_id': 'vib-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 150.0,
            'unit': 'hz'
        }
        assert self.processor.validate(data) is False
        
    def test_transform(self):
        data = {
            'sensor_id': 'vib-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 45.5,
            'unit': 'hz',
            'location': 'motor-1',
            'axis': 'x'
        }
        result = self.processor.transform(data)
        assert result['value'] == 45.5
        assert result['unit'] == 'hz'
        assert result['axis'] == 'x'
```

### 4. Run Tests Locally

```bash
# Run all tests
pytest tests/ -v

# Run specific test
pytest tests/test_vibration_processor.py -v

# Check coverage
pytest tests/ --cov=src --cov-report=term
```

### 5. Deploy Changes

#### Option A: Automatic Deployment (with CI/CD)

```bash
# Commit changes
git add src/processors/vibration.py
git add src/main.py
git add tests/test_vibration_processor.py

# Or run the below to add all changes
git add .

git commit -m "Added vibration sensor processor"

# Push to dev (deploys to dev/staging)
git push origin dev

# After testing in dev/staging, merge to main
git checkout main
git merge dev
git push origin main  # Requires approval for production
```

#### Option B: Manual Deployment

```bash
# Build new image
docker build -t log-processor:v1.1.0 .

# Tag and push to ECR
ECR_REPO=<your-ecr-repo>
docker tag log-processor:v1.1.0 $ECR_REPO:v1.1.0
docker push $ECR_REPO:v1.1.0

# Update Helm deployment
helm upgrade log-processor \
  infrastructure/helm/log-processor \
  --namespace log-processing \
  --set image.tag=v1.1.0 \
  --wait
```

### 6. Verify Deployment

```bash
# Check pod logs
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor --tail=50

# Send test message
aws sqs send-message \
  --queue-url $QUEUE_URL \
  --message-body '{
    "sensor_type": "vibration",
    "sensor_id": "vib-001",
    "timestamp": "2024-01-01T00:00:00Z",
    "value": 45.5,
    "unit": "hz",
    "location": "motor-1",
    "axis": "x"
  }'

# Verify processing
kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f
```

## Advanced Customization

### Custom Validation Logic

```python
def validate(self, data: Dict[str, Any]) -> bool:
    """Complex validation with multiple checks"""
    # Basic field validation
    if not all(field in data for field in self.required_fields):
        return False
    
    # Range validation
    if not self.validate_range(data['value'], data['unit']):
        return False
    
    # Custom business logic
    if data.get('calibration_status') != 'valid':
        return False
    
    return True
```

### Unit Conversion

```python
def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
    """Transform with unit conversion"""
    value = float(data['value'])
    
    # Convert different units to standard
    if data['unit'] == 'rpm':
        value = value / 60  # Convert RPM to Hz
    elif data['unit'] == 'rad/s':
        value = value / (2 * 3.14159)  # Convert rad/s to Hz
    
    return {
        'sensor_id': data['sensor_id'],
        'timestamp': data['timestamp'],
        'value': round(value, 2),
        'unit': 'hz',
        'original_unit': data['unit']
    }
```

### Enrichment with External Data

```python
def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
    """Transform with data enrichment"""
    # Get additional context from external service
    device_info = self.get_device_info(data['sensor_id'])
    
    return {
        'sensor_id': data['sensor_id'],
        'timestamp': data['timestamp'],
        'value': round(float(data['value']), 2),
        'unit': data['unit'],
        'device_type': device_info.get('type'),
        'location': device_info.get('location'),
        'zone': device_info.get('zone')
    }
```

### Async Processing

```python
import asyncio
from typing import Dict, Any

class AsyncVibrationProcessor(BaseProcessor):
    """Async processor for high-throughput scenarios"""
    
    async def process_async(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Async processing with concurrent operations"""
        # Validate
        if not self.validate(data):
            raise ValueError("Invalid data")
        
        # Transform and enrich concurrently
        transformed, enriched = await asyncio.gather(
            self.transform_async(data),
            self.enrich_async(data)
        )
        
        return {**transformed, **enriched}
```

## Best Practices

### 1. Validation
- Always validate required fields
- Check data types and ranges
- Validate business rules
- Return clear error messages

### 2. Transformation
- Keep transformations idempotent
- Preserve original values when converting units
- Add metadata (processed_at, sensor_type)
- Round floating-point values appropriately

### 3. Error Handling
- Use try-except blocks for external calls
- Log errors with context
- Increment error metrics
- Don't lose messages on transient errors

### 4. Testing
- Test valid data
- Test invalid data (out of range, missing fields)
- Test edge cases (boundary values)
- Test unit conversions
- Aim for >80% code coverage

### 5. Observability
- Add custom metrics for new sensor types
- Include sensor_type in all log messages
- Add trace attributes for debugging
- Create Grafana dashboard for new sensor

## Monitoring New Sensors

### Add Custom Metrics

```python
# In your processor
self.metrics.increment_counter(
    "vibration_high_frequency_detected",
    {"sensor_id": data['sensor_id']}
)
```

### Create Grafana Dashboard

1. Navigate to Grafana
2. Create new dashboard
3. Add panels:
   - Message processing rate (by sensor_type)
   - Error rate (by sensor_type)
   - Value distribution histogram
   - Latency percentiles

### Set Up Alerts

```yaml
# AlertManager configuration
groups:
  - name: vibration_alerts
    rules:
      - alert: HighVibrationDetected
        expr: vibration_value > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High vibration detected on {{ $labels.sensor_id }}"
```

## Rollback

If issues occur after deploying a new sensor type:

```bash
# Rollback Helm deployment
helm rollback log-processor -n log-processing

# Or deploy previous version
helm upgrade log-processor \
  infrastructure/helm/log-processor \
  --namespace log-processing \
  --set image.tag=v1.0.0 \
  --wait
```

## Example: Complete Implementation

See `examples/motion_sensor.py` for a complete example of adding a motion sensor processor with:
- Complex validation
- Data enrichment
- Custom metrics
- Unit tests
- Integration tests

## Support

For questions or issues:
- Review existing processors in `src/processors/`
- Check test examples in `tests/`
- Consult architecture documentation in `docs/ARCHITECTURE.md`
