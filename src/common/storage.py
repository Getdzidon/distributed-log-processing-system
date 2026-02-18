"""Storage manager for AWS S3 and DynamoDB.

Handles:
- Raw log storage in S3 (partitioned by date)
- Processed metrics in DynamoDB (with TTL)
- Error handling and logging
"""

import boto3
import json
import os
from typing import Dict, Any
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

class StorageManager:
    """Handles storage operations for S3 and DynamoDB"""
    
    def __init__(self):
        self.s3 = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')
        self.raw_bucket = os.getenv('RAW_LOGS_BUCKET')
        self.processed_table = os.getenv('PROCESSED_METRICS_TABLE')
        self.table = self.dynamodb.Table(self.processed_table) if self.processed_table else None
        
    def store_raw_log(self, sensor_type: str, data: Dict[str, Any]) -> str:
        """Store raw log to S3"""
        timestamp = datetime.utcnow()
        key = f"raw/{sensor_type}/{timestamp.year}/{timestamp.month:02d}/{timestamp.day:02d}/{timestamp.timestamp()}.json"
        
        try:
            self.s3.put_object(
                Bucket=self.raw_bucket,
                Key=key,
                Body=json.dumps(data),
                ContentType='application/json',
                ServerSideEncryption='AES256'
            )
            logger.info(f"Stored raw log to S3: {key}")
            return key
        except Exception as e:
            logger.error(f"Failed to store raw log: {e}")
            raise
            
    def store_processed_metric(self, data: Dict[str, Any]) -> None:
        """Store processed metric to DynamoDB"""
        try:
            item = {
                'sensor_id': data['sensor_id'],
                'timestamp': data['timestamp'],
                'sensor_type': data['sensor_type'],
                'value': str(data['value']),
                'unit': data.get('unit', ''),
                'processed_at': data['processed_at'],
                'ttl': int(datetime.utcnow().timestamp()) + (90 * 24 * 3600)  # 90 days TTL
            }
            
            self.table.put_item(Item=item)
            logger.info(f"Stored processed metric for sensor {data['sensor_id']}")
        except Exception as e:
            logger.error(f"Failed to store processed metric: {e}")
            raise

storage = StorageManager()
