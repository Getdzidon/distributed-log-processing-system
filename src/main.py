"""Main application entry point.

SQS-based log processor that:
1. Polls SQS queue for sensor messages
2. Routes to appropriate processor based on sensor_type
3. Stores raw logs in S3
4. Stores processed metrics in DynamoDB
5. Emits observability data (metrics, traces, logs)
"""

import boto3
import json
import os
import sys
import logging
from typing import Dict
from processors.temperature import TemperatureProcessor
from processors.humidity import HumidityProcessor
from processors.pressure import PressureProcessor
from common.storage import storage
from common.observability import tracer, metrics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Processor registry
PROCESSORS: Dict[str, object] = {
    'temperature': TemperatureProcessor(),
    'humidity': HumidityProcessor(),
    'pressure': PressureProcessor()
}

class LogProcessorService:
    """Main service for processing sensor logs"""
    
    def __init__(self):
        self.sqs = boto3.client('sqs')
        self.queue_url = os.getenv('QUEUE_URL')
        self.max_messages = int(os.getenv('MAX_MESSAGES', '10'))
        self.wait_time = int(os.getenv('WAIT_TIME_SECONDS', '20'))
        
        if not self.queue_url:
            raise ValueError("QUEUE_URL environment variable is required")
            
    def process_message(self, message: dict) -> None:
        """Process a single SQS message"""
        with tracer.start_as_current_span("process_message") as span:
            try:
                body = json.loads(message['Body'])
                sensor_type = body.get('sensor_type')
                
                span.set_attribute("message.id", message['MessageId'])
                span.set_attribute("sensor.type", sensor_type)
                
                if sensor_type not in PROCESSORS:
                    logger.warning(f"Unknown sensor type: {sensor_type}")
                    metrics.increment_counter("unknown_sensor_type", {"sensor_type": sensor_type})
                    return
                
                # Store raw log
                storage.store_raw_log(sensor_type, body)
                
                # Process with appropriate processor
                processor = PROCESSORS[sensor_type]
                processed_data = processor.process(body)
                
                # Store processed metric
                storage.store_processed_metric(processed_data)
                
                # Delete message from queue
                self.sqs.delete_message(
                    QueueUrl=self.queue_url,
                    ReceiptHandle=message['ReceiptHandle']
                )
                
                logger.info(f"Successfully processed message {message['MessageId']}")
                
            except Exception as e:
                logger.error(f"Error processing message: {e}", exc_info=True)
                metrics.increment_counter("message_processing_errors")
                raise
                
    def run(self):
        """Main processing loop"""
        logger.info(f"Starting log processor service, polling queue: {self.queue_url}")
        
        while True:
            try:
                response = self.sqs.receive_message(
                    QueueUrl=self.queue_url,
                    MaxNumberOfMessages=self.max_messages,
                    WaitTimeSeconds=self.wait_time,
                    AttributeNames=['All']
                )
                
                messages = response.get('Messages', [])
                
                if messages:
                    logger.info(f"Received {len(messages)} messages")
                    metrics.record_histogram("batch_size", len(messages))
                    
                    for message in messages:
                        self.process_message(message)
                else:
                    logger.debug("No messages received")
                    
            except KeyboardInterrupt:
                logger.info("Shutting down gracefully...")
                sys.exit(0)
            except Exception as e:
                logger.error(f"Error in main loop: {e}", exc_info=True)
                metrics.increment_counter("main_loop_errors")

if __name__ == "__main__":
    service = LogProcessorService()
    service.run()
