namespace NSharpLang.Compiler

enum NullState {
    Unknown,
    Null,
    MaybeNull,
    NotNull,
    Oblivious
}

class NullStateFacts {
    static func GetDiagnosticText(state: NullState): string {
        if state == NullState.Null {
            return "null"
        }

        if state == NullState.MaybeNull {
            return "maybe-null"
        }

        if state == NullState.NotNull {
            return "not-null"
        }

        if state == NullState.Oblivious {
            return "oblivious"
        }

        return "unknown"
    }

    static func GetSchemaText(state: NullState): string {
        if state == NullState.Null {
            return "null"
        }

        if state == NullState.MaybeNull {
            return "maybeNull"
        }

        if state == NullState.NotNull {
            return "notNull"
        }

        if state == NullState.Oblivious {
            return "oblivious"
        }

        return "unknown"
    }
}
