namespace TaskCli

import System.Collections.Generic
import TaskCli.Models
import TaskCli.Services

test "AddTask creates a task with correct fields" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    tags.Add("backend")
    result := service.AddTask("Write tests", Priority.High, tags, "")

    resultText := match result {
        CommandResult.Success { message } => message,
        _ => "unexpected"
    }
    assert resultText.Contains("Write tests")
}

test "AddTask rejects empty title" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    result := service.AddTask("", Priority.Medium, tags, "")

    isError := match result {
        CommandResult.Error { message } => true,
        _ => false
    }
    assert isError == true
}

test "MarkDone changes task status" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("Test task", Priority.Low, tags, "")
    result := service.MarkDone(1)

    isSuccess := match result {
        CommandResult.Success { message } => true,
        _ => false
    }
    assert isSuccess == true

    tasks := service.GetTasks()
    assert tasks.Count == 1
    assert tasks[0].GetStatusText() == "Done"
}

test "MarkDone returns error for missing task" {
    store := new TaskStore()
    service := new TaskService(store)

    result := service.MarkDone(999)

    isError := match result {
        CommandResult.Error { message } => true,
        _ => false
    }
    assert isError == true
}

test "MarkInProgress changes task status" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("Test task", Priority.Medium, tags, "")
    result := service.MarkInProgress(1)

    isSuccess := match result {
        CommandResult.Success { message } => true,
        _ => false
    }
    assert isSuccess == true

    tasks := service.GetTasks()
    assert tasks[0].GetStatusText() == "InProgress"
}

test "DeleteTask removes the task" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("Task to delete", Priority.Low, tags, "")
    assert service.GetTasks().Count == 1

    result := service.DeleteTask(1)

    isSuccess := match result {
        CommandResult.Success { message } => true,
        _ => false
    }
    assert isSuccess == true
    assert service.GetTasks().Count == 0
}

test "SearchTasks finds matching tasks" {
    store := new TaskStore()
    service := new TaskService(store)

    tags1 := new List<string>()
    tags1.Add("backend")
    service.AddTask("Write unit tests", Priority.High, tags1, "")

    tags2 := new List<string>()
    tags2.Add("frontend")
    service.AddTask("Review PR", Priority.Medium, tags2, "")

    results := service.SearchTasks("test")
    assert results.Count == 1
    assert results[0].Title == "Write unit tests"
}

test "SearchTasks matches on tags" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    tags.Add("backend")
    service.AddTask("Some task", Priority.Low, tags, "")

    results := service.SearchTasks("backend")
    assert results.Count == 1
}

test "GetStats returns correct counts" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("Task 1", Priority.High, tags, "")
    service.AddTask("Task 2", Priority.Medium, tags, "")
    service.AddTask("Task 3", Priority.Low, tags, "")

    service.MarkDone(1)
    service.MarkInProgress(2)

    stats := service.GetStats()
    assert stats.Total == 3
    assert stats.DoneCount == 1
    assert stats.InProgressCount == 1
    assert stats.TodoCount == 1
}

test "GetFilteredTasks filters by status" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("Task 1", Priority.High, tags, "")
    service.AddTask("Task 2", Priority.Medium, tags, "")
    service.MarkDone(1)

    filter := new Filter {
        Query: "",
        StatusName: "done",
        PriorityName: "",
        Tag: ""
    }
    filtered := service.GetFilteredTasks(filter)
    assert filtered.Count == 1
    assert filtered[0].Title == "Task 1"
}

test "GetFilteredTasks filters by tag" {
    store := new TaskStore()
    service := new TaskService(store)

    tags1 := new List<string>()
    tags1.Add("backend")
    service.AddTask("Backend task", Priority.High, tags1, "")

    tags2 := new List<string>()
    tags2.Add("frontend")
    service.AddTask("Frontend task", Priority.Medium, tags2, "")

    filter := new Filter {
        Query: "",
        StatusName: "",
        PriorityName: "",
        Tag: "backend"
    }
    filtered := service.GetFilteredTasks(filter)
    assert filtered.Count == 1
    assert filtered[0].Title == "Backend task"
}

test "Multiple tasks get sequential IDs" {
    store := new TaskStore()
    service := new TaskService(store)

    tags := new List<string>()
    service.AddTask("First", Priority.Low, tags, "")
    service.AddTask("Second", Priority.Low, tags, "")
    service.AddTask("Third", Priority.Low, tags, "")

    tasks := service.GetTasks()
    assert tasks[0].Id == 1
    assert tasks[1].Id == 2
    assert tasks[2].Id == 3
}
