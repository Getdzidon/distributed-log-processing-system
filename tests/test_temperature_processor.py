import pytest
from unittest.mock import Mock, patch
from src.processors.temperature import TemperatureProcessor

class TestTemperatureProcessor:
    
    def setup_method(self):
        self.processor = TemperatureProcessor()
        
    def test_validate_valid_celsius(self):
        data = {
            'sensor_id': 'temp-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 25.5,
            'unit': 'celsius'
        }
        assert self.processor.validate(data) is True
        
    def test_validate_valid_fahrenheit(self):
        data = {
            'sensor_id': 'temp-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 77.0,
            'unit': 'fahrenheit'
        }
        assert self.processor.validate(data) is True
        
    def test_validate_out_of_range(self):
        data = {
            'sensor_id': 'temp-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 150.0,
            'unit': 'celsius'
        }
        assert self.processor.validate(data) is False
        
    def test_validate_missing_fields(self):
        data = {
            'sensor_id': 'temp-001',
            'value': 25.5
        }
        assert self.processor.validate(data) is False
        
    def test_transform_celsius(self):
        data = {
            'sensor_id': 'temp-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 25.5,
            'unit': 'celsius',
            'location': 'room-1'
        }
        result = self.processor.transform(data)
        assert result['value'] == 25.5
        assert result['unit'] == 'celsius'
        assert result['location'] == 'room-1'
        
    def test_transform_fahrenheit_to_celsius(self):
        data = {
            'sensor_id': 'temp-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 32.0,
            'unit': 'fahrenheit'
        }
        result = self.processor.transform(data)
        assert result['value'] == 0.0
        assert result['unit'] == 'celsius'
        assert result['original_unit'] == 'fahrenheit'
