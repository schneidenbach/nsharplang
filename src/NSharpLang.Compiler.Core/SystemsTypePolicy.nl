namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT A TYPE IS WORTH, AND WHETHER IT MAY CROSS A SYSTEMS BOUNDARY.
//
// Three systems rules ask questions of a type reference and nothing else: how many bytes does one of
// these cost when it is copied, does it borrow a stack frame, and is it a shape a `[hot]` or
// `[boundary]` signature may expose. They were three separate families in the analyzer's closure
// scoring and they are ONE owner here, because they share the only state any of them keeps — the
// three sets of type names the declaration walk registers. Splitting them would have left those sets
// in C# and blocked whichever family moved second.
//
// THE THREE SETS ARE THE WHOLE STATE, AND THEY ARE SOURCE FACTS RATHER THAN SEMANTIC ONES. A systems
// project's own `struct`, `ref struct` and `enum` declarations are registered by NAME as the walk
// meets them, cleared once per analysis, and read by exactly the rules below. Nothing here consults a
// semantic model: a systems policy that changed its answer with an import, or with whether a
// reference assembly happened to load, would not be a policy a developer could reason about.
//
// SIZES ARE A CONSERVATIVE COPY SHAPE, NOT `sizeof`. The point of `EstimateTypeSize` is to decide
// whether returning a `Result<T,E>` costs more than the v1 hot-path guidance of 128 bytes, so it
// deliberately over-charges what it cannot see: an unrecognised name costs 8, a registered struct
// costs 32, an unrecognised generic costs 32, and a `Result` pays a 16-byte tag-and-padding
// allowance on top of both payloads.
//
// THE SIZE TABLE IS KEYED BY THE LANGUAGE KEYWORD AND THAT IS BEHAVIOUR, NOT AN OVERSIGHT. The
// element type is SIMPLIFIED before it is sized, so `System.Int32` arrives as `Int32`, misses every
// keyword row and lands on the 8-byte unknown default while `int` lands on 4. Widening the table to
// accept CLR spellings would change the reported byte count of every systems project that writes
// one, so it is pinned here rather than quietly improved.
//
// REF-LIKE IS A LEXICAL TEST AND `ContainsRefLikeType` IS ITS TRANSITIVE CLOSURE. `Span`,
// `ReadOnlySpan`, anything by-ref, and any locally declared `ref struct` borrow a frame; a type that
// merely CONTAINS one — a generic argument, an array element, a nullable inner, a union arm — carries
// the same lifetime obligation outward, which is what the `[hot]` return-lifetime rule needs.
//
// HOSTILE SURFACE ANSWERS WITH ITS REASON, AND THE REASON IS THE DIAGNOSTIC. The C# original was a
// `bool` with an `out string`; here it is a nullable string, which is exact rather than approximate:
// every affirmative arm assigns a non-empty reason before it answers, so "hostile" and "has a reason"
// are the same fact. Three of the reasons are the matched table name itself and two are sentences,
// and all five reach a developer verbatim inside an NSYS070 message.
//
// `hotStrict` IS DROPPED WHEN THE WALK ENTERS AN ARRAY, AND ONLY THERE. An array's ELEMENT is not
// itself the exposed surface — the array is — so the stricter "no HotSummary surface rule" arm is
// switched off for one hop. By-ref, nullable and union recursion keep it.
class SystemsTypePolicy {
    structTypesValue: HashSet<string>
    refStructTypesValue: HashSet<string>
    enumTypesValue: HashSet<string>

    constructor() {
        structTypesValue = new HashSet<string>(StringComparer.Ordinal)
        refStructTypesValue = new HashSet<string>(StringComparer.Ordinal)
        enumTypesValue = new HashSet<string>(StringComparer.Ordinal)
    }

    // One call per analysis, from the analyzer's own reset block, replacing three separate clears.
    func BeginAnalysis() {
        structTypesValue.Clear()
        refStructTypesValue.Clear()
        enumTypesValue.Clear()
    }

    // Registered from the declaration walk. A `record struct` registers as a struct and nothing else;
    // only a `struct` declared `ref` also registers as ref-like.
    func RegisterStructType(name: string) {
        structTypesValue.Add(name)
    }

    func RegisterRefStructType(name: string) {
        refStructTypesValue.Add(name)
    }

