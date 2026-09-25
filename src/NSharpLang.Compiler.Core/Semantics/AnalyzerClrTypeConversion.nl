namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// The analyzer's TypeInfo → CLR `Type` CONSTRUCTION FUNNEL.
//
// Everything the semantic phase does that needs a real reflection type — comparing against a
// referenced assembly's member signature, binding an overload, constructing a closed generic,
// reifying a delegate for a lambda target — goes through here. Two entry points sit at the top and
// they are NOT interchangeable:
//
//   * TryConvertTypeInfoToClrType is the EXACT conversion. It answers null the moment any position
//     names a type the CLR does not have — which is every N#-declared class, record, struct,
//     interface, union, enum and newtype — because a caller that gets a Type back must be able to
//     trust that it denotes the type the program actually wrote.
//   * TryConvertTypeInfoToClrTypeForBinding is the SURROGATE conversion. Where the exact conversion
//     gives up on an N#-declared type it substitutes `object`, so CLR-level method binding can still
//     proceed; the real N# types stay tracked separately as TypeInfo bindings. Never use it where
//     the answer is treated as the program's type.
//
// Both resolve declared aliases at EVERY position they descend through, via the declaration
// context — an array element, a nullable inner type, a type argument, a delegate parameter and a
// union arm are each re-entered through the funnel, so `type Meters = int` converts identically
// wherever it is written.
//
// The well-known-type bag is NULLABLE and that state is live, not defensive: until the analyzer has
// loaded its MetadataLoadContext there are no metadata facts at all, and the funnel falls back to
// `AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType`, which answers with the COMPILER's own runtime
// types and resolves no aliases. Because the bag is built and torn down over an analyzer's
// lifetime, this owner is rebuilt at those two points rather than mutated; its own fields never
// change after construction.
//
// Do not reintroduce any of this in C#, and do not give it diagnostics: the funnel reports nothing
// and records nothing. A conversion that cannot be made is a null answer, and the caller decides
// what that means.
class AnalyzerClrTypeConversion {
    declarationContext: AnalyzerDeclarationContext
    wellKnownTypes: AnalyzerWellKnownTypes?

    constructor(context: AnalyzerDeclarationContext, wellKnown: AnalyzerWellKnownTypes?) {
        declarationContext = context
        wellKnownTypes = wellKnown
    }

    // The exact conversion. Null means "the CLR has no such type", which for a source-declared type
    // is the normal answer rather than a failure.
    func TryConvertTypeInfoToClrType(typeInfo: TypeInfo): Type? {
        resolvedType := declarationContext.ResolveDeclaredAlias(typeInfo)

        reflectionType := resolvedType as ReflectionTypeInfo
        if reflectionType != null {
            return reflectionType.Type
        }

        facts := wellKnownTypes
        if facts == null {
            return AnalyzerWellKnownTypeFacts.BuiltInRuntimeClrType(resolvedType)
        }

        simple := resolvedType as SimpleTypeInfo
        if simple != null {
            return BuiltInClrType(facts, simple)
        }

        arrayType := resolvedType as ArrayTypeInfo
        if arrayType != null {
            elementType := TryConvertTypeInfoToClrType(arrayType.ElementType)
            if elementType == null {
                return null
            }

            return elementType.MakeArrayType()
        }

        nullableType := resolvedType as NullableTypeInfo
        if nullableType != null {
            return TryConvertNullableType(nullableType.InnerType)
        }

        obliviousType := resolvedType as ObliviousTypeInfo
        if obliviousType != null {
            return TryConvertTypeInfoToClrType(obliviousType.InnerType)
        }

        genericType := resolvedType as GenericTypeInfo
        if genericType != null {
            return TryConstructKnownGenericType(genericType)
        }

        tupleType := resolvedType as TupleTypeInfo
        if tupleType != null {
            return TryConstructValueTupleType(tupleType.Elements, 0)
        }

        functionType := resolvedType as FunctionTypeInfo
        if functionType != null {
            return TryConstructDelegateType(functionType)
        }

        unionType := resolvedType as AnonymousUnionTypeInfo
        if unionType != null {
            return TryConstructRuntimeUnionType(unionType)
        }

        return null
    }

