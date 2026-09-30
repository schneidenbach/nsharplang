namespace NSharpLang.CensusGenericInterfaceMethod.Tests

import System
import System.Collections.Generic
import Microsoft.Extensions.Logging

// A CAPTURING LOGGER — the member that could not be written before this slice.
//
// `ILogger.Log<TState>` declares `TState` on the METHOD, so the slot's `state` and `formatter`
// parameters are spelled in a type parameter owned by the interface's own `MethodDef`, while the
// class writes its own. Until the match unified the two lists by position, this class declined at
// `emit.declaration.interface-unimplemented`.
class CapturedLogger: ILogger {
    Entries: List<string>
    Levels: List<LogLevel>
    Scopes: int

    constructor() {
        Entries = new List<string>()
        Levels = new List<LogLevel>()
        Scopes = 0
    }

    func Log<TState>(logLevel: LogLevel, _eventId: EventId, state: TState, exception: Exception?, formatter: Func<TState, Exception?, string>) {
        Levels.Add(logLevel)
        Entries.Add(formatter(state, exception))
    }

    func IsEnabled(logLevel: LogLevel): bool {
        return logLevel != LogLevel.None
    }

    func BeginScope<TState>(_state: TState): IDisposable? {
        Scopes = Scopes + 1
        return null
    }

    // A GENERIC METHOD OF THE SAME CLASS THAT IS NOT AN INTERFACE MEMBER. It must stay an ordinary
    // non-virtual method: the interface bits are decided by name and arity against the interface's
    // own rows, and `Describe` matches none of them.
    func Describe<TValue>(value: TValue): string {
        return Entries.Count.ToString() + ":" + (value == null ? "absent" : "present")
    }
}

// The interface is the only way in: a read through `CapturedLogger` itself would pass whether or not
// the slot exists.
func WriteThrough(sink: ILogger, level: LogLevel, text: string): bool {
    if !sink.IsEnabled(level) {
        return false
    }
    sink.Log<string>(level, new EventId(7, "probe"), text, null, (state, error) => state + (error == null ? "" : "!"))
    return true
}

func WriteFailureThrough(sink: ILogger, text: string, error: Exception): void {
    sink.Log<string>(LogLevel.Error, new EventId(9, "fail"), text, error, (state, failure) => state + "/" + (failure == null ? "" : failure.Message))
}
