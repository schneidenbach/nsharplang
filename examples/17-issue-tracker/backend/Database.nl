// Database.nl — In-memory store. Simple, no external dependencies.

namespace IssueTracker

import System.Collections.Generic
import "Models"

class IssueStore {
    issues: List<Issue>

    constructor() {
        issues = new List<Issue>()
    }

    func GetAll(): List<Issue> {
        return issues
    }

    func Add(issue: Issue) {
        issues.Add(issue)
    }

    func FindById(id: int): int {
        for i := 0; i < issues.Count; i++ {
            if issues[i].Id == id {
                return i
            }
        }

        return -1
    }

    func GetAt(index: int): Issue {
        return issues[index]
    }

    func Update(updated: Issue) {
        for i := 0; i < issues.Count; i++ {
            if issues[i].Id == updated.Id {
                issues[i] = updated
                return
            }
        }
    }
}
