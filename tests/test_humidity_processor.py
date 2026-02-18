import pytest
from src.processors.humidity import HumidityProcessor

class TestHumidityProcessor:
    
    def setup_method(self):
        self.processor = HumidityProcessor()
        
    def test_validate_valid_data(self):
        data = {
            'sensor_id': 'hum-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 65.5
        }
        assert self.processor.validate(data) is True
        
    def test_validate_out_of_range(self):
        data = {
            'sensor_id': 'hum-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 150.0
        }
        assert self.processor.validate(data) is False
        
    def test_transform(self):
        data = {
            'sensor_id': 'hum-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 65.5,
            'location': 'room-1'
        }
        result = self.processor.transform(data)
        assert result['value'] == 65.5
        assert result['unit'] == 'percent'
        assert result['location'] == 'room-1'
