// Models.nl — All domain types in one file, like a Go package.
// No separate Models/ directory. Types that belong together live together.

namespace IssueTracker

import System

// Priority is a simple enum — no data variants needed
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

// IssueStatus is a union, not an enum — each state carries different data.
// InProgress has an assignee. Closed has a resolution. Open has nothing.
// This is what unions are for: when the shape of the data changes per variant.
union IssueStatus {
    Open
    InProgress { assigneeId: int }
    Closed { resolution: string, closedAt: DateTime }
}

// Typed domain errors as a union — no stringly-typed exceptions.
// Callers match on the variant, not on exception message substrings.
union IssueError {
    NotFound { id: int }
    InvalidTransition { from: string, to: string }
    ValidationFailed { field: string, reason: string }
}

// Records are immutable value types — perfect for domain models
record Issue {
    Id: int
    Title: string
    Description: string
    Status: IssueStatus
    Priority: Priority
    CreatedAt: DateTime
    Tags: string[]
}

record User {
    Id: int
    Name: string
    Email: string
}

record Comment {
    Id: int
    IssueId: int
    AuthorId: int
    Body: string
    CreatedAt: DateTime
}

// Format an error for API responses — exhaustive match means
// the compiler forces you to handle every variant. Add a new
// IssueError case and every match breaks until you handle it.
class Errors {
    static func Format(err: IssueError): string {
        return match err {
            IssueError.NotFound { id } => $"Issue #{id} not found",
            IssueError.InvalidTransition { from, to } => $"Cannot move from {from} to {to}",
            IssueError.ValidationFailed { field, reason } => $"{field}: {reason}"
        }
    }
}