    // The surrogate conversion: like the exact one, but an N#-declared type becomes `object` so CLR
    // binding can proceed. Generic, nullable and array shells are rebuilt around surrogate contents;
    // every other family that the exact conversion rejects stays rejected.
    func TryConvertTypeInfoToClrTypeForBinding(typeInfo: TypeInfo): Type? {
        result := TryConvertTypeInfoToClrType(typeInfo)
        if result != null {
            return result
        }

        facts := wellKnownTypes
        if facts == null {
            return null
        }

        resolvedType := declarationContext.ResolveDeclaredAlias(typeInfo)

        // A SOURCE ENUM'S SURROGATE IS `System.Enum`, NOT `object`. An enum's base type is fixed by
        // the CLR, and naming it is what lets `flags.HasFlag(other)` bind the `System.Enum`
        // parameter the runtime declares. `object` is still satisfied, because `System.Enum` is one;
        // the surrogate simply stopped throwing away the one thing every enum is known to be.
        surrogateEnum := resolvedType as EnumTypeInfo
        if surrogateEnum != null {
            return facts.Enum
        }

        if IsSurrogateUserDefinedType(resolvedType) {
            // A SOURCE TYPE'S SURROGATE IS THE NEAREST CLR TYPE IT IS KNOWN TO BE, and `object` is
            // only the answer when nothing better is written. `class Names: List<string>` has no CLR
            // handle of its own while it is being compiled, but the CLR already holds the type its
            // `:` clause names, and a `Names` IS a `List<string>` — so binding `names.Add("a")`
            // against `object` was throwing away the one fact the declaration states. Every CLR-level
            // measurement of the receiver — the declaring type's own type arguments for a call on a
            // generic base, an overload that takes the base, an extension whose receiver slot the base
            // satisfies — reads the base instead, and the answer stays a surrogate because the DERIVED
            // type is still not named.
            surrogateBase := TryConvertDeclaredBaseChainToClrType(resolvedType)
            if surrogateBase != null {
                return surrogateBase
            }

            return facts.Object
        }

        genericType := resolvedType as GenericTypeInfo
        if genericType != null {
            return ConstructSurrogateGenericType(facts, genericType, false)
        }

        nullableType := resolvedType as NullableTypeInfo
        if nullableType != null {
            clrInnerType := TryConvertTypeInfoToClrTypeForBinding(nullableType.InnerType)
            nullableOpen := facts.NullableOpen
            if clrInnerType == null || nullableOpen == null {
                return null
            }

            return WrapInNullable(nullableOpen, clrInnerType)
        }

        arrayType := resolvedType as ArrayTypeInfo
        if arrayType != null {
            elementType := TryConvertTypeInfoToClrTypeForBinding(arrayType.ElementType)
            if elementType == null {
                return null
            }

            return elementType.MakeArrayType()
        }

        return null
    }

    // A function type reified as an `Action`/`Func` delegate. Public because the lambda-to-delegate
    // path asks for it directly, without going through the type-shaped entry point.
    func TryConstructDelegateType(functionType: FunctionTypeInfo): Type? {
        parameterTypes := functionType.ParameterTypes
        returnType := functionType.ReturnType
        facts := wellKnownTypes
        if parameterTypes == null || returnType == null || facts == null {
            return null
        }

        parameterCount := parameterTypes.Count
        clrParameterTypes := new Type[](parameterCount)
        index := 0
        while index < parameterCount {
            clrParameterType := TryConvertTypeInfoToClrType(parameterTypes[index])
            if clrParameterType == null {
                return null
            }

            clrParameterTypes[index] = clrParameterType
            index = index + 1
        }

        clrReturnType := TryConvertTypeInfoToClrType(returnType)
        if clrReturnType == null {
            return null
        }

        // A void return picks the Action family; everything else picks Func, whose type arguments
        // are the parameters followed by the return type.
        if clrReturnType.FullName == "System.Void" {
            return ActionDelegateType(facts, clrParameterTypes)
        }

        funcTypes := new Type[](parameterCount + 1)
        copyIndex := 0
        while copyIndex < parameterCount {
            funcTypes[copyIndex] = clrParameterTypes[copyIndex]
            copyIndex = copyIndex + 1
        }

        funcTypes[parameterCount] = clrReturnType
        return FuncDelegateType(facts, funcTypes, parameterCount)
    }

