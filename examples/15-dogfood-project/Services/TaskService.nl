namespace TaskTracker.Services

import System
import System.Collections.Generic
import System.Linq
import TaskTracker.Models
import System.Text
import "../Models/Task"

// Service for managing tasks
class TaskService {
    tasks: List<Task>
    nextId: int

    constructor() {
        tasks = new List<Task>()
        nextId = 1
    }

    // Create a new task
    func CreateTask(title: string, description: string, priority: Priority, assignedTo: string): TaskResult {
        if title == "" {
            return new TaskResult.ValidationError("Title cannot be empty")
        }

        task := new Task {
            Id: nextId,
            Title: title,
            Description: description,
            Priority: priority,
            Status: Status.Todo,
            AssignedTo: assignedTo,
            CreatedAt: DateTime.Now,
            Tags: new List<string>()
        }

        nextId = nextId + 1
        tasks.Add(task)
        return new TaskResult.Success(task)
    }

    // Get a task by ID
    func GetTask(id: int): TaskResult {
        task := tasks.FirstOrDefault(t => t.Id == id)
        if task == null {
            return new TaskResult.NotFound(id)
        }
        return new TaskResult.Success(task)
    }

    // Get all tasks, optionally filtered
    func GetTasks(status: Status?): List<Task> {
        if status != null {
            return tasks.Where(t => t.Status == status).ToList()
        }
        return tasks.ToList()
    }

    // Get tasks by assignee
    func GetTasksByAssignee(name: string): List<Task> {
        return tasks.Where(t => t.AssignedTo == name).ToList()
    }

    // Get high priority tasks that are not done
    func GetUrgentTasks(): List<Task> {
        return tasks.Where(t => (t.Priority == Priority.High || t.Priority == Priority.Critical) && t.Status != Status.Done).ToList()
    }

    // Update task status
    func UpdateStatus(id: int, newStatus: Status): TaskResult {
        task := tasks.FirstOrDefault(t => t.Id == id)
        if task == null {
            return new TaskResult.NotFound(id)
        }

        // Records are immutable, so we create a new one
        updated := task with { Status: newStatus }
        index := tasks.FindIndex(t => t.Id == id)
        tasks[index] = updated
        return new TaskResult.Success(updated)
    }

    // Add a tag to a task
    func AddTag(id: int, tag: string): TaskResult {
        task := tasks.FirstOrDefault(t => t.Id == id)
        if task == null {
            return new TaskResult.NotFound(id)
        }
        task.Tags.Add(tag)
        return new TaskResult.Success(task)
    }

    // Get statistics
    func GetStats(): TaskStats {
        return new TaskStats {
            Total: tasks.Count,
            Todo: tasks.Count(t => t.Status == Status.Todo),
            InProgress: tasks.Count(t => t.Status == Status.InProgress),
            Done: tasks.Count(t => t.Status == Status.Done),
            Overdue: tasks.Count(t => t.IsOverdue())
        }
    }
}

// Statistics summary
record TaskStats {
    Total: int
    Todo: int
    InProgress: int
    Done: int
    Overdue: int

    func FormatSummary(): string {
        summary := new StringBuilder()
        summary.AppendLine($"Total: {Total}")
        summary.AppendLine($"Todo: {Todo}")
        summary.AppendLine($"In Progress: {InProgress}")
        summary.AppendLine($"Done: {Done}")
        summary.AppendLine($"Overdue: {Overdue}")
        summary.Append($"Completion Rate: {GetCompletionRate()}%")
        return summary.ToString()
    }

    func GetCompletionRate(): double {
        if Total == 0 {
            return 0.0
        }
        return (Done * 100.0) / Total
    }
}
