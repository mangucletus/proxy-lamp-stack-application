#!/bin/bash
# Custom metrics collection script for Proxy LAMP Stack
# This script collects application-specific metrics and sends them to CloudWatch

# Set error handling
set -euo pipefail

# Configuration
NAMESPACE="ProxyLAMP/Application"
LOG_FILE="/var/log/proxy-lamp-metrics.log"
HEALTH_ENDPOINT="http://localhost/health.php"

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "unknown")

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to send metric to CloudWatch
send_metric() {
    local metric_name=$1
    local value=$2
    local unit=$3
    local dimensions=$4
    
    aws cloudwatch put-metric-data \
        --region "$REGION" \
        --namespace "$NAMESPACE" \
        --metric-data MetricName="$metric_name",Value="$value",Unit="$unit",Dimensions="$dimensions" \
        2>/dev/null || log_message "ERROR: Failed to send metric $metric_name"
}

# Function to get Apache metrics
collect_apache_metrics() {
    log_message "Collecting Apache metrics..."
    
    # Apache connections
    APACHE_CONNECTIONS=$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
    send_metric "ApacheConnections" "$APACHE_CONNECTIONS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Apache processes
    APACHE_PROCESSES=$(pgrep -c apache2 || echo "0")
    send_metric "ApacheProcesses" "$APACHE_PROCESSES" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Check if Apache is running
    if systemctl is-active --quiet apache2; then
        APACHE_STATUS=1
    else
        APACHE_STATUS=0
    fi
    send_metric "ApacheStatus" "$APACHE_STATUS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Get Apache server-status if available
    if curl -s http://localhost/server-status?auto >/dev/null 2>&1; then
        # Parse server-status output
        STATUS_OUTPUT=$(curl -s http://localhost/server-status?auto)
        
        TOTAL_ACCESSES=$(echo "$STATUS_OUTPUT" | grep "Total Accesses:" | awk '{print $3}' || echo "0")
        TOTAL_TRAFFIC=$(echo "$STATUS_OUTPUT" | grep "Total kBytes:" | awk '{print $3}' || echo "0")
        CPU_LOAD=$(echo "$STATUS_OUTPUT" | grep "CPULoad:" | awk '{print $2}' || echo "0")
        UPTIME=$(echo "$STATUS_OUTPUT" | grep "Uptime:" | awk '{print $2}' || echo "0")
        REQUESTS_SEC=$(echo "$STATUS_OUTPUT" | grep "ReqPerSec:" | awk '{print $2}' || echo "0")
        BYTES_SEC=$(echo "$STATUS_OUTPUT" | grep "BytesPerSec:" | awk '{print $2}' || echo "0")
        BYTES_REQ=$(echo "$STATUS_OUTPUT" | grep "BytesPerReq:" | awk '{print $2}' || echo "0")
        BUSY_WORKERS=$(echo "$STATUS_OUTPUT" | grep "BusyWorkers:" | awk '{print $2}' || echo "0")
        IDLE_WORKERS=$(echo "$STATUS_OUTPUT" | grep "IdleWorkers:" | awk '{print $2}' || echo "0")
        
        send_metric "ApacheTotalAccesses" "$TOTAL_ACCESSES" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
        send_metric "ApacheRequestsPerSec" "$REQUESTS_SEC" "Count/Second" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
        send_metric "ApacheBytesPerSec" "$BYTES_SEC" "Bytes/Second" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
        send_metric "ApacheBusyWorkers" "$BUSY_WORKERS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
        send_metric "ApacheIdleWorkers" "$IDLE_WORKERS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    fi
}

# Function to get PHP metrics
collect_php_metrics() {
    log_message "Collecting PHP metrics..."
    
    # PHP-FPM processes (if using PHP-FPM)
    PHP_FPM_PROCESSES=$(pgrep -c php-fpm || echo "0")
    send_metric "PHPFPMProcesses" "$PHP_FPM_PROCESSES" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # PHP error count from error log (last 5 minutes)
    PHP_ERRORS=$(grep -c "$(date -d '5 minutes ago' '+%d-%b-%Y %H:%M')" /var/log/apache2/error.log 2>/dev/null || echo "0")
    send_metric "PHPErrors" "$PHP_ERRORS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
}

# Function to get system metrics
collect_system_metrics() {
    log_message "Collecting system metrics..."
    
    # Disk usage for /var/www
    DISK_USAGE=$(df /var/www | tail -1 | awk '{print $5}' | sed 's/%//')
    send_metric "DiskUsagePercent" "$DISK_USAGE" "Percent" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ,MountPoint=/var/www"
    
    # Memory usage
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
    send_metric "MemoryUsagePercent" "$MEMORY_USAGE" "Percent" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Load average
    LOAD_1MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    LOAD_5MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs)
    LOAD_15MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | xargs)
    
    send_metric "LoadAverage1Min" "$LOAD_1MIN" "None" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    send_metric "LoadAverage5Min" "$LOAD_5MIN" "None" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    send_metric "LoadAverage15Min" "$LOAD_15MIN" "None" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Network connections
    TCP_CONNECTIONS=$(ss -t | wc -l)
    send_metric "TCPConnections" "$TCP_CONNECTIONS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Process count
    PROCESS_COUNT=$(ps aux | wc -l)
    send_metric "ProcessCount" "$PROCESS_COUNT" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
}

