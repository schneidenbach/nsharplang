namespace TaskCli.Services

import System
import System.Collections.Generic
import System.Linq
import System.Threading.Tasks
import TaskCli.Models

// Business logic for task management
class TaskService {
    store: TaskStore
    tasks: List<TaskItem>
    nextId: int

    constructor(taskStore: TaskStore) {
        store = taskStore
        tasks = new List<TaskItem>()
        nextId = 1
    }

    // Load tasks from persistent storage
    func async LoadTasks(): Task<bool> {
        tasks = await store.Load()
        // Calculate next available ID
        maxId := 0
        for task in tasks {
            if task.Id > maxId {
                maxId = task.Id
            }
        }
        nextId = maxId + 1
        return await Task.FromResult(true)
    }

    // Save tasks to persistent storage
    func async SaveTasks(): Task<bool> {
        await store.Save(tasks)
        return await Task.FromResult(true)
    }

    // Add a new task
    func AddTask(title: string, priority: Priority, tags: List<string>, dueDate: string): CommandResult {
        if title.Length == 0 {
            return new CommandResult.Error("Title cannot be empty")
        }

        task := new TaskItem {
            Id: nextId,
            Title: title,
            Status: new Status.Todo {},
            Priority: priority,
            Tags: tags,
            DueDate: dueDate,
            CreatedAt: DateTime.Now
        }

        nextId = nextId + 1
        tasks.Add(task)

        priorityText := task.GetPriorityText()
        tagText := ""
        if tags.Count > 0 {
            tagParts := new List<string>()
            for t in tags {
                tagParts.Add($"#{t}")
            }
            tagText = " " + String.Join(" ", tagParts)
        }
        return new CommandResult.Success($"Created task #{task.Id}: {task.Title} [{priorityText}]{tagText}")
    }

    // Mark a task as done
    func MarkDone(id: int): CommandResult {
        index := FindTaskIndex(id)
        if index < 0 {
            return new CommandResult.Error($"Task #{id} not found")
        }

        updated := tasks[index] with { Status: new Status.Done {} }
        tasks[index] = updated
        return new CommandResult.Success($"Completed task #{id}: {updated.Title}")
    }

    // Mark a task as in progress
    func MarkInProgress(id: int): CommandResult {
        index := FindTaskIndex(id)
        if index < 0 {
            return new CommandResult.Error($"Task #{id} not found")
        }

        updated := tasks[index] with { Status: new Status.InProgress {} }
        tasks[index] = updated
        return new CommandResult.Success($"Started task #{id}: {updated.Title}")
    }

    // Delete a task
    func DeleteTask(id: int): CommandResult {
        index := FindTaskIndex(id)
        if index < 0 {
            return new CommandResult.Error($"Task #{id} not found")
        }

        task := tasks[index]
        tasks.RemoveAt(index)
        return new CommandResult.Success($"Deleted task #{id}: {task.Title}")
    }

    // Get all tasks
    func GetTasks(): List<TaskItem> {
        return tasks.ToList()
    }

    // Get filtered tasks
    func GetFilteredTasks(filter: Filter): List<TaskItem> {
        result := tasks.ToList()

        if filter.HasQuery() {
            filtered := new List<TaskItem>()
            for task in result {
                if task.MatchesQuery(filter.Query) {
                    filtered.Add(task)
                }
            }
            result = filtered
        }

        if filter.HasStatus() {
            statusName := filter.StatusName.ToLower()
            filtered := new List<TaskItem>()
            for task in result {
                if task.GetStatusText().ToLower() == statusName {
                    filtered.Add(task)
                }
            }
            result = filtered
        }

        if filter.HasPriority() {
            priorityName := filter.PriorityName.ToLower()
            filtered := new List<TaskItem>()
            for task in result {
                if task.GetPriorityText().ToLower() == priorityName {
                    filtered.Add(task)
                }
            }
            result = filtered
        }

        if filter.HasTag() {
            tag := filter.Tag
            filtered := new List<TaskItem>()
            for task in result {
                if task.Tags.Contains(tag) {
                    filtered.Add(task)
                }
            }
            result = filtered
        }

        return result
    }

    // Search tasks by query string
    func SearchTasks(query: string): List<TaskItem> {
        results := new List<TaskItem>()
        for task in tasks {
            if task.MatchesQuery(query) {
                results.Add(task)
            }
        }
        return results
    }

    // Get task statistics
    func GetStats(): TaskStats {
        todoCount := 0
        inProgressCount := 0
        doneCount := 0

        for task in tasks {
            statusText := task.GetStatusText()
            if statusText == "Todo" {
                todoCount = todoCount + 1
            } else if statusText == "InProgress" {
                inProgressCount = inProgressCount + 1
            } else if statusText == "Done" {
                doneCount = doneCount + 1
            }
        }

        return new TaskStats {
            Total: tasks.Count,
            TodoCount: todoCount,
            InProgressCount: inProgressCount,
            DoneCount: doneCount
        }
    }

    // Get priority breakdown for stats
    func GetPriorityBreakdown(): List<PriorityStats> {
        result := new List<PriorityStats>()

        // High priority
        highTotal := 0
        highDone := 0
        for task in tasks {
            if task.Priority == Priority.High {
                highTotal = highTotal + 1
                if task.GetStatusText() == "Done" {
                    highDone = highDone + 1
                }
            }
        }
        result.Add(new PriorityStats { Name: "HIGH", Total: highTotal, Done: highDone })

        // Medium priority
        medTotal := 0
        medDone := 0
        for task in tasks {
            if task.Priority == Priority.Medium {
                medTotal = medTotal + 1
                if task.GetStatusText() == "Done" {
                    medDone = medDone + 1
                }
            }
        }
        result.Add(new PriorityStats { Name: "MEDIUM", Total: medTotal, Done: medDone })

        // Low priority
        lowTotal := 0
        lowDone := 0
        for task in tasks {
            if task.Priority == Priority.Low {
                lowTotal = lowTotal + 1
                if task.GetStatusText() == "Done" {
                    lowDone = lowDone + 1
                }
            }
        }
        result.Add(new PriorityStats { Name: "LOW", Total: lowTotal, Done: lowDone })

        return result
    }

    // Get tag breakdown for stats
    func GetTagBreakdown(): List<TagStats> {
        tagCounts := new Dictionary<string, int>()
        for task in tasks {
            for tag in task.Tags {
                if tagCounts.ContainsKey(tag) {
                    tagCounts[tag] = tagCounts[tag] + 1
                } else {
                    tagCounts[tag] = 1
                }
            }
        }

        result := new List<TagStats>()
        for kvp in tagCounts {
            result.Add(new TagStats { Name: kvp.Key, Count: kvp.Value })
        }
        return result
    }

    // Find task index by ID, returns -1 if not found
    func FindTaskIndex(id: int): int {
        for i := 0; i < tasks.Count; i++ {
            if tasks[i].Id == id {
                return i
            }
        }
        return -1
    }
}

// Statistics summary
record TaskStats {
    Total: int
    TodoCount: int
    InProgressCount: int
    DoneCount: int
}

// Priority breakdown for stats
record PriorityStats {
    Name: string
    Total: int
    Done: int
}

// Tag breakdown for stats
record TagStats {
    Name: string
    Count: int
}
