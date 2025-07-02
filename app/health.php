<?php
// ----------------------------------------
// Health Check Endpoint for Load Balancer
// ----------------------------------------

// Set content type to JSON
header('Content-Type: application/json');
header('Cache-Control: no-cache, must-revalidate');

// Start timing the health check
$start_time = microtime(true);

// Initialize health check response
$health = [
    'status' => 'healthy',
    'timestamp' => date('c'),
    'server' => gethostname(),
    'version' => '1.0.0',
    'environment' => 'production',
    'checks' => []
];

// ----------------------------------------
// Basic System Health Checks
// ----------------------------------------

// Check PHP version
$health['checks']['php'] = [
    'status' => 'healthy',
    'version' => PHP_VERSION,
    'memory_limit' => ini_get('memory_limit'),
    'memory_usage' => memory_get_usage(true),
    'memory_peak' => memory_get_peak_usage(true)
];

// Check disk space
$disk_free = disk_free_space('/');
$disk_total = disk_total_space('/');
$disk_usage_percent = $disk_total > 0 ? (($disk_total - $disk_free) / $disk_total) * 100 : 100;

$health['checks']['disk'] = [
    'status' => $disk_usage_percent < 90 ? 'healthy' : ($disk_usage_percent < 95 ? 'warning' : 'critical'),
    'usage_percent' => round($disk_usage_percent, 2),
    'free_space_gb' => round($disk_free / (1024 * 1024 * 1024), 2),
    'total_space_gb' => round($disk_total / (1024 * 1024 * 1024), 2)
];

// ----------------------------------------
// Apache Web Server Health Check
// ----------------------------------------

try {
    // Check if Apache is responding
    $apache_status = 'healthy';
    
    // Try to get Apache server status (if mod_status is enabled)
    $apache_info = [];
    if (function_exists('apache_get_version')) {
        $apache_info['version'] = apache_get_version();
    }
    
    // Check server load if available
    if (function_exists('sys_getloadavg')) {
        $load = sys_getloadavg();
        $apache_info['load_average'] = [
            '1min' => round($load[0], 2),
            '5min' => round($load[1], 2),
            '15min' => round($load[2], 2)
        ];
        
        // Mark as warning if load is high
        if ($load[0] > 2.0) {
            $apache_status = $load[0] > 4.0 ? 'critical' : 'warning';
        }
    }
    
    $health['checks']['apache'] = [
        'status' => $apache_status,
        'info' => $apache_info
    ];
    
} catch (Exception $e) {
    $health['checks']['apache'] = [
        'status' => 'unhealthy',
        'error' => $e->getMessage()
    ];
    $health['status'] = 'unhealthy';
}

// ----------------------------------------
// Database Connection Health Check
// ----------------------------------------

try {
    // Include database configuration
    require_once 'config.php';
    
    $db_start_time = microtime(true);
    
    // Test basic connection
    if ($conn->connect_error) {
        throw new Exception("Connection failed: " . $conn->connect_error);
    }
    
    // Test database query
    $result = $conn->query("SELECT 1 as health_check, NOW() as server_time");
    if (!$result) {
        throw new Exception("Query failed: " . $conn->error);
    }
    
    $row = $result->fetch_assoc();
    $db_response_time = round((microtime(true) - $db_start_time) * 1000, 2);
    
    // Check database performance
    $db_status = 'healthy';
    if ($db_response_time > 1000) {
        $db_status = 'warning'; // Response time > 1 second
    }
    if ($db_response_time > 3000) {
        $db_status = 'critical'; // Response time > 3 seconds
    }
    
    // Get database statistics
    $stats_query = "SHOW GLOBAL STATUS WHERE Variable_name IN ('Connections', 'Queries', 'Uptime', 'Threads_connected')";
    $stats_result = $conn->query($stats_query);
    $db_stats = [];
    
    if ($stats_result) {
        while ($stat_row = $stats_result->fetch_assoc()) {
            $db_stats[$stat_row['Variable_name']] = $stat_row['Value'];
        }
    }
    
    $health['checks']['database'] = [
        'status' => $db_status,
        'response_time_ms' => $db_response_time,
        'server_time' => $row['server_time'],
        'connection_id' => $conn->thread_id,
        'server_version' => $conn->server_info,
        'statistics' => $db_stats
    ];
    
    // Test application table
    $table_check = $conn->query("SELECT COUNT(*) as task_count FROM tasks LIMIT 1");
    if ($table_check) {
        $table_row = $table_check->fetch_assoc();
        $health['checks']['application'] = [
            'status' => 'healthy',
            'tasks_table' => 'accessible',
            'total_tasks' => $table_row['task_count']
        ];
    } else {
        $health['checks']['application'] = [
            'status' => 'warning',
            'tasks_table' => 'not_accessible',
            'error' => $conn->error
        ];
    }
    
} catch (Exception $e) {
    $health['checks']['database'] = [
        'status' => 'unhealthy',
        'error' => $e->getMessage(),
        'response_time_ms' => isset($db_response_time) ? $db_response_time : null
    ];
    $health['status'] = 'unhealthy';
}

