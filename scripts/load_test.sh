#!/bin/bash
# Load testing script - sends multiple messages concurrently

QUEUE_URL=${QUEUE_URL:-""}
NUM_MESSAGES=${NUM_MESSAGES:-1000}
CONCURRENCY=${CONCURRENCY:-10}

if [ -z "$QUEUE_URL" ]; then
    echo "Error: QUEUE_URL environment variable not set"
    exit 1
fi

echo "Starting load test..."
echo "Queue: $QUEUE_URL"
echo "Messages: $NUM_MESSAGES"
echo "Concurrency: $CONCURRENCY"

send_message() {
    local i=$1
    local sensor_types=("temperature" "humidity" "pressure")
    local sensor_type=${sensor_types[$((i % 3))]}
    
    aws sqs send-message \
        --queue-url "$QUEUE_URL" \
        --message-body "{
            \"sensor_type\": \"$sensor_type\",
            \"sensor_id\": \"sensor-$(printf %04d $i)\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
            \"value\": $((RANDOM % 100)),
            \"unit\": \"celsius\",
            \"location\": \"zone-$((i % 10))\"
        }" > /dev/null 2>&1
}

export -f send_message
export QUEUE_URL

seq 1 $NUM_MESSAGES | xargs -P $CONCURRENCY -I {} bash -c 'send_message {}'

echo "Load test completed!"
echo "Monitor: kubectl top pods -n log-processing"
