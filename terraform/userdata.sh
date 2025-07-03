#!/bin/bash
# FIXED EC2 User Data Script for Proxy LAMP Stack with Load Balancer, RDS, and Monitoring

set -e  # Exit on any error
exec > >(tee /var/log/user-data.log) 2>&1  # Log all output

echo "=== STARTING LAMP STACK SETUP $(date) ==="

#-------------------------------
# 1. Update and Upgrade Packages
#-------------------------------
echo "Updating packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

#-------------------------------
# 2. Install Apache Web Server
#-------------------------------
echo "Installing Apache..."
apt-get install -y apache2

#-------------------------------
# 3. Install PHP and Extensions
#-------------------------------
echo "Installing PHP..."
apt-get install -y php php-mysql libapache2-mod-php php-cli php-common php-mbstring php-xml php-curl php-json php-zip

#-------------------------------
# 4. Install MySQL Client
#-------------------------------
echo "Installing MySQL client..."
apt-get install -y mysql-client-core-8.0

#-------------------------------
# 5. Install AWS CLI and CloudWatch Agent
#-------------------------------
echo "Installing AWS tools..."
apt-get install -y awscli htop iotop nethogs curl jq
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

#-------------------------------
# 6. Enable and Start Apache IMMEDIATELY
#-------------------------------
echo "Starting Apache..."
systemctl enable apache2
systemctl start apache2

# Wait for Apache to fully start
sleep 5

# Verify Apache is running
if ! systemctl is-active --quiet apache2; then
    echo "ERROR: Apache failed to start"
    systemctl status apache2
    exit 1
fi

echo "Apache is running successfully"

#-------------------------------
# 7. Create Basic Index Page IMMEDIATELY
#-------------------------------
echo "Creating basic index page..."
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>LAMP Stack Loading...</title>
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .status { color: #27ae60; font-weight: bold; }
        .loading { color: #f39c12; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 LAMP Stack Loading...</h1>
        <p class="status">✅ Apache: Running</p>
        <p class="loading">⏳ PHP: Installing...</p>
        <p class="loading">⏳ Database: Connecting...</p>
        <p class="loading">⏳ Application: Loading...</p>
        <hr>
        <p><strong>Server:</strong> HOSTNAME_PLACEHOLDER</p>
        <p><strong>Time:</strong> TIME_PLACEHOLDER</p>
        <p><strong>Status:</strong> Initializing...</p>
        <hr>
        <p>Please wait while the application loads. This page will refresh automatically.</p>
    </div>
</body>
</html>
EOF

# Replace placeholders in the HTML
sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" /var/www/html/index.html
sed -i "s/TIME_PLACEHOLDER/$(date)/g" /var/www/html/index.html

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

echo "Basic index page created and accessible"

#-------------------------------
# 8. Test Basic Apache Functionality
#-------------------------------
echo "Testing Apache..."
if curl -s -f http://localhost/ > /dev/null; then
    echo "✅ Apache is responding to HTTP requests"
else
    echo "❌ Apache is not responding"
    exit 1
fi

#-------------------------------
# 9. Configure Apache for Load Balancer
#-------------------------------
echo "Configuring Apache for load balancer..."
a2enmod rewrite headers ssl

# Configure Apache to work behind load balancer
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF'
# Load Balancer Configuration
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16

# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"

# Health check endpoint optimization
<Location "/health.php">
    SetEnvIf Request_URI "^/health\.php$" dontlog
    CustomLog /var/log/apache2/access.log combined env=!dontlog
</Location>
EOF

a2enconf load-balancer
systemctl restart apache2

# Wait for Apache restart
sleep 5

#-------------------------------
# 10. Create Health Check Endpoint EARLY
#-------------------------------
echo "Creating health check endpoint..."
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'healthy',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'services' => [
        'apache' => 'running',
        'php' => 'running'
    ]
]);
?>
EOF

chown www-data:www-data /var/www/html/health.php
chmod 644 /var/www/html/health.php

# Test health endpoint
echo "Testing health endpoint..."
if curl -s http://localhost/health.php | grep -q "healthy"; then
    echo "✅ Health endpoint is working"
else
    echo "❌ Health endpoint is not working"
fi

#-------------------------------
# 11. Configure Database Connection
#-------------------------------
echo "Configuring database connection..."

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"

# Function to get tag value
get_tag_value() {
    local tag_key="$1"
    aws ec2 describe-tags \
        --region "$REGION" \
        --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$tag_key" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo ""
}

# Try to get database info from tags
DB_ENDPOINT=$(get_tag_value "DatabaseEndpoint")
DB_PASSWORD_TAG=$(get_tag_value "DatabasePassword")

echo "DB_ENDPOINT from tags: $DB_ENDPOINT"

