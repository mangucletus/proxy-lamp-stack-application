<?php
// Include the database configuration file to establish a connection
include 'config.php';

// Get server information for load balancer display
$server_name = gethostname();
$server_ip = $_SERVER['SERVER_ADDR'] ?? 'unknown';
$load_balancer_info = !empty($_SERVER['HTTP_X_FORWARDED_FOR']) ? $_SERVER['HTTP_X_FORWARDED_FOR'] : 'Direct';

// Prepare an SQL query to fetch all tasks from the 'tasks' table
// The tasks are ordered by 'created_at' in descending order (most recent first)
$sql = "SELECT * FROM tasks ORDER BY created_at DESC";

// Execute the query and store the result
$result = $conn->query($sql);

// Get task statistics for dashboard
$stats_sql = "SELECT 
    COUNT(*) as total_tasks,
    COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_tasks,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_tasks,
    DATE(MAX(created_at)) as last_activity
    FROM tasks";
$stats_result = $conn->query($stats_sql);
$stats = $stats_result->fetch_assoc();

// Handle success/error messages from URL parameters
$message = '';
$message_type = '';

if (isset($_GET['success']) && $_GET['success'] == '1') {
    $message = 'Task added successfully!';
    $message_type = 'success';
} elseif (isset($_GET['deleted']) && $_GET['deleted'] == '1') {
    $message = 'Task deleted successfully!';
    $message_type = 'success';
} elseif (isset($_GET['error'])) {
    switch($_GET['error']) {
        case '1':
            $message = 'Failed to add task. Please try again.';
            break;
        case '2':
            $message = 'Invalid request. Please fill in the task field.';
            break;
        case '3':
            $message = 'Failed to delete task. Please try again.';
            break;
        case '4':
            $message = 'Invalid task ID. Please try again.';
            break;
        default:
            $message = 'An error occurred. Please try again.';
    }
    $message_type = 'error';
}
?>

<!-- Start of the HTML document -->
<!DOCTYPE html>
<html lang="en">
<head>
    <!-- Basic HTML document setup -->
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="High-availability LAMP Stack To-Do Application with Load Balancer">
    <meta name="keywords" content="LAMP, Load Balancer, AWS, Terraform, Auto Scaling">
    <meta name="author" content="Proxy LAMP Stack">
    
    <title>Proxy LAMP Stack To-Do App</title>

    <!-- Link to external stylesheet -->
    <link rel="stylesheet" href="styles.css">
    
    <!-- Favicon -->
    <link rel="icon" type="image/x-icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📋</text></svg>">
