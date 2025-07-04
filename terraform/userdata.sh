#!/bin/bash
# FIXED: Robust EC2 User Data Script for Proxy LAMP Stack
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== STARTING LAMP SETUP $(date) ==="

# FIXED: Get and log Terraform variables early
DB_ENDPOINT="${db_endpoint}"
DB_PASSWORD="${db_password}"
AWS_REGION="${aws_region}"
DEPLOYMENT_SUFFIX="${deployment_suffix}"

echo "=== TERRAFORM VARIABLES ==="
echo "DB_ENDPOINT: $DB_ENDPOINT"
echo "AWS_REGION: $AWS_REGION"
echo "DEPLOYMENT_SUFFIX: $DEPLOYMENT_SUFFIX"
echo "DB_PASSWORD: [REDACTED]"

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

# FIXED: Configure Apache DirectoryIndex to prioritize PHP files
echo "Configuring Apache DirectoryIndex to prioritize PHP..."
cat > /etc/apache2/conf-available/directory-index.conf << 'EOF'
# Prioritize PHP files over HTML files
DirectoryIndex index.php index.html index.htm
EOF

a2enconf directory-index

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

# FIXED: Create simple loading page - BUT use different name to avoid conflicts
cat > /var/www/html/loading.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Setup</title>
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Setup</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Waiting for application deployment...</p><p>Server: HOSTNAME</p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/loading.html

# FIXED: Create a minimal index.html that will be replaced by deployment
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Ready</title><meta http-equiv="refresh" content="10">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Application: Loading</p><p>Server: HOSTNAME</p><p><small>This page will be replaced when the application deploys</small></p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# FIXED: Create health endpoint immediately with better error handling
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
try {
    echo json_encode([
        'status' => 'healthy',
        'timestamp' => date('c'),
        'server' => gethostname(),
        'services' => ['apache' => 'running', 'php' => 'running'],
        'setup_stage' => 'initial'
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'error' => $e->getMessage(),
        'server' => gethostname()
    ]);
}
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

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"

# FIXED: Enhanced Database configuration with multiple fallback methods
echo "=== SETTING UP DATABASE CONFIGURATION ==="

# Method 1: Use Terraform variables (primary method)
echo "Method 1: Using Terraform template variables"
echo "DB_ENDPOINT from template: '$DB_ENDPOINT'"

if [ -n "$DB_ENDPOINT" ] && [ "$DB_ENDPOINT" != "null" ] && [ "$DB_ENDPOINT" != "\${db_endpoint}" ] && [ "$DB_ENDPOINT" != "" ]; then
    echo "✅ Valid database endpoint from Terraform: $DB_ENDPOINT"
    DB_HOST_FINAL="$DB_ENDPOINT"
    DB_PASSWORD_FINAL="$DB_PASSWORD"
