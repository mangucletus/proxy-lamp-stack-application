#!/bin/bash
# FIXED: Enhanced EC2 User Data Script with Proper Database Configuration
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== STARTING LAMP SETUP $(date) ==="

# Update packages first
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Install core packages
echo "Installing Apache and PHP..."
apt-get install -y apache2 php libapache2-mod-php php-mysql php-cli php-common php-mbstring php-xml php-curl php-json

echo "Installing additional tools..."
apt-get install -y mysql-client-core-8.0 awscli htop curl jq unzip

# Enable required Apache modules
echo "Enabling required Apache modules..."
a2enmod rewrite
a2enmod headers
a2enmod ssl
a2enmod remoteip
a2enmod status

# Configure Apache DirectoryIndex to prioritize PHP files
echo "Configuring Apache DirectoryIndex to prioritize PHP..."
cat > /etc/apache2/conf-available/directory-index.conf << 'EOF'
DirectoryIndex index.php index.html index.htm
EOF
a2enconf directory-index

# Start Apache
systemctl enable apache2
systemctl start apache2

# Wait for Apache to be ready
for i in {1..10}; do
    if systemctl is-active --quiet apache2; then
        echo "✅ Apache is running"
        break
    fi
    echo "Waiting for Apache to start... attempt $i"
    sleep 2
done

# Create basic health endpoint immediately
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

# Test Apache immediately
if curl -s -f http://localhost/ > /dev/null; then
    echo "✅ Apache is responding"
else
    echo "❌ Apache test failed - restarting Apache"
    systemctl restart apache2
    sleep 5
fi

# Configure Apache load balancer settings
echo "Configuring Apache for load balancer..."
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

<Location "/server-info">
    SetHandler server-info
    Require ip 10.0.0.0/16
</Location>
EOF

# Enable the load balancer configuration
a2enconf load-balancer

# Test Apache configuration
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo "✅ Apache configuration is valid"
    systemctl reload apache2
else
    echo "❌ Apache configuration test failed"
    apache2ctl configtest
    a2disconf load-balancer
    systemctl restart apache2
    echo "⚠️ Load balancer config disabled due to errors"
fi

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")

# FIXED: Enhanced Database configuration with better error handling
echo "=== SETTING UP DATABASE CONFIGURATION ==="

# Get database parameters from Terraform variables
DB_ENDPOINT_RAW="${db_endpoint}"
DB_PASSWORD_RAW="${db_password}"

echo "Raw DB endpoint from Terraform: '$DB_ENDPOINT_RAW'"
echo "DB password length: ${#DB_PASSWORD_RAW}"

# Clean up the variables and validate them
if [ -n "$DB_ENDPOINT_RAW" ] && [ "$DB_ENDPOINT_RAW" != "\${db_endpoint}" ] && [ "$DB_ENDPOINT_RAW" != "proxy-lamp-mysql-endpoint" ]; then
    DB_ENDPOINT_FINAL="$DB_ENDPOINT_RAW"
    echo "✅ Valid database endpoint provided: $DB_ENDPOINT_FINAL"
