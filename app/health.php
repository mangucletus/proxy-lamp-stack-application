<?php
// ----------------------------------------
// Enhanced Health Check Endpoint for Load Balancer
// ----------------------------------------

// Determine output format - HTML for browsers, JSON for load balancers
$output_html = false;
$user_agent = $_SERVER['HTTP_USER_AGENT'] ?? '';

// Output HTML if:
// 1. Accessed via browser (contains Mozilla, Chrome, Safari, etc.)
// 2. Or if 'format=html' parameter is specified
// 3. Or if 'pretty' or 'debug' parameters are specified
if (strpos($user_agent, 'Mozilla') !== false || 
    isset($_GET['format']) && $_GET['format'] === 'html' ||
    isset($_GET['pretty']) || 
    isset($_GET['debug'])) {
    $output_html = true;
}

// For JSON output, set headers
if (!$output_html) {
    header('Content-Type: application/json');
    header('Cache-Control: no-cache, must-revalidate');
    header('Access-Control-Allow-Origin: *');
}

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

if ($output_html) {
    // HTML Dashboard Output
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>System Health Dashboard</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 20px;
                line-height: 1.6;
            }

            .dashboard {
                max-width: 1200px;
                margin: 0 auto;
                background: rgba(255, 255, 255, 0.95);
                border-radius: 20px;
                box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
                backdrop-filter: blur(10px);
                overflow: hidden;
            }

            .header {
                background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
                color: white;
                padding: 30px;
                text-align: center;
                position: relative;
            }

            .header h1 {
                font-size: 2.5rem;
                margin-bottom: 10px;
                font-weight: 300;
            }

            .overall-status {
                display: inline-block;
                padding: 10px 20px;
                border-radius: 50px;
                font-weight: 600;
                text-transform: uppercase;
                letter-spacing: 1px;
                margin-top: 10px;
            }

            .status-healthy { background: #27ae60; color: white; }
            .status-warning { background: #f39c12; color: white; }
            .status-critical { background: #e74c3c; color: white; }
            .status-degraded { background: #8e44ad; color: white; }

            .timestamp {
                margin-top: 15px;
                opacity: 0.8;
                font-size: 0.9rem;
            }

            .content {
                padding: 30px;
            }

            .metrics-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
                gap: 25px;
                margin-bottom: 30px;
            }

            .metric-card {
                background: white;
                border-radius: 15px;
                padding: 25px;
                box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
                border-left: 5px solid #3498db;
                transition: transform 0.3s ease, box-shadow 0.3s ease;
            }

            .metric-card:hover {
                transform: translateY(-5px);
                box-shadow: 0 15px 40px rgba(0, 0, 0, 0.15);
            }

            .metric-card.healthy { border-left-color: #27ae60; }
            .metric-card.warning { border-left-color: #f39c12; }
            .metric-card.critical { border-left-color: #e74c3c; }

            .metric-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 20px;
            }

            .metric-title {
                font-size: 1.2rem;
                font-weight: 600;
                color: #2c3e50;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .metric-status {
                padding: 5px 12px;
                border-radius: 20px;
                font-size: 0.8rem;
                font-weight: 600;
                text-transform: uppercase;
            }

            .metric-details {
                display: grid;
                gap: 12px;
            }

            .detail-row {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 8px 0;
                border-bottom: 1px solid #ecf0f1;
            }

            .detail-row:last-child {
                border-bottom: none;
            }

            .detail-label {
                font-weight: 500;
                color: #7f8c8d;
                text-transform: capitalize;
            }

            .detail-value {
                font-weight: 600;
                color: #2c3e50;
            }

            .progress-bar {
                width: 100%;
                height: 8px;
                background: #ecf0f1;
                border-radius: 4px;
                overflow: hidden;
                margin-top: 5px;
            }

            .progress-fill {
                height: 100%;
                transition: width 0.3s ease;
                border-radius: 4px;
            }

            .progress-healthy { background: #27ae60; }
            .progress-warning { background: #f39c12; }
            .progress-critical { background: #e74c3c; }

            .file-list {
                display: grid;
                gap: 8px;
                margin-top: 10px;
            }

            .file-item {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 8px 12px;
                background: #f8f9fa;
                border-radius: 8px;
                font-size: 0.9rem;
            }

            .file-status {
                width: 10px;
                height: 10px;
                border-radius: 50%;
                margin-left: 10px;
            }

            .file-healthy { background: #27ae60; }
            .file-missing { background: #e74c3c; }

            .info-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                gap: 25px;
                margin-top: 30px;
            }

            .info-card {
                background: #f8f9fa;
                border-radius: 10px;
                padding: 20px;
                border: 1px solid #e9ecef;
            }

            .info-title {
                font-size: 1.1rem;
                font-weight: 600;
                color: #495057;
                margin-bottom: 15px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }

            .extension-grid {
                display: grid;
                grid-template-columns: repeat(2, 1fr);
                gap: 10px;
                margin-top: 10px;
            }

            .extension-item {
                display: flex;
                align-items: center;
                gap: 8px;
                padding: 5px 0;
            }

            .extension-indicator {
                width: 8px;
                height: 8px;
                border-radius: 50%;
            }

            .refresh-btn {
                position: fixed;
                bottom: 30px;
                right: 30px;
                background: #3498db;
                color: white;
                border: none;
                width: 60px;
                height: 60px;
                border-radius: 50%;
                font-size: 1.2rem;
                cursor: pointer;
                box-shadow: 0 5px 20px rgba(52, 152, 219, 0.3);
                transition: all 0.3s ease;
            }

            .refresh-btn:hover {
                background: #2980b9;
                transform: scale(1.1);
            }

            @media (max-width: 768px) {
                .metrics-grid {
                    grid-template-columns: 1fr;
                }
                
                .header h1 {
                    font-size: 2rem;
                }
                
                .content {
                    padding: 20px;
                }
            }
        </style>
    </head>
    <body>
        <div class="dashboard">
            <div class="header">
                <h1>System Health Dashboard</h1>
                <div class="overall-status status-<?php echo $health['status']; ?>">
                    System Status: <?php echo ucfirst($health['status']); ?>
                </div>
                <div class="timestamp">
                    Last Updated: <?php echo date('F j, Y g:i:s A T', strtotime($health['timestamp'])); ?>
                </div>
                <div class="timestamp">
                    Server: <?php echo $health['server']; ?> | Environment: <?php echo $health['environment']; ?>
                </div>
            </div>

            <div class="content">
                <div class="metrics-grid">
                    <!-- PHP Health -->
                    <div class="metric-card <?php echo $health['checks']['php']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">PHP Runtime</div>
                            <div class="metric-status status-<?php echo $health['checks']['php']['status']; ?>">
                                <?php echo $health['checks']['php']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Version</span>
                                <span class="detail-value"><?php echo $health['checks']['php']['version']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">SAPI</span>
                                <span class="detail-value"><?php echo $health['checks']['php']['sapi']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Memory Usage</span>
                                <span class="detail-value"><?php echo $health['checks']['php']['memory_usage']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Memory Peak</span>
                                <span class="detail-value"><?php echo $health['checks']['php']['memory_peak']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Memory Limit</span>
                                <span class="detail-value"><?php echo $health['checks']['php']['memory_limit']; ?></span>
                            </div>
                        </div>
                        <div class="extension-grid">
                            <?php foreach ($health['checks']['php']['extensions'] as $ext => $loaded): ?>
                                <div class="extension-item">
                                    <div class="extension-indicator <?php echo $loaded ? 'file-healthy' : 'file-missing'; ?>"></div>
                                    <span><?php echo strtoupper($ext); ?></span>
                                </div>
                            <?php endforeach; ?>
                        </div>
                    </div>

                    <!-- Disk Usage -->
                    <div class="metric-card <?php echo $health['checks']['disk']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">Disk Usage</div>
                            <div class="metric-status status-<?php echo $health['checks']['disk']['status']; ?>">
                                <?php echo $health['checks']['disk']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Usage</span>
                                <span class="detail-value"><?php echo $health['checks']['disk']['usage_percent']; ?>%</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill progress-<?php echo $health['checks']['disk']['status']; ?>" 
                                     style="width: <?php echo $health['checks']['disk']['usage_percent']; ?>%"></div>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Free Space</span>
                                <span class="detail-value"><?php echo $health['checks']['disk']['free_space_gb']; ?> GB</span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Total Space</span>
                                <span class="detail-value"><?php echo $health['checks']['disk']['total_space_gb']; ?> GB</span>
                            </div>
                        </div>
                    </div>

                    <!-- System Load -->
                    <?php if (isset($health['checks']['system_load'])): ?>
                    <div class="metric-card <?php echo $health['checks']['system_load']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">System Load</div>
                            <div class="metric-status status-<?php echo $health['checks']['system_load']['status']; ?>">
                                <?php echo $health['checks']['system_load']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">1 Minute</span>
                                <span class="detail-value"><?php echo $health['checks']['system_load']['load_1min']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">5 Minutes</span>
                                <span class="detail-value"><?php echo $health['checks']['system_load']['load_5min']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">15 Minutes</span>
                                <span class="detail-value"><?php echo $health['checks']['system_load']['load_15min']; ?></span>
                            </div>
                        </div>
                    </div>
                    <?php endif; ?>

                    <!-- Database -->
                    <div class="metric-card <?php echo $health['checks']['database']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">Database</div>
                            <div class="metric-status status-<?php echo $health['checks']['database']['status']; ?>">
                                <?php echo $health['checks']['database']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <?php if (isset($health['checks']['database']['response_time_ms'])): ?>
                                <div class="detail-row">
                                    <span class="detail-label">Response Time</span>
                                    <span class="detail-value"><?php echo $health['checks']['database']['response_time_ms']; ?> ms</span>
                                </div>
                                <div class="detail-row">
                                    <span class="detail-label">Server Version</span>
                                    <span class="detail-value"><?php echo $health['checks']['database']['server_version']; ?></span>
                                </div>
                                <div class="detail-row">
                                    <span class="detail-label">Connection ID</span>
                                    <span class="detail-value"><?php echo $health['checks']['database']['connection_id']; ?></span>
                                </div>
                            <?php else: ?>
                                <div class="detail-row">
                                    <span class="detail-label">Status</span>
                                    <span class="detail-value"><?php echo $health['checks']['database']['message'] ?? $health['checks']['database']['error'] ?? 'Unknown'; ?></span>
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>

                    <!-- Application -->
                    <div class="metric-card <?php echo $health['checks']['application']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">Application</div>
                            <div class="metric-status status-<?php echo $health['checks']['application']['status']; ?>">
                                <?php echo $health['checks']['application']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <?php if (isset($health['checks']['application']['total_tasks'])): ?>
                                <div class="detail-row">
                                    <span class="detail-label">Tasks Table</span>
                                    <span class="detail-value"><?php echo $health['checks']['application']['tasks_table']; ?></span>
                                </div>
                                <div class="detail-row">
                                    <span class="detail-label">Total Tasks</span>
                                    <span class="detail-value"><?php echo $health['checks']['application']['total_tasks']; ?></span>
                                </div>
                            <?php else: ?>
                                <div class="detail-row">
                                    <span class="detail-label">Status</span>
                                    <span class="detail-value"><?php echo $health['checks']['application']['message'] ?? $health['checks']['application']['error'] ?? 'Unknown'; ?></span>
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>

                    <!-- File System -->
                    <div class="metric-card <?php echo $health['checks']['filesystem']['status']; ?>">
                        <div class="metric-header">
                            <div class="metric-title">File System</div>
                            <div class="metric-status status-<?php echo $health['checks']['filesystem']['status']; ?>">
                                <?php echo $health['checks']['filesystem']['status']; ?>
                            </div>
                        </div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Writable</span>
                                <span class="detail-value"><?php echo $health['checks']['filesystem']['writable'] ? 'Yes' : 'No'; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Missing Files</span>
                                <span class="detail-value"><?php echo count($health['checks']['filesystem']['missing_files']); ?></span>
                            </div>
                        </div>
                        <div class="file-list">
                            <?php foreach ($health['checks']['filesystem']['file_permissions'] as $file => $info): ?>
                                <div class="file-item">
                                    <span><?php echo $file; ?></span>
                                    <div style="display: flex; align-items: center;">
                                        <?php if ($info['exists']): ?>
                                            <span style="font-size: 0.8rem; margin-right: 8px;">
                                                <?php echo number_format($info['size'] / 1024, 1); ?> KB
                                            </span>
                                        <?php endif; ?>
                                        <div class="file-status <?php echo $info['exists'] ? 'file-healthy' : 'file-missing'; ?>"></div>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        </div>
                    </div>
                </div>

                <!-- Additional Information -->
                <div class="info-grid">
                    <div class="info-card">
                        <div class="info-title">Performance Metrics</div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Response Time</span>
                                <span class="detail-value"><?php echo $health['performance']['response_time_ms']; ?> ms</span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Memory Usage</span>
                                <span class="detail-value"><?php echo $health['performance']['memory_usage_mb']; ?> MB</span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Peak Memory</span>
                                <span class="detail-value"><?php echo $health['performance']['peak_memory_mb']; ?> MB</span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">CPU Time</span>
                                <span class="detail-value"><?php echo $health['performance']['cpu_time_ms']; ?> ms</span>
                            </div>
                        </div>
                    </div>

                    <div class="info-card">
                        <div class="info-title">Server Information</div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Hostname</span>
                                <span class="detail-value"><?php echo $health['instance']['hostname']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Server Software</span>
                                <span class="detail-value"><?php echo $health['instance']['server_software']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Timezone</span>
                                <span class="detail-value"><?php echo $health['instance']['timezone']; ?></span>
                            </div>
                        </div>
                    </div>

                    <div class="info-card">
                        <div class="info-title">Network Information</div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Server Address</span>
                                <span class="detail-value"><?php echo $health['checks']['network']['server_addr']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Server Port</span>
                                <span class="detail-value"><?php echo $health['checks']['network']['server_port']; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Remote Address</span>
                                <span class="detail-value"><?php echo $health['checks']['network']['remote_addr']; ?></span>
                            </div>
                        </div>
                    </div>

                    <div class="info-card">
                        <div class="info-title">Load Balancer</div>
                        <div class="metric-details">
                            <div class="detail-row">
                                <span class="detail-label">Behind Proxy</span>
                                <span class="detail-value"><?php echo $health['load_balancer']['behind_proxy'] ? 'Yes' : 'No'; ?></span>
                            </div>
                            <div class="detail-row">
                                <span class="detail-label">Original Host</span>
                                <span class="detail-value"><?php echo $health['load_balancer']['original_host']; ?></span>
                            </div>
                            <?php if ($health['load_balancer']['forwarded_for']): ?>
                                <div class="detail-row">
                                    <span class="detail-label">Forwarded For</span>
                                    <span class="detail-value"><?php echo $health['load_balancer']['forwarded_for']; ?></span>
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <button class="refresh-btn" onclick="location.reload()" title="Refresh Dashboard">
            ↻
        </button>

        <script>
            // Auto-refresh every 30 seconds
            setTimeout(function() {
                location.reload();
            }, 30000);
            
            // Add smooth animations
            document.addEventListener('DOMContentLoaded', function() {
                const cards = document.querySelectorAll('.metric-card');
                cards.forEach((card, index) => {
                    card.style.opacity = '0';
                    card.style.transform = 'translateY(20px)';
                    setTimeout(() => {
                        card.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
                        card.style.opacity = '1';
                        card.style.transform = 'translateY(0)';
                    }, index * 100);
                });
            });
        </script>
    </body>
    </html>
    <?php
} else {
    // JSON output for load balancers and API consumers
    if (isset($_GET['pretty']) || isset($_GET['debug'])) {
        echo json_encode($health, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    } else {
        echo json_encode($health, JSON_UNESCAPED_SLASHES);
    }
}

// ----------------------------------------
// Clean up resources
// ----------------------------------------

if (isset($conn) && $conn instanceof mysqli) {
    $conn->close();
}

exit();
?>