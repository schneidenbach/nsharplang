namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit


// EMIT-TIME TYPE IDENTITY. Ported WHOLE to N# by `015-B10` out of `ColumnarIlEmitter.cs`, where it stood
// as five private statics serving 104 call sites — the emitter's operand, parameter, field and return
// identity predicate. The C# owner now forwards to this one and holds no copy of the rule.
//
// Type equality that treats two CLOSED instantiations of the same user generic as EQUAL even when they
// are distinct `TypeBuilderInstantiation` instances: `MakeGenericType` over a `TypeBuilder` does not
// cache, and `TypeBuilderInstantiation` equality is referential — so `new Box<Box<int>>(new Box<int>(v))`
// produces one `Box<int>` from the inner construction and ANOTHER from the ctor-parameter substitution.
//
// ⚠ THIS IS NOT `ColumnarReferenceConversionFacts.ExactTypeShapeMatches`, AND IT IS NOT
// `ColumnarBaseTypePlanner.SameInterfaceType`. All three walk the same skeleton and all three differ
// where it matters, so none may be folded into another:
//
//   | | this one | `ExactTypeShapeMatches` | `SameInterfaceType` |
//   | enum arm | yes, `IsSameEnumType` | none | none |
//   | by-ref arm | yes, recursive | none | none |
//   | two `TypeBuilder`s | equal when `FullName` and `Module` agree | none | always UNEQUAL |
//   | generic definitions | compared RECURSIVELY | compared by reference | compared recursively |
//   | reflection reads | guarded (see below) | raw | raw |
//
// Every reflection read here is guarded, and that is a product rule rather than defensiveness: a
// `TypeBuilder` or a bare generic parameter throws `NotImplementedException`/`NotSupportedException`
// out of `IsByRef`, `IsSZArray`, `GetElementType` and `TypeHandle` while the type graph is still
// unbaked, and an identity predicate that throws mid-emit is not a decline — it is a crash.
class ColumnarTypeEquivalenceFacts {
    static func TypesEquivalent(a: Type, b: Type): bool {
        if a == b {
            return true
        }

        if ColumnarTypeOfPlanner.IsEnumType(a) || ColumnarTypeOfPlanner.IsEnumType(b) {
            return IsSameEnumType(a, b)
        }

        if IsByRefType(a) || IsByRefType(b) {
            if !IsByRefType(a) || !IsByRefType(b) {
                return false
            }

            aByRefElement := TryGetElementType(a)
            bByRefElement := TryGetElementType(b)
            return aByRefElement != null && bByRefElement != null && TypesEquivalent(aByRefElement, bByRefElement)
        }

        if IsSzArrayType(a) || IsSzArrayType(b) {
            if !IsSzArrayType(a) || !IsSzArrayType(b) {
                return false
            }

            aElement := TryGetElementType(a)
            bElement := TryGetElementType(b)
            return aElement != null && bElement != null && TypesEquivalent(aElement, bElement)
        }

        if a is TypeBuilder || b is TypeBuilder {
            if !(a is TypeBuilder) || !(b is TypeBuilder) {
                return false
            }

            return SameDeclaredIdentity(a, b)
        }

        // Structural equivalence for closed generic INSTANTIATIONS — user-headed (`Box<int>`) AND
        // builder-bound BCL-headed (`List<Pt>`, `Dictionary<string, Pt>`): every independent
        // `MakeGenericType` over a builder yields a referentially DISTINCT `TypeBuilderInstantiation`
        // (probe-proven), so definitions must match and arguments recurse. Fully baked instantiations are
        // cached by the runtime and were already matched by the reference test above.
        if !a.get_IsGenericType() || !b.get_IsGenericType() || a.get_IsGenericTypeDefinition() || b.get_IsGenericTypeDefinition() {
            return false
        }

        if !TypesEquivalent(a.GetGenericTypeDefinition(), b.GetGenericTypeDefinition()) {
            return false
        }

        aArguments := a.GetGenericArguments()
        bArguments := b.GetGenericArguments()
        if aArguments.Length != bArguments.Length {
            return false
        }

        index := 0
        while index < aArguments.Length {
            if !TypesEquivalent(aArguments[index], bArguments[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // `IsByRef` is answerable for every baked type and throws for some unbaked emit-time shapes. A throw
    // means "not known to be by-ref", which is the same answer the caller needs.
    static func IsByRefType(candidate: Type): bool {
        try {
            return candidate.get_IsByRef()
        } catch ex: NotImplementedException {
            return false
        } catch ex: NotSupportedException {
            return false
        }
    }

    // ⚠ `Type.IsSZArray` throws `NotImplementedException` on a bare generic parameter and on some
    // `TypeBuilder`-rooted shapes — a recorded landmine in this repository. When it throws, the SPELLING
    // is the fallback oracle: an array type has an element type AND a `[]` suffix on its name. Both
    // halves are required, because a name check alone would claim a user type literally called `Foo[]`
    // and an element-type check alone would claim a by-ref or pointer type.
    static func IsSzArrayType(candidate: Type): bool {
        reflectionAnswered := false
        reflectionAnswer := false
        try {
            reflectionAnswer = candidate.get_IsSZArray()
            reflectionAnswered = true
        } catch ex: NotImplementedException {
            reflectionAnswered = false
        } catch ex: NotSupportedException {
            reflectionAnswered = false
        }

        if reflectionAnswered {
            return reflectionAnswer
        }

        if TryGetElementType(candidate) == null {
            return false
        }

        name := candidate.get_Name()
        if name != null && name.EndsWith("[]", StringComparison.Ordinal) {
            return true
        }

        fullName := candidate.get_FullName()
        return fullName != null && fullName.EndsWith("[]", StringComparison.Ordinal)
    }

    // Null means "no element type is knowable here", which covers both a non-composite type and a shape
    // whose element type the emit-time reflection surface refuses to answer.
    static func TryGetElementType(candidate: Type): Type {
        try {
            return candidate.GetElementType()
        } catch ex: NotImplementedException {
            return null
        } catch ex: NotSupportedException {
            return null
        }
    }

    // Two enum types are the same enum when their runtime handles agree. `TypeHandle` throws for an
    // `EnumBuilder`/`TypeBuilder`, and there the enum's declared name inside its own module is the
    // identity: a source enum cannot be declared twice under one name in one module.
    static func IsSameEnumType(a: Type, b: Type): bool {
        if !ColumnarTypeOfPlanner.IsEnumType(a) || !ColumnarTypeOfPlanner.IsEnumType(b) {
            return false
        }

        handlesMatch := false
        try {
            handlesMatch = a.get_TypeHandle().Equals(b.get_TypeHandle())
        } catch ex: NotSupportedException {
            handlesMatch = false
        }

        if handlesMatch {
            return true
        }

        return SameDeclaredIdentity(a, b)
    }

    // One declared name inside one module is one type. Both callers above fall back to this when the
    // reflection surface refuses a handle, and they are the same test in the C# owner too. The MODULE
    // half is load-bearing rather than belt-and-braces: one process emits many dynamic assemblies (the
    // test host emits one per case), so two distinct builders CAN carry the same `FullName`, and a
    // name-only test would silently equate two unrelated types.
    //
    // ⚠ THE ONE PLACE THIS PORT IS NOT A DIRECT TRANSCRIPTION, AND EXACTLY WHY.
    // The C# owner reads `a.Module` directly. `System.Reflection.Module` is NOT on
    // `ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName`'s list — `MethodInfo`, `FieldInfo`,
    // `PropertyInfo`, `ParameterInfo`, `AssemblyName` and `RuntimeTypeHandle` all are — so the packaged
    // bootstrap SDK that compiles THIS file declines `a.get_Module()` at emit with `NL103`
    // (`emit.local.initializer`). The property is therefore read REFLECTIVELY: that invokes the very
    // same getter and compares the very same two references, so it is a faithful spelling rather than a
    // weaker predicate — and weakening a type-identity predicate is the one thing this port may not do.
    // It is also off the hot path by construction: the `FullName` test above returns false first for
    // every ordinary mismatch, so the reflective read runs only for two DISTINCT builders sharing a name.
    // Put `System.Reflection.Module` on that list at the next SDK repack and this detour deletes itself.
    static func SameDeclaredIdentity(a: Type, b: Type): bool {
        if !string.Equals(a.get_FullName(), b.get_FullName(), StringComparison.Ordinal) {
            return false
        }

        moduleProperty := typeof(Type).GetProperty("Module")
        if moduleProperty == null {
            throw new InvalidOperationException("System.Type must expose a Module property.")
        }

        aModule := moduleProperty.GetValue(a)
        bModule := moduleProperty.GetValue(b)
        return Object.ReferenceEquals(aModule, bModule)
    }
}