# Function to get application health metrics
collect_health_metrics() {
    log_message "Collecting application health metrics..."
    
    # Health check response time and status
    HEALTH_START=$(date +%s.%N)
    HEALTH_RESPONSE=$(curl -s -w "%{http_code}" "$HEALTH_ENDPOINT" -o /tmp/health_response.json 2>/dev/null || echo "000")
    HEALTH_END=$(date +%s.%N)
    
    HEALTH_RESPONSE_TIME=$(echo "$HEALTH_END - $HEALTH_START" | bc | awk '{printf "%.0f", $1 * 1000}')
    
    if [[ "$HEALTH_RESPONSE" == "200" ]]; then
        HEALTH_STATUS=1
        
        # Parse health check response for detailed metrics
        if [[ -f /tmp/health_response.json ]]; then
            # Database response time
            DB_RESPONSE_TIME=$(jq -r '.checks.database.response_time_ms // 0' /tmp/health_response.json 2>/dev/null || echo "0")
            send_metric "DatabaseResponseTime" "$DB_RESPONSE_TIME" "Milliseconds" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
            
            # Disk usage from health check
            DISK_USAGE_HEALTH=$(jq -r '.checks.disk.usage_percent // 0' /tmp/health_response.json 2>/dev/null || echo "0")
            send_metric "DiskUsagePercentHealth" "$DISK_USAGE_HEALTH" "Percent" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
            
            # Task count
            TASK_COUNT=$(jq -r '.checks.application.total_tasks // 0' /tmp/health_response.json 2>/dev/null || echo "0")
            send_metric "TaskCount" "$TASK_COUNT" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
        fi
    else
        HEALTH_STATUS=0
    fi
    
    send_metric "HealthCheckStatus" "$HEALTH_STATUS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    send_metric "HealthCheckResponseTime" "$HEALTH_RESPONSE_TIME" "Milliseconds" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Clean up temp file
    rm -f /tmp/health_response.json
}

# Function to get database metrics
collect_database_metrics() {
    log_message "Collecting database metrics..."
    
    # Test database connection
    DB_START=$(date +%s.%N)
    if curl -s "$HEALTH_ENDPOINT" | jq -e '.checks.database.status == "healthy"' >/dev/null 2>&1; then
        DB_STATUS=1
        DB_END=$(date +%s.%N)
        DB_CONNECTION_TIME=$(echo "$DB_END - $DB_START" | bc | awk '{printf "%.0f", $1 * 1000}')
    else
        DB_STATUS=0
        DB_CONNECTION_TIME=0
    fi
    
    send_metric "DatabaseConnectionStatus" "$DB_STATUS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    send_metric "DatabaseConnectionTime" "$DB_CONNECTION_TIME" "Milliseconds" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
}

# Function to get log-based metrics
collect_log_metrics() {
    log_message "Collecting log-based metrics..."
    
    # Count errors in Apache error log (last 5 minutes)
    ERROR_COUNT=$(grep -c "$(date -d '5 minutes ago' '+\[.*\] \[error\]')" /var/log/apache2/error.log 2>/dev/null || echo "0")
    send_metric "ApacheErrorCount" "$ERROR_COUNT" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Count 4xx and 5xx responses in access log (last 5 minutes)
    CURRENT_TIME=$(date '+%d/%b/%Y:%H:%M')
    PREV_TIME=$(date -d '5 minutes ago' '+%d/%b/%Y:%H:%M')
    
    HTTP_4XX=$(awk -v start="$PREV_TIME" -v end="$CURRENT_TIME" '$4 >= "["start && $4 <= "["end && $9 ~ /^4/ {count++} END {print count+0}' /var/log/apache2/access.log 2>/dev/null || echo "0")
    HTTP_5XX=$(awk -v start="$PREV_TIME" -v end="$CURRENT_TIME" '$4 >= "["start && $4 <= "["end && $9 ~ /^5/ {count++} END {print count+0}' /var/log/apache2/access.log 2>/dev/null || echo "0")
    
    send_metric "HTTP4XXCount" "$HTTP_4XX" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    send_metric "HTTP5XXCount" "$HTTP_5XX" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Request count (last 5 minutes)
    REQUEST_COUNT=$(awk -v start="$PREV_TIME" -v end="$CURRENT_TIME" '$4 >= "["start && $4 <= "["end {count++} END {print count+0}' /var/log/apache2/access.log 2>/dev/null || echo "0")
    send_metric "RequestCount" "$REQUEST_COUNT" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
}

# Function to collect custom application metrics
collect_application_metrics() {
    log_message "Collecting custom application metrics..."
    
    # Check if the main application files exist
    if [[ -f "/var/www/html/index.php" ]]; then
        APP_FILES_STATUS=1
    else
        APP_FILES_STATUS=0
    fi
    send_metric "ApplicationFilesStatus" "$APP_FILES_STATUS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
    
    # Check file permissions
    if [[ -r "/var/www/html/index.php" && -r "/var/www/html/health.php" ]]; then
        FILE_PERMISSIONS_STATUS=1
    else
        FILE_PERMISSIONS_STATUS=0
    fi
    send_metric "FilePermissionsStatus" "$FILE_PERMISSIONS_STATUS" "Count" "InstanceId=$INSTANCE_ID,AvailabilityZone=$AZ"
}

# Main execution
main() {
    log_message "Starting custom metrics collection for instance $INSTANCE_ID in region $REGION"
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_message "ERROR: AWS CLI not found"
        exit 1
    fi
    
    # Check if instance has appropriate IAM permissions
    if ! aws sts get-caller-identity &>/dev/null; then
        log_message "ERROR: No AWS credentials or insufficient permissions"
        exit 1
    fi
    
    # Collect all metrics
    collect_apache_metrics
    collect_php_metrics
    collect_system_metrics
    collect_health_metrics
    collect_database_metrics
    collect_log_metrics
    collect_application_metrics
    
    log_message "Custom metrics collection completed successfully"
}

# Error handling
trap 'log_message "ERROR: Script failed at line $LINENO"' ERR

# Run main function
main "$@"