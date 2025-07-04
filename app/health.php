<?php
// ----------------------------------------
// Enhanced Health Check Endpoint for Load Balancer
// ----------------------------------------

// Set content type to JSON and disable caching
header('Content-Type: application/json');
header('Cache-Control: no-cache, must-revalidate');
header('Access-Control-Allow-Origin: *');

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
// PHP Environment Health Checks
// ----------------------------------------

$health['checks']['php'] = [
    'status' => 'healthy',
    'version' => PHP_VERSION,
    'sapi' => php_sapi_name(),
    'memory_limit' => ini_get('memory_limit'),
    'memory_usage' => round(memory_get_usage(true) / (1024 * 1024), 2) . 'MB',
    'memory_peak' => round(memory_get_peak_usage(true) / (1024 * 1024), 2) . 'MB',
    'max_execution_time' => ini_get('max_execution_time'),
    'extensions' => [
        'mysqli' => extension_loaded('mysqli'),
        'curl' => extension_loaded('curl'),
        'json' => extension_loaded('json'),
        'mbstring' => extension_loaded('mbstring')
    ]
];

// ----------------------------------------
// System Health Checks
// ----------------------------------------

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

// Check system load if available
if (function_exists('sys_getloadavg')) {
    $load = sys_getloadavg();
    $load_status = 'healthy';
    if ($load[0] > 2.0) {
        $load_status = $load[0] > 4.0 ? 'critical' : 'warning';
    }
    
    $health['checks']['system_load'] = [
        'status' => $load_status,
        'load_1min' => round($load[0], 2),
        'load_5min' => round($load[1], 2),
        'load_15min' => round($load[2], 2)
    ];
}

// ----------------------------------------
// Apache Web Server Health Check
// ----------------------------------------

try {
    $apache_status = 'healthy';
    $apache_info = [];
    
    // Get Apache version if available
    if (function_exists('apache_get_version')) {
        $apache_info['version'] = apache_get_version();
    }
    
    // Check if we can determine Apache is running
    if (isset($_SERVER['SERVER_SOFTWARE'])) {
        $apache_info['server_software'] = $_SERVER['SERVER_SOFTWARE'];
    }
    
    // Check request headers for load balancer info
    if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $apache_info['behind_load_balancer'] = true;
        $apache_info['forwarded_for'] = $_SERVER['HTTP_X_FORWARDED_FOR'];
    } else {
        $apache_info['behind_load_balancer'] = false;
    }
    
    $health['checks']['apache'] = [
        'status' => $apache_status,
        'info' => $apache_info
    ];
    
} catch (Exception $e) {
    $health['checks']['apache'] = [
        'status' => 'warning',
        'error' => $e->getMessage()
    ];
}

// ----------------------------------------
// Database Connection Health Check
// ----------------------------------------

$db_config_file = '/var/www/html/.db_config';
$config_file_exists = file_exists('config.php');

