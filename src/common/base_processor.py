"""Base processor class for all sensor types.

Provides common functionality:
- Validation and transformation hooks
- Built-in observability (metrics, tracing, logging)
- Error handling and reporting
"""

from abc import ABC, abstractmethod
from typing import Dict, Any
import logging
from datetime import datetime
from .observability import tracer, metrics

logger = logging.getLogger(__name__)

class BaseProcessor(ABC):
    """Base class for all sensor processors with built-in observability"""
    
    def __init__(self, sensor_type: str):
        self.sensor_type = sensor_type
        self.metrics = metrics
        
    @abstractmethod
    def validate(self, data: Dict[str, Any]) -> bool:
        """Validate sensor data format"""
        pass
    
    @abstractmethod
    def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Transform raw sensor data"""
        pass
    
    def process(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Process sensor data with observability"""
        with tracer.start_as_current_span(f"process_{self.sensor_type}") as span:
            span.set_attribute("sensor.type", self.sensor_type)
            span.set_attribute("sensor.id", data.get("sensor_id", "unknown"))
            
            try:
                if not self.validate(data):
                    self.metrics.increment_counter("validation_errors", {"sensor_type": self.sensor_type})
                    raise ValueError(f"Invalid data format for {self.sensor_type}")
                
                transformed = self.transform(data)
                transformed["processed_at"] = datetime.utcnow().isoformat()
                transformed["sensor_type"] = self.sensor_type
                
                self.metrics.increment_counter("messages_processed", {"sensor_type": self.sensor_type})
                self.metrics.record_histogram("processing_duration", 
                                             span.end_time - span.start_time if span.end_time else 0,
                                             {"sensor_type": self.sensor_type})
                
                logger.info(f"Processed {self.sensor_type} data", extra={
                    "sensor_id": data.get("sensor_id"),
                    "sensor_type": self.sensor_type
                })
                
                return transformed
                
            except Exception as e:
                self.metrics.increment_counter("processing_errors", {"sensor_type": self.sensor_type})
                span.set_attribute("error", True)
                span.set_attribute("error.message", str(e))
                logger.error(f"Error processing {self.sensor_type}: {e}", exc_info=True)
                raise