    // `NSharpLang.Runtime.Union<,>` over exactly two converted arms. A union of any other arity has
    // no runtime representation, and a project without the runtime assembly has none at all.
    func TryConstructRuntimeUnionType(unionType: AnonymousUnionTypeInfo): Type? {
        facts := wellKnownTypes
        if facts == null {
            return null
        }

        unionOpen := facts.GetRuntimeUnionOpen()
        if unionOpen == null || unionType.Arms.Count != 2 {
            return null
        }

        firstArm := TryConvertTypeInfoToClrType(unionType.Arms[0])
        secondArm := TryConvertTypeInfoToClrType(unionType.Arms[1])
        if firstArm == null || secondArm == null {
            return null
        }

        arguments := new Type[](2)
        arguments[0] = firstArm
        arguments[1] = secondArm
        return unionOpen.MakeGenericType(arguments)
    }

    // `T?` is `Nullable<T>` only when T is a value type; over a reference type the annotation has no
    // CLR shape of its own and the inner type is the answer.
    func TryConvertNullableType(innerType: TypeInfo): Type? {
        clrInnerType := TryConvertTypeInfoToClrType(innerType)
        if clrInnerType == null {
            return null
        }

        facts := wellKnownTypes
        if facts == null {
            return null
        }

        nullableOpen := facts.NullableOpen
        if nullableOpen == null {
            return null
        }

        return WrapInNullable(nullableOpen, clrInnerType)
    }

    // A generic whose definition is either carried on the TypeInfo (an imported generic) or looked
    // up in the compiler-known table by name and arity. Type arguments convert EXACTLY, with one
    // exception: `JsonTypeInfo<T>` accepts a surrogate argument, because source-generated JSON
    // metadata is routinely written over N#-declared types and binding it is the whole point.
    func TryConstructKnownGenericType(genericType: GenericTypeInfo): Type? {
        definition := genericType.GenericDefinition
        candidateDefinition: Type? = null
        if definition == null {
            candidateDefinition = AnalyzerWellKnownTypeFacts.KnownOpenGenericType(wellKnownTypes, genericType.Name, genericType.TypeArguments.Count)
        } else {
            reflectionDefinition := definition as ReflectionTypeInfo
            if reflectionDefinition != null {
                candidateDefinition = reflectionDefinition.Type
            }
        }

        typeDefinition := NormalizeOpenDefinition(candidateDefinition)
        if typeDefinition == null || typeDefinition.GetGenericArguments().Length != genericType.TypeArguments.Count {
            return null
        }

        count := genericType.TypeArguments.Count
        arguments := new Type[](count)
        index := 0
        while index < count {
            typeArgument := genericType.TypeArguments[index]
            clrTypeArgument := TryConvertTypeInfoToClrType(typeArgument)
            if clrTypeArgument == null && IsJsonTypeInfoGenericName(genericType.Name) {
                clrTypeArgument = TryConvertTypeInfoToClrTypeForBinding(typeArgument)
            }

            if clrTypeArgument == null {
                return null
            }

            arguments[index] = clrTypeArgument
            index = index + 1
        }

        return CloseGenericDefinition(typeDefinition, genericType.Name, arguments)
    }