if ($config_file_exists) {
    try {
        // Capture output to prevent interference with JSON response
        ob_start();
        $error_level = error_reporting(0);
        
        // Try to include config and test database
        include_once 'config.php';
        
        error_reporting($error_level);
        ob_end_clean();
        
        if (isset($conn) && $conn instanceof mysqli) {
            $db_start_time = microtime(true);
            
            // Test basic connection
            if ($conn->connect_error) {
                throw new Exception("Connection failed: " . $conn->connect_error);
            }
            
            // Test database query with timeout
            $conn->options(MYSQLI_OPT_READ_TIMEOUT, 3);
            $result = $conn->query("SELECT 1 as health_check, NOW() as server_time, VERSION() as db_version");
            
            if (!$result) {
                throw new Exception("Query failed: " . $conn->error);
            }
            
            $row = $result->fetch_assoc();
            $db_response_time = round((microtime(true) - $db_start_time) * 1000, 2);
            
            $db_status = 'healthy';
            if ($db_response_time > 1000) {
                $db_status = 'warning';
            }
            if ($db_response_time > 3000) {
                $db_status = 'critical';
            }
            
            $health['checks']['database'] = [
                'status' => $db_status,
                'response_time_ms' => $db_response_time,
                'server_time' => $row['server_time'],
                'server_version' => $row['db_version'],
                'connection_id' => $conn->thread_id,
                'host_info' => $conn->host_info
            ];
            
            // Test application tables
            try {
                $table_result = $conn->query("SELECT COUNT(*) as task_count FROM tasks LIMIT 1");
                if ($table_result) {
                    $table_row = $table_result->fetch_assoc();
                    $health['checks']['application'] = [
                        'status' => 'healthy',
                        'tasks_table' => 'accessible',
                        'total_tasks' => (int)$table_row['task_count']
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
            throw new Exception("Database connection object not available");
        }
        
    } catch (Exception $e) {
        $health['checks']['database'] = [
            'status' => 'warning',
            'error' => $e->getMessage(),
            'config_file_exists' => $config_file_exists,
            'db_config_file_exists' => file_exists($db_config_file)
        ];
        
        $health['checks']['application'] = [
            'status' => 'warning',
            'error' => 'Database connectivity issues'
        ];
    }
} else {
    $health['checks']['database'] = [
        'status' => 'warning',
        'message' => 'Database configuration file not found',
        'config_file_exists' => false,
        'db_config_file_exists' => file_exists($db_config_file)
    ];
    
    $health['checks']['application'] = [
        'status' => 'warning',
        'message' => 'Application not fully configured'
    ];
}

// ----------------------------------------
// File System Health Check
// ----------------------------------------

try {
    $required_files = ['index.php', 'config.php', 'add.php', 'delete.php', 'styles.css'];
    $missing_files = [];
    $file_permissions = [];
    
    foreach ($required_files as $file) {
        if (file_exists($file)) {
            $file_permissions[$file] = [
                'exists' => true,
                'readable' => is_readable($file),
                'size' => filesize($file)
            ];
        } else {
            $missing_files[] = $file;
            $file_permissions[$file] = ['exists' => false];
        }
    }
    
    // Test write capability
    $test_file = '/tmp/health_check_' . time() . '.tmp';
    $write_test = file_put_contents($test_file, 'health check test');
    
    if ($write_test !== false) {
        unlink($test_file);
        $filesystem_status = empty($missing_files) ? 'healthy' : 'warning';
    } else {
        $filesystem_status = 'critical';
    }
    
    $health['checks']['filesystem'] = [
        'status' => $filesystem_status,
        'writable' => $write_test !== false,
        'missing_files' => $missing_files,
        'file_permissions' => $file_permissions,
        'document_root' => $_SERVER['DOCUMENT_ROOT'] ?? '/var/www/html'
    ];
    
} catch (Exception $e) {
    $health['checks']['filesystem'] = [
        'status' => 'warning',
        'error' => $e->getMessage()
    ];
}

// ----------------------------------------
// Network and Request Health Check
// ----------------------------------------

$health['checks']['network'] = [
    'status' => 'healthy',
    'server_addr' => $_SERVER['SERVER_ADDR'] ?? 'unknown',
    'server_port' => $_SERVER['SERVER_PORT'] ?? 'unknown',
    'request_method' => $_SERVER['REQUEST_METHOD'] ?? 'unknown',
    'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
    'remote_addr' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
    'request_uri' => $_SERVER['REQUEST_URI'] ?? 'unknown'
];

// ----------------------------------------
// Calculate Overall Health Status
// ----------------------------------------

$status_priorities = [
    'critical' => 4,
    'unhealthy' => 3,
    'warning' => 2,
    'degraded' => 1,
    'healthy' => 0
];

$overall_priority = 0;
$overall_status = 'healthy';

foreach ($health['checks'] as $check_name => $check_result) {
    $check_status = $check_result['status'];
    $priority = $status_priorities[$check_status] ?? 0;
    
    if ($priority > $overall_priority) {
        $overall_priority = $priority;
        $overall_status = $check_status;
    }
}

$health['status'] = $overall_status;

// ----------------------------------------
// Add Performance Metrics
// ----------------------------------------

$end_time = microtime(true);
$health['performance'] = [
    'response_time_ms' => round(($end_time - $start_time) * 1000, 2),
    'memory_usage_mb' => round(memory_get_usage(true) / (1024 * 1024), 2),
    'peak_memory_mb' => round(memory_get_peak_usage(true) / (1024 * 1024), 2),
    'cpu_time_ms' => round((microtime(true) - $_SERVER['REQUEST_TIME_FLOAT']) * 1000, 2)
];

// ----------------------------------------
// Set HTTP Status Code Based on Health
// ----------------------------------------

switch ($health['status']) {
    case 'healthy':
        http_response_code(200);
        break;
    case 'warning':
    case 'degraded':
        http_response_code(200); // Still return 200 for load balancer
        break;
    case 'unhealthy':
    case 'critical':
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
    'request_time' => date('c', $_SERVER['REQUEST_TIME']),
    'uptime' => function_exists('sys_getloadavg') ? 'available' : 'unavailable',
    'timezone' => date_default_timezone_get()
];

// ----------------------------------------
// Add Load Balancer Information
// ----------------------------------------

$health['load_balancer'] = [
    'behind_proxy' => !empty($_SERVER['HTTP_X_FORWARDED_FOR']),
    'forwarded_for' => $_SERVER['HTTP_X_FORWARDED_FOR'] ?? null,
    'forwarded_proto' => $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? null,
    'real_ip' => $_SERVER['HTTP_X_REAL_IP'] ?? null,
    'original_host' => $_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? 'unknown'
];

// ----------------------------------------
// Output Health Check Response
// ----------------------------------------

// Pretty print JSON for debugging, minified for production
if (isset($_GET['pretty']) || isset($_GET['debug'])) {
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