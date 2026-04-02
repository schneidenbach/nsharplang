// Notifier.nl — Duck interfaces: Go-style structural typing.
// No class ever writes "implements INotifier". If it has the right
// method signatures, it satisfies the interface automatically.

namespace IssueTracker

import System.Collections.Generic
import "Models"

// Duck interface — any type with a matching Notify method qualifies.
// No explicit implementation required. This is how Go interfaces work.
duck interface INotifier {
    func Notify(issue: Issue, message: string)
}

// ConsoleNotifier satisfies INotifier by having a matching Notify method.
// Notice: no ": INotifier" anywhere. The compiler figures it out.
class ConsoleNotifier {
    func Notify(issue: Issue, message: string) {
        print $"[console] #{issue.Id} {issue.Title}: {message}"
    }
}

// SlackNotifier also satisfies INotifier — different implementation, same shape.
class SlackNotifier {
    webhookUrl: string

    constructor(url: string) {
        webhookUrl = url
    }

    func Notify(issue: Issue, message: string) {
        // In production this would POST to Slack
        print $"[slack → {webhookUrl}] #{issue.Id}: {message}"
    }
}

// NotifierHub collects notifiers and broadcasts to all of them.
// The duck interface INotifier is internal — it only appears in private fields,
// never in public signatures. Concrete types go in, duck matching happens at assignment.
class NotifierHub {
    // camelCase → private. The duck interface type stays hidden.
    notifiers: List<INotifier>

    constructor() {
        notifiers = new List<INotifier>()
    }

    // Register takes concrete types. The duck interface match happens
    // when they're added to the List<INotifier> — no cast, no "implements".
    func Register(console: ConsoleNotifier) {
        notifiers.Add(console)
    }

    func Register(slack: SlackNotifier) {
        notifiers.Add(slack)
    }

    // PascalCase → public. Broadcasts to every registered notifier.
    func Broadcast(issue: Issue, message: string) {
        for n in notifiers {
            n.Notify(issue, message)
        }
    }
}
