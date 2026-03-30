namespace DogfoodProject

import System
import DogfoodProject.Services
import "Services/TaskService"

// Dogfood Project — exercises cross-file refs, unions, records
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

record BatchResult {
    Processed: int
    Skipped: int
    Errors: int
}

func DisplayResult(result: TaskResult) {
    x := match result {
        TaskResult.Success { task } => $"Created: {task}",
        TaskResult.Error { message } => $"Failed: {message}"
    }
    print x
}

func FormatPriority(p: Priority): string {
    return match p {
        Priority.Low => "LOW",
        Priority.Medium => "MED",
        Priority.High => "HIGH",
        Priority.Critical => "CRIT"
    }
}
func Main() {
    service := new TaskService()
    print "=== Task Manager ==="

    // Create several tasks with different priorities
    r1 := service.CreateTask("Write parser", 2)
    DisplayResult(r1)

    r2 := service.CreateTask("Add tests", 1)
    DisplayResult(r2)

    r3 := service.CreateTask("Fix bug #42", 3)
    DisplayResult(r3)

    r4 := service.CreateTask("Update docs", 0)
    DisplayResult(r4)

    r5 := service.CreateTask("Review PR", 1)
    DisplayResult(r5)

    // Show all tasks sorted by priority
    print "\n=== All Tasks ==="
    print $"Showing {service.GetTaskCount()} tasks:"
    allTasks := service.GetAllTasks()
    for task in allTasks {
        print $"  [{task.Priority}] {task.Title} (id={task.Id})"
    }

    // Filter to urgent tasks only (high and critical priority)
    print "\n=== Urgent Tasks ==="
    totalCount := service.GetTaskCount()
    print $"Filtering {totalCount} total tasks for urgency..."
    print $"Looking for High and Critical priority..."

    urgent := service.GetUrgentTasks()
    for task in urgent {
        print $"  !! {task.Title}"
    }

    // Complete some tasks and show progress
    service.CompleteTask(1)
    service.CompleteTask(3)
    print "\nCompleted tasks 1 and 3"

    completed := service.GetCompletedCount()
    print $"Quick check: {completed} done so far"
    // Show summary statistics
    print "\n=== Statistics ==="
    stats := service.GetStats()
    print $"Tasks: {stats.Total}"
    print $"Done:  {stats.Completed}"
    print $"Left:  {stats.Pending}"

    rate := stats.CompletionRate()
    print $"Rate:            {stats.Pending} left, {rate}% done"
    print stats.IsHealthy()
    print stats.Pending
}
