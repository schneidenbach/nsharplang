namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// THE FOUR HANDLES ONE `foreach` LOWERING NEEDS, resolved together because none of them is a fact on
// its own: a `GetEnumerator` without a `MoveNext` is not the pattern, and the `Current` getter's
// return type is the loop variable's type only because the other two made it an enumerator.
class ForeachEnumeratorPattern {
    GetEnumeratorMethod: MethodInfo
    EnumeratorType: Type
    MoveNextMethod: MethodInfo
    CurrentGetter: MethodInfo

    constructor(getEnumeratorMethod: MethodInfo, enumeratorType: Type, moveNextMethod: MethodInfo, currentGetter: MethodInfo) {
        if getEnumeratorMethod == null || enumeratorType == null || moveNextMethod == null || currentGetter == null {
            throw new InvalidOperationException("A foreach enumerator pattern cannot be built from missing members.")
        }

        GetEnumeratorMethod = getEnumeratorMethod
        EnumeratorType = enumeratorType
        MoveNextMethod = moveNextMethod
        CurrentGetter = currentGetter
    }

    // WHAT THE LOOP VARIABLE IS BOUND TO. `Span<T>.Enumerator.Current` is a `ref T`, and the element
    // is `T`: the loop variable is a COPY of the current element, and the by-ref spelling is the
    // enumerator's way of avoiding a second copy on the way out, not part of the element type.
    ElementType: Type => CurrentGetter.get_ReturnType().get_IsByRef() ? RequiredElementType() : CurrentGetter.get_ReturnType()

    CurrentReturnsByRef: bool => CurrentGetter.get_ReturnType().get_IsByRef()

    func RequiredElementType(): Type {
        element := CurrentGetter.get_ReturnType().GetElementType()
        if element == null {
            throw new InvalidOperationException("A by-ref 'Current' must name the element type it refers to.")
        }

        return element
    }
}

// WHAT `for x in e` LOOKS FOR ON A CLR TYPE, AND NOTHING ELSE.
//
// This is the C# `foreach` pattern (Roslyn's `ForEachLoopBinder`) written once, over `System.Type`,
// so that the ANALYSER and the EMITTER cannot disagree about which collections iterate. The order is
// the language rule, not a preference:
//
//   1  an accessible parameterless instance `GetEnumerator()` whose return type carries a readable
//      `Current` and a parameterless `bool MoveNext()` — the ENUMERATOR PATTERN, which is what makes
//      `List<T>`, `Dictionary<K,V>`, `Span<T>` and `JsonElement.ArrayEnumerator` iterate WITHOUT any
//      of them being named here;
//   2  `IEnumerable<T>`, when the pattern does not answer;
//   3  the non-generic `IEnumerable`, whose element type is `object`.
//
// Arrays and `string` are decided by their own arms in the callers, because their lowering is an
// INDEX loop rather than an enumerator and only the caller knows which of the two it is emitting.
//
// EVERY IDENTITY TEST HERE IS BY `FullName`, NEVER BY `typeof`. The analyser reads referenced
// assemblies through a MetadataLoadContext, where the projected `System.Boolean` is NOT
// `typeof(bool)` and the projected `IEnumerable<>` is NOT `typeof(IEnumerable<>)`; an identity
// comparison answers NO for every type that arrives that way, which is exactly why a `foreach` over
// a `JsonElement.ArrayEnumerator` — a struct that both implements `IEnumerable<JsonElement>` AND
// carries the pattern — used to be rejected as "not enumerable". The name test is exact in the
// metadata world and in the runtime world alike, and the conversion table beside this one
// (`AnalyzerReflectionTypeConversion`) is keyed the same way for the same reason.
//
// EVERY MEMBER LOOKUP WALKS THE DECLARATION CHAIN ITSELF rather than asking the binder. `GetMethod`
// and `GetProperty` throw `AmbiguousMatchException` when a derived type shadows the member being
// asked for, and an exception escaping type inference is a crashed `nlc`; a `DeclaredOnly` walk from
// the most derived declaration outward answers the SAME member the binder would have chosen and
// cannot throw. For an INTERFACE the chain is its base interfaces, because an interface has no
// `BaseType` and `IReadOnlyList<T>` inherits its `GetEnumerator` rather than declaring one.
class ForeachPatternFacts {
    static func SequenceInterfaceName(): string {
        return "System.Collections.Generic.IEnumerable`1"
    }

    static func AsyncSequenceInterfaceName(): string {
        return "System.Collections.Generic.IAsyncEnumerable`1"
    }

    static func NonGenericSequenceName(): string {
        return "System.Collections.IEnumerable"
    }

