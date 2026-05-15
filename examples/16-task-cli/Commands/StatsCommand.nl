namespace TaskCli.Commands

import TaskCli.Models
import TaskCli.Services


// Handle the "stats" command
class StatsCommand {
    static func Run(service: TaskService) {
        stats := service.GetStats()
        priorityBreakdown := service.GetPriorityBreakdown()
        tagBreakdown := service.GetTagBreakdown()
        Formatter.PrintStats(stats, priorityBreakdown, tagBreakdown)
    }
}