    // AN EXTERNAL GENERIC INSTANTIATED OVER AN OPEN TYPE PARAMETER, CLOSED FOR BINDING ONLY.
    //
    // `func FirstOf<U>(xs: List<U>)` and `class Mid<U>: List<U>` name a `List<U>` whose `U` has no CLR
    // handle anywhere in the analysis — it is the parameter the CALLER will fix — so both conversions
    // above answer null for it, and every member of the instantiation answered `unknown`: the call was
    // never bound, its result was silently untyped, and the emitter then declined with a return-type
    // mismatch against an empty type. A type parameter used as a type ARGUMENT is the same situation a
    // source type is in, and it gets the same surrogate: `object` in that slot, so the definition's
    // members can be found and a method group bound. The spelled `U` is what the answer carries — the
    // member arms read off the OPEN definition and the binder rebuilds every signature position from
    // the spelled receiver — so the `object` never survives into a type the program sees.
    //
    // A SEPARATE ENTRY POINT, NOT A WIDER `TryConvertTypeInfoToClrTypeForBinding`. That one also
    // measures ARGUMENTS for overload applicability, and `List<U>` passed where `List<object>` is
    // expected is not a conversion the CLR makes; this answer is only ever used where the instantiation
    // is the RECEIVER whose members are being looked up. A bare `U` still answers null, exactly as
    // `AnalyzerReflectionArgumentBinder.IsOpenWrittenTypeArgument` expects of a written type argument.
    func TryConvertOpenInstantiationForBinding(typeInfo: TypeInfo): Type? {
        facts := wellKnownTypes
        if facts == null {
            return null
        }

        genericType := declarationContext.ResolveDeclaredAlias(typeInfo) as GenericTypeInfo
        if genericType == null {
            return null
        }

        return ConstructSurrogateGenericType(facts, genericType, true)
    }

    // The surrogate half of generic construction. It reads the SMALLER surrogate vocabulary, and
    // every type argument converts through the surrogate entry point rather than the exact one.
    // `admitOpenTypeParameters` is the receiver-only widening `TryConvertOpenInstantiationForBinding`
    // asks for; every other caller passes false.
    func ConstructSurrogateGenericType(facts: AnalyzerWellKnownTypes, genericType: GenericTypeInfo, admitOpenTypeParameters: bool): Type? {
        definition := genericType.GenericDefinition
        candidateDefinition: Type? = null
        if definition == null {
            candidateDefinition = AnalyzerWellKnownTypeFacts.BindingSurrogateOpenGenericType(facts, genericType.Name, genericType.TypeArguments.Count)
        } else {
            reflectionDefinition := definition as ReflectionTypeInfo
            if reflectionDefinition != null {
                candidateDefinition = reflectionDefinition.Type
            }
        }

        typeDefinition := NormalizeOpenDefinition(candidateDefinition)
        if typeDefinition == null || typeDefinition.GetGenericArguments().Length != genericType.TypeArguments.Count {
            return null
        }

        count := genericType.TypeArguments.Count
        arguments := new Type[](count)
        index := 0
        while index < count {
            clrTypeArgument := SurrogateTypeArgument(facts, genericType.TypeArguments[index], admitOpenTypeParameters)
            if clrTypeArgument == null {
                return null
            }

            arguments[index] = clrTypeArgument
            index = index + 1
        }

        return CloseGenericDefinition(typeDefinition, genericType.Name, arguments)
    }

    // ONE TYPE ARGUMENT OF A SURROGATE INSTANTIATION. The ordinary surrogate answers first; only when
    // it cannot, and only when the caller admitted open parameters, does a type parameter — bare, or
    // nested inside another external generic such as `Dictionary<string, List<U>>` — bind as `object`.
    func SurrogateTypeArgument(facts: AnalyzerWellKnownTypes, typeArgument: TypeInfo, admitOpenTypeParameters: bool): Type? {
        converted := TryConvertTypeInfoToClrTypeForBinding(typeArgument)
        if converted != null || !admitOpenTypeParameters {
            return converted
        }

        resolved := declarationContext.ResolveDeclaredAlias(typeArgument)
        if IsOpenTypeParameter(facts, resolved) {
            return facts.Object
        }

        nested := resolved as GenericTypeInfo
        if nested != null {
            return ConstructSurrogateGenericType(facts, nested, true)
        }

        return null
    }

    // THE ANALYZER SPELLS A TYPE PARAMETER IN SCOPE AS A BARE `SimpleTypeInfo` (see
    // `AnalyzerScopeStack.DeclareTypeParameter`). Every built-in is spelled that way too, and every one
    // of them converts through `BuiltInClrType`; the four with no CLR form are excluded by name, and a
    // name that resolved to nothing is `unknown`, never a parameter.
    func IsOpenTypeParameter(facts: AnalyzerWellKnownTypes, candidate: TypeInfo): bool {
        simple := candidate as SimpleTypeInfo
        if simple == null || BuiltInTypes.IsUnknown(candidate) {
            return false
        }

        if BuiltInTypes.Is(candidate, BuiltInTypes.Null) || BuiltInTypes.Is(candidate, BuiltInTypes.Never) || BuiltInTypes.Is(candidate, BuiltInTypes.Void) {
            return false
        }

        return BuiltInClrType(facts, simple) == null
    }

