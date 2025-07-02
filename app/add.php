<?php
// Include the database configuration file which contains connection details
include 'config.php';

// Check if the request method is POST and the 'task' field is not empty
if ($_SERVER["REQUEST_METHOD"] == "POST" && !empty($_POST['task'])) {
    
    // Remove any leading/trailing whitespace from the task input
    $task = trim($_POST['task']);
    
    // Prepare an SQL statement to safely insert the task into the database
    // This helps prevent SQL injection by using placeholders
    $stmt = $conn->prepare("INSERT INTO tasks (task) VALUES (?)");
    
    // Bind the user input ($task) to the placeholder in the SQL statement
    // "s" means the value is a string
    $stmt->bind_param("s", $task);
    
    // Execute the prepared statement
    if ($stmt->execute()) {
        // If successful, redirect back to index.php with a success flag
        header("Location: index.php?success=1");
    } else {
        // If insertion fails, redirect with a general error flag
        header("Location: index.php?error=1");
    }
    
    // Close the prepared statement to free up resources
    $stmt->close();
} else {
    // If request is not POST or task is empty, redirect with a different error code
    header("Location: index.php?error=2");
}

// Close the database connection
$conn->close();

// Exit to ensure no further code is executed after redirection
exit();
?>
