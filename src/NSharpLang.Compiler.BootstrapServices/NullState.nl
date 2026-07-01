namespace NSharpLang.Compiler

public enum NullState {
    Unknown,
    Null,
    MaybeNull,
    NotNull,
    Oblivious
}

public class NullStateFacts {
    public static func GetDiagnosticText(state: NullState): string {
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

    public static func GetSchemaText(state: NullState): string {
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
