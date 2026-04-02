namespace TaskCli.Services

import System.Collections.Generic
import System.Text
import TaskCli.Models

// Pretty-print formatting for task output
class Formatter {
    // Print a formatted task table
    static func PrintTaskTable(tasks: List<TaskItem>) {
        if tasks.Count == 0 {
            print "No tasks found."
            return
        }

        // Print header
        print FormatHeader()

        // Print each task
        for task in tasks {
            print FormatTaskRow(task)
        }
    }

    // Format table header
    static func FormatHeader(): string {
        sb := new StringBuilder()
        sb.Append(" #".PadRight(5))
        sb.Append("Status".PadRight(16))
        sb.Append("Priority".PadRight(10))
        sb.Append("Title".PadRight(30))
        sb.Append("Tags".PadRight(15))
        sb.Append("Due")
        return sb.ToString()
    }

    // Format a single task row
    static func FormatTaskRow(task: TaskItem): string {
        sb := new StringBuilder()

        // ID
        idStr := $" {task.Id}"
        sb.Append(idStr.PadRight(5))

        // Status with icon
        statusStr := $"{task.GetStatusIcon()} {task.GetStatusText()}"
        sb.Append(statusStr.PadRight(16))

        // Priority
        sb.Append(task.GetPriorityText().PadRight(10))

        // Title (truncate if too long)
        title := task.Title
        if title.Length > 28 {
            title = title.Substring(0, 25) + "..."
        }
        sb.Append(title.PadRight(30))

        // Tags
        tagStr := FormatTags(task.Tags)
        sb.Append(tagStr.PadRight(15))

        // Due date
        if task.DueDate.Length > 0 {
            sb.Append(task.DueDate)
        } else {
            sb.Append("-")
        }

        return sb.ToString()
    }

    // Format tags as #tag1 #tag2
    static func FormatTags(tags: List<string>): string {
        if tags.Count == 0 {
            return "-"
        }
        sb := new StringBuilder()
        for i := 0; i < tags.Count; i++ {
            if i > 0 {
                sb.Append(" ")
            }
            sb.Append($"#{tags[i]}")
        }
        return sb.ToString()
    }

    // Print a command result with appropriate formatting
    static func PrintResult(result: CommandResult) {
        output := match result {
            CommandResult.Success { message } => message,
            CommandResult.Error { message } => $"Error: {message}",
            _ => "Unknown result"
        }
        print output
    }

    // Print task statistics
    static func PrintStats(stats: TaskStats, priorityBreakdown: List<PriorityStats>, tagBreakdown: List<TagStats>) {
        // Summary line
        print $"Tasks: {stats.Total} total, {stats.DoneCount} done, {stats.InProgressCount} in progress, {stats.TodoCount} todo"

        // Completion percentage
        completion := 0
        if stats.Total > 0 {
            completion = (stats.DoneCount * 100) / stats.Total
        }
        print $"Completion: {completion}%"

        // Priority breakdown
        sb := new StringBuilder()
        sb.Append("By priority: ")
        for i := 0; i < priorityBreakdown.Count; i++ {
            p := priorityBreakdown[i]
            if i > 0 {
                sb.Append(", ")
            }
            sb.Append($"{p.Name}: {p.Done}/{p.Total}")
        }
        print sb.ToString()

        // Tag breakdown
        if tagBreakdown.Count > 0 {
            tagSb := new StringBuilder()
            tagSb.Append("By tag: ")
            for i := 0; i < tagBreakdown.Count; i++ {
                t := tagBreakdown[i]
                if i > 0 {
                    tagSb.Append(", ")
                }
                taskWord := "task"
                if t.Count != 1 {
                    taskWord = "tasks"
                }
                tagSb.Append($"#{t.Name}: {t.Count} {taskWord}")
            }
            print tagSb.ToString()
        }
    }

    // Print search results in compact format
    static func PrintSearchResults(tasks: List<TaskItem>, query: string) {
        if tasks.Count == 0 {
            print $"No tasks matching \"{query}\""
            return
        }

        print $"Found {tasks.Count} task(s) matching \"{query}\":"
        for task in tasks {
            print FormatTaskRow(task)
        }
    }

    // Print CLI usage information
    static func PrintUsage() {
        print "taskr - A CLI task manager"
        print ""
        print "Usage:"
        print "  taskr add <title> [--priority low|medium|high] [--tag <tag>] [--due <date>]"
        print "  taskr list [--status todo|inprogress|done] [--priority low|medium|high] [--tag <tag>]"
        print "  taskr done <id>"
        print "  taskr start <id>"
        print "  taskr delete <id>"
        print "  taskr stats"
        print "  taskr search <query>"
    }
}