# If not found in tags, try Auto Scaling Group tags
if [ -z "$DB_ENDPOINT" ]; then
    ASG_NAME=$(aws autoscaling describe-auto-scaling-instances \
        --region "$REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'AutoScalingInstances[0].AutoScalingGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ASG_NAME" ]; then
        DB_ENDPOINT=$(aws autoscaling describe-tags \
            --region "$REGION" \
            --filters "Name=auto-scaling-group,Values=$ASG_NAME" "Name=key,Values=DatabaseEndpoint" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "")
        
        DB_PASSWORD_TAG=$(aws autoscaling describe-tags \
            --region "$REGION" \
            --filters "Name=auto-scaling-group,Values=$ASG_NAME" "Name=key,Values=DatabasePassword" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "")
    fi
fi

# Use template variables as fallback
DB_ENDPOINT_FINAL="${db_endpoint}"
DB_PASSWORD_FINAL="${db_password}"

# If template variables are placeholder values, use tag values
if [ -z "$DB_ENDPOINT_FINAL" ] || [ "$DB_ENDPOINT_FINAL" = "proxy-lamp-mysql-endpoint" ]; then
    DB_ENDPOINT_FINAL="$DB_ENDPOINT"
fi

if [ -z "$DB_PASSWORD_FINAL" ] || [ "$DB_PASSWORD_FINAL" = "ProxySecurePass123!" ]; then
    DB_PASSWORD_FINAL="$DB_PASSWORD_TAG"
fi

# Final fallback values (FIXED: Properly escaped for Terraform)
DB_ENDPOINT_FINAL="$${DB_ENDPOINT_FINAL:-proxy-lamp-mysql-endpoint}"
DB_PASSWORD_FINAL="$${DB_PASSWORD_FINAL:-ProxySecurePass123!}"

echo "Final DB endpoint: $DB_ENDPOINT_FINAL"

# Create database configuration file
cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_ENDPOINT_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF

chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

# Also set as environment variables
export DB_HOST="$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"

# Add to Apache environment
cat >> /etc/apache2/envvars << EOF
export DB_HOST="$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

#-------------------------------
# 12. Wait for Database and Test Connection
#-------------------------------
if [ -n "$DB_ENDPOINT_FINAL" ] && [ "$DB_ENDPOINT_FINAL" != "proxy-lamp-mysql-endpoint" ]; then
    echo "Testing database connection..."
    
    # Wait for database to be available (up to 10 minutes)
    for i in {1..60}; do
        if mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✅ Database connection successful!"
            
            # Create database and table if they don't exist
            mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" << 'MYSQL_EOF'
CREATE DATABASE IF NOT EXISTS proxylamptodoapp;
USE proxylamptodoapp;
CREATE TABLE IF NOT EXISTS tasks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    task VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status ENUM('pending', 'completed') DEFAULT 'pending',
    INDEX idx_created_at (created_at),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
MYSQL_EOF
            
            echo "✅ Database and table setup completed"
            break
        else
            echo "Waiting for database... attempt $i/60"
            sleep 10
        fi
    done
else
    echo "⚠️ Database endpoint not configured, will be set during deployment"
fi

#-------------------------------
# 13. Update Status Page
#-------------------------------
echo "Updating status page..."
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>LAMP Stack Ready</title>
    <meta http-equiv="refresh" content="60">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .status { color: #27ae60; font-weight: bold; }
        .loading { color: #f39c12; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 LAMP Stack Status</h1>
        <p class="status">✅ Apache: Running</p>
        <p class="status">✅ PHP: Running</p>
        <p class="loading">⏳ Application: Loading...</p>
        <hr>
        <p><strong>Server:</strong> HOSTNAME_PLACEHOLDER</p>
        <p><strong>Time:</strong> TIME_PLACEHOLDER</p>
        <p><strong>Status:</strong> Ready for application deployment</p>
        <hr>
        <p><a href="/health.php">Health Check</a></p>
        <p>The system is ready. Application files will be deployed shortly.</p>
    </div>
</body>
</html>
EOF

sed -i "s/HOSTNAME_PLACEHOLDER/$(hostname)/g" /var/www/html/index.html
sed -i "s/TIME_PLACEHOLDER/$(date)/g" /var/www/html/index.html

#-------------------------------
# 14. Configure CloudWatch Agent
#-------------------------------
echo "Configuring CloudWatch agent..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

# Basic CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "ProxyLAMP/Application",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": ["tcp_established", "tcp_time_wait"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/apache2/access.log",
                        "log_group_name": "/aws/ec2/proxy-lamp/apache/access",
                        "log_stream_name": "{instance_id}/apache-access.log"
                    },
                    {
                        "file_path": "/var/log/apache2/error.log",
                        "log_group_name": "/aws/ec2/proxy-lamp/apache/error",
                        "log_stream_name": "{instance_id}/apache-error.log"
                    },
                    {
                        "file_path": "/var/log/cloud-init-output.log",
                        "log_group_name": "/aws/ec2/proxy-lamp/cloud-init",
                        "log_stream_name": "{instance_id}/cloud-init.log"
                    }
                ]
            }
        }
    }
}
EOF