// ----------------------------------------
// File System Health Check
// ----------------------------------------

try {
    // Check if we can write to the web directory
    $test_file = '/tmp/health_check_' . time() . '.tmp';
    $write_test = file_put_contents($test_file, 'health check test');
    
    if ($write_test !== false) {
        unlink($test_file); // Clean up test file
        $filesystem_status = 'healthy';
    } else {
        $filesystem_status = 'unhealthy';
    }
    
    $health['checks']['filesystem'] = [
        'status' => $filesystem_status,
        'writable' => $write_test !== false,
        'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? 'unknown'
    ];
    
} catch (Exception $e) {
    $health['checks']['filesystem'] = [
        'status' => 'unhealthy',
        'error' => $e->getMessage()
    ];
}

// ----------------------------------------
// Network Connectivity Check
// ----------------------------------------

try {
    // Check internet connectivity (optional - comment out if not needed)
    $network_status = 'healthy';
    
    // Check if we can resolve DNS
    $dns_check = gethostbyname('aws.amazon.com');
    $can_resolve_dns = $dns_check !== 'aws.amazon.com';
    
    $health['checks']['network'] = [
        'status' => $can_resolve_dns ? 'healthy' : 'warning',
        'dns_resolution' => $can_resolve_dns,
        'server_ip' => $_SERVER['SERVER_ADDR'] ?? 'unknown',
        'client_ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
    ];
    
} catch (Exception $e) {
    $health['checks']['network'] = [
        'status' => 'warning',
        'error' => $e->getMessage()
    ];
}

// ----------------------------------------
// Load Balancer Specific Checks
// ----------------------------------------

// Check for load balancer headers
$lb_headers = [];
$lb_headers['x_forwarded_for'] = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? null;
$lb_headers['x_forwarded_proto'] = $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? null;
$lb_headers['x_forwarded_port'] = $_SERVER['HTTP_X_FORWARDED_PORT'] ?? null;

$health['load_balancer'] = [
    'behind_lb' => !empty($lb_headers['x_forwarded_for']),
    'headers' => $lb_headers,
    'protocol' => $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? $_SERVER['REQUEST_SCHEME'] ?? 'http'
];

// ----------------------------------------
// Calculate Overall Health Status
// ----------------------------------------

$critical_checks = ['database', 'filesystem'];
$warning_checks = ['disk', 'apache'];

foreach ($health['checks'] as $check_name => $check_result) {
    if ($check_result['status'] === 'unhealthy' || $check_result['status'] === 'critical') {
        if (in_array($check_name, $critical_checks)) {
            $health['status'] = 'unhealthy';
            break;
        } else {
            $health['status'] = 'degraded';
        }
    } elseif ($check_result['status'] === 'warning' && $health['status'] === 'healthy') {
        $health['status'] = 'warning';
    }
}

// ----------------------------------------
// Add Performance Metrics
// ----------------------------------------

$end_time = microtime(true);
$health['performance'] = [
    'response_time_ms' => round(($end_time - $start_time) * 1000, 2),
    'memory_usage_mb' => round(memory_get_usage(true) / (1024 * 1024), 2),
    'peak_memory_mb' => round(memory_get_peak_usage(true) / (1024 * 1024), 2)
];

// ----------------------------------------
// Set HTTP Status Code Based on Health
// ----------------------------------------

switch ($health['status']) {
    case 'healthy':
    case 'warning':
        http_response_code(200);
        break;
    case 'degraded':
        http_response_code(200); // Still return 200 for load balancer
        break;
    case 'unhealthy':
        http_response_code(503); // Service Unavailable
        break;
    default:
        http_response_code(500);
}

// ----------------------------------------
// Add Instance Information
// ----------------------------------------

$health['instance'] = [
    'hostname' => gethostname(),
    'server_software' => $_SERVER['SERVER_SOFTWARE'] ?? 'unknown',
    'php_sapi' => php_sapi_name(),
    'request_time' => $_SERVER['REQUEST_TIME'] ?? time(),
    'request_id' => uniqid('req_', true)
];

// ----------------------------------------
// Optional: Add AWS Metadata
// ----------------------------------------

if (function_exists('curl_init')) {
    try {
        // Get instance metadata (with timeout)
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'http://169.254.169.254/latest/meta-data/instance-id');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 2);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 1);
        $instance_id = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        if ($http_code === 200 && $instance_id) {
            $health['aws'] = [
                'instance_id' => $instance_id,
                'metadata_accessible' => true
            ];
        }
    } catch (Exception $e) {
        // Not running on EC2 or metadata service unavailable
        $health['aws'] = [
            'metadata_accessible' => false
        ];
    }
}

// ----------------------------------------
// Output Health Check Response
// ----------------------------------------

// Pretty print JSON in development
if (isset($_GET['pretty']) || $_SERVER['HTTP_USER_AGENT'] ?? '' === 'curl') {
    echo json_encode($health, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
} else {
    echo json_encode($health, JSON_UNESCAPED_SLASHES);
}

// ----------------------------------------
// Clean up resources
// ----------------------------------------

if (isset($conn) && $conn instanceof mysqli) {
    $conn->close();
}

exit();
?>