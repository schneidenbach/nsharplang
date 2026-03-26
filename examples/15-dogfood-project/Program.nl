namespace TaskTracker

import System
import System.Collections.Generic
import TaskTracker.Models
import TaskTracker.Services
import "Models/Task"
import "Services/TaskService"

func PrintTask(task: Task) {
    print task.GetInfo()
    if task.Tags.Count > 0 {
        print $"  Tags: {String.Join(", ", task.Tags)}"
    }
}

func FormatTask(task: Task): string {
    if task.Tags.Count > 0 {
        return task.GetInfo() + "\n  Tags: " + String.Join(", ", task.Tags)
    }
    return task.GetInfo()
}

func DescribeResult(result: TaskResult): string {
    return match result {
        TaskResult.Success { task } => FormatTask(task),
        TaskResult.NotFound { id } => $"Task {id} not found",
        TaskResult.ValidationError { message } => $"Error: {message}",
        _ => "Unknown result"
    }
}

func PrintResult(result: TaskResult) {
    print DescribeResult(result)
}

func Main() {
    service := new TaskService()

    // Create some tasks
    print "=== Creating Tasks ==="
    r1 := service.CreateTask("Build CLI toolchain", "Add nlc query commands", Priority.Critical, "Spencer")
    r2 := service.CreateTask("Write tests", "Add integration tests for query commands", Priority.High, "Spencer")
    r3 := service.CreateTask("Update docs", "Fix stale documentation", Priority.Medium, "Claude")
    r4 := service.CreateTask("Add daemon mode", "Background analysis server", Priority.High, "Spencer")
    r5 := service.CreateTask("", "Bad task with no title", Priority.Low, "Nobody")

    PrintResult(r1)
    PrintResult(r2)
    PrintResult(r3)
    PrintResult(r4)
    PrintResult(r5)

    // Update some statuses
    print "\n=== Updating Status ==="
    service.UpdateStatus(1, Status.Done)
    service.UpdateStatus(2, Status.InProgress)

    // Add tags
    service.AddTag(1, "cli")
    service.AddTag(1, "tooling")
    service.AddTag(2, "testing")

    // Try to find a non-existent task
    print "\n=== Looking Up Tasks ==="
    PrintResult(service.GetTask(1))
    PrintResult(service.GetTask(999))

    // Show urgent tasks
    print "\n=== Urgent Tasks ==="
    urgent := service.GetUrgentTasks()
    for task in urgent {
        PrintTask(task)
    }

    // Show tasks by assignee
    print "\n=== Spencer's Tasks ==="
    spencerTasks := service.GetTasksByAssignee("Spencer")
    for task in spencerTasks {
        PrintTask(task)
    }

    // Show stats
    print "\n=== Statistics ==="
    stats := service.GetStats()
    print $"Total: {stats.Total}"
    print $"Todo: {stats.Todo}"
    print $"In Progress: {stats.InProgress}"
    print $"Done: {stats.Done}"
    print $"Overdue: {stats.Overdue}"
    print $"Completion Rate: {stats.GetCompletionRate()}%"
    print "\nSummary"
    print stats.FormatSummary()
}
