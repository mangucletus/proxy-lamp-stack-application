<?php
// ----------------------------------------
// Database Configuration and Connection for RDS
// ----------------------------------------

// Get database credentials from environment variables or use defaults
$servername = getenv('DB_HOST') ?: "proxy-lamp-mysql-endpoint"; // Will be replaced by deployment script
$username = getenv('DB_USER') ?: "admin";
$password = getenv('DB_PASSWORD') ?: "ProxySecurePass123!";
$dbname = getenv('DB_NAME') ?: "proxylamptodoapp";
$port = getenv('DB_PORT') ?: 3306;

// Alternative: Get credentials from AWS Secrets Manager (more secure)
if (function_exists('curl_init') && !getenv('DB_HOST')) {
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
            // Get region from instance metadata
            $region_url = 'http://169.254.169.254/latest/meta-data/placement/region';
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $region_url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_HTTPHEADER, ["X-aws-ec2-metadata-token: $token"]);
            curl_setopt($ch, CURLOPT_TIMEOUT, 5);
            $region = curl_exec($ch);
            curl_close($ch);

            // Note: In production, you would use AWS SDK to get secrets from Secrets Manager
            // For this demo, we'll use environment variables set by the user data script
        }
    } catch (Exception $e) {
        // Fallback to environment variables if metadata service fails
        error_log("Failed to get AWS metadata: " . $e->getMessage());
    }
}

// ----------------------------------------
// Create a connection to the MySQL database
// ----------------------------------------

// Create a new instance of the MySQLi class using the above credentials.
// This object-oriented method is preferred over the old mysql_* functions.
$conn = new mysqli($servername, $username, $password, $dbname, $port);

// ----------------------------------------
// Check for a successful connection
// ----------------------------------------

// If the connection fails, $conn->connect_error will contain the error message.
// Use die() to immediately terminate the script and display the error.
if ($conn->connect_error) {
    // Log the error for debugging (don't expose to users in production)
    error_log("Database connection failed: " . $conn->connect_error);
    
    // Show user-friendly error message
    die("Database connection failed. Please try again later.");
}

// ----------------------------------------
// Set Character Encoding for the Connection
// ----------------------------------------

// Set the connection charset to UTF-8 with full Unicode support (utf8mb4).
// This ensures that characters like emojis or other special characters
// are stored and retrieved correctly from the database.
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

// Check if the tasks table exists, create it if it doesn't
$table_check = $conn->query("SHOW TABLES LIKE 'tasks'");
if ($table_check->num_rows == 0) {
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
    
    if (!$conn->query($create_table_sql)) {
        error_log("Error creating tasks table: " . $conn->error);
    }
}

// ----------------------------------------
// Database Health Check Function
// ----------------------------------------

function checkDatabaseHealth($connection) {
    try {
        $result = $connection->query("SELECT 1");
        if ($result && $result->num_rows > 0) {
            return [
                'status' => 'healthy',
                'response_time' => null, // You could measure this
                'connection_id' => $connection->thread_id
            ];
        } else {
            return [
                'status' => 'unhealthy',
                'error' => 'Query failed'
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
        $this->connection = new mysqli($servername, $username, $password, $dbname, $port);
        
        if ($this->connection->connect_error) {
            throw new Exception("Database connection failed: " . $this->connection->connect_error);
        }
        
        $this->connection->set_charset("utf8mb4");
    }
    
    public static function getInstance() {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }
    
    public function getConnection() {
        // Check if connection is still alive
        if (!$this->connection->ping()) {
            // Reconnect if connection is lost
            $this->connection->close();
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
    'connection_status' => $conn->connect_error ? 'failed' : 'connected',
    'server_version' => $conn->connect_error ? 'unknown' : $conn->server_info,
    'thread_id' => $conn->connect_error ? null : $conn->thread_id
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
?>