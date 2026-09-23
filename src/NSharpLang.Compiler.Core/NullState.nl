namespace NSharpLang.Compiler

enum NullState {
    Unknown,
    Null,
    MaybeNull,
    NotNull,
    Oblivious
}

class NullStateFacts {

    // THE STATE A TYPE IMPLIES WITH NO FLOW FACT AT ALL, over a type whose declared aliases the
    // caller has ALREADY resolved. The reflected arm is the interesting one: a CLR value type that is
    // not `Nullable<T>` can never be null and is NOT-NULL, while every other reflected type is
    // OBLIVIOUS rather than not-null — external metadata the analyzer has not been told the
    // nullability of must not produce a confident answer in either direction.
    //
    // It lives here rather than on the null-flow owner because TWO owners need it and they must not
    // drift: what a dereference is judged against, and what an `out` parameter leaves in the
    // variable the callee wrote.
    static func DefaultFor(resolved: TypeInfo): NullState {
        if BuiltInTypes.Is(resolved, BuiltInTypes.Null) {
            return NullState.Null
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return NullState.MaybeNull
        }

        unknown := resolved as UnknownTypeInfo
        if unknown != null {
            return NullState.Unknown
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            if reflectionType.Type.IsValueType && System.Nullable.GetUnderlyingType(reflectionType.Type) == null {
                return NullState.NotNull
            }

            return NullState.Oblivious
        }

        return NullState.NotNull
    }

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
