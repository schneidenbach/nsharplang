namespace TaskCli.Commands

import System
import TaskCli.Models
import TaskCli.Services

// Handle the "list" and "search" commands
class ListCommand {
    // List tasks with optional filters
    static func Run(service: TaskService, args: string[]) {
        filter := new Filter {
            Query: "",
            StatusName: FindArgValue(args, "--status"),
            PriorityName: FindArgValue(args, "--priority"),
            Tag: FindArgValue(args, "--tag")
        }

        tasks := service.GetFilteredTasks(filter)
        Formatter.PrintTaskTable(tasks)
    }

    // Search tasks by query
    static func RunSearch(service: TaskService, args: string[]) {
        if args.Length == 0 {
            print "Error: Search query is required"
            print "Usage: taskr search <query>"
            return
        }

        query := args[0]
        results := service.SearchTasks(query)
        Formatter.PrintSearchResults(results, query)
    }

    // Find the value after a named flag
    static func FindArgValue(args: string[], flag: string): string {
        for i := 0; i < args.Length - 1; i++ {
            if args[i] == flag {
                return args[i + 1]
            }
        }
        return ""
    }
}