    // Closing a definition over converted arguments must stay INSIDE one reflection context. The
    // definition can arrive from a different context than the arguments — the async call-return
    // wrap carries the RUNTIME `Task´1`/`ValueTask´1` while a declared annotation's argument is its
    // MetadataLoadContext twin — and `MakeGenericType` does not fail on the mix: it answers a
    // `TypeBuilderInstantiation`, whose every member lookup throws NotSupportedException. That
    // poisoned shape crashed `nlc check` on any member use of an `async func(): T` call result.
    // The mix is detected on the RESULT and re-homed into the arguments' context through the
    // compiler-known table; a close the CLR refuses outright (a metadata definition over a foreign
    // argument throws instead of poisoning) or a mix the table cannot re-home is a null answer —
    // never a poisoned instantiation.
    // A WRITTEN TUPLE'S CLR FORM: `System.ValueTuple`N` closed over the element types, with the
    // eighth and later elements nested in a REST tuple exactly as the CLR spells them.
    //
    // ELEMENT NAMES ARE NOT PART OF THE CLR TYPE. They travel in `TupleElementNamesAttribute` on the
    // declaring POSITION, so `(Item: string, Count: int)` and `(string, int)` convert to the same
    // `ValueTuple<string, int>` -- which is what makes a written tuple usable as a type argument to a
    // referenced assembly's generic method at all. Without this arm the funnel answered null for
    // every tuple, and `Enumerable.Empty<(int, string)>()` was rejected before its arguments were
    // ever scored.
    func TryConstructValueTupleType(elements: List<TupleTypeElementInfo>, start: int): Type? {
        remaining := elements.Count - start
        if remaining <= 0 {
            return null
        }

        arity := remaining
        restType: Type? = null
        if remaining > 7 {
            arity = 8
            restType = TryConstructValueTupleType(elements, start + 7)
            if restType == null {
                return null
            }
        }

        openDefinition := typeof(object)
        if !declarationContext.TryResolveKnownOpenGeneric("ValueTuple", arity, out openDefinition) {
            return null
        }

        arguments := new Type[](arity)
        index := 0
        while index < arity {
            if restType != null && index == 7 {
                arguments[index] = restType
            } else {
                converted := TryConvertTypeInfoToClrType(elements[start + index].Type)
                if converted == null {
                    return null
                }

                arguments[index] = converted
            }

            index = index + 1
        }

        return CloseGenericDefinition(openDefinition, "ValueTuple", arguments)
    }

    func CloseGenericDefinition(typeDefinition: Type, genericName: string, arguments: Type[]): Type? {
        closed: Type? = null
        try {
            closed = typeDefinition.MakeGenericType(arguments)
        } catch {
            closed = null
        }

        if closed != null {
            if !IsPoisonedMixedInstantiation(closed) {
                return closed
            }
        }

        rehomed := NormalizeOpenDefinition(AnalyzerWellKnownTypeFacts.KnownOpenGenericType(wellKnownTypes, genericName, arguments.Length))
        if rehomed == null {
            return null
        }

        if rehomed.GetGenericArguments().Length != arguments.Length {
            return null
        }

        reclosed: Type? = null
        try {
            reclosed = rehomed.MakeGenericType(arguments)
        } catch {
            reclosed = null
        }

        if reclosed == null {
            return null
        }

        if IsPoisonedMixedInstantiation(reclosed) {
            return null
        }

        return reclosed
    }

    // The CLR's answer for a generic instantiation whose definition and arguments come from
    // different reflection universes, named by its implementation class because the platform
    // exposes no public predicate for it. The mixed-context contract pins this detection, so a
    // platform rename fails a test rather than silently reopening the crash.
    static func IsPoisonedMixedInstantiation(closed: Type): bool {
        boxed := closed as object
        return boxed.GetType().Name == "TypeBuilderInstantiation"
    }