    static func DisposableName(): string {
        return "System.IDisposable"
    }

    static func BooleanName(): string {
        return "System.Boolean"
    }

    static func StringName(): string {
        return "System.String"
    }

    // THE ENUMERATOR THE PATTERN FINDS, or null when this type has none. Both enumerator members are
    // required before the answer is given: a `GetEnumerator` whose return type carries only one of
    // them is not the pattern, and the type falls through to the interface arms exactly as it does
    // in C#.
    static func FindPattern(clrType: Type): ForeachEnumeratorPattern? {
        getEnumerator := FindParameterlessInstanceMethod(clrType, "GetEnumerator")
        if getEnumerator == null {
            return null
        }

        enumeratorType := getEnumerator.get_ReturnType()
        if enumeratorType == null || IsVoid(enumeratorType) || enumeratorType.get_IsByRef() {
            return null
        }

        moveNext := FindParameterlessInstanceMethod(enumeratorType, "MoveNext")
        if moveNext == null || !IsBoolean(moveNext.get_ReturnType()) {
            return null
        }

        currentGetter := FindCurrentGetter(enumeratorType)
        if currentGetter == null {
            return null
        }

        return new ForeachEnumeratorPattern(getEnumerator, enumeratorType, moveNext, currentGetter)
    }

    // The CLOSED `IEnumerable<T>` this type iterates as, or null. A type that names SEVERAL
    // instantiations answers none: C# calls that ambiguous rather than choosing, and the caller's
    // non-generic arm is the honest remainder.
    static func FindSequenceInterface(clrType: Type): Type? {
        return FindUniqueConstructedInterface(clrType, SequenceInterfaceName())
    }

    static func FindAsyncSequenceInterface(clrType: Type): Type? {
        return FindUniqueConstructedInterface(clrType, AsyncSequenceInterfaceName())
    }

    static func FindUniqueConstructedInterface(clrType: Type, definitionName: string): Type? {
        found: Type? = null
        if MatchesConstructedDefinition(clrType, definitionName) {
            found = clrType
        }

        interfaces := SafeGetInterfaces(clrType)
        for candidate in interfaces {
            if MatchesConstructedDefinition(candidate, definitionName) {
                if found == null {
                    found = candidate
                } else {
                    if !SameConstruction(found, candidate) {
                        return null
                    }
                }
            }
        }

        return found
    }

    // THE OPEN DEFINITION IS ONE OF ITS OWN CONSTRUCTIONS, for this question. A `GenericTypeInfo`
    // whose definition is `IAsyncEnumerable<>` asks this walk about the DEFINITION and substitutes
    // the answer by position afterwards, so refusing a definition here would answer "not a sequence"
    // for the one shape that always is.
    static func MatchesConstructedDefinition(candidate: Type, definitionName: string): bool {
        if candidate == null || !candidate.get_IsGenericType() {
            return false
        }

        try {
            definition := candidate.GetGenericTypeDefinition()
            return definition != null && definition.FullName == definitionName
        } catch {
            return false
        }
    }

