namespace TaskCli.Commands

import System
import TaskCli.Models
import TaskCli.Services


// Handle the "delete" command
class DeleteCommand {
    static func Run(service: TaskService, args: string[]) {
        if args.Length == 0 {
            print "Error: Task ID is required"
            print "Usage: taskr delete <id>"
            return
        }

        id := ParseId(args[0])
        if id < 0 {
            print $"Error: Invalid task ID: {args[0]}"
            return
        }

        result := service.DeleteTask(id)
        Formatter.PrintResult(result)
    }

    // Parse a string to int, returns -1 on failure
    static func ParseId(s: string): int {
        result := 0
        if Int32.TryParse(s, out result) {
            return result
        }

        return -1
    }
}
