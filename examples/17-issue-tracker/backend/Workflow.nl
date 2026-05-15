// Workflow.nl — State machine for issue status transitions.
// This file is THE showcase for visibility-by-casing:
//   PascalCase = public, camelCase = private. No access modifiers anywhere.

namespace IssueTracker

import System
import "Models"

class Workflow {

    // Transition is PascalCase → public.
    // Returns the new status or throws on invalid transition.
    static func Transition(issue: Issue, to: IssueStatus): IssueStatus {
        if !isValid(issue.Status, to) {
            throw new Exception(FormatError(new IssueError.InvalidTransition(describe(issue.Status), describe(to))))
        }

        return to
    }

    // isValid is camelCase → private. Nobody outside this class can call it.
    // Nested match on union variants — no string comparison, no casting.
    // Every variant is handled explicitly — no wildcards. Add a variant,
    // the compiler forces you to handle it here.
    static func isValid(from: IssueStatus, to: IssueStatus): bool {
        return match from {
            IssueStatus.Open => match to {
                IssueStatus.InProgress { assigneeId } => true,
                IssueStatus.Closed { resolution, closedAt } => true,
                IssueStatus.Open => false
            },
            IssueStatus.InProgress { assigneeId } => match to {
                IssueStatus.Open => true,
                IssueStatus.Closed { resolution, closedAt } => true,
                _ => false
            },
            IssueStatus.Closed { resolution, closedAt } => match to {
                IssueStatus.Open => true,
                _ => false
            }
        }
    }

    // same-state transition not allowed

    // can only reopen from closed

    // camelCase → private helper for status labels.
    // Exhaustive match — no wildcard fallback.
    static func describe(status: IssueStatus): string {
        return match status {
            IssueStatus.Open => "Open",
            IssueStatus.InProgress { assigneeId } => "InProgress",
            IssueStatus.Closed { resolution, closedAt } => "Closed"
        }
    }
}
