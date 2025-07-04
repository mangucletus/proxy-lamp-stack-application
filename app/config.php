<?php
// ----------------------------------------
// Enhanced Database Configuration and Connection for RDS
// ----------------------------------------

// FIXED: Enhanced error handling and multiple configuration methods
$servername = null;
$username = "admin";
$password = null;
$dbname = "proxylamptodoapp";
$port = 3306;

// Method 1: Get database credentials from environment variables
$servername = getenv('DB_HOST') ?: null;
$username = getenv('DB_USER') ?: "admin";
$password = getenv('DB_PASSWORD') ?: null;
$dbname = getenv('DB_NAME') ?: "proxylamptodoapp";
$port = getenv('DB_PORT') ?: 3306;

error_log("Config.php - Method 1 (Environment): DB_HOST=" . ($servername ?: 'null'));

// Method 2: Try to read from config file created by user data script
if (!$servername || !$password) {
    $config_file = '/var/www/html/.db_config';
    error_log("Config.php - Checking for config file: $config_file");
    
    if (file_exists($config_file)) {
        error_log("Config.php - Config file exists, attempting to read");
        
        // Try multiple parsing methods
        $config_data = null;
        
        // Method 2a: Try parse_ini_file
        try {
            $config_data = parse_ini_file($config_file);
            if ($config_data) {
                error_log("Config.php - Successfully parsed config file with parse_ini_file");
            }
        } catch (Exception $e) {
            error_log("Config.php - parse_ini_file failed: " . $e->getMessage());
        }
        
        // Method 2b: Try manual parsing if parse_ini_file failed
        if (!$config_data) {
            try {
                $config_content = file_get_contents($config_file);
                if ($config_content) {
                    error_log("Config.php - Attempting manual parsing of config file");
                    $lines = explode("\n", $config_content);
                    $config_data = [];
                    
                    foreach ($lines as $line) {
                        $line = trim($line);
                        if (empty($line) || strpos($line, '=') === false) {
                            continue;
                        }
                        
                        list($key, $value) = explode('=', $line, 2);
                        $config_data[trim($key)] = trim($value);
                    }
                    
                    if (!empty($config_data)) {
                        error_log("Config.php - Successfully parsed config file manually");
                    }
                }
            } catch (Exception $e) {
                error_log("Config.php - Manual parsing failed: " . $e->getMessage());
            }
        }
        
        // Apply configuration if we got it
        if ($config_data && is_array($config_data)) {
            $servername = $servername ?: ($config_data['DB_HOST'] ?? null);
            $username = $config_data['DB_USER'] ?? $username;
            $password = $password ?: ($config_data['DB_PASSWORD'] ?? null);
            $dbname = $config_data['DB_NAME'] ?? $dbname;
            $port = $config_data['DB_PORT'] ?? $port;
            
            error_log("Config.php - Applied config from file: DB_HOST=" . ($servername ?: 'null'));
        } else {
            error_log("Config.php - Failed to parse config file or config data is empty");
        }
    } else {
        error_log("Config.php - Config file does not exist: $config_file");
    }
}