</head>
<body>
    <div class="container">
        <!-- Page header with title and description -->
        <header>
            <h2>Proxy LAMP Stack To-Do Application</h2>
            <p>High-Availability LAMP Stack with Load Balancer, Auto-Scaling, RDS MySQL, and Comprehensive Monitoring on AWS</p>
        </header>

        <!-- Display success/error messages -->
        <?php if (!empty($message)): ?>
            <div class="message <?php echo $message_type; ?>">
                <?php echo htmlspecialchars($message); ?>
            </div>
        <?php endif; ?>

        <!-- Dashboard with statistics -->
        <div class="dashboard">
            <div class="stat-card">
                <div class="stat-number"><?php echo $stats['total_tasks'] ?? 0; ?></div>
                <div class="stat-label">Total Tasks</div>
            </div>
            <div class="stat-card">
                <div class="stat-number"><?php echo $stats['pending_tasks'] ?? 0; ?></div>
                <div class="stat-label">Pending</div>
            </div>
            <div class="stat-card">
                <div class="stat-number"><?php echo $stats['completed_tasks'] ?? 0; ?></div>
                <div class="stat-label">Completed</div>
            </div>
            <div class="stat-card">
                <div class="stat-number"><?php echo $stats['last_activity'] ? date('M j', strtotime($stats['last_activity'])) : 'Never'; ?></div>
                <div class="stat-label">Last Activity</div>
            </div>
        </div>

        <!-- Form to add a new task -->
        <div class="add-task-form">
            <h3>➕ Add New Task</h3>
            <form action="add.php" method="POST" id="taskForm">
                <!-- Input field for the task description -->
                <input type="text" 
                       name="task" 
                       id="taskInput"
                       placeholder="Enter a new task..." 
                       required 
                       maxlength="255"
                       autocomplete="off">
                
                <!-- Submit button to send the task to add.php -->
                <button type="submit" id="submitBtn">
                    <span class="btn-text">Add Task</span>
                    <span class="btn-loading" style="display: none;">Adding...</span>
                </button>
            </form>
        </div>

        <!-- Section to display tasks -->
        <div class="tasks-container">
            <div class="section-header">
                <h2>📋 Your Tasks</h2>
                <?php if ($result->num_rows > 0): ?>
                    <div class="task-count"><?php echo $result->num_rows; ?> task<?php echo $result->num_rows !== 1 ? 's' : ''; ?></div>
                <?php endif; ?>
            </div>
            
            <?php if ($result->num_rows > 0): ?>
                <!-- If there are tasks, loop through each one and display -->
                <ul class="task-list">
                    <?php while($row = $result->fetch_assoc()): ?>
                        <li class="task-item" data-task-id="<?php echo $row['id']; ?>">
                            <div class="task-content">
                                <div class="task-header">
                                    <!-- Sanitize and display the task text -->
                                    <span class="task-text" title="<?php echo htmlspecialchars($row['task']); ?>">
                                        <?php echo htmlspecialchars($row['task']); ?>
                                    </span>
                                    
                                    <!-- Task status badge -->
                                    <span class="task-status <?php echo $row['status'] ?? 'pending'; ?>">
                                        <?php echo ucfirst($row['status'] ?? 'pending'); ?>
                                    </span>
                                </div>
                                
                                <!-- Display formatted creation date of the task -->
                                <div class="task-meta">
                                    <small class="task-date">
                                        📅 Added: <?php echo date('M j, Y g:i A', strtotime($row['created_at'])); ?>
                                    </small>
                                    
                                    <?php if (!empty($row['updated_at']) && $row['updated_at'] !== $row['created_at']): ?>
                                        <small class="task-updated">
                                            🔄 Updated: <?php echo date('M j, Y g:i A', strtotime($row['updated_at'])); ?>
                                        </small>
                                    <?php endif; ?>
                                </div>
                            </div>
                            
                            <div class="task-actions">
                                <!-- Delete button, links to delete.php with task ID as parameter -->
                                <a href="delete.php?id=<?php echo $row['id']; ?>" 
                                   class="delete-btn" 
                                   onclick="return confirmDelete('<?php echo htmlspecialchars($row['task'], ENT_QUOTES); ?>')"
                                   title="Delete this task">
                                    🗑️ Delete
                                </a>
                            </div>
                        </li>
                    <?php endwhile; ?>
                </ul>
            <?php else: ?>
                <!-- Message to show when there are no tasks -->
                <div class="no-tasks">
                    <div class="no-tasks-icon">📝</div>
                    <h3>No tasks yet!</h3>
                    <p>Add your first task above to get started!</p>
                </div>
            <?php endif; ?>
        </div>

        <!-- Footer with deployment note -->
        <footer>
            <div class="footer-content">
                <div class="deployment-info">
                    <p>Deployed on AWS with Terraform Infrastructure as Code</p>
                    <p>CI/CD Pipeline powered by GitHub Actions</p>
                </div>
                <div class="footer-links">
                    <a href="health.php" target="_blank" title="System Health Check">🔍 Health Check</a>
                    <span class="separator">|</span>
                    <a href="https://github.com/mangucletus/proxy-lamp-stack-application" target="_blank" title="View Source Code">📦 Source Code</a>
                </div>
            </div>
        </footer>
    </div>

    <!-- JavaScript for enhanced functionality -->
    <script>
        // Enhanced form submission with loading state
        document.getElementById('taskForm').addEventListener('submit', function(e) {
            const submitBtn = document.getElementById('submitBtn');
            const btnText = submitBtn.querySelector('.btn-text');
            const btnLoading = submitBtn.querySelector('.btn-loading');
            
            // Show loading state
            btnText.style.display = 'none';
            btnLoading.style.display = 'inline';
            submitBtn.disabled = true;
            
            // Re-enable after 3 seconds to prevent stuck state
            setTimeout(() => {
                btnText.style.display = 'inline';
                btnLoading.style.display = 'none';
                submitBtn.disabled = false;
            }, 3000);
        });

        // Enhanced delete confirmation
        function confirmDelete(taskText) {
            const shortText = taskText.length > 50 ? taskText.substring(0, 50) + '...' : taskText;
            return confirm(`Are you sure you want to delete this task?\n\n"${shortText}"\n\nThis action cannot be undone.`);
        }

        // Auto-hide messages after 5 seconds
        const message = document.querySelector('.message');
        if (message) {
            setTimeout(() => {
                message.style.opacity = '0';
                setTimeout(() => {
                    message.style.display = 'none';
                }, 300);
            }, 5000);
        }

        // Health indicator animation
        const healthIndicator = document.querySelector('.health-indicator');
        if (healthIndicator) {
            setInterval(() => {
                healthIndicator.style.opacity = '0.5';
                setTimeout(() => {
                    healthIndicator.style.opacity = '1';
                }, 200);
            }, 3000);
        }

        // Auto-refresh task count every 30 seconds (optional)
        if (window.location.search.includes('auto-refresh')) {
            setInterval(() => {
                fetch('health.php')
                    .then(response => response.json())
                    .then(data => {
                        if (data.checks && data.checks.application && data.checks.application.total_tasks !== undefined) {
                            const taskCountElement = document.querySelector('.metrics-bar .metric-value:last-child');
                            if (taskCountElement) {
                                taskCountElement.textContent = data.checks.application.total_tasks;
                            }
                        }
                    })
                    .catch(error => console.log('Auto-refresh error:', error));
            }, 30000);
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', function(e) {
            // Ctrl/Cmd + Enter to submit form
            if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
                const taskInput = document.getElementById('taskInput');
                if (taskInput === document.activeElement && taskInput.value.trim()) {
                    document.getElementById('taskForm').submit();
                }
            }
            
            // Focus on input with 'n' key (like GitHub)
            if (e.key === 'n' && !e.ctrlKey && !e.metaKey && e.target.tagName !== 'INPUT') {
                e.preventDefault();
                document.getElementById('taskInput').focus();
            }
        });

        // Show keyboard shortcuts hint
        document.getElementById('taskInput').addEventListener('focus', function() {
            if (!this.dataset.hintShown) {
                console.log('💡 Tip: Press Ctrl+Enter to quickly add tasks, or press "n" to focus on this input field');
                this.dataset.hintShown = 'true';
            }
        });
    </script>
</body>
</html>

<?php
// Close the database connection to free up resources
$conn->close();
?>