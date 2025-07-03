#!/bin/bash
# Diagnostic script to fix the Apache/PHP issues

echo "🔍 LAMP Stack Diagnostic and Fix Script"
echo "========================================"

# Check if running as root/sudo
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Function to check Apache status
check_apache() {
    echo "📋 Checking Apache Status..."
    
    if $SUDO systemctl is-active apache2 >/dev/null 2>&1; then
        echo "✅ Apache is running"
        return 0
    else
        echo "❌ Apache is not running"
        echo "Status:"
        $SUDO systemctl status apache2 --no-pager || true
        return 1
    fi
}

# Function to check Apache configuration
check_apache_config() {
    echo "📋 Checking Apache Configuration..."
    
    if $SUDO apache2ctl configtest 2>/dev/null; then
        echo "✅ Apache configuration is valid"
        return 0
    else
        echo "❌ Apache configuration has errors:"
        $SUDO apache2ctl configtest
        return 1
    fi
}

# Function to check PHP syntax
check_php_syntax() {
    echo "📋 Checking PHP Syntax..."
    
    local errors=0
    if [ -d "/var/www/html" ]; then
        for phpfile in /var/www/html/*.php; do
            if [ -f "$phpfile" ]; then
                if ! php -l "$phpfile" >/dev/null 2>&1; then
                    echo "❌ PHP syntax error in $phpfile:"
                    php -l "$phpfile"
                    errors=$((errors + 1))
                else
                    echo "✅ $phpfile syntax OK"
                fi
            fi
        done
    fi
    
    if [ $errors -eq 0 ]; then
        echo "✅ All PHP files have valid syntax"
        return 0
    else
        echo "❌ Found $errors PHP files with syntax errors"
        return 1
    fi
}

# Function to check file permissions
check_permissions() {
    echo "📋 Checking File Permissions..."
    
    if [ -d "/var/www/html" ]; then
        # Check ownership
        local owner=$(stat -c %U /var/www/html)
        local group=$(stat -c %G /var/www/html)
        
        if [ "$owner" = "www-data" ] && [ "$group" = "www-data" ]; then
            echo "✅ Directory ownership is correct (www-data:www-data)"
        else
            echo "❌ Directory ownership is incorrect ($owner:$group), should be www-data:www-data"
            return 1
        fi
        
        # Check permissions
        local perms=$(stat -c %a /var/www/html)
        if [ "$perms" = "755" ]; then
            echo "✅ Directory permissions are correct (755)"
        else
            echo "⚠️ Directory permissions are $perms, recommended is 755"
        fi
        
        # Check PHP file permissions
        for phpfile in /var/www/html/*.php; do
            if [ -f "$phpfile" ]; then
                local file_perms=$(stat -c %a "$phpfile")
                if [ "$file_perms" = "644" ]; then
                    echo "✅ $(basename $phpfile) permissions correct (644)"
                else
                    echo "⚠️ $(basename $phpfile) permissions are $file_perms, recommended is 644"
                fi
            fi
        done
    else
        echo "❌ /var/www/html directory does not exist"
        return 1
    fi
    
    return 0
}

# Function to check database connectivity
check_database() {
    echo "📋 Checking Database Connectivity..."
    
    if [ -f "/var/www/html/config.php" ]; then
        # Try to get database info from config
        local db_host=$(grep -o "DB_HOST=.*" /var/www/html/.db_config 2>/dev/null | cut -d'=' -f2 || echo "")
        local db_user=$(grep -o "DB_USER=.*" /var/www/html/.db_config 2>/dev/null | cut -d'=' -f2 || echo "")
        
        if [ -n "$db_host" ] && [ -n "$db_user" ]; then
            echo "✅ Database configuration found"
            echo "   Host: $db_host"
            echo "   User: $db_user"
        else
            echo "⚠️ Database configuration incomplete or missing"
        fi
    else
        echo "⚠️ config.php not found"
    fi
}

# Function to check logs
check_logs() {
    echo "📋 Checking Error Logs..."
    
    echo "--- Apache Error Log (last 10 lines) ---"
    $SUDO tail -10 /var/log/apache2/error.log 2>/dev/null || echo "No Apache error log found"
    
    echo "--- PHP Error Log (if exists) ---"
    if [ -f "/var/log/php_errors.log" ]; then
        $SUDO tail -10 /var/log/php_errors.log
    else
        echo "No PHP error log found"
    fi
}

# Function to fix common issues
fix_issues() {
    echo "🔧 Attempting to Fix Common Issues..."
    
    # Fix permissions
    echo "Fixing file permissions..."
    $SUDO chown -R www-data:www-data /var/www/html/
    $SUDO chmod -R 755 /var/www/html/
    $SUDO chmod 644 /var/www/html/*.php 2>/dev/null || true
    $SUDO chmod 644 /var/www/html/*.css 2>/dev/null || true
    
    # Remove execute permissions from non-executable files
    $SUDO find /var/www/html/ -name "*.php" -exec chmod 644 {} \;
    $SUDO find /var/www/html/ -name "*.css" -exec chmod 644 {} \;
    
    # Ensure Apache modules are enabled
    echo "Enabling required Apache modules..."
    $SUDO a2enmod rewrite headers ssl 2>/dev/null || true
    
    # Test configuration
    if $SUDO apache2ctl configtest >/dev/null 2>&1; then
        echo "✅ Apache configuration is valid"
        
        # Restart Apache
        echo "Restarting Apache..."
        if $SUDO systemctl restart apache2; then
            echo "✅ Apache restarted successfully"
            
            # Wait and test
            sleep 3
            if curl -s http://localhost/ >/dev/null 2>&1; then
                echo "✅ Apache is responding to HTTP requests"
            else
                echo "❌ Apache is not responding to HTTP requests"
            fi
        else
            echo "❌ Failed to restart Apache"
            $SUDO systemctl status apache2 --no-pager
        fi
    else
        echo "❌ Apache configuration still has errors"
        $SUDO apache2ctl configtest
    fi
}

# Function to create a simple test page
create_test_page() {
    echo "📄 Creating Simple Test Page..."
    
    $SUDO tee /var/www/html/test.php > /dev/null << 'EOF'
<?php
header('Content-Type: text/html; charset=UTF-8');
echo "<h1>Apache PHP Test</h1>";
echo "<p>✅ Apache and PHP are working!</p>";
echo "<p>Server: " . $_SERVER['SERVER_NAME'] . "</p>";
echo "<p>PHP Version: " . PHP_VERSION . "</p>";
echo "<p>Current Time: " . date('Y-m-d H:i:s') . "</p>";

// Test basic functionality
echo "<h2>Basic Tests</h2>";
echo "<p>✅ PHP is executing</p>";

// Test file operations
if (is_writable('/tmp')) {
    echo "<p>✅ File system is writable</p>";
} else {
    echo "<p>❌ File system is not writable</p>";
}

// Test database (if config exists)
if (file_exists('config.php')) {
    echo "<p>✅ config.php exists</p>";
    try {
        @include_once 'config.php';
        if (isset($conn) && $conn instanceof mysqli) {
            if (!$conn->connect_error) {
                echo "<p>✅ Database connection successful</p>";
            } else {
                echo "<p>⚠️ Database connection failed: " . $conn->connect_error . "</p>";
            }
        } else {
            echo "<p>⚠️ Database connection object not found</p>";
        }
    } catch (Exception $e) {
        echo "<p>⚠️ Database configuration error: " . $e->getMessage() . "</p>";
    }
} else {
    echo "<p>⚠️ config.php not found</p>";
}

echo "<h2>Server Information</h2>";
echo "<pre>";
echo "Server Software: " . ($_SERVER['SERVER_SOFTWARE'] ?? 'Unknown') . "\n";
echo "Document Root: " . ($_SERVER['DOCUMENT_ROOT'] ?? 'Unknown') . "\n";
echo "Request URI: " . ($_SERVER['REQUEST_URI'] ?? 'Unknown') . "\n";
echo "</pre>";
?>
EOF

    $SUDO chown www-data:www-data /var/www/html/test.php
    $SUDO chmod 644 /var/www/html/test.php
    
    echo "✅ Test page created at /test.php"
    echo "   Access it at: http://your-server-ip/test.php"
}

# Main execution
main() {
    echo "Starting diagnostic checks..."
    echo ""
    
    # Run checks
    check_apache
    apache_running=$?
    
    check_apache_config
    config_ok=$?
    
    check_php_syntax
    php_ok=$?
    
    check_permissions
    perms_ok=$?
    
    check_database
    
    echo ""
    echo "📊 DIAGNOSTIC SUMMARY"
    echo "===================="
    echo "Apache Running: $([ $apache_running -eq 0 ] && echo "✅ YES" || echo "❌ NO")"
    echo "Apache Config: $([ $config_ok -eq 0 ] && echo "✅ OK" || echo "❌ ERROR")"
    echo "PHP Syntax: $([ $php_ok -eq 0 ] && echo "✅ OK" || echo "❌ ERROR")"
    echo "Permissions: $([ $perms_ok -eq 0 ] && echo "✅ OK" || echo "⚠️ ISSUES")"
    
    echo ""
    if [ $apache_running -ne 0 ] || [ $config_ok -ne 0 ] || [ $php_ok -ne 0 ]; then
        echo "🔧 Issues detected. Would you like to attempt automatic fixes? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fix_issues
        fi
        
        echo ""
        echo "📄 Would you like to create a simple test page? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            create_test_page
        fi
    else
        echo "✅ All basic checks passed!"
        
        # Test HTTP connectivity
        if curl -s http://localhost/ >/dev/null 2>&1; then
            echo "✅ HTTP connectivity working"
        else
            echo "❌ HTTP connectivity not working"
            check_logs
        fi
    fi
    
    echo ""
    echo "🔍 For more detailed information, check the logs:"
    echo "   Apache Error Log: sudo tail -f /var/log/apache2/error.log"
    echo "   Apache Access Log: sudo tail -f /var/log/apache2/access.log"
    echo "   System Log: sudo journalctl -u apache2 -f"
}

# Run main function
main "$@"