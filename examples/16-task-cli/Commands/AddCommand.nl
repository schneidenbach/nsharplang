namespace TaskCli.Commands

import System
import System.Collections.Generic
import TaskCli.Models
import TaskCli.Services

// Handle the "add" command
class AddCommand {
    static func Run(service: TaskService, args: string[]) {
        if args.Length == 0 {
            print "Error: Title is required"
            print "Usage: taskr add <title> [--priority low|medium|high] [--tag <tag>] [--due <date>]"
            return
        }

        title := args[0]

        // Parse priority flag
        priority := Priority.Medium
        priorityStr := FindArgValue(args, "--priority")
        if priorityStr.Length > 0 {
            lower := priorityStr.ToLower()
            if lower == "high" {
                priority = Priority.High
            } else if lower == "low" {
                priority = Priority.Low
            }
        }

        // Parse tag flags (can have multiple)
        tags := FindAllArgValues(args, "--tag")

        // Parse due date
        dueDate := FindArgValue(args, "--due")

        // Create the task
        result := service.AddTask(title, priority, tags, dueDate)
        Formatter.PrintResult(result)
    }

    // Find the value after a named flag (e.g., --priority high)
    static func FindArgValue(args: string[], flag: string): string {
        for i := 0; i < args.Length - 1; i++ {
            if args[i] == flag {
                return args[i + 1]
            }
        }
        return ""
    }

    // Find all values after repeated named flags (e.g., --tag a --tag b)
    static func FindAllArgValues(args: string[], flag: string): List<string> {
        result := new List<string>()
        for i := 0; i < args.Length - 1; i++ {
            if args[i] == flag {
                result.Add(args[i + 1])
            }
        }
        return result
    }
}
