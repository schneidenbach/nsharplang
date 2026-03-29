namespace IssueTracker

import System
import System.Collections.Generic
import "Models"
import "Database"
import "Notifier"
import "Service"

test "CreateIssue returns issue with correct fields" {
    store := new IssueStore()
    service := new IssueService(store, new NotifierHub())

    tags := new List<string>()
    tags.Add("backend")
    issue := service.CreateIssue("Fix login bug", "Users can't log in", Priority.High, tags.ToArray())

    assert issue.Id == 1
    assert issue.Title == "Fix login bug"
    assert issue.Tags.Length == 1
}

test "CreateIssue with empty title uses error tuples" {
    store := new IssueStore()
    service := new IssueService(store, new NotifierHub())

    tags := new List<string>()
    // Go-style error handling: result, err :=
    issue, err := service.CreateIssue("", "no title", Priority.Low, tags.ToArray())
    assert err != null
    assert err.Message.Contains("title")
}

test "CreateIssue assigns sequential IDs" {
    store := new IssueStore()
    service := new IssueService(store, new NotifierHub())

    tags := new List<string>()
    first := service.CreateIssue("First", "desc", Priority.Low, tags.ToArray())
    second := service.CreateIssue("Second", "desc", Priority.Medium, tags.ToArray())

    assert first.Id == 1
    assert second.Id == 2
}

test "TransitionIssue moves Open to InProgress" {
    store := new IssueStore()
    service := new IssueService(store, new NotifierHub())

    tags := new List<string>()
    service.CreateIssue("Test issue", "desc", Priority.Medium, tags.ToArray())

    updated := service.TransitionIssue(1, new IssueStatus.InProgress(42))

    statusName := match updated.Status {
        IssueStatus.InProgress { assigneeId } => $"InProgress:{assigneeId}",
        _ => "other"
    }
    assert statusName == "InProgress:42"
}

test "TransitionIssue rejects invalid transition" {
    store := new IssueStore()
    service := new IssueService(store, new NotifierHub())

    tags := new List<string>()
    service.CreateIssue("Test issue", "desc", Priority.Medium, tags.ToArray())

    // Open -> Open is not a valid transition
    _, err := service.TransitionIssue(1, new IssueStatus.Open {})
    assert err != null
}

test "FormatError produces correct messages for each variant" {
    notFound := Errors.Format(new IssueError.NotFound(42))
    assert notFound.Contains("42")

    invalid := Errors.Format(new IssueError.InvalidTransition("Open", "Open"))
    assert invalid.Contains("Open")

    validation := Errors.Format(new IssueError.ValidationFailed("title", "cannot be empty"))
    assert validation.Contains("title")
    assert validation.Contains("cannot be empty")
}