    func RegisterEnumType(name: string) {
        enumTypesValue.Add(name)
    }

    // Published for the ONE reader outside this owner's own rules: the hot-readiness test that asks
    // whether an upper-case receiver is a locally declared enum before it reports NSYS110. Registered
    // enums are the reason `Color.Red` is not a warmup obligation.
    func IsEnumTypeName(name: string): bool {
        return enumTypesValue.Contains(name)
    }

    // The value-typed names: the language's own primitives, three BCL structs that behave like them,
    // and every struct or enum this project declares. Applied to an ERASED name, so it is simplified
    // first — `System.Guid` and `Guid` must classify alike.
    func IsValueTypeName(name: string): bool {
        simpleName := SystemsTypeNames.SimpleName(name)
        if IsPrimitiveValueTypeName(simpleName) {
            return true
        }

        return structTypesValue.Contains(simpleName) || enumTypesValue.Contains(simpleName)
    }

    func IsPrimitiveValueTypeName(name: string): bool {
        if name == "bool" || name == "byte" || name == "sbyte" || name == "short" || name == "ushort" {
            return true
        }

        if name == "int" || name == "uint" || name == "long" || name == "ulong" || name == "float" {
            return true
        }

        if name == "double" || name == "decimal" || name == "char" || name == "nint" || name == "nuint" {
            return true
        }

        return name == "DateTime" || name == "Guid" || name == "TimeSpan"
    }

    // Borrows a frame: the two span constructors, anything by-ref, and any locally declared
    // `ref struct`. Deliberately name based — a `ref struct` from another assembly is not visible to
    // a source-level walk, and guessing at one would fire on ordinary code.
    func IsRefLikeType(typeReference: TypeReference): bool {
        name := SystemsTypeNames.SimpleName(SystemsTypeNames.ErasedName(typeReference))
        if name == "Span" || name == "ReadOnlySpan" {
            return true
        }

        if typeReference as ByRefTypeReference != null {
            return true
        }

        return refStructTypesValue.Contains(name)
    }

    // The transitive closure of the above through every shape that can hold another type. A `Span`
    // inside a tuple-shaped union arm still escapes with the value that holds it.
    func ContainsRefLikeType(typeReference: TypeReference): bool {
        if IsRefLikeType(typeReference) {
            return true
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            typeArguments := generic.TypeArguments
            argumentIndex := 0
            while argumentIndex < typeArguments.Count {
                if ContainsRefLikeType(typeArguments[argumentIndex]) {
                    return true
                }

                argumentIndex = argumentIndex + 1
            }

            return false
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return ContainsRefLikeType(array.ElementType)
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return ContainsRefLikeType(nullable.InnerType)
        }

        unionType := typeReference as UnionTypeReference
        if unionType != null {
            arms := unionType.Arms
            armIndex := 0
            while armIndex < arms.Count {
                if ContainsRefLikeType(arms[armIndex]) {
                    return true
                }

                armIndex = armIndex + 1
            }

            return false
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return ContainsRefLikeType(byRef.InnerType)
        }

        return false
    }

    // `Result<T,E>` and nothing else: the arity is part of the identity, so a one-argument `Result`
    // is not one. This is what the must-use rule and the ABI-size rule both key on.
    func IsResultType(typeReference: TypeReference): bool {
        generic := typeReference as GenericTypeReference
        if generic == null {
            return false
        }

        return SystemsTypeNames.SimpleName(generic.Name) == "Result" && generic.TypeArguments.Count == 2
    }

    // Tag plus padding plus both payloads. A `Result` of the wrong arity sizes as ZERO rather than as
    // an unknown 32, which is what keeps `EstimateTypeSize`'s `Result` arm from over-reporting a
    // malformed reference: the arity check lives here and the caller does not repeat it.
    func EstimateResultSize(typeReference: TypeReference): int {
        generic := typeReference as GenericTypeReference
        if generic == null || generic.TypeArguments.Count != 2 {
            return 0
        }

        return 16 + EstimateTypeSize(generic.TypeArguments[0]) + EstimateTypeSize(generic.TypeArguments[1])
    }

