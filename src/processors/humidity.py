from typing import Dict, Any
from common.base_processor import BaseProcessor

class HumidityProcessor(BaseProcessor):
    """Processor for humidity sensor data"""
    
    def __init__(self):
        super().__init__("humidity")
        
    def validate(self, data: Dict[str, Any]) -> bool:
        """Validate humidity data"""
        required_fields = ['sensor_id', 'timestamp', 'value']
        if not all(field in data for field in required_fields):
            return False
        
        # Validate humidity range (0-100%)
        return 0 <= float(data['value']) <= 100
        
    def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Transform humidity data to standard format"""
        return {
            'sensor_id': data['sensor_id'],
            'timestamp': data['timestamp'],
            'value': round(float(data['value']), 2),
            'unit': 'percent',
            'location': data.get('location', 'unknown')
        }