// Method 3: Try to get credentials from AWS Secrets Manager or Instance Metadata
if (!$servername || !$password) {
    error_log("Config.php - Attempting to get database config from AWS metadata");
    
    if (function_exists('curl_init')) {
        try {
            // Get instance metadata token
            $token_url = 'http://169.254.169.254/latest/api/token';
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $token_url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
            curl_setopt($ch, CURLOPT_HTTPHEADER, ['X-aws-ec2-metadata-token-ttl-seconds: 21600']);
            curl_setopt($ch, CURLOPT_TIMEOUT, 5);
            $token = curl_exec($ch);
            curl_close($ch);

            if ($token) {
                error_log("Config.php - Got metadata token, attempting to get instance ID");
                
                // Get instance ID
                $instance_id_url = 'http://169.254.169.254/latest/meta-data/instance-id';
                $ch = curl_init();
                curl_setopt($ch, CURLOPT_URL, $instance_id_url);
                curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
                curl_setopt($ch, CURLOPT_HTTPHEADER, ["X-aws-ec2-metadata-token: $token"]);
                curl_setopt($ch, CURLOPT_TIMEOUT, 5);
                $instance_id = curl_exec($ch);
                curl_close($ch);

                if ($instance_id) {
                    error_log("Config.php - Got instance ID: $instance_id");
                    
                    // Try to get database endpoint from instance tags using AWS CLI
                    if (function_exists('shell_exec')) {
                        $db_endpoint_cmd = "aws ec2 describe-tags --filters 'Name=resource-id,Values=$instance_id' 'Name=key,Values=DatabaseEndpoint' --query 'Tags[0].Value' --output text 2>/dev/null";
                        $db_password_cmd = "aws ec2 describe-tags --filters 'Name=resource-id,Values=$instance_id' 'Name=key,Values=DatabasePassword' --query 'Tags[0].Value' --output text 2>/dev/null";
                        
                        $tag_db_endpoint = trim(shell_exec($db_endpoint_cmd) ?? '');
                        $tag_db_password = trim(shell_exec($db_password_cmd) ?? '');
                        
                        if (!empty($tag_db_endpoint) && $tag_db_endpoint !== 'None' && $tag_db_endpoint !== 'null') {
                            $servername = $servername ?: $tag_db_endpoint;
                            error_log("Config.php - Got DB endpoint from tags: $servername");
                        }
                        
                        if (!empty($tag_db_password) && $tag_db_password !== 'None' && $tag_db_password !== 'null') {
                            $password = $password ?: $tag_db_password;
                            error_log("Config.php - Got DB password from tags");
                        }
                    }
                }
            }
        } catch (Exception $e) {
            error_log("Config.php - AWS metadata retrieval failed: " . $e->getMessage());
        }
    }
}

// Method 4: Try to find RDS instances in the region
if (!$servername || $servername === 'localhost') {
    error_log("Config.php - Attempting to discover RDS instances");
    
    if (function_exists('shell_exec')) {
        try {
            // Try to find RDS instances that might be ours
            $rds_cmd = "aws rds describe-db-instances --query 'DBInstances[?DBInstanceStatus==`available`].Endpoint.Address' --output text 2>/dev/null";
            $rds_endpoints = trim(shell_exec($rds_cmd) ?? '');
            
            if (!empty($rds_endpoints) && $rds_endpoints !== 'None') {
                $endpoints = explode("\t", $rds_endpoints);
                if (!empty($endpoints[0])) {
                    $discovered_endpoint = trim($endpoints[0]);
                    if (!empty($discovered_endpoint)) {
                        $servername = $discovered_endpoint;
                        error_log("Config.php - Discovered RDS endpoint: $servername");
                    }
                }
            }
        } catch (Exception $e) {
            error_log("Config.php - RDS discovery failed: " . $e->getMessage());
        }
    }
}

// FIXED: Enhanced validation with better error messages
if (!$servername || empty(trim($servername))) {
    error_log("ERROR: Database host not configured. Servername: " . ($servername ?: 'null'));
    
    // FIXED: Instead of dying immediately, try one more fallback
    $servername = 'localhost';  // Last resort fallback
    error_log("Config.php - Using localhost as final fallback");
}

if (!$password || empty(trim($password))) {
    error_log("ERROR: Database password not configured. Password: " . ($password ? '[SET]' : 'null'));
    
    // FIXED: Instead of dying immediately, set a placeholder
    $password = 'placeholder';
    error_log("Config.php - Using placeholder password");
}

// Final configuration summary
error_log("Config.php - Final configuration: Host=$servername, User=$username, DB=$dbname, Port=$port");

// ----------------------------------------
// Create a connection to the MySQL database with retry logic
// ----------------------------------------

$conn = null;
$max_retries = 3;
$retry_delay = 2; // seconds

