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
    $health['status'] = 'degraded'; // Don't fail completely for Apache issues
}

// ----------------------------------------
// Database Connection Health Check (NON-BLOCKING)
// ----------------------------------------

try {
    // Try to include database configuration, but don't fail if it doesn't exist
    $db_config_exists = false;
    if (file_exists('config.php')) {
        // Capture any errors from config.php without stopping execution
        ob_start();
        $error_level = error_reporting(0); // Suppress errors temporarily
        
        try {
            include_once 'config.php';
            $db_config_exists = true;
        } catch (Exception $e) {
            // Config file has issues, but don't fail the health check
            error_log("Database config error: " . $e->getMessage());
        }
        
        error_reporting($error_level); // Restore error reporting
        ob_end_clean();
    }
    
    if ($db_config_exists && isset($conn) && $conn instanceof mysqli) {
        $db_start_time = microtime(true);
        
        // Test basic connection
        if ($conn->connect_error) {
            throw new Exception("Connection failed: " . $conn->connect_error);
        }
        
        // Test database query with timeout
        $conn->options(MYSQLI_OPT_READ_TIMEOUT, 5); // 5 second timeout
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
        
        $health['checks']['database'] = [
            'status' => $db_status,
            'response_time_ms' => $db_response_time,
            'server_time' => $row['server_time'],
            'connection_id' => $conn->thread_id,
            'server_version' => $conn->server_info,
        ];
        
        // Test application table (non-blocking)
        try {
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
            $health['checks']['application'] = [
                'status' => 'warning',
                'tasks_table' => 'error',
                'error' => $e->getMessage()
            ];
        }
        
    } else {
        // Database config doesn't exist or is not loaded - this is OK for initial health checks
        $health['checks']['database'] = [
            'status' => 'warning',
            'message' => 'Database configuration not available or not loaded',
            'config_exists' => $db_config_exists
        ];
        
        $health['checks']['application'] = [
            'status' => 'warning',
            'message' => 'Application database not configured yet'
        ];
    }
    
} catch (Exception $e) {
    // Database issues shouldn't fail the entire health check
    $health['checks']['database'] = [
        'status' => 'warning',
        'error' => $e->getMessage()
    ];
    
    $health['checks']['application'] = [
        'status' => 'warning',
        'error' => 'Database connectivity issues'
    ];
    
    // Only mark as degraded, not unhealthy
    if ($health['status'] === 'healthy') {
        $health['status'] = 'warning';
    }
}

// ----------------------------------------
// File System Health Check
// ----------------------------------------

try {
    // Check if we can write to the temp directory
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
        'status' => 'warning',
        'error' => $e->getMessage()
    ];
}

// ----------------------------------------
// Application Files Check
// ----------------------------------------

$required_files = ['index.php', 'config.php'];
$missing_files = [];
$file_status = 'healthy';

foreach ($required_files as $file) {
    if (!file_exists($file)) {
        $missing_files[] = $file;
    }
}

if (!empty($missing_files)) {
    $file_status = 'warning';
}

$health['checks']['application_files'] = [
    'status' => $file_status,
    'required_files' => $required_files,
    'missing_files' => $missing_files,
    'document_root_files' => glob('*.php') ?: []
];

// ----------------------------------------
// Calculate Overall Health Status
// ----------------------------------------

// Only fail if critical systems are down
$critical_checks = ['php', 'filesystem'];
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
// Output Health Check Response
// ----------------------------------------

// Pretty print JSON for debugging
echo json_encode($health, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

// ----------------------------------------
// Clean up resources
// ----------------------------------------

if (isset($conn) && $conn instanceof mysqli) {
    $conn->close();
}

exit();
?>