#-------------------------------
# 15. Create Custom Metrics Script
#-------------------------------
cat > /usr/local/bin/custom-metrics.sh << 'EOF'
#!/bin/bash
# Custom metrics for CloudWatch

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Apache connection metrics
APACHE_CONNECTIONS=$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
aws cloudwatch put-metric-data --region $REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=ApacheConnections,Value=$APACHE_CONNECTIONS,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID

# Disk usage metrics
DISK_USAGE=$(df /var/www | tail -1 | awk '{print $5}' | sed 's/%//')
aws cloudwatch put-metric-data --region $REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=DiskUsagePercent,Value=$DISK_USAGE,Unit=Percent,Dimensions=InstanceId=$INSTANCE_ID

# Memory usage metrics
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.1f"), $3/$2 * 100.0}')
aws cloudwatch put-metric-data --region $REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=MemoryUsagePercent,Value=$MEMORY_USAGE,Unit=Percent,Dimensions=InstanceId=$INSTANCE_ID

# Apache status check
if systemctl is-active --quiet apache2; then
    APACHE_STATUS=1
else
    APACHE_STATUS=0
fi
aws cloudwatch put-metric-data --region $REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=ApacheStatus,Value=$APACHE_STATUS,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID
EOF

chmod +x /usr/local/bin/custom-metrics.sh

#-------------------------------
# 16. Configure System Tuning and Security
#-------------------------------
echo "Configuring system tuning..."

# Optimize kernel parameters for web server performance
cat >> /etc/sysctl.conf << 'EOF'
# Network performance tuning for load balanced web server
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 1024
EOF

sysctl -p

# Install and configure Fail2Ban for security
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true

[apache-auth]
enabled = true

[apache-badbots]
enabled = true

[apache-noscript]
enabled = true

[apache-overflows]
enabled = true
EOF

systemctl enable fail2ban
systemctl start fail2ban

#-------------------------------
# 17. Configure Log Rotation
#-------------------------------
cat > /etc/logrotate.d/proxy-lamp << 'EOF'
/var/log/apache2/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root adm
    postrotate
        systemctl reload apache2
    endscript
}
EOF

#-------------------------------
# 18. Enable Apache Status Module
#-------------------------------
echo "Enabling Apache status module..."
a2enmod status
echo "ExtendedStatus On" >> /etc/apache2/apache2.conf

# Configure Apache server-status for monitoring
cat > /etc/apache2/conf-available/server-status.conf << 'EOF'
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>
EOF
a2enconf server-status

# Restart Apache
systemctl restart apache2
sleep 5

#-------------------------------
# 19. Start CloudWatch Agent
#-------------------------------
echo "Starting CloudWatch agent..."
sleep 30  # Wait for network connectivity

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl enable amazon-cloudwatch-agent

#-------------------------------
# 20. Final Health Checks
#-------------------------------
echo "Performing final health checks..."

# Test Apache
if systemctl is-active --quiet apache2; then
    echo "✅ Apache is running"
else
    echo "❌ Apache is not running"
    systemctl status apache2
    exit 1
fi

# Test HTTP connectivity
if curl -s -f http://localhost/ > /dev/null; then
    echo "✅ HTTP connectivity working"
else
    echo "❌ HTTP connectivity failed"
    exit 1
fi

# Test health endpoint
if curl -s http://localhost/health.php | grep -q "healthy"; then
    echo "✅ Health endpoint working"
else
    echo "❌ Health endpoint failed"
fi

#-------------------------------
# 21. Create Application Deployment Directory
#-------------------------------
mkdir -p /tmp/app-deployment
chown ubuntu:ubuntu /tmp/app-deployment

#-------------------------------
# 22. Signal Completion
#-------------------------------
echo "LAMP Stack installation completed!" >> /var/log/cloud-init-output.log
echo "$(date): LAMP Stack setup completed successfully" >> /var/log/setup.log

# Create completion marker
touch /tmp/lamp-setup-complete

echo "=== LAMP STACK SETUP COMPLETED SUCCESSFULLY $(date) ==="

# Final status
systemctl status apache2 --no-pager
ps aux | grep apache2 | grep -v grep | wc -l | xargs echo 'Apache processes:'
curl -s http://localhost/health.php | jq . || echo "Health check response available"

exit 0