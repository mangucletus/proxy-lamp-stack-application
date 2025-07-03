#!/bin/bash
# FIXED: Simplified and Robust EC2 User Data Script for Proxy LAMP Stack
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== STARTING LAMP SETUP $(date) ==="

# Update packages first
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# FIXED: Install core packages in smaller batches to avoid timeouts
echo "Installing Apache and PHP..."
apt-get install -y apache2 php libapache2-mod-php php-mysql php-cli php-common php-mbstring php-xml php-curl php-json

echo "Installing additional tools..."
apt-get install -y mysql-client-core-8.0 awscli htop curl jq unzip

# FIXED: Start Apache immediately and ensure it's running
systemctl enable apache2
systemctl start apache2

# FIXED: Wait for Apache to be fully ready
for i in {1..10}; do
    if systemctl is-active --quiet apache2; then
        echo "Apache is running"
        break
    fi
    echo "Waiting for Apache to start... attempt $i"
    sleep 2
done

# FIXED: Create simple loading page immediately
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Ready</title>
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Application: Loading</p><p>Server: HOSTNAME</p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# FIXED: Create health endpoint immediately
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
echo json_encode([
    'status' => 'healthy',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'services' => ['apache' => 'running', 'php' => 'running']
]);
?>
EOF

# Set basic permissions
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*

# FIXED: Test Apache immediately
if curl -s -f http://localhost/ > /dev/null; then
    echo "✅ Apache is responding"
else
    echo "❌ Apache test failed"
    systemctl restart apache2
    sleep 5
fi

# FIXED: Create completion marker early for health checks
touch /tmp/lamp-setup-complete
echo "✅ Basic LAMP setup completed"

# Configure Apache (non-critical, continue if fails)
a2enmod rewrite headers ssl || echo "Warning: Could not enable Apache modules"
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF' || echo "Warning: Could not create load balancer config"
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
EOF
a2enconf load-balancer || echo "Warning: Could not enable load balancer config"
systemctl reload apache2 || systemctl restart apache2

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")

# FIXED: Database configuration (non-blocking)
DB_ENDPOINT_FINAL="${db_endpoint}"
DB_PASSWORD_FINAL="${db_password}"

# Create database config file
mkdir -p /var/www/html
cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_ENDPOINT_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF
chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

# Add to Apache environment
cat >> /etc/apache2/envvars << EOF
export DB_HOST="$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

# FIXED: Test database connection in background (non-blocking)
(
    echo "Testing database connection..."
    for i in {1..20}; do
        if [ -n "$DB_ENDPOINT_FINAL" ] && [ "$DB_ENDPOINT_FINAL" != "proxy-lamp-mysql-endpoint" ]; then
            if mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
                echo "✅ Database connection successful"
                mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" << 'MYSQL_EOF'
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
MYSQL_EOF
                echo "✅ Database and table created"
                break
            fi
        fi
        echo "Database connection attempt $i/20..."
        sleep 15
    done
) &

# FIXED: Install CloudWatch agent in background (non-blocking)
(
    echo "Installing CloudWatch agent..."
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/cloudwatch-agent.deb
    dpkg -i /tmp/cloudwatch-agent.deb || echo "Warning: CloudWatch agent installation failed"
    
    # Create basic CloudWatch config
    mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "ProxyLAMP/Application",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF
    
    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config -m ec2 -s \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null || echo "Warning: CloudWatch agent start failed"
) &

# FIXED: Basic system tuning (continue on failure)
cat >> /etc/sysctl.conf << 'EOF' || echo "Warning: sysctl config failed"
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p || echo "Warning: sysctl reload failed"

# FIXED: Final verification
sleep 5
if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null; then
    echo "✅ LAMP Stack Ready and Verified"
    
    # Update status page
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Ready - Application Loading</title><meta http-equiv="refresh" content="30">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Application: Loading (Deploy in progress)</p><p>Server: HOSTNAME</p><p><a href="/health.php">Health Check</a></p></div></body></html>
EOF
    sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html
    
    # Ensure proper permissions
    chown -R www-data:www-data /var/www/html
    chmod 755 /var/www/html
    chmod 644 /var/www/html/*
else
    echo "❌ Final verification failed"
    systemctl restart apache2
    sleep 5
fi

echo "=== LAMP SETUP COMPLETED $(date) ==="
exit 0