    // TWO CONSTRUCTIONS OF ONE DEFINITION ARE THE SAME ONLY IF THEIR ARGUMENTS ARE. `List<int>`
    // names `IEnumerable<int>` once through the class and once through `IList<int>`, and that is not
    // an ambiguity; a type naming `IEnumerable<int>` and `IEnumerable<string>` is.
    static func SameConstruction(left: Type, right: Type): bool {
        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        index := 0
        while index < leftArguments.Length {
            if !SameTypeIdentity(leftArguments[index], rightArguments[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func SameTypeIdentity(left: Type, right: Type): bool {
        if Object.ReferenceEquals(left, right) {
            return true
        }

        if left == null || right == null {
            return false
        }

        leftName := left.get_AssemblyQualifiedName()
        rightName := right.get_AssemblyQualifiedName()
        if leftName == null || rightName == null {
            return left.FullName != null && left.FullName == right.FullName
        }

        return leftName == rightName
    }

    static func ImplementsNonGenericSequence(clrType: Type): bool {
        return NamesInterface(clrType, NonGenericSequenceName())
    }

    static func ImplementsDisposable(clrType: Type): bool {
        return NamesInterface(clrType, DisposableName())
    }

    static func NamesInterface(clrType: Type, interfaceName: string): bool {
        if clrType == null {
            return false
        }

        if clrType.FullName == interfaceName {
            return true
        }

        interfaces := SafeGetInterfaces(clrType)
        for interfaceItem in interfaces {
            if interfaceItem.FullName == interfaceName {
                return true
            }
        }

        return false
    }

    // A REF STRUCT CANNOT IMPLEMENT AN INTERFACE, so `Span<T>.Enumerator` can only be disposed
    // through the PATTERN — a public parameterless `void Dispose()`. That is the same rule C# uses,
    // and it is why this lookup exists beside the interface test rather than instead of it.
    static func FindPatternDispose(clrType: Type): MethodInfo? {
        dispose := FindParameterlessInstanceMethod(clrType, "Dispose")
        if dispose == null || !IsVoid(dispose.get_ReturnType()) {
            return null
        }

        return dispose
    }

    static func IsBoolean(candidate: Type): bool {
        return candidate != null && candidate.FullName == BooleanName()
    }

    static func IsString(candidate: Type): bool {
        return candidate != null && candidate.FullName == StringName()
    }

    static func IsVoid(candidate: Type): bool {
        return candidate != null && candidate.FullName == "System.Void"
    }

    // THE MOST DERIVED PARAMETERLESS PUBLIC INSTANCE METHOD OF THIS NAME. The walk is `DeclaredOnly`
    // from the type outward so that a shadowing declaration wins without the binder's ambiguity
    // exception, and an interface continues into its base interfaces because it has no `BaseType`.
    static func FindParameterlessInstanceMethod(owner: Type, name: string): MethodInfo? {
        if owner == null {
            return null
        }

        current: Type? = owner
        while current != null {
            declared := DeclaredParameterlessInstanceMethod(current, name)
            if declared != null {
                return declared
            }

            current = SafeBaseType(current)
        }

        if !owner.get_IsInterface() {
            return null
        }

        interfaces := SafeGetInterfaces(owner)
        for interfaceItem in interfaces {
            declared := DeclaredParameterlessInstanceMethod(interfaceItem, name)
            if declared != null {
                return declared
            }
        }

        return null
    }

    static func DeclaredParameterlessInstanceMethod(owner: Type, name: string): MethodInfo? {
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly
        methods := SafeGetMethods(owner, flags)
        for candidate in methods {
            if candidate.Name == name && !candidate.get_IsGenericMethodDefinition() && candidate.GetParameters().Length == 0 {
                return candidate
            }
        }

        return null
    }

    // THE ENUMERATOR'S `Current` GETTER. An INDEXED property named `Current` is not it, and a
    // write-only one is not it either.
    static func FindCurrentGetter(owner: Type): MethodInfo? {
        if owner == null {
            return null
        }

        current: Type? = owner
        while current != null {
            declared := DeclaredCurrentGetter(current)
            if declared != null {
                return declared
            }

            current = SafeBaseType(current)
        }

        if !owner.get_IsInterface() {
            return null
        }

        interfaces := SafeGetInterfaces(owner)
        for interfaceItem in interfaces {
            declared := DeclaredCurrentGetter(interfaceItem)
            if declared != null {
                return declared
            }
        }

        return null
    }

    static func DeclaredCurrentGetter(owner: Type): MethodInfo? {
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly
        properties := SafeGetProperties(owner, flags)
        for candidate in properties {
            if candidate.Name == "Current" && candidate.GetIndexParameters().Length == 0 {
                getter := candidate.get_GetMethod()
                if getter != null {
                    return getter
                }
            }
        }

        return null
    }

    // THE THREE REFLECTION CALLS THIS OWNER MAKES ON A TYPE IT DID NOT CREATE. A metadata-only type
    // whose references cannot be resolved throws from any of them, and a `foreach` over such a value
    // must decline rather than crash the analyser.
    static func SafeGetInterfaces(clrType: Type): Type[] {
        if clrType == null {
            return new Type[](0)
        }

        try {
            resolved := clrType.GetInterfaces()
            if resolved == null {
                return new Type[](0)
            }

            return resolved
        } catch {
            return new Type[](0)
        }
    }

    static func SafeGetMethods(clrType: Type, flags: BindingFlags): MethodInfo[] {
        try {
            resolved := clrType.GetMethods(flags)
            if resolved == null {
                return new MethodInfo[](0)
            }

            return resolved
        } catch {
            return new MethodInfo[](0)
        }
    }

    static func SafeGetProperties(clrType: Type, flags: BindingFlags): PropertyInfo[] {
        try {
            resolved := clrType.GetProperties(flags)
            if resolved == null {
                return new PropertyInfo[](0)
            }

            return resolved
        } catch {
            return new PropertyInfo[](0)
        }
    }

    static func SafeBaseType(clrType: Type): Type? {
        try {
            return clrType.get_BaseType()
        } catch {
            return null
        }
    }
}
