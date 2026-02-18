import pytest
from src.processors.pressure import PressureProcessor

class TestPressureProcessor:
    
    def setup_method(self):
        self.processor = PressureProcessor()
        
    def test_validate_valid_hpa(self):
        data = {
            'sensor_id': 'press-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 1013.25,
            'unit': 'hPa'
        }
        assert self.processor.validate(data) is True
        
    def test_validate_valid_psi(self):
        data = {
            'sensor_id': 'press-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 14.7,
            'unit': 'psi'
        }
        assert self.processor.validate(data) is True
        
    def test_transform_psi_to_hpa(self):
        data = {
            'sensor_id': 'press-001',
            'timestamp': '2024-01-01T00:00:00Z',
            'value': 14.7,
            'unit': 'psi'
        }
        result = self.processor.transform(data)
        assert result['unit'] == 'hPa'
        assert result['original_unit'] == 'psi'
        assert result['value'] > 1000  # Approximate conversion check
