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
    // not `Nullable<T>` can never be null and is NOT-NULL, while a reflected SHARED-FRAMEWORK class
    // type is OBLIVIOUS rather than not-null — the analyzer has never enforced the framework's own
    // reference annotations, and must not produce a confident answer about them in either direction.
    //
    // A class type from ANY OTHER referenced assembly is not-null, exactly as the same declaration is
    // in source: its metadata's maybe-null positions arrive as `NullableTypeInfo` and its unstated ones
    // as `ObliviousTypeInfo` (see `NullabilityMetadataReflection`), so a bare reflected type is one
    // that says not-null. Without this a program split into two projects meant something different:
    // `if map.TryGetValue(key, out found) { return found }` left `found` oblivious over a referenced
    // `Node` and not-null over a source one, and the return reported NL202.
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

            if !ExternalAssemblyScan.IsSharedFrameworkAssembly(reflectionType.Type.Assembly) {
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