    // A built-in simple type read out of the metadata facts. A simple type that is not one of the
    // sixteen built-ins has no CLR spelling here and answers null.
    func BuiltInClrType(facts: AnalyzerWellKnownTypes, simple: SimpleTypeInfo): Type? {
        if BuiltInTypes.Is(simple, BuiltInTypes.Int) {
            return facts.Int32
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Long) {
            return facts.Int64
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Float) {
            return facts.Single
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Double) {
            return facts.Double
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Decimal) {
            return facts.Decimal
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Byte) {
            return facts.Byte
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.SByte) {
            return facts.SByte
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Short) {
            return facts.Int16
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.UShort) {
            return facts.UInt16
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.UInt) {
            return facts.UInt32
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.ULong) {
            return facts.UInt64
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Char) {
            return facts.Char
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Bool) {
            return facts.Boolean
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.String) {
            return facts.String
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Void) {
            return facts.Void
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Object) {
            return facts.Object
        }
        return null
    }

    func ActionDelegateType(facts: AnalyzerWellKnownTypes, parameterTypes: Type[]): Type? {
        count := parameterTypes.Length
        if count == 0 {
            return facts.Action
        }
        if count == 1 {
            return MakeGenericOrNull(facts.Action1, parameterTypes)
        }
        if count == 2 {
            return MakeGenericOrNull(facts.Action2, parameterTypes)
        }
        if count == 3 {
            return MakeGenericOrNull(facts.Action3, parameterTypes)
        }
        if count == 4 {
            return MakeGenericOrNull(facts.Action4, parameterTypes)
        }
        return null
    }

    func FuncDelegateType(facts: AnalyzerWellKnownTypes, funcTypes: Type[], parameterCount: int): Type? {
        if parameterCount == 0 {
            return MakeGenericOrNull(facts.Func1, funcTypes)
        }
        if parameterCount == 1 {
            return MakeGenericOrNull(facts.Func2, funcTypes)
        }
        if parameterCount == 2 {
            return MakeGenericOrNull(facts.Func3, funcTypes)
        }
        if parameterCount == 3 {
            return MakeGenericOrNull(facts.Func4, funcTypes)
        }
        if parameterCount == 4 {
            return MakeGenericOrNull(facts.Func5, funcTypes)
        }
        return null
    }

    // THE NEAREST CLR TYPE A SOURCE-DECLARED TYPE IS KNOWN TO BE, by walking the `:` clause.
    //
    // The walk is the DECLARED base chain, not the CLR one, because the derived links have no CLR
    // form yet: `class Deeper: Names` and `class Names: List<string>` answer `List<string>` for both.
    // Only the EXACT conversion is accepted for a link, so a base the CLR cannot name either — a
    // source generic instantiated over a source type, say — keeps walking rather than contributing a
    // surrogate of its own; the chain then ends at `object` exactly as it did before.
    //
    // The depth bound is what makes a cyclic `:` clause a null answer instead of a hang. A cycle is a
    // program error the declaration walk reports; this owner reports nothing, so it must simply stop.
    func TryConvertDeclaredBaseChainToClrType(sourceType: TypeInfo): Type? {
        current := sourceType
        depth := 0
        while depth < 64 {
            shape := new AnalyzerSourceMemberShape()
            if !declarationContext.TryGetSourceMemberShape(current, null, out shape) {
                return null
            }

            declaredBase := shape.BaseType
            if declaredBase == null {
                return null
            }

            resolvedBase := declarationContext.ResolveDeclaredAlias(declaredBase)
            externalBase := TryConvertTypeInfoToClrType(resolvedBase)
            if externalBase != null {
                return externalBase
            }

            current = resolvedBase
            depth = depth + 1
        }

        return null
    }

