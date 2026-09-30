namespace Census.ExceptionMembers

import System
import System.Collections.Generic


// EVERY READABLE PROPERTY AN EXCEPTION DECLARES, NOT THE ONES SOMEBODY HAPPENED TO LIST.
//
// The receiver arm for an exception already said "ANY readable instance property", but the fence
// behind it asked a NARROWER question than the backend's own: a property whose type was not in the
// admitted-value-type list declined even when the columnar backend could hold, store and pass that
// exact type everywhere else. So `Exception.Data` (an `IDictionary`) and
// `AggregateException.InnerExceptions` (a `ReadOnlyCollection<Exception>`) could not be read at
// all, and neither could any property a referenced package's exception adds whose type is an
// ordinary supported one.
class ExceptionMemberFacts {

    // `Exception.Data` is an `IDictionary`, which the admitted-value-type list never named.
    static func DataCount(error: Exception): int {
        data := error.Data
        return data.Count
    }

    static func DataIsEmpty(error: Exception): bool {
        return DataCount(error) == 0
    }

    // `AggregateException.InnerExceptions` is a `ReadOnlyCollection<Exception>` — a constructed
    // generic over a source-visible external type, which is exactly what the backend's own
    // supported-type fence admits.
    static func InnerCount(error: AggregateException): int {
        return error.InnerExceptions.Count
    }

    static func FirstInnerMessage(error: AggregateException): string {
        inner := error.InnerExceptions
        if inner.Count == 0 {
            return ""
        }

        return inner[0].Message
    }

    // The rows that already worked, kept beside the new ones so a regression in either direction is
    // a failing test rather than a silent narrowing.
    static func Code(error: Exception): int {
        return error.HResult
    }

    static func Text(error: Exception): string {
        return error.Message
    }

    static func Origin(error: Exception): string? {
        return error.Source
    }

    static func Build(): AggregateException {
        inner := new List<Exception>()
        inner.Add(new InvalidOperationException("first"))
        inner.Add(new ArgumentNullException("second"))
        return new AggregateException("outer", inner)
    }
}