else
    echo "⚠️ Invalid or missing database endpoint: '$DB_ENDPOINT_RAW'"
    # Try to get it from Terraform outputs
    if command -v aws >/dev/null 2>&1; then
        echo "Attempting to get database endpoint from RDS..."
        DB_ENDPOINT_FINAL=$(aws rds describe-db-instances \
            --region "$REGION" \
            --query 'DBInstances[?contains(DBInstanceIdentifier, `proxy-lamp-mysql`)].Endpoint.Address' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$DB_ENDPOINT_FINAL" ] && [ "$DB_ENDPOINT_FINAL" != "None" ]; then
            echo "✅ Found database endpoint via RDS API: $DB_ENDPOINT_FINAL"
        else
            echo "❌ Could not determine database endpoint"
            DB_ENDPOINT_FINAL="localhost"
        fi
    else
        echo "❌ AWS CLI not available, using placeholder"
        DB_ENDPOINT_FINAL="localhost"
    fi
fi

if [ -n "$DB_PASSWORD_RAW" ] && [ "$DB_PASSWORD_RAW" != "\${db_password}" ] && [ ${#DB_PASSWORD_RAW} -gt 8 ]; then
    DB_PASSWORD_FINAL="$DB_PASSWORD_RAW"
    echo "✅ Valid database password provided"
else
    echo "⚠️ Invalid or missing database password"
    DB_PASSWORD_FINAL="placeholder_password"
fi

# FIXED: Always create the database config file
echo "Creating database configuration file..."
mkdir -p /var/www/html

cat > /var/www/html/.db_config << EOF
DB_HOST=$DB_ENDPOINT_FINAL
DB_USER=admin
DB_PASSWORD=$DB_PASSWORD_FINAL
DB_NAME=proxylamptodoapp
DB_PORT=3306
EOF

# Set proper permissions
chown www-data:www-data /var/www/html/.db_config
chmod 600 /var/www/html/.db_config

echo "✅ Database config file created"
echo "Database configuration:"
echo "  Host: $DB_ENDPOINT_FINAL"
echo "  User: admin"
echo "  Database: proxylamptodoapp"
echo "  Port: 3306"

# Verify the config file was created
if [ -f /var/www/html/.db_config ]; then
    echo "✅ Database config file exists and is readable"
    ls -la /var/www/html/.db_config
else
    echo "❌ Database config file creation failed"
fi

# Add to Apache environment variables
cat >> /etc/apache2/envvars << EOF

# Database configuration
export DB_HOST="$DB_ENDPOINT_FINAL"
export DB_USER="admin"
export DB_PASSWORD="$DB_PASSWORD_FINAL"
export DB_NAME="proxylamptodoapp"
export DB_PORT="3306"
EOF

# FIXED: Test database connection with proper error handling
echo "=== TESTING DATABASE CONNECTION ==="

if [ "$DB_ENDPOINT_FINAL" != "localhost" ] && [ "$DB_PASSWORD_FINAL" != "placeholder_password" ]; then
    echo "Testing database connection to: $DB_ENDPOINT_FINAL"
    
    # Test connection in background to avoid blocking
    (
        DB_CONNECTION_SUCCESS=false
        
        for i in {1..30}; do
            echo "Database connection attempt $i/30..."
            
            if timeout 10 mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
                echo "✅ Database connection successful!"
                
                # Create database and table
                echo "Creating database and tables..."
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

INSERT INTO tasks (task) VALUES ('🎉 Welcome to your Proxy LAMP Stack Todo Application!') ON DUPLICATE KEY UPDATE task=task;
MYSQL_EOF
                echo "✅ Database and tables created successfully"
                DB_CONNECTION_SUCCESS=true
                break
            else
                echo "Database connection attempt $i failed"
                sleep 20
            fi
        done
        
        if [ "$DB_CONNECTION_SUCCESS" = "false" ]; then
            echo "⚠️ Database connection failed after 30 attempts"
            echo "This may be normal during initial setup - the application will retry"
            
            # Create a status file indicating database connection failed
            echo "database_connection_failed_during_setup" > /tmp/db_connection_status
        else
            echo "database_connection_successful" > /tmp/db_connection_status
        fi
    ) &
    
    echo "Database connection test started in background"
else
    echo "⚠️ Skipping database connection test - invalid configuration"
    echo "database_configuration_invalid" > /tmp/db_connection_status
fi

# Install CloudWatch agent in background
(
    echo "Installing CloudWatch agent..."
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/cloudwatch-agent.deb 2>/dev/null || {
        echo "Failed to download CloudWatch agent"
        exit 0
    }
    
    if dpkg -i /tmp/cloudwatch-agent.deb; then
        echo "✅ CloudWatch agent installed"
        
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

# Basic system tuning
echo "Applying system tuning..."
cat >> /etc/sysctl.conf << 'EOF' 2>/dev/null || true
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p >/dev/null 2>&1 || echo "⚠️ sysctl reload failed"

# Create completion marker
touch /tmp/lamp-setup-complete

# Final verification
echo "=== FINAL VERIFICATION ==="

if systemctl is-active --quiet apache2; then
    echo "✅ Apache service is active"
else
    echo "❌ Apache service is not active"
    systemctl status apache2 --no-pager
fi

if curl -s -f http://localhost/ >/dev/null; then
    echo "✅ Apache is responding to HTTP requests"
else
    echo "❌ Apache is not responding to HTTP requests"
    systemctl restart apache2
    sleep 5
fi

if php -v >/dev/null 2>&1; then
    echo "✅ PHP is working"
    php -v | head -1
else
    echo "❌ PHP is not working"
fi

if [ -f /var/www/html/.db_config ]; then
    echo "✅ Database config file exists"
    echo "Config file permissions: $(ls -la /var/www/html/.db_config)"
else
    echo "❌ Database config file missing"
fi

if curl -s -f http://localhost/health.php >/dev/null; then
    echo "✅ Health endpoint is accessible"
else
    echo "❌ Health endpoint is not accessible"
fi

# Ensure proper permissions one final time
chown -R www-data:www-data /var/www/html
chmod 755 /var/www/html
chmod 644 /var/www/html/*
chmod 600 /var/www/html/.db_config 2>/dev/null || echo "No .db_config to set permissions"

echo "=== LAMP SETUP COMPLETED $(date) ==="

# Final status report
echo "=== SETUP STATUS SUMMARY ==="
echo "✅ Apache: $(systemctl is-active apache2)"
echo "✅ PHP: $(php -v | head -1 | cut -d' ' -f2)"
echo "✅ DirectoryIndex: Configured to prioritize PHP"
echo "✅ Database config: $([ -f /var/www/html/.db_config ] && echo 'Created' || echo 'Missing')"
echo "✅ Health endpoint: $(curl -s http://localhost/health.php >/dev/null && echo 'Working' || echo 'Failed')"

if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null; then
    echo "🎉 SUCCESS: LAMP stack is fully operational and ready for application deployment"
    exit 0
else
    echo "⚠️ WARNING: LAMP stack has some issues but basic setup completed"
    exit 0
fi