    // THE RESULT ABI RULE: whether returning this shape costs more than the v1 hot-path guidance of
    // 128 bytes, and the sentence that says so. Null means acceptable. The threshold and the number
    // in the sentence belong together — a caller holding one without the other would have to
    // re-derive the size to say anything useful — so both live here and the walk relays.
    //
    // THE `IsResultType` GUARD IS LOAD-BEARING AND IS NOT THE SAME TEST AS THE SIZE. Any generic of
    // arity two sizes as `16 + both payloads`, so `Unknown<Wide, Wide>` would exceed the guidance
    // without ever being a `Result`. The identity is checked first, exactly as the C# original did.
    func ResultAbiReason(typeReference: TypeReference?): string? {
        if typeReference == null {
            return null
        }

        if !IsResultType(typeReference) {
            return null
        }

        resultSize := EstimateResultSize(typeReference)
        if resultSize <= 128 {
            return null
        }

        return "Result<T,E> copy shape is estimated at " + resultSize.ToString() + " bytes, above the v1 hot-path guidance of 128 bytes"
    }

    // The copy shape of one value. Every arm is a deliberate over-estimate of what the analyzer
    // cannot see, and the order of the generic arms is the order of the original's `when` guards:
    // span-shaped first, `Result` second, everything else 32.
    func EstimateTypeSize(typeReference: TypeReference): int {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return EstimateSimpleTypeSize(SystemsTypeNames.SimpleName(simple.Name))
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            genericName := SystemsTypeNames.SimpleName(generic.Name)
            if genericName == "Span" || genericName == "ReadOnlySpan" || genericName == "Memory" || genericName == "ReadOnlyMemory" {
                return 16
            }

            if genericName == "Result" {
                return EstimateResultSize(generic)
            }

            return 32
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return 8
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return EstimateTypeSize(nullable.InnerType) + 1
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return 8
        }

        unionType := typeReference as UnionTypeReference
        if unionType != null {
            arms := unionType.Arms
            if arms.Count == 0 {
                return 0
            }

            largest := EstimateTypeSize(arms[0])
            armIndex := 1
            while armIndex < arms.Count {
                armSize := EstimateTypeSize(arms[armIndex])
                if armSize > largest {
                    largest = armSize
                }

                armIndex = armIndex + 1
            }

            return largest + 8
        }

