namespace TaskCli.Commands

import System
import System.Collections.Generic
import TaskCli.Models
import TaskCli.Services
import "../Models/Task"
import "../Services/TaskService"
import "../Services/Formatter"

// Handle the "stats" command
class StatsCommand {
    static func Run(service: TaskService) {
        stats := service.GetStats()
        priorityBreakdown := service.GetPriorityBreakdown()
        tagBreakdown := service.GetTagBreakdown()
        Formatter.PrintStats(stats, priorityBreakdown, tagBreakdown)
    }
}
