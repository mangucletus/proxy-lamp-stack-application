#!/bin/bash
# EC2 User Data Script for Proxy LAMP Stack with Load Balancer, RDS, and Monitoring

#-------------------------------
# 1. Update and Upgrade Packages
#-------------------------------
apt-get update -y         # Fetches the list of available updates
apt-get upgrade -y        # Installs the latest versions of all packages

#-------------------------------
# 2. Install Apache Web Server
#-------------------------------
apt-get install -y apache2  # Installs the Apache2 HTTP server

#-------------------------------
# 3. Install PHP and Extensions
#-------------------------------
apt-get install -y php php-mysql libapache2-mod-php php-cli php-common php-mbstring php-xml php-curl php-json php-zip
# Installs PHP, the MySQL driver, Apache PHP module, and common PHP extensions

#-------------------------------
# 4. Install MySQL Client (for RDS connection)
#-------------------------------
apt-get install -y mysql-client-core-8.0
# MySQL client to connect to RDS database

#-------------------------------
# 5. Install AWS CLI and CloudWatch Agent
#-------------------------------
apt-get install -y awscli   # Installs AWS CLI
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

#-------------------------------
# 6. Install Additional Monitoring Tools
#-------------------------------
apt-get install -y htop iotop nethogs curl jq
# Performance monitoring and debugging tools

#-------------------------------
# 7. Enable and Start Services
#-------------------------------
systemctl start apache2     # Starts Apache service
systemctl enable apache2    # Ensures Apache starts on boot

#-------------------------------
# 8. Configure Apache for Load Balancer
#-------------------------------
# Enable necessary Apache modules
a2enmod rewrite           # Enables mod_rewrite module for clean URLs
a2enmod headers           # Enables mod_headers for load balancer support
a2enmod ssl               # Enables SSL module for future HTTPS support

# Configure Apache to work behind load balancer
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF'
# Load Balancer Configuration
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16

# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"

# Health check endpoint optimization
<Location "/health.php">
    SetEnvIf Request_URI "^/health\.php$" dontlog
    CustomLog /var/log/apache2/access.log combined env=!dontlog
</Location>
EOF

a2enconf load-balancer
systemctl restart apache2 # Restarts Apache to apply changes

#-------------------------------
# 9. Set File Permissions
#-------------------------------
chown -R www-data:www-data /var/www/html  # Changes ownership to Apache user
chmod -R 755 /var/www/html                # Grants read & execute permissions

#-------------------------------
# 10. Clean Up Default Page
#-------------------------------
rm -f /var/www/html/index.html  # Removes Apache default welcome page

#-------------------------------
# 11. Create App Directory and Basic Health Check
#-------------------------------
mkdir -p /var/www/html/app             # Creates app folder
chown -R www-data:www-data /var/www/html/app  # Sets proper ownership

# Create temporary health check until app deployment
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

#-------------------------------
# 12. Configure Database Connection
#-------------------------------
# Get database endpoint from EC2 user data or instance tags
INSTANCE_ID=$$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Function to get tag value
get_tag_value() {
    local tag_key="$$1"
    aws ec2 describe-tags \
        --region "$$REGION" \
        --filters "Name=resource-id,Values=$$INSTANCE_ID" "Name=key,Values=$$tag_key" \
        --query 'Tags[0].Value' \
        --output text 2>/dev/null || echo ""
}

# Try to get database info from tags (set by Terraform)
DB_ENDPOINT=$$(get_tag_value "DatabaseEndpoint")
DB_PASSWORD_TAG=$$(get_tag_value "DatabasePassword")

# If not found in tags, try other methods
if [ -z "$$DB_ENDPOINT" ]; then
    # Try to get from Auto Scaling Group tags
    ASG_NAME=$$(aws autoscaling describe-auto-scaling-instances \
        --region "$$REGION" \
        --instance-ids "$$INSTANCE_ID" \
        --query 'AutoScalingInstances[0].AutoScalingGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$$ASG_NAME" ]; then
        DB_ENDPOINT=$$(aws autoscaling describe-tags \
            --region "$$REGION" \
            --filters "Name=auto-scaling-group,Values=$$ASG_NAME" "Name=key,Values=DatabaseEndpoint" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "")
        
        DB_PASSWORD_TAG=$$(aws autoscaling describe-tags \
            --region "$$REGION" \
            --filters "Name=auto-scaling-group,Values=$$ASG_NAME" "Name=key,Values=DatabasePassword" \
            --query 'Tags[0].Value' \
            --output text 2>/dev/null || echo "")
    fi
fi

# Use template variables if available, otherwise use discovered values
DB_ENDPOINT_FINAL="${db_endpoint}"
DB_PASSWORD_FINAL="${db_password}"

# If template variables are empty, try to get from instance tags
if [ -z "$$DB_ENDPOINT_FINAL" ] || [ "$$DB_ENDPOINT_FINAL" = "proxy-lamp-mysql-endpoint" ]; then
    DB_ENDPOINT_FINAL="$$DB_ENDPOINT"
fi

if [ -z "$$DB_PASSWORD_FINAL" ] || [ "$$DB_PASSWORD_FINAL" = "ProxySecurePass123!" ]; then
    DB_PASSWORD_FINAL="$$DB_PASSWORD_TAG"
fi

# Final fallback values
DB_ENDPOINT_FINAL="$${DB_ENDPOINT_FINAL:-proxy-lamp-mysql-endpoint}"
DB_PASSWORD_FINAL="$${DB_PASSWORD_FINAL:-ProxySecurePass123!}"

# Create database configuration file for PHP
cat > /var/www/html/.db_config << EOF
DB_HOST=$$DB_ENDPOINT_FINAL
DB_USER=admin
DB_PASSWORD=$$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF

# Set proper permissions for config file
chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

# Also set as environment variables for this session
export DB_HOST="$$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"

# Add to Apache environment
cat >> /etc/apache2/envvars << EOF
export DB_HOST="$$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

echo "Database configuration set - Host: $$DB_ENDPOINT_FINAL"

#-------------------------------
# 13. Configure CloudWatch Agent
#-------------------------------
# Create CloudWatch agent configuration directory
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

# Basic CloudWatch agent configuration (will be replaced by deployment)
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
            "diskio": {
                "measurement": ["io_time", "read_bytes", "write_bytes", "reads", "writes"],
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
            },
            "processes": {
                "measurement": ["running", "sleeping", "dead"],
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
# 14. Create Custom Metrics Script
#-------------------------------
cat > /usr/local/bin/custom-metrics.sh << 'EOF'
#!/bin/bash
# Custom metrics for CloudWatch

INSTANCE_ID=$$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Apache connection metrics
APACHE_CONNECTIONS=$$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
aws cloudwatch put-metric-data --region $$REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=ApacheConnections,Value=$$APACHE_CONNECTIONS,Unit=Count,Dimensions=InstanceId=$$INSTANCE_ID

# Disk usage metrics
DISK_USAGE=$$(df /var/www | tail -1 | awk '{print $$5}' | sed 's/%//')
aws cloudwatch put-metric-data --region $$REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=DiskUsagePercent,Value=$$DISK_USAGE,Unit=Percent,Dimensions=InstanceId=$$INSTANCE_ID

# Memory usage metrics
MEMORY_USAGE=$$(free | grep Mem | awk '{printf("%.1f"), $$3/$$2 * 100.0}')
aws cloudwatch put-metric-data --region $$REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=MemoryUsagePercent,Value=$$MEMORY_USAGE,Unit=Percent,Dimensions=InstanceId=$$INSTANCE_ID

# Apache status check
if systemctl is-active --quiet apache2; then
    APACHE_STATUS=1
else
    APACHE_STATUS=0
fi
aws cloudwatch put-metric-data --region $$REGION --namespace "ProxyLAMP/Application" \
    --metric-data MetricName=ApacheStatus,Value=$$APACHE_STATUS,Unit=Count,Dimensions=InstanceId=$$INSTANCE_ID
EOF

chmod +x /usr/local/bin/custom-metrics.sh

#-------------------------------
# 15. Configure Log Rotation
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
# 16. Set up System Tuning for Load Balancer
#-------------------------------
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

#-------------------------------
# 17. Install and Configure Fail2Ban for Security
#-------------------------------
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
# 18. Create Application Deployment Directory
#-------------------------------
mkdir -p /tmp/app-deployment
chown ubuntu:ubuntu /tmp/app-deployment

#-------------------------------
# 19. Final Setup and Verification
#-------------------------------
# Enable Apache status module for monitoring
a2enmod status
echo "ExtendedStatus On" >> /etc/apache2/apache2.conf

# Configure Apache server-status for monitoring (restricted to localhost)
cat > /etc/apache2/conf-available/server-status.conf << 'EOF'
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>
EOF
a2enconf server-status

# Restart services
systemctl restart apache2

# Verify services are running
systemctl is-active apache2 && echo "Apache is running" || echo "Apache failed to start"

#-------------------------------
# 20. Wait for Network Connectivity and Start CloudWatch Agent
#-------------------------------
# Wait for network connectivity before starting CloudWatch agent
sleep 30

# Start CloudWatch agent with basic configuration
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl enable amazon-cloudwatch-agent

#-------------------------------
# 21. Test Database Connection
#-------------------------------
# Test database connection and create a simple test
echo "Testing database connection..."
if [ -n "$$DB_ENDPOINT_FINAL" ] && [ "$$DB_ENDPOINT_FINAL" != "proxy-lamp-mysql-endpoint" ]; then
    # Wait for database to be available
    for i in {1..30}; do
        if mysql -h "$$DB_ENDPOINT_FINAL" -u admin -p"$${DB_PASSWORD_FINAL}" -e "SELECT 1;" 2>/dev/null; then
            echo "Database connection successful!"
            break
        else
            echo "Waiting for database... attempt $$i/30"
            sleep 10
        fi
    done
else
    echo "Database endpoint not configured, will be set during deployment"
fi

#-------------------------------
# 22. Completion Marker
#-------------------------------
echo "LAMP Stack installation completed!" >> /var/log/cloud-init-output.log
echo "$$(date): Proxy LAMP Stack setup completed" >> /var/log/setup.log

# Final system status
echo "=== System Status ===" >> /var/log/setup.log
systemctl status apache2 --no-pager >> /var/log/setup.log
systemctl status amazon-cloudwatch-agent --no-pager >> /var/log/setup.log

# Create marker file for deployment script
touch /tmp/lamp-setup-complete

echo "Proxy LAMP Stack installation completed successfully!"