        return 32
    }

    // The keyword table, consulted AFTER the project's own declarations so that a struct or enum
    // named `int` — which the language does not allow, but the table cannot assume — would answer as
    // the declaration rather than the keyword. An unrecognised name is 8 bytes: a pointer's worth,
    // the same as a reference, which is the conservative answer for a shape the walk cannot see.
    func EstimateSimpleTypeSize(name: string): int {
        if enumTypesValue.Contains(name) {
            return 4
        }

        if structTypesValue.Contains(name) {
            return 32
        }

        if name == "bool" || name == "byte" || name == "sbyte" {
            return 1
        }

        if name == "short" || name == "ushort" || name == "char" {
            return 2
        }

        if name == "int" || name == "uint" || name == "float" {
            return 4
        }

        if name == "long" || name == "ulong" || name == "double" || name == "nint" || name == "nuint" {
            return 8
        }

        if name == "decimal" || name == "Guid" {
            return 16
        }

        if name == "DateTime" || name == "TimeSpan" {
            return 8
        }

        return 8
    }

    // WHETHER A `[hot]` OR `[boundary]` SIGNATURE MAY EXPOSE THIS TYPE, AND WHY NOT. Null means the
    // surface is acceptable; any other answer is the reason a developer reads inside NSYS070.
    // `hotStrict` is the caller's `[hot]`-ness: a `[boundary]` only refuses the named hostile shapes,
    // while a `[hot]` signature also refuses anything it has no summary rule for.
    func HostileSurfaceReason(typeReference: TypeReference?, hotStrict: bool, constraints: List<GenericConstraint>?): string? {
        if typeReference == null {
            return null
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return HostileSurfaceReason(byRef.InnerType, hotStrict, constraints)
        }

        // The ONLY place strictness is dropped: an array's element is not the exposed surface.
        array := typeReference as ArrayTypeReference
        if array != null {
            return HostileSurfaceReason(array.ElementType, false, constraints)
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return HostileSurfaceReason(nullable.InnerType, hotStrict, constraints)
        }

        unionType := typeReference as UnionTypeReference
        if unionType != null {
            arms := unionType.Arms
            armIndex := 0
            while armIndex < arms.Count {
                armReason := HostileSurfaceReason(arms[armIndex], hotStrict, constraints)
                if armReason != null {
                    return armReason
                }

                armIndex = armIndex + 1
            }

            return null
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            return HostileGenericReason(generic, hotStrict, constraints)
        }

        simple := typeReference as SimpleTypeReference
        if simple != null {
            return HostileSimpleReason(SystemsTypeNames.SimpleName(simple.Name), hotStrict, constraints)
        }

        return null
    }

    // `Result` is transparent — it is the sanctioned way to carry an error across a systems boundary,
    // so only its payloads are judged. The span and memory constructors are always acceptable. The
    // fourteen named collection, sequence and delegate constructors are always hostile, and their
    // NAME is the reason. Anything else is acceptable to a `[boundary]` and unknown to a `[hot]`.
    func HostileGenericReason(generic: GenericTypeReference, hotStrict: bool, constraints: List<GenericConstraint>?): string? {
        name := SystemsTypeNames.SimpleName(generic.Name)
        if name == "Result" {
            typeArguments := generic.TypeArguments
            argumentIndex := 0
            while argumentIndex < typeArguments.Count {
                argumentReason := HostileSurfaceReason(typeArguments[argumentIndex], hotStrict, constraints)
                if argumentReason != null {
                    return argumentReason
                }

                argumentIndex = argumentIndex + 1
            }

            return null
        }

        if name == "Span" || name == "ReadOnlySpan" || name == "Memory" || name == "ReadOnlyMemory" {
            return null
        }

        if IsHostileGenericConstructorName(name) {
            return name
        }

        if hotStrict {
            return "generic type '" + name + "' has no HotSummary surface rule"
        }

        return null
    }

    func IsHostileGenericConstructorName(name: string): bool {
        if name == "IEnumerable" || name == "IQueryable" || name == "IEnumerator" || name == "IAsyncEnumerable" {
            return true
        }

        if name == "Task" || name == "ValueTask" || name == "Func" || name == "Action" || name == "List" {
            return true
        }

        return name == "Dictionary" || name == "IList" || name == "ICollection" || name == "IReadOnlyList" || name == "IReadOnlyCollection"
    }

    // A generic PARAMETER constrained to `struct` is a value type by declaration, and it is checked
    // FIRST so that a `T: struct` never falls through to the unsummarized-type arm. `string` is
    // acceptable by name even though it is not a value type: a systems boundary may take one, and the
    // two span names appear here as well because a span written without arguments is still a span.
    func HostileSimpleReason(name: string, hotStrict: bool, constraints: List<GenericConstraint>?): string? {
        if IsValueConstrainedGenericParameter(name, constraints) {
            return null
        }

        if IsValueTypeName(name) || name == "string" || name == "ReadOnlySpan" || name == "Span" {
            return null
        }

        if name == "object" || name == "dynamic" || name == "Type" || name == "Stream" || name == "Delegate" {
            return name
        }

        if hotStrict && !structTypesValue.Contains(name) && !enumTypesValue.Contains(name) {
            return "managed or unsummarized type '" + name + "'"
        }

        return null
    }

    // The `struct` special constraint on the type parameter of this exact name. Tested as a FLAG
    // rather than as equality, because `T: class, new()` and `T: struct` share one bit field.
    func IsValueConstrainedGenericParameter(name: string, constraints: List<GenericConstraint>?): bool {
        if constraints == null {
            return false
        }

        structBit := Convert.ToInt32(SpecialConstraintKind.Struct)
        index := 0
        while index < constraints.Count {
            constraint := constraints[index]
            if constraint.TypeParameter == name && (Convert.ToInt32(constraint.SpecialConstraints) & structBit) == structBit {
                return true
            }

            index = index + 1
        }

        return false
    }

    // WHETHER A `new` REACHES THE HEAP. A typeless `new` — the parser's shape for an implicitly typed
    // construction — is assumed to, and so is every array creation regardless of element type: the
    // array object itself is the allocation. Everything else is a heap allocation exactly when its
    // erased name is not a value type.
    func IsHeapAllocation(expression: NewExpression): bool {
        typeReference := expression.Type
        if typeReference == null {
            return true
        }

        if typeReference as ArrayTypeReference != null {
            return true
        }

        return !IsValueTypeName(SystemsTypeNames.ErasedName(typeReference))
    }
}
