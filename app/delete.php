<?php
// Include the database configuration file.
// This file is expected to define the database connection variable `$conn`.
include 'config.php';

// Check if the 'id' parameter is provided in the URL (GET request) and is a number
if (isset($_GET['id']) && is_numeric($_GET['id'])) {
    
    // Sanitize and convert the 'id' parameter to an integer for safety
    $id = intval($_GET['id']);
    
    // Prepare an SQL DELETE statement using a placeholder (?) to prevent SQL injection
    $stmt = $conn->prepare("DELETE FROM tasks WHERE id = ?");
    
    // Bind the actual `$id` value to the placeholder in the prepared statement.
    // "i" denotes the type of the parameter as an integer
    $stmt->bind_param("i", $id);
    
    // Execute the prepared SQL statement
    if ($stmt->execute()) {
        // If the deletion was successful, redirect the user back to the index page
        // and add a query parameter to indicate success (`deleted=1`)
        header("Location: index.php?deleted=1");
    } else {
        // If there was an error while executing the statement,
        // redirect to the index page with an error code (`error=3`)
        header("Location: index.php?error=3");
    }

    // Close the prepared statement to free server resources
    $stmt->close();

} else {
    // If the 'id' parameter was missing or not numeric, redirect with an error code (`error=4`)
    header("Location: index.php?error=4");
}

// Close the database connection to release the resource
$conn->close();

// Ensure no further script execution after redirection
exit();
?>
