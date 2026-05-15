namespace TaskCli.Services

import System
import System.Collections.Generic
import System.IO
import System.Threading.Tasks
import TaskCli.Models


// Persists tasks to a pipe-delimited file with async I/O
class TaskStore {
    filePath: string

    constructor() {
        dir := Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".taskr")
        if !Directory.Exists(dir) {
            Directory.CreateDirectory(dir)
        }

        filePath = Path.Combine(dir, "tasks.dat")
    }

    // Load all tasks from disk
    async func Load(): Task<List<TaskItem>> {
        if !File.Exists(filePath) {
            return new List<TaskItem>()
        }

        lines := await File.ReadAllLinesAsync(filePath)
        tasks := new List<TaskItem>()

        for line in lines {
            trimmed := line.Trim()
            if trimmed.Length > 0 {
                pipeDelim := "|"
                parts := trimmed.Split(pipeDelim)
                if parts.Length >= 7 {
                    task := ParseLine(parts)
                    tasks.Add(task)
                }
            }
        }

        return tasks
    }

    // Save all tasks to disk
    async func Save(tasks: List<TaskItem>): Task<bool> {
        lines := new List<string>()
        for task in tasks {
            lines.Add(FormatLine(task))
        }

        await File.WriteAllLinesAsync(filePath, lines)
        return true
    }

    // Format a task as a pipe-delimited line
    // Format: Id|Title|Status|Priority|Tags|DueDate|CreatedAt
    func FormatLine(task: TaskItem): string {
        statusStr := StatusToString(task.Status)
        tags := String.Join(",", task.Tags)
        created := task.CreatedAt.ToString("yyyy-MM-ddTHH:mm:ss")
        return $"{task.Id}|{task.Title}|{statusStr}|{(int)task.Priority}|{tags}|{task.DueDate}|{created}"
    }

    // Parse a pipe-delimited line into a TaskItem
    func ParseLine(parts: string[]): TaskItem {
        tags := new List<string>()
        if parts[4].Length > 0 {
            commaDelim := ","
            tagParts := parts[4].Split(commaDelim)
            for tag in tagParts {
                if tag.Trim().Length > 0 {
                    tags.Add(tag.Trim())
                }
            }
        }

        return new TaskItem {
            Id: Int32.Parse(parts[0]),
            Title: parts[1],
            Status: ParseStatus(parts[2]),
            Priority: (Priority)Int32.Parse(parts[3]),
            Tags: tags,
            DueDate: parts[5],
            CreatedAt: DateTime.Parse(parts[6])
        }
    }

    // Convert Status union to string for storage
    static func StatusToString(status: Status): string {
        return match status {
            Status.Todo => "Todo",
            Status.InProgress => "InProgress",
            Status.Done => "Done",
            _ => "Todo"
        }
    }

    // Parse string back to Status union
    static func ParseStatus(s: string): Status {
        if s == "InProgress" {
            return new Status.InProgress {  }
        }

        if s == "Done" {
            return new Status.Done {  }
        }

        return new Status.Todo {  }
    }
}
