#!/bin/bash
# Compact EC2 User Data Script for Proxy LAMP Stack
set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== STARTING LAMP SETUP $(date) ==="

# Update packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install core packages
apt-get install -y apache2 php php-mysql libapache2-mod-php php-cli php-common php-mbstring php-xml php-curl php-json php-zip mysql-client-core-8.0 awscli htop curl jq

# Download and install CloudWatch agent
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Start Apache immediately
systemctl enable apache2
systemctl start apache2
sleep 3

# Create basic index page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Loading</title><meta http-equiv="refresh" content="30">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Loading</h1><p>✅ Apache: Running</p><p>⏳ Application: Loading</p><p>Server: HOSTNAME</p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure Apache for load balancer
a2enmod rewrite headers ssl
cat > /etc/apache2/conf-available/load-balancer.conf << 'EOF'
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy 10.0.0.0/16
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
EOF
a2enconf load-balancer
systemctl restart apache2
sleep 3

# Create health endpoint
cat > /var/www/html/health.php << 'EOF'
<?php
header('Content-Type: application/json');
echo json_encode(['status'=>'healthy','timestamp'=>date('c'),'server'=>gethostname(),'services'=>['apache'=>'running','php'=>'running']]);
?>
EOF
chown www-data:www-data /var/www/html/health.php

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "eu-central-1")

# Function to get tag value
get_tag_value() {
    aws ec2 describe-tags --region "$REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$1" --query 'Tags[0].Value' --output text 2>/dev/null || echo ""
}

# Get database info from tags or ASG
DB_ENDPOINT=$(get_tag_value "DatabaseEndpoint")
DB_PASSWORD_TAG=$(get_tag_value "DatabasePassword")

if [ -z "$DB_ENDPOINT" ]; then
    ASG_NAME=$(aws autoscaling describe-auto-scaling-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query 'AutoScalingInstances[0].AutoScalingGroupName' --output text 2>/dev/null || echo "")
    if [ -n "$ASG_NAME" ]; then
        DB_ENDPOINT=$(aws autoscaling describe-tags --region "$REGION" --filters "Name=auto-scaling-group,Values=$ASG_NAME" "Name=key,Values=DatabaseEndpoint" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
        DB_PASSWORD_TAG=$(aws autoscaling describe-tags --region "$REGION" --filters "Name=auto-scaling-group,Values=$ASG_NAME" "Name=key,Values=DatabasePassword" --query 'Tags[0].Value' --output text 2>/dev/null || echo "")
    fi
fi

# Use template variables or fallback
DB_ENDPOINT_FINAL="${db_endpoint}"
DB_PASSWORD_FINAL="${db_password}"

if [ -z "$DB_ENDPOINT_FINAL" ] || [ "$DB_ENDPOINT_FINAL" = "proxy-lamp-mysql-endpoint" ]; then
    DB_ENDPOINT_FINAL="$DB_ENDPOINT"
fi
if [ -z "$DB_PASSWORD_FINAL" ] || [ "$DB_PASSWORD_FINAL" = "ProxySecurePass123!" ]; then
    DB_PASSWORD_FINAL="$DB_PASSWORD_TAG"
fi

DB_ENDPOINT_FINAL="$${DB_ENDPOINT_FINAL:-proxy-lamp-mysql-endpoint}"
DB_PASSWORD_FINAL="$${DB_PASSWORD_FINAL:-ProxySecurePass123!}"

# Create database config
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

# Test database connection and create table
if [ -n "$DB_ENDPOINT_FINAL" ] && [ "$DB_ENDPOINT_FINAL" != "proxy-lamp-mysql-endpoint" ]; then
    for i in {1..30}; do
        if mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" -e "SELECT 1;" >/dev/null 2>&1; then
            mysql -h "$DB_ENDPOINT_FINAL" -u admin -p"$DB_PASSWORD_FINAL" << 'MYSQL_EOF'
CREATE DATABASE IF NOT EXISTS proxylamptodoapp;
USE proxylamptodoapp;
CREATE TABLE IF NOT EXISTS tasks (id INT AUTO_INCREMENT PRIMARY KEY,task VARCHAR(255) NOT NULL,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,status ENUM('pending','completed') DEFAULT 'pending',INDEX idx_created_at (created_at),INDEX idx_status (status)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
MYSQL_EOF
            break
        else
            sleep 20
        fi
    done
fi

# Update status page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>LAMP Ready</title><meta http-equiv="refresh" content="60">
<style>body{font-family:Arial;margin:40px;background:#f5f5f5}.container{background:white;padding:30px;border-radius:10px}</style>
</head><body><div class="container"><h1>🚀 LAMP Stack Ready</h1><p>✅ Apache: Running</p><p>✅ PHP: Running</p><p>⏳ Application: Loading</p><p>Server: HOSTNAME</p><p><a href="/health.php">Health Check</a></p></div></body></html>
EOF
sed -i "s/HOSTNAME/$(hostname)/g" /var/www/html/index.html

# Configure CloudWatch agent
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{"metrics":{"namespace":"ProxyLAMP/Application","metrics_collected":{"cpu":{"measurement":["cpu_usage_idle","cpu_usage_user","cpu_usage_system"],"metrics_collection_interval":60},"disk":{"measurement":["used_percent"],"metrics_collection_interval":60,"resources":["*"]},"mem":{"measurement":["mem_used_percent"],"metrics_collection_interval":60}}},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/apache2/access.log","log_group_name":"/aws/ec2/proxy-lamp/apache/access","log_stream_name":"{instance_id}/apache-access.log"},{"file_path":"/var/log/apache2/error.log","log_group_name":"/aws/ec2/proxy-lamp/apache/error","log_stream_name":"{instance_id}/apache-error.log"}]}}}}
EOF

# Create custom metrics script
cat > /usr/local/bin/custom-metrics.sh << 'EOF'
#!/bin/bash
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
APACHE_CONNECTIONS=$(netstat -an | grep :80 | grep ESTABLISHED | wc -l)
aws cloudwatch put-metric-data --region $REGION --namespace "ProxyLAMP/Application" --metric-data MetricName=ApacheConnections,Value=$APACHE_CONNECTIONS,Unit=Count,Dimensions=InstanceId=$INSTANCE_ID
EOF
chmod +x /usr/local/bin/custom-metrics.sh

# Basic system tuning
cat >> /etc/sysctl.conf << 'EOF'
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p

# Enable Apache status
a2enmod status
echo "ExtendedStatus On" >> /etc/apache2/apache2.conf
cat > /etc/apache2/conf-available/server-status.conf << 'EOF'
<Location "/server-status">
SetHandler server-status
Require local
</Location>
EOF
a2enconf server-status
systemctl restart apache2
sleep 3

# Start CloudWatch agent
sleep 15
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent

# Final checks
if systemctl is-active --quiet apache2 && curl -s -f http://localhost/ >/dev/null; then
    echo "✅ LAMP Stack Ready"
else
    echo "❌ Setup failed"
    exit 1
fi

# Create deployment directory and completion marker
mkdir -p /tmp/app-deployment
chown ubuntu:ubuntu /tmp/app-deployment
touch /tmp/lamp-setup-complete

echo "LAMP Stack installation completed!" >> /var/log/cloud-init-output.log
echo "=== LAMP SETUP COMPLETED $(date) ==="
exit 0