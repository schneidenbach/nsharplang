namespace TaskTracker

import System
import System.Collections.Generic
import TaskTracker.Models
import TaskTracker.Services
import "Models/Task"
import "Services/TaskService"

func PrintTask(task: Task) {
    Console.WriteLine(task.GetInfo())
    if task.Tags.Count > 0 {
        Console.WriteLine($"  Tags: {String.Join(", ", task.Tags)}")
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
    Console.WriteLine(DescribeResult(result))
}

func Main() {
    service := new TaskService()

    // Create some tasks
    Console.WriteLine("=== Creating Tasks ===")
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
    Console.WriteLine("\n=== Updating Status ===")
    service.UpdateStatus(1, Status.Done)
    service.UpdateStatus(2, Status.InProgress)

    // Add tags
    service.AddTag(1, "cli")
    service.AddTag(1, "tooling")
    service.AddTag(2, "testing")

    // Try to find a non-existent task
    Console.WriteLine("\n=== Looking Up Tasks ===")
    PrintResult(service.GetTask(1))
    PrintResult(service.GetTask(999))

    // Show urgent tasks
    Console.WriteLine("\n=== Urgent Tasks ===")
    urgent := service.GetUrgentTasks()
    for task in urgent {
        PrintTask(task)
    }

    // Show tasks by assignee
    Console.WriteLine("\n=== Spencer's Tasks ===")
    spencerTasks := service.GetTasksByAssignee("Spencer")
    for task in spencerTasks {
        PrintTask(task)
    }

    // Show stats
    Console.WriteLine("\n=== Statistics ===")
    stats := service.GetStats()
    Console.WriteLine($"Total: {stats.Total}")
    Console.WriteLine($"Todo: {stats.Todo}")
    Console.WriteLine($"In Progress: {stats.InProgress}")
    Console.WriteLine($"Done: {stats.Done}")
    Console.WriteLine($"Overdue: {stats.Overdue}")
    Console.WriteLine($"Completion Rate: {stats.GetCompletionRate()}%")
    Console.WriteLine("\nSummary")
    Console.WriteLine(stats.FormatSummary())
}