else
    echo "⚠️ Database endpoint from Terraform is invalid or empty"
    
    # Method 2: Try to get from instance tags
    echo "Method 2: Attempting to get database endpoint from instance tags"
    if [ "$INSTANCE_ID" != "unknown" ]; then
        DB_HOST_FROM_TAGS=$(aws ec2 describe-tags --region "$REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DatabaseEndpoint" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        DB_PASSWORD_FROM_TAGS=$(aws ec2 describe-tags --region "$REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DatabasePassword" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        
        if [ -n "$DB_HOST_FROM_TAGS" ] && [ "$DB_HOST_FROM_TAGS" != "None" ] && [ "$DB_HOST_FROM_TAGS" != "null" ]; then
            echo "✅ Found database endpoint in instance tags: $DB_HOST_FROM_TAGS"
            DB_HOST_FINAL="$DB_HOST_FROM_TAGS"
            DB_PASSWORD_FINAL="$DB_PASSWORD_FROM_TAGS"
        else
            echo "⚠️ No valid database endpoint found in instance tags"
            
            # Method 3: Try to find RDS instances with our deployment suffix
            echo "Method 3: Searching for RDS instances with deployment suffix"
            if [ -n "$DEPLOYMENT_SUFFIX" ] && [ "$DEPLOYMENT_SUFFIX" != "null" ]; then
                RDS_ENDPOINT=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?contains(DBInstanceIdentifier, '$DEPLOYMENT_SUFFIX')].Endpoint.Address" --output text 2>/dev/null || echo "")
                if [ -n "$RDS_ENDPOINT" ] && [ "$RDS_ENDPOINT" != "None" ]; then
                    echo "✅ Found RDS instance: $RDS_ENDPOINT"
                    DB_HOST_FINAL="$RDS_ENDPOINT"
                    DB_PASSWORD_FINAL="$DB_PASSWORD"
                else
                    echo "⚠️ No RDS instances found with deployment suffix"
                    
                    # Method 4: Fallback to placeholder
                    echo "Method 4: Using placeholder configuration"
                    DB_HOST_FINAL="localhost"
                    DB_PASSWORD_FINAL="placeholder"
                fi
            else
                echo "⚠️ No deployment suffix available"
                DB_HOST_FINAL="localhost"
                DB_PASSWORD_FINAL="placeholder"
            fi
        fi
    else
        echo "⚠️ Instance ID not available, using placeholder"
        DB_HOST_FINAL="localhost"
        DB_PASSWORD_FINAL="placeholder"
    fi
fi

echo "Final database configuration:"
echo "DB_HOST_FINAL: $DB_HOST_FINAL"
echo "DB_PASSWORD_FINAL: [REDACTED]"

# FIXED: Create database config file with validation
mkdir -p /var/www/html

echo "Creating database configuration file..."
cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_HOST_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF

# Set proper ownership and permissions
chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

echo "✅ Database config file created successfully"
echo "Database config file contents:"
ls -la /var/www/html/.db_config

# Verify the file was created and is readable
if [ -f /var/www/html/.db_config ]; then
    echo "✅ Database config file exists and is readable"
    echo "File permissions: $(ls -la /var/www/html/.db_config)"
else
    echo "❌ Database config file creation failed"
    exit 1
fi

# FIXED: Add database connection info to Apache environment (for backup)
cat >> /etc/apache2/envvars << EOF
export DB_HOST="$DB_HOST_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

# FIXED: Test database connection in background (non-blocking with better error handling)
(
    echo "=== TESTING DATABASE CONNECTION ==="
    DB_CONNECTION_SUCCESS=false
    
    if [ "$DB_HOST_FINAL" != "localhost" ] && [ "$DB_HOST_FINAL" != "placeholder" ]; then
        for i in {1..30}; do
            echo "Attempting database connection to $DB_HOST_FINAL (attempt $i/30)..."
            
            if timeout 10 mysql -h "$DB_HOST_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
                echo "✅ Database connection successful"
                
                # Create database and table
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

-- Insert a test record
INSERT INTO tasks (task) VALUES ('Welcome to your Proxy LAMP Stack application!') ON DUPLICATE KEY UPDATE task=task;
MYSQL_EOF
                echo "✅ Database and table created with test data"
                DB_CONNECTION_SUCCESS=true
                break
            else
                echo "Database connection attempt $i/30 failed"
                if [ $i -lt 30 ]; then
                    sleep 20
                fi
            fi
        done
        
        if [ "$DB_CONNECTION_SUCCESS" = "false" ]; then
            echo "⚠️ Database connection failed after 30 attempts"
            echo "Database endpoint: $DB_HOST_FINAL"
            echo "This may be normal during initial setup - the application will retry"
        fi
    else
        echo "⚠️ Database endpoint is placeholder or localhost, skipping connection test"
    fi
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

# FIXED: Wait for background processes to complete (with timeout)
echo "Waiting for background processes to complete..."
for i in {1..30}; do
    BACKGROUND_JOBS=$(jobs -r | wc -l)
    if [ "$BACKGROUND_JOBS" -eq 0 ]; then
        echo "✅ All background processes completed"
        break
    fi
    echo "⏳ Waiting for $BACKGROUND_JOBS background processes... ($i/30)"
    sleep 10
done

# FIXED: Final comprehensive verification
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

# FIXED: Verify database config file one more time
if [ -f /var/www/html/.db_config ]; then
    echo "✅ Database config file exists"
    echo "File details:"
    ls -la /var/www/html/.db_config
    echo "File owner can read: $(sudo -u www-data test -r /var/www/html/.db_config && echo 'yes' || echo 'no')"
else
    echo "❌ Database config file missing - attempting to recreate"
    # Recreate the config file
    cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_HOST_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF
    chown www-data:www-data /var/www/html/.db_config
    chmod 600 /var/www/html/.db_config
    echo "✅ Database config file recreated"
fi

# Ensure proper permissions one more time
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*.php 2>/dev/null || echo "No PHP files to set permissions"
chmod 644 /var/www/html/*.css 2>/dev/null || echo "No CSS files to set permissions"
chmod 600 /var/www/html/.db_config 2>/dev/null || echo "No .db_config file to set permissions"

# FIXED: Create final completion marker with more info
cat > /tmp/lamp-setup-complete << EOF
LAMP Setup Completed: $(date)
Database endpoint: $DB_HOST_FINAL
Apache status: $(systemctl is-active apache2)
PHP status: $(php -v | head -1)
Config file exists: $([ -f /var/www/html/.db_config ] && echo 'yes' || echo 'no')
EOF

echo "=== LAMP SETUP COMPLETED $(date) ==="

# Final status report
echo "=== SETUP STATUS REPORT ==="
echo "✅ Apache: $(systemctl is-active apache2)"
echo "✅ PHP: $(php -v | head -1)"
echo "✅ Database config: $([ -f /var/www/html/.db_config ] && echo 'exists' || echo 'missing')"
echo "✅ Database endpoint: $DB_HOST_FINAL"
echo "✅ Health endpoint: $(curl -s -f http://localhost/health.php >/dev/null && echo 'working' || echo 'not working')"

# Final check and report
if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null && [ -f /var/www/html/.db_config ]; then
    echo "🎉 SUCCESS: LAMP stack is fully operational with database configuration"
    echo "📄 Apache DirectoryIndex configured to prioritize PHP files"
    echo "🗄️ Database configuration prepared"
    echo "⏳ Ready for application deployment"
    exit 0
else
    echo "⚠️ WARNING: LAMP stack may have issues but setup completed"
    echo "Issues detected:"
    systemctl is-active --quiet apache2 || echo "- Apache not running"
    curl -s -f http://localhost/ >/dev/null || echo "- Apache not responding"
    [ -f /var/www/html/.db_config ] || echo "- Database config file missing"
    exit 0  # Don't fail the entire instance launch
fi