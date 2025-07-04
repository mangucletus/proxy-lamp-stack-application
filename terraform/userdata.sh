#!/bin/bash
# Compact EC2 User Data Script for Proxy LAMP Stack
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== LAMP SETUP START $(date) ==="

# Get Terraform variables
DB_ENDPOINT="${db_endpoint}"
DB_PASSWORD="${db_password}"
AWS_REGION="${aws_region}"
DEPLOYMENT_SUFFIX="${deployment_suffix}"

echo "DB_ENDPOINT: $DB_ENDPOINT"

# Update and install packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 php libapache2-mod-php php-mysql php-cli php-common php-mbstring php-xml php-curl php-json mysql-client-core-8.0 awscli curl jq

# Enable Apache modules
a2enmod rewrite headers ssl remoteip

# Configure Apache DirectoryIndex
cat > /etc/apache2/conf-available/directory-index.conf << 'EOF'
DirectoryIndex index.php index.html index.htm
EOF
a2enconf directory-index

# Start Apache
systemctl enable apache2
systemctl start apache2

# Wait for Apache
for i in {1..10}; do
    systemctl is-active --quiet apache2 && break
    sleep 2
done

# Create loading page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Ready</title><meta http-equiv="refresh" content="10">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Application: Loading</p><p>Server: HOSTNAME</p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# Create health endpoint
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'healthy',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'services' => ['apache' => 'running', 'php' => 'running'],
    'setup_stage' => 'initial'
]);
?>
EOF

# Set permissions
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*

# Test Apache
curl -s -f http://localhost/ > /dev/null || systemctl restart apache2

# Configure load balancer settings
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF'
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16
RemoteIPInternalProxy 172.16.0.0/12
RemoteIPInternalProxy 192.168.0.0/16
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
<Location "/server-status">
    SetHandler server-status
    Require ip 10.0.0.0/16
</Location>
EOF

a2enconf load-balancer
a2enmod status

# Test and reload Apache config
apache2ctl configtest && systemctl reload apache2 || {
    a2disconf load-balancer
    systemctl restart apache2
}

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")

# Database configuration with fallbacks
echo "=== DATABASE CONFIG ==="
DB_HOST_FINAL=""
DB_PASSWORD_FINAL=""

# Method 1: Terraform variables
if [ -n "$DB_ENDPOINT" ] && [ "$DB_ENDPOINT" != "null" ] && [ "$DB_ENDPOINT" != "\${db_endpoint}" ]; then
    DB_HOST_FINAL="$DB_ENDPOINT"
    DB_PASSWORD_FINAL="$DB_PASSWORD"
    echo "Using Terraform DB endpoint: $DB_HOST_FINAL"
else
    # Method 2: Instance tags
    if [ "$INSTANCE_ID" != "unknown" ]; then
        DB_HOST_FINAL=$(aws ec2 describe-tags --region "$AWS_REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DatabaseEndpoint" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        DB_PASSWORD_FINAL=$(aws ec2 describe-tags --region "$AWS_REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DatabasePassword" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
    fi
    
    # Method 3: RDS discovery
    if [ -z "$DB_HOST_FINAL" ] || [ "$DB_HOST_FINAL" = "None" ]; then
        DB_HOST_FINAL=$(aws rds describe-db-instances --region "$AWS_REGION" --query "DBInstances[?contains(DBInstanceIdentifier, '$DEPLOYMENT_SUFFIX')].Endpoint.Address" --output text 2>/dev/null | head -1)
        DB_PASSWORD_FINAL="$DB_PASSWORD"
    fi
    
    # Method 4: Fallback
    if [ -z "$DB_HOST_FINAL" ] || [ "$DB_HOST_FINAL" = "None" ]; then
        DB_HOST_FINAL="localhost"
        DB_PASSWORD_FINAL="placeholder"
    fi
fi

echo "Final DB config: Host=$DB_HOST_FINAL"

# Create database config file
mkdir -p /var/www/html
cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_HOST_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF

chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

# Add to Apache environment
cat >> /etc/apache2/envvars << EOF
export DB_HOST="$DB_HOST_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

# Test database connection (background)
(
    if [ "$DB_HOST_FINAL" != "localhost" ] && [ "$DB_HOST_FINAL" != "placeholder" ]; then
        for i in {1..20}; do
            if timeout 10 mysql -h "$DB_HOST_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
                echo "✅ Database connection successful"
                mysql -h "$DB_HOST_FINAL" -u admin -p"$DB_PASSWORD_FINAL" << 'MYSQL_EOF'
CREATE DATABASE IF NOT EXISTS proxylamptodoapp;
USE proxylamptodoapp;
CREATE TABLE IF NOT EXISTS tasks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    task VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    status ENUM('pending','completed') DEFAULT 'pending',
    INDEX idx_created_at (created_at),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO tasks (task) VALUES ('Welcome to your Proxy LAMP Stack application!') ON DUPLICATE KEY UPDATE task=task;
MYSQL_EOF
                echo "✅ Database and table created"
                break
            fi
            sleep 15
        done
    fi
) &

# Install CloudWatch agent (background)
(
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/cloudwatch-agent.deb && \
    dpkg -i /tmp/cloudwatch-agent.deb && \
    mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/ && \
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "ProxyLAMP/Application",
        "metrics_collected": {
            "cpu": {"measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"], "metrics_collection_interval": 60},
            "disk": {"measurement": ["used_percent"], "metrics_collection_interval": 60, "resources": ["*"]},
            "mem": {"measurement": ["mem_used_percent"], "metrics_collection_interval": 60}
        }
    }
}
EOF
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null
) &

# System tuning
cat >> /etc/sysctl.conf << 'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p >/dev/null 2>&1 || true

# Final verification
echo "=== FINAL VERIFICATION ==="

# Check services
systemctl is-active --quiet apache2 && echo "✅ Apache: running" || echo "❌ Apache: not running"
php -v >/dev/null 2>&1 && echo "✅ PHP: working" || echo "❌ PHP: not working"
curl -s -f http://localhost/health.php >/dev/null && echo "✅ Health endpoint: working" || echo "❌ Health endpoint: not working"

# Verify database config
if [ -f /var/www/html/.db_config ]; then
    echo "✅ Database config file exists"
    ls -la /var/www/html/.db_config
else
    echo "❌ Database config file missing"
    # Recreate if missing
    cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_HOST_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF
    chown www-data:www-data /var/www/html/.db_config
    chmod 600 /var/www/html/.db_config
fi

# Final permissions
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*.php 2>/dev/null || true
chmod 644 /var/www/html/*.css 2>/dev/null || true
chmod 600 /var/www/html/.db_config 2>/dev/null || true

# Create completion marker
cat > /tmp/lamp-setup-complete << EOF
LAMP Setup Completed: $(date)
Database endpoint: $DB_HOST_FINAL
Apache status: $(systemctl is-active apache2)
Config file exists: $([ -f /var/www/html/.db_config ] && echo 'yes' || echo 'no')
EOF

echo "=== LAMP SETUP COMPLETED $(date) ==="

# Final status
if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null && [ -f /var/www/html/.db_config ]; then
    echo "🎉 SUCCESS: LAMP stack fully operational"
    exit 0
else
    echo "⚠️ WARNING: Issues detected but continuing"
    exit 0
fi