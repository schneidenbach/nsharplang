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

        if IsSurrogateUserDefinedType(resolvedType) {
            return facts.Object
        }

        genericType := resolvedType as GenericTypeInfo
        if genericType != null {
            return ConstructSurrogateGenericType(facts, genericType)
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
        if clrReturnType.get_FullName() == "System.Void" {
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

        return typeDefinition.MakeGenericType(arguments)
    }

    // The surrogate half of generic construction. It reads the SMALLER surrogate vocabulary, and
    // every type argument converts through the surrogate entry point rather than the exact one.
    func ConstructSurrogateGenericType(facts: AnalyzerWellKnownTypes, genericType: GenericTypeInfo): Type? {
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
            clrTypeArgument := TryConvertTypeInfoToClrTypeForBinding(genericType.TypeArguments[index])
            if clrTypeArgument == null {
                return null
            }

            arguments[index] = clrTypeArgument
            index = index + 1
        }

        return typeDefinition.MakeGenericType(arguments)
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

    // The seven N#-declared families that get an `object` surrogate. Everything else — simple types,
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

        if candidate.get_IsGenericType() && !candidate.get_IsGenericTypeDefinition() {
            return candidate.GetGenericTypeDefinition()
        }

        if !candidate.get_IsGenericTypeDefinition() {
            return null
        }

        return candidate
    }

    static func WrapInNullable(nullableOpen: Type, clrInnerType: Type): Type {
        if !clrInnerType.get_IsValueType() {
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
