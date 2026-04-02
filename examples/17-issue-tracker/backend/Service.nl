// Service.nl — Issue service with error tuples and camelCase private helpers.
// Shows Go-style error handling: result, err := instead of try/catch.

namespace IssueTracker

import System
import System.Linq
import System.Collections.Generic
import "Models"
import "Database"
import "Notifier"
import "Workflow"

class IssueService {
    store: IssueStore
    notifiers: NotifierHub
    nextId: int

    constructor(store: IssueStore, notifiers: NotifierHub) {
        this.store = store
        this.notifiers = notifiers
        nextId = 1
    }

    // PascalCase → public
    func CreateIssue(title: string, description: string, priority: Priority, tags: string[]): Issue {
        err := validate(title)
        if err != null {
            throw err
        }

        issue := new Issue {
            Id: nextId,
            Title: title,
            Description: description,
            Status: new IssueStatus.Open {},
            Priority: priority,
            CreatedAt: DateTime.UtcNow,
            Tags: tags
        }
        nextId = nextId + 1
        store.Add(issue)

        // Duck interface in action — NotifierHub broadcasts to all
        // registered notifiers, regardless of their concrete type.
        notifiers.Broadcast(issue, "created")

        return issue
    }

    func TransitionIssue(id: int, newStatus: IssueStatus): Issue {
        index := store.FindById(id)
        if index < 0 {
            throw new Exception(
                FormatError(new IssueError.NotFound(id))
            )
        }
        issue := store.GetAt(index)
        status := Workflow.Transition(issue, newStatus)
        updated := issue with { Status: status }
        store.Update(updated)

        notifiers.Broadcast(updated, "transitioned")

        return updated
    }

    func GetAll(): List<Issue> {
        return store.GetAll()
    }

    func FindByPriority(priority: Priority): List<Issue> {
        return store.GetAll().Where(i => i.Priority == priority).ToList()
    }

    func FindByTag(tag: string): List<Issue> {
        return store.GetAll().Where(i => i.Tags.Contains(tag)).ToList()
    }

    // camelCase → private. Validation logic that no caller needs to see.
    func validate(title: string): Exception {
        if title == null || title.Length == 0 {
            return new Exception(
                FormatError(new IssueError.ValidationFailed("title", "cannot be empty"))
            )
        }
        if title.Length > 200 {
            return new Exception(
                FormatError(new IssueError.ValidationFailed("title", "must be under 200 characters"))
            )
        }
        return null
    }
}
