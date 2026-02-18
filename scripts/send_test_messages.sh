#!/bin/bash
# Script to send test messages to SQS queue

set -e

QUEUE_URL=${QUEUE_URL:-""}

if [ -z "$QUEUE_URL" ]; then
    echo "Error: QUEUE_URL environment variable not set"
    echo "Usage: QUEUE_URL=<your-queue-url> ./send_test_messages.sh"
    exit 1
fi

echo "Sending test messages to: $QUEUE_URL"

# Temperature sensor message
echo "Sending temperature message..."
aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body '{
        "sensor_type": "temperature",
        "sensor_id": "temp-001",
        "timestamp": "2024-01-15T10:30:00Z",
        "value": 22.5,
        "unit": "celsius",
        "location": "server-room-1"
    }'

# Humidity sensor message
echo "Sending humidity message..."
aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body '{
        "sensor_type": "humidity",
        "sensor_id": "hum-001",
        "timestamp": "2024-01-15T10:30:00Z",
        "value": 65.0,
        "location": "server-room-1"
    }'

# Pressure sensor message
echo "Sending pressure message..."
aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body '{
        "sensor_type": "pressure",
        "sensor_id": "press-001",
        "timestamp": "2024-01-15T10:30:00Z",
        "value": 1013.25,
        "unit": "hPa",
        "location": "server-room-1"
    }'

echo "Test messages sent successfully!"
echo "Check pod logs: kubectl logs -n log-processing -l app.kubernetes.io/name=log-processor -f"
