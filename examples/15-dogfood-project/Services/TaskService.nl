namespace DogfoodProject.Services

import System
import DogfoodProject

union TaskResult {
    Success { task: string }
    Error { message: string }
}

record Task {
    Id: int
    Title: string
    Priority: int
    IsCompleted: bool
}

class TaskService {
    tasks: List<Task> = []
    nextId: int = 1

    func CreateTask(title: string, priority: int): TaskResult {
        task := new Task {
            Id: nextId,
            Title: title,
            Priority: priority,
            IsCompleted: false
        }
        nextId = nextId + 1
        tasks.Add(task)
        return new TaskResult.Success { task: title }
    }

    func GetAllTasks(): List<Task> {
        return tasks
    }

    func GetTaskCount(): int {
        return tasks.Count
    }

    func GetUrgentTasks(): List<Task> {
        result: List<Task> = []
        for task in tasks {
            if task.Priority >= 2 {
                if !task.IsCompleted {
                    result.Add(task)
                }
            }
        }
        return result
    }

    func CompleteTask(id: int) {
        for task in tasks {
            if task.Id == id {
                task.IsCompleted = true
            }
        }
    }

    func GetCompletedCount(): int {
        count := 0
        for task in tasks {
            if task.IsCompleted {
                count = count + 1
            }
        }
        return count
    }

    func GetPendingCount(): int {
        count := 0
        for task in tasks {
            if !task.IsCompleted {
                count = count + 1
            }
        }
        return count
    }

    func FindTaskById(id: int): Task? {
        for task in tasks {
            if task.Id == id {
                return task
            }
        }
        return null
    }

    func HasPendingTasks(): bool {
        return GetPendingCount() > 0
    }
    func GetStats(): TaskStats {
        total := tasks.Count
        done := 0
        for task in tasks {
            if task.IsCompleted {
                done = done + 1
            }
        }
        pending := total - done
        return new TaskStats {       Total: total, Completed: done, Pending: pending }
    }
}
record TaskStats {
    Total: int
    Completed: int
    Pending: int

    func CompletionRate(): int {
        if Total == 0 {
            return 0
        }
        return ((Completed * 100)) / Total
    }
    func HasTasks(): bool { return Total > 0 }
    func IsHealthy(): bool {
        return ((Completed * 100)) / Total > 50
    }
}
