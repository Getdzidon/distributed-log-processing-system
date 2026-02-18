from typing import Dict, Any
from common.base_processor import BaseProcessor

class PressureProcessor(BaseProcessor):
    """Processor for pressure sensor data"""
    
    def __init__(self):
        super().__init__("pressure")
        
    def validate(self, data: Dict[str, Any]) -> bool:
        """Validate pressure data"""
        required_fields = ['sensor_id', 'timestamp', 'value', 'unit']
        if not all(field in data for field in required_fields):
            return False
        
        # Validate pressure range (800-1200 hPa)
        if data['unit'] == 'hPa':
            return 800 <= float(data['value']) <= 1200
        elif data['unit'] == 'psi':
            return 11.6 <= float(data['value']) <= 17.4
        
        return False
        
    def transform(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Transform pressure data to standard format"""
        value = float(data['value'])
        
        # Convert to hPa if needed
        if data['unit'] == 'psi':
            value = value * 68.9476
            
        return {
            'sensor_id': data['sensor_id'],
            'timestamp': data['timestamp'],
            'value': round(value, 2),
            'unit': 'hPa',
            'original_unit': data['unit'],
            'location': data.get('location', 'unknown')
        }
