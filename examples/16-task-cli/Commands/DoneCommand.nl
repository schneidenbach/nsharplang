namespace TaskCli.Commands

import System
import TaskCli.Models
import TaskCli.Services


// Handle the "done" and "start" commands
class DoneCommand {

    // Mark a task as done
    static func RunDone(service: TaskService, args: string[]) {
        if args.Length == 0 {
            print "Error: Task ID is required"
            print "Usage: taskr done <id>"
            return
        }

        id := ParseId(args[0])
        if id < 0 {
            print $"Error: Invalid task ID: {args[0]}"
            return
        }

        result := service.MarkDone(id)
        Formatter.PrintResult(result)
    }

    // Mark a task as in progress
    static func RunStart(service: TaskService, args: string[]) {
        if args.Length == 0 {
            print "Error: Task ID is required"
            print "Usage: taskr start <id>"
            return
        }

        id := ParseId(args[0])
        if id < 0 {
            print $"Error: Invalid task ID: {args[0]}"
            return
        }

        result := service.MarkInProgress(id)
        Formatter.PrintResult(result)
    }

    // Parse a string to int, returns -1 on failure
    static func ParseId(s: string): int {
        result := -1
        try {
            result = Int32.Parse(s)
        } catch {
            result = -1
        }

        return result
    }
}