for ($retry = 1; $retry <= $max_retries; $retry++) {
    try {
        error_log("Config.php - Connection attempt $retry/$max_retries to $servername:$port");
        
        // Create a new instance of the MySQLi class
        $conn = new mysqli($servername, $username, $password, $dbname, $port);
        
        // Check for connection errors
        if ($conn->connect_error) {
            throw new Exception("Connection failed: " . $conn->connect_error);
        }
        
        // If we get here, connection was successful
        error_log("Config.php - Database connection successful on attempt $retry");
        break;
        
    } catch (Exception $e) {
        error_log("Config.php - Connection attempt $retry failed: " . $e->getMessage());
        
        if ($conn) {
            $conn->close();
            $conn = null;
        }
        
        if ($retry < $max_retries) {
            error_log("Config.php - Retrying in $retry_delay seconds...");
            sleep($retry_delay);
            $retry_delay *= 2; // Exponential backoff
        } else {
            error_log("Config.php - All connection attempts failed");
            
            // FIXED: Provide more helpful error message based on the host
            if ($servername === 'localhost' || $servername === 'placeholder') {
                $error_message = "Database not properly configured. The application is still setting up - please try again in a few minutes.";
            } else {
                $error_message = "Unable to connect to database. The database may still be starting up - please try again in a few minutes.";
            }
            
            die($error_message);
        }
    }
}

// ----------------------------------------
// Set Character Encoding for the Connection
// ----------------------------------------