    // THE EXTERNAL BASE A SOURCE TYPE'S `:` CLAUSE REACHES, AS WRITTEN — the TypeInfo twin of
    // `TryConvertDeclaredBaseChainToClrType`, and the reason it exists is the one position that walk
    // cannot express. `class Mid<U>: List<U>` IS a `List<U>`, but `List<U>` has no exact CLR form, so
    // the CLR walk stepped past it and answered nothing; and even for `class Names: List<string>`,
    // which it does answer, it hands back a CLR type with the spelling gone. A call on a `Mid<U>`
    // receiver binds against `List<T>`'s members, and the binder reads `T` off the receiver's SPELLED
    // type arguments — so the receiver it is given has to be the base as the source wrote it.
    //
    // A SOURCE GENERIC receiver (`Mid<int>` written outside the declaration) walks its definition
    // under the substitution its arguments induce, so the answer is `List<int>` rather than
    // `List<U>`. The answer is only ever an instantiation the CLR can bind against — exactly or through
    // `TryConvertOpenInstantiationForBinding` — and a receiver that is not a source type at all, or
    // whose chain ends without reaching one, answers null. The depth bound is a cyclic `:` clause's
    // null answer, as it is in the CLR walk above.
    func TryResolveDeclaredExternalBase(sourceType: TypeInfo): TypeInfo? {
        current := declarationContext.ResolveDeclaredAlias(sourceType)
        depth := 0
        while depth < 64 {
            owner := current
            substitution: Dictionary<string, TypeInfo>? = null
            sourceGeneric := current as GenericTypeInfo
            if sourceGeneric != null {
                definition := sourceGeneric.GenericDefinition
                if definition != null && definition as ReflectionTypeInfo == null {
                    substitution = declarationContext.CreateGenericSubstitution(definition, sourceGeneric.TypeArguments)
                    owner = definition
                }
            }

            shape := new AnalyzerSourceMemberShape()
            if !declarationContext.TryGetSourceMemberShape(owner, substitution, out shape) {
                if depth == 0 {
                    return null
                }

                if TryConvertTypeInfoToClrType(current) != null || TryConvertOpenInstantiationForBinding(current) != null {
                    return current
                }

                return null
            }

            declaredBase := shape.BaseType
            if declaredBase == null {
                return null
            }

            current = declarationContext.ResolveDeclaredAlias(declaredBase)
            depth = depth + 1
        }

        return null
    }

    // The seven N#-declared families that get a CLR surrogate. Everything else — simple types,
    // unknowns, tuples, method groups, anonymous unions — does not.
    static func IsSurrogateUserDefinedType(candidate: TypeInfo): bool {
        classType := candidate as ClassTypeInfo
        if classType != null {
            return true
        }
        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return true
        }
        structType := candidate as StructTypeInfo
        if structType != null {
            return true
        }
        interfaceType := candidate as InterfaceTypeInfo
        if interfaceType != null {
            return true
        }
        unionType := candidate as UnionTypeInfo
        if unionType != null {
            return true
        }
        enumType := candidate as EnumTypeInfo
        if enumType != null {
            return true
        }
        newtypeType := candidate as NewtypeInfo
        if newtypeType != null {
            return true
        }
        return false
    }

    // Reduces a candidate definition to an OPEN generic definition: a closed generic gives up its
    // definition, an already-open one is itself, and anything non-generic is not a definition at all.
    static func NormalizeOpenDefinition(candidate: Type?): Type? {
        if candidate == null {
            return null
        }

        if candidate.IsGenericType && !candidate.IsGenericTypeDefinition {
            return candidate.GetGenericTypeDefinition()
        }

        if !candidate.IsGenericTypeDefinition {
            return null
        }

        return candidate
    }

    static func WrapInNullable(nullableOpen: Type, clrInnerType: Type): Type {
        if !clrInnerType.IsValueType {
            return clrInnerType
        }

        arguments := new Type[](1)
        arguments[0] = clrInnerType
        return nullableOpen.MakeGenericType(arguments)
    }

    static func MakeGenericOrNull(definition: Type?, arguments: Type[]): Type? {
        if definition == null {
            return null
        }

        return definition.MakeGenericType(arguments)
    }

    // Both spellings the analyzer may carry for `JsonTypeInfo<T>`.
    static func IsJsonTypeInfoGenericName(name: string): bool {
        return name == "JsonTypeInfo" || name == "System.Text.Json.Serialization.Metadata.JsonTypeInfo"
    }
}
