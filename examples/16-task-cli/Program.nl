namespace TaskCli

import System
import System.Threading.Tasks
import TaskCli.Models
import TaskCli.Services
import TaskCli.Commands

async func Main() {
    rawArgs := Environment.GetCommandLineArgs()

    if rawArgs.Length < 2 {
        Formatter.PrintUsage()
        return
    }

    command := rawArgs[1].ToLower()

    // Collect remaining args after the command name
    remainingArgs := new System.Collections.Generic.List<string>()
    for i := 2; i < rawArgs.Length; i++ {
        remainingArgs.Add(rawArgs[i])
    }
    args := remainingArgs.ToArray()

    // Initialize store and service
    store := new TaskStore()
    service := new TaskService(store)
    await service.LoadTasks()

    needsSave := false

    if command == "add" {
        AddCommand.Run(service, args)
        needsSave = true
    } else if command == "list" {
        ListCommand.Run(service, args)
    } else if command == "done" {
        DoneCommand.RunDone(service, args)
        needsSave = true
    } else if command == "start" {
        DoneCommand.RunStart(service, args)
        needsSave = true
    } else if command == "delete" {
        DeleteCommand.Run(service, args)
        needsSave = true
    } else if command == "stats" {
        StatsCommand.Run(service)
    } else if command == "search" {
        ListCommand.RunSearch(service, args)
    } else {
        print $"Unknown command: {command}"
        Formatter.PrintUsage()
    }

    if needsSave {
        await service.SaveTasks()
    }
}