if ($conn) {
    // Set the connection charset to UTF-8 with full Unicode support (utf8mb4).
    if (!$conn->set_charset("utf8mb4")) {
        error_log("Error loading character set utf8mb4: " . $conn->error);
    }

    // ----------------------------------------
    // Set Connection Timeout and Options
    // ----------------------------------------

    // Set MySQL connection options for better performance and reliability
    if (!$conn->options(MYSQLI_OPT_CONNECT_TIMEOUT, 10)) {
        error_log("Setting MYSQLI_OPT_CONNECT_TIMEOUT failed");
    }

    // Enable automatic reconnection
    if (!$conn->options(MYSQLI_OPT_READ_TIMEOUT, 30)) {
        error_log("Setting MYSQLI_OPT_READ_TIMEOUT failed");
    }

    // ----------------------------------------
    // Initialize Database Schema (if needed)
    // ----------------------------------------

    try {
        // Check if the tasks table exists, create it if it doesn't
        $table_check = $conn->query("SHOW TABLES LIKE 'tasks'");
        if ($table_check && $table_check->num_rows == 0) {
            error_log("Config.php - Tasks table not found, creating it");
            
            $create_table_sql = "
                CREATE TABLE tasks (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    task VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    status ENUM('pending', 'completed') DEFAULT 'pending',
                    INDEX idx_created_at (created_at),
                    INDEX idx_status (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ";
            
            if ($conn->query($create_table_sql)) {
                error_log("Config.php - Tasks table created successfully");
                
                // Insert a welcome task
                $welcome_task = "Welcome to your Proxy LAMP Stack Todo Application! 🎉";
                $insert_stmt = $conn->prepare("INSERT INTO tasks (task) VALUES (?)");
                if ($insert_stmt) {
                    $insert_stmt->bind_param("s", $welcome_task);
                    if ($insert_stmt->execute()) {
                        error_log("Config.php - Welcome task inserted successfully");
                    }
                    $insert_stmt->close();
                }
            } else {
                error_log("Config.php - Error creating tasks table: " . $conn->error);
            }
        } else {
            error_log("Config.php - Tasks table already exists");
        }
    } catch (Exception $e) {
        error_log("Config.php - Error during schema initialization: " . $e->getMessage());
    }
}

// ----------------------------------------
// Database Health Check Function
// ----------------------------------------

function checkDatabaseHealth($connection) {
    if (!$connection) {
        return [
            'status' => 'unhealthy',
            'error' => 'No database connection'
        ];
    }
    
    try {
        $start_time = microtime(true);
        $result = $connection->query("SELECT 1 as health_check, NOW() as current_time");
        $response_time = round((microtime(true) - $start_time) * 1000, 2);
        
        if ($result && $result->num_rows > 0) {
            $row = $result->fetch_assoc();
            return [
                'status' => 'healthy',
                'response_time_ms' => $response_time,
                'server_time' => $row['current_time'],
                'connection_id' => $connection->thread_id
            ];
        } else {
            return [
                'status' => 'unhealthy',
                'error' => 'Query failed',
                'response_time_ms' => $response_time
            ];
        }
    } catch (Exception $e) {
        return [
            'status' => 'unhealthy',
            'error' => $e->getMessage()
        ];
    }
}

// ----------------------------------------
// Connection Pool Management (Basic)
// ----------------------------------------

class DatabaseManager {
    private static $instance = null;
    private $connection;
    
    private function __construct() {
        global $servername, $username, $password, $dbname, $port;
        
        $max_retries = 3;
        $retry_delay = 1;
        
        for ($i = 1; $i <= $max_retries; $i++) {
            try {
                $this->connection = new mysqli($servername, $username, $password, $dbname, $port);
                
                if ($this->connection->connect_error) {
                    throw new Exception("Connection failed: " . $this->connection->connect_error);
                }
                
                $this->connection->set_charset("utf8mb4");
                error_log("DatabaseManager - Connection established on attempt $i");
                break;
                
            } catch (Exception $e) {
                error_log("DatabaseManager - Connection attempt $i failed: " . $e->getMessage());
                
                if ($this->connection) {
                    $this->connection->close();
                    $this->connection = null;
                }
                
                if ($i < $max_retries) {
                    sleep($retry_delay);
                    $retry_delay *= 2;
                } else {
                    throw new Exception("DatabaseManager failed after $max_retries attempts");
                }
            }
        }
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    public function getConnection() {
        // Check if connection is still alive
        if (!$this->connection || !$this->connection->ping()) {
            error_log("DatabaseManager - Connection lost, reconnecting...");
            // Reconnect if connection is lost
            if ($this->connection) {
                $this->connection->close();
            }
            $this->__construct();
        }
        return $this->connection;
    }
    
    public function getHealthStatus() {
        return checkDatabaseHealth($this->connection);
    }
    
    public function closeConnection() {
        if ($this->connection) {
            $this->connection->close();
        }
    }
}

// ----------------------------------------
// Performance Monitoring
// ----------------------------------------

function logDatabaseQuery($query, $execution_time = null) {
    $log_entry = [
        'timestamp' => date('Y-m-d H:i:s'),
        'query' => substr($query, 0, 100), // Log first 100 chars only
        'execution_time' => $execution_time,
        'memory_usage' => memory_get_usage(true)
    ];
    
    // In production, you might want to send this to CloudWatch
    error_log("DB Query: " . json_encode($log_entry));
}

// ----------------------------------------
// Configuration Summary
// ----------------------------------------

// Store connection info for health checks (without sensitive data)
$db_config_info = [
    'host' => $servername,
    'database' => $dbname,
    'port' => $port,
    'charset' => 'utf8mb4',
    'connection_status' => $conn ? ($conn->connect_error ? 'failed' : 'connected') : 'no_connection',
    'server_version' => $conn && !$conn->connect_error ? $conn->server_info : 'unknown',
    'thread_id' => $conn && !$conn->connect_error ? $conn->thread_id : null
];

// ----------------------------------------
// Error Handling and Logging Configuration
// ----------------------------------------

// Set error reporting for database operations
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

// Custom error handler for database operations
function handleDatabaseError($errno, $errstr, $errfile, $errline) {
    $error_info = [
        'error_number' => $errno,
        'error_message' => $errstr,
        'file' => $errfile,
        'line' => $errline,
        'timestamp' => date('Y-m-d H:i:s'),
        'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
        'request_uri' => $_SERVER['REQUEST_URI'] ?? 'unknown'
    ];
    
    error_log("Database Error: " . json_encode($error_info));
    
    // Don't expose internal errors to users
    if (!ini_get('display_errors')) {
        return true;
    }
}

set_error_handler('handleDatabaseError', E_ERROR | E_WARNING);

// Log successful connection for debugging
if ($conn && !$conn->connect_error) {
    error_log("Config.php - Database connection successful - Host: $servername, Database: $dbname");
} else {
    error_log("Config.php - Database connection failed or not established");
}
?>