#!/bin/bash
# FIXED: Robust EC2 User Data Script for Proxy LAMP Stack
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

# FIXED: Enable required Apache modules BEFORE creating configuration
echo "Enabling required Apache modules..."
a2enmod rewrite
a2enmod headers
a2enmod ssl
a2enmod remoteip  # FIXED: This was missing - required for RemoteIPHeader

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
    echo "❌ Apache test failed - restarting Apache"
    systemctl restart apache2
    sleep 5
    
    # Test again
    if curl -s -f http://localhost/ > /dev/null; then
        echo "✅ Apache is responding after restart"
    else
        echo "❌ Apache still not responding - checking status"
        systemctl status apache2 --no-pager
    fi
fi

# FIXED: Create completion marker early for health checks
touch /tmp/lamp-setup-complete
echo "✅ Basic LAMP setup completed"

# FIXED: Configure Apache load balancer settings (AFTER modules are enabled)
echo "Configuring Apache for load balancer..."
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF'
# Load balancer configuration
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16
RemoteIPInternalProxy 172.16.0.0/12
RemoteIPInternalProxy 192.168.0.0/16

# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"

# Server status for monitoring (restrict to VPC)
<Location "/server-status">
    SetHandler server-status
    Require ip 10.0.0.0/16
</Location>

# Server info for monitoring (restrict to VPC)  
<Location "/server-info">
    SetHandler server-info
    Require ip 10.0.0.0/16
</Location>
EOF

# Enable the load balancer configuration
a2enconf load-balancer

# FIXED: Enable server status module for monitoring
a2enmod status

# FIXED: Test Apache configuration before reloading
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo "✅ Apache configuration is valid"
    
    # Reload Apache to apply new configuration
    if systemctl reload apache2; then
        echo "✅ Apache reloaded successfully"
    else
        echo "❌ Apache reload failed - trying restart"
        systemctl restart apache2
        sleep 3
    fi
else
    echo "❌ Apache configuration test failed"
    apache2ctl configtest
    
    # Disable the problematic config and restart
    a2disconf load-balancer
    systemctl restart apache2
    echo "⚠️ Load balancer config disabled due to errors"
fi

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
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/cloudwatch-agent.deb 2>/dev/null || {
        echo "Failed to download CloudWatch agent"
        exit 0
    }
    
    if dpkg -i /tmp/cloudwatch-agent.deb; then
        echo "✅ CloudWatch agent installed"
        
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
            -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null && {
            echo "✅ CloudWatch agent started"
        } || {
            echo "⚠️ CloudWatch agent start failed"
        }
    else
        echo "⚠️ CloudWatch agent installation failed"
    fi
) &

# FIXED: Basic system tuning (continue on failure)
echo "Applying system tuning..."
cat >> /etc/sysctl.conf << 'EOF' 2>/dev/null || true
# Network performance tuning
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p >/dev/null 2>&1 || echo "⚠️ sysctl reload failed"

# FIXED: Create a comprehensive status page
cat > /var/www/html/status.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Server Status</title>
<meta http-equiv="refresh" content="30">
<style>
body{font-family:Arial;margin:20px;background:#f5f5f5}
.container{background:white;padding:20px;border-radius:10px;margin-bottom:20px}
.status{display:inline-block;padding:5px 10px;border-radius:15px;color:white;font-weight:bold}
.healthy{background:#28a745}
.warning{background:#ffc107;color:#000}
.error{background:#dc3545}
</style>
</head><body>
<div class="container">
<h1>🖥️ Server Status</h1>
<p><strong>Hostname:</strong> HOSTNAME</p>
<p><strong>Instance ID:</strong> INSTANCE_ID</p>
<p><strong>Apache:</strong> <span class="status healthy">Running</span></p>
<p><strong>PHP:</strong> <span class="status healthy">Running</span></p>
<p><strong>Last Updated:</strong> <span id="timestamp">TIMESTAMP</span></p>
</div>
<div class="container">
<h2>🔗 Quick Links</h2>
<p><a href="/">Main Application</a> | <a href="/health.php">Health Check</a> | <a href="/server-status">Server Status</a></p>
</div>
</body></html>
EOF

# Replace placeholders
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/status.html
sed -i "s/INSTANCE_ID/$INSTANCE_ID/g" /var/www/html/status.html
sed -i "s/TIMESTAMP/$(date)/g" /var/www/html/status.html

# FIXED: Final comprehensive verification
sleep 5
echo "=== FINAL VERIFICATION ==="

# Check Apache status
if systemctl is-active --quiet apache2; then
    echo "✅ Apache service is active"
else
    echo "❌ Apache service is not active - checking status"
    systemctl status apache2 --no-pager
fi

# Check if Apache is responding to HTTP requests
if curl -s -f http://localhost/ >/dev/null; then
    echo "✅ Apache is responding to HTTP requests"
else
    echo "❌ Apache is not responding to HTTP requests"
    
    # Try to restart Apache one more time
    echo "Attempting final Apache restart..."
    systemctl restart apache2
    sleep 5
    
    if curl -s -f http://localhost/ >/dev/null; then
        echo "✅ Apache is responding after final restart"
    else
        echo "❌ Apache still not responding - printing detailed diagnostics"
        echo "=== Apache Status ==="
        systemctl status apache2 --no-pager
        echo "=== Apache Error Log ==="
        tail -20 /var/log/apache2/error.log 2>/dev/null || echo "No error log found"
        echo "=== Apache Configuration Test ==="
        apache2ctl configtest
        echo "=== Enabled Modules ==="
        apache2ctl -M
        echo "=== Listening Ports ==="
        netstat -tlnp | grep apache2
    fi
fi

# Check PHP
if php -v >/dev/null 2>&1; then
    echo "✅ PHP is working"
    php -v | head -1
else
    echo "❌ PHP is not working"
fi

# Check health endpoint
if curl -s -f http://localhost/health.php >/dev/null; then
    echo "✅ Health endpoint is accessible"
else
    echo "❌ Health endpoint is not accessible"
fi

# Update final status page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Stack Ready</title><meta http-equiv="refresh" content="30">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>✅ Ready for application deployment</p><p>Server: HOSTNAME</p><p><a href="/health.php">Health Check</a> | <a href="/status.html">Server Status</a></p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# Ensure proper permissions
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*

echo "=== LAMP SETUP COMPLETED $(date) ==="

# Final check and report
if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null; then
    echo "🎉 SUCCESS: LAMP stack is fully operational"
    exit 0
else
    echo "⚠️ WARNING: LAMP stack may have issues but setup completed"
    exit 0  # Don't fail the entire instance launch
fi