#!/bin/bash
# Custom metrics collection script for Proxy LAMP Stack

set -euo pipefail

# Configuration
NAMESPACE="ProxyLAMP/Application"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")

# Function to send metric to CloudWatch
send_metric() {
    local metric_name=$1
    local value=$2
    local unit=$3
    
    aws cloudwatch put-metric-data \
        --region "$REGION" \
        --namespace "$NAMESPACE" \
        --metric-data MetricName="$metric_name",Value="$value",Unit="$unit",Dimensions="InstanceId=$INSTANCE_ID" \
        2>/dev/null || echo "Failed to send metric $metric_name"
}

# Apache connections
APACHE_CONNECTIONS=$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
send_metric "ApacheConnections" "$APACHE_CONNECTIONS" "Count"

# Disk usage
DISK_USAGE=$(df /var/www | tail -1 | awk '{print $5}' | sed 's/%//')
send_metric "DiskUsagePercent" "$DISK_USAGE" "Percent"

# Memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
send_metric "MemoryUsagePercent" "$MEMORY_USAGE" "Percent"

# Apache status
if systemctl is-active --quiet apache2; then
    APACHE_STATUS=1
else
    APACHE_STATUS=0
fi
send_metric "ApacheStatus" "$APACHE_STATUS" "Count"

echo "Custom metrics sent successfully"
