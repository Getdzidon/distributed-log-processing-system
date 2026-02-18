"""Temperature sensor processor.

Handles temperature data from sensors:
- Validates temperature range (-100 to 100°C)
- Converts Fahrenheit to Celsius
- Normalizes to standard format
"""

from typing import Dict, Any
from common.base_processor import BaseProcessor

class TemperatureProcessor(BaseProcessor):
    """Processor for temperature sensor data"""
    
    def __init__(self):
        super().__init__("temperature")
        
    def validate(self, data: Dict[str, Any]) -> bool:
        """Validate temperature data"""
        required_fields = ['sensor_id', 'timestamp', 'value', 'unit']
        if not all(field in data for field in required_fields):
            return False
        
        # Validate temperature range (-100 to 100 Celsius)
        if data['unit'] == 'celsius':
            return -100 <= float(data['value']) <= 100
        elif data['unit'] == 'fahrenheit':
            return -148 <= float(data['value']) <= 212
        
        return False
        
    def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Transform temperature data to standard format"""
        value = float(data['value'])
        
        # Convert to Celsius if needed
        if data['unit'] == 'fahrenheit':
            value = (value - 32) * 5/9
            
        return {
            'sensor_id': data['sensor_id'],
            'timestamp': data['timestamp'],
            'value': round(value, 2),
            'unit': 'celsius',
            'original_unit': data['unit'],
            'location': data.get('location', 'unknown')
        }
