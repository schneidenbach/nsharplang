namespace ExceptionFilters

import System
import System.Collections.Generic


// EXCEPTION FILTERS — `catch <binding> when <expr>`.
//
// A filter decides whether a handler runs at all. It is NOT the same as opening the handler with an
// `if`, and it is not the same as catching and rethrowing, because the CLR runs a filter on its
// FIRST pass — while the frames between the throw and this handler are still on the stack. A handler
// that decides it does not want the exception after unwinding has already destroyed that stack.
//
// Run this and watch the ordering: `filter` is printed BEFORE the inner `finally`.
class AuditLog {
    entries: List<string> = new List<string>()

    func Note(text: string): bool {
        entries.Add(text)
        Console.WriteLine("  " + text)
        return true
    }

    func Reset() {
        entries.Clear()
    }
}

class RequestFailed: Exception {
    status: int

    constructor(status: int): base("request failed with status " + status.ToString()) {
        this.status = status
    }

    Status: int => status
}

// A filter picks WHICH failures this handler owns. A 5xx is retried here; anything else is left for
// a caller that knows more than this function does.
func Fetch(status: int): string {
    try {
        throw new RequestFailed(status)
    } catch failure: RequestFailed when failure.Status >= 500 {
        return "retrying after " + failure.Status.ToString()
    }
}

// The ordering demonstration: the filter runs before the `finally` nested inside the region.
func ShowOrdering(log: AuditLog) {
    log.Reset()
    try {
        try {
            throw new RequestFailed(503)
        } finally {
            log.Note("finally (the region is being unwound)")
        }
    } catch failure: RequestFailed when log.Note("filter (the stack is still intact here)") {
        log.Note("handler")
    }
}

// A filter may also prove something the handler then relies on. `InnerException` is nullable; the
// guard is the test, so the handler reads it directly.
func Describe(withCause: bool): string {
    try {
        if withCause {
            throw new InvalidOperationException("outer", new RequestFailed(404))
        }
        throw new InvalidOperationException("outer")
    } catch e: InvalidOperationException when e.InnerException != null {
        return "caused by: " + e.InnerException.Message
    } catch e: InvalidOperationException {
        return "no cause recorded"
    }
}

func main() {
    Console.WriteLine("A filter chooses which failures a handler owns:")
    Console.WriteLine("  " + Fetch(503))

    Console.WriteLine("")
    Console.WriteLine("A filter runs BEFORE unwinding, so it sees the stack the throw left:")
    ShowOrdering(new AuditLog())

    Console.WriteLine("")
    Console.WriteLine("What a filter proves is available in the handler:")
    Console.WriteLine("  " + Describe(true))
    Console.WriteLine("  " + Describe(false))
}
