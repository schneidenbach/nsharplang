namespace TaskTracker.Models

import System
import System.Collections.Generic

// Task priority levels
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

// Task status
enum Status {
    Todo = 0,
    InProgress = 1,
    Done = 2,
    Cancelled = 3
}

// A single task in the tracker
record Task {
    Id: int
    Title: string
    Description: string
    Priority: Priority
    Status: Status
    AssignedTo: string
    CreatedAt: DateTime
    Tags: List<string>

    func IsOverdue(): bool {
        return Status != Status.Done && CreatedAt.AddDays(7) < DateTime.Now
    }

    func GetInfo(): string {
        return $"[{Id}] {Title} ({Priority}) - {Status}"
    }
}

// Result type for operations that can fail
union TaskResult {
    Success { task: Task }
    NotFound { id: int }
    ValidationError { message: string }
}
