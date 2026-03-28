namespace TaskCli.Models

import System
import System.Collections.Generic

// Type alias for task identifiers
type TaskId = int

// Priority levels for tasks
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2
}

// Task status as a discriminated union
union Status {
    Todo
    InProgress
    Done
}

// A task in the task manager
record TaskItem {
    Id: int
    Title: string
    Status: Status
    Priority: Priority
    Tags: List<string>
    DueDate: string
    CreatedAt: DateTime

    func GetStatusIcon(): string {
        return match Status {
            Status.Todo => "○",
            Status.InProgress => "●",
            Status.Done => "✓",
            _ => "?"
        }
    }

    func GetStatusText(): string {
        return match Status {
            Status.Todo => "Todo",
            Status.InProgress => "InProgress",
            Status.Done => "Done",
            _ => "Unknown"
        }
    }

    func GetPriorityText(): string {
        return match Priority {
            Priority.Low => "LOW",
            Priority.Medium => "MEDIUM",
            Priority.High => "HIGH",
            _ => "UNKNOWN"
        }
    }

    func MatchesQuery(query: string): bool {
        lower := query.ToLower()
        if Title.ToLower().Contains(lower) {
            return true
        }
        for tag in Tags {
            if tag.ToLower().Contains(lower) {
                return true
            }
        }
        return false
    }
}

// Result of a task operation
union CommandResult {
    Success { message: string }
    TaskFound { task: TaskItem }
    Error { message: string }
}
