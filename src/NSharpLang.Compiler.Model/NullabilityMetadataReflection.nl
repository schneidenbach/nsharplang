namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection


// The reflection half of the nullability metadata reader. `NullabilityMetadataCore` already owns
// every decision that is a pure function of facts; this class owns the READING of those facts off
// CLR reflection — the `NullabilityInfoContext` walk, the `CustomAttributeData` scan and the CLR
// display form — and composes the two.
//
// Shape notes, all measured rather than assumed (see STATUS.md's slice-12 record):
//   * `new NullabilityInfoContext()` is not on the emitter's `new` chain, so the context is built
//     through its reflected constructor with an `object?[]` argument array.
//   * `GetCustomAttributesData()` and `ConstructorArguments` answer a closed `IList<T>`, whose
//     `Count` lives on `ICollection<T>` and is therefore invisible to a generic-interface receiver.
//     `SequenceCount` routes through an `object` local and the non-generic `IList` instead.
//   * A boxed value cannot be unboxed, so the `[NotNullWhen(...)]` argument is compared against a
//     boxed constant.
//
// THE TYPE OVERRIDE IS DATA, NOT A FUNCTION. A caller that needs some positions answered with the N#
// types a call site supplied hands in an `AnalyzerReflectionTypeOverride` — the bindings themselves —
// so nothing crosses a boundary and the override always ANSWERS rather than declining. (Slice 12B
// carried it as `Func<Type, object>` because the conversion it composed with was still C#; with that
// conversion N#-owned there is no boundary left to encode.)
class NullabilityMetadataReflection {
    static func ConvertType(clrType: Type): TypeInfo {
        return ConvertReflectedType(clrType, null, null)
    }

    // THE OVERRIDE ARM IS BACK, AND IT HAS A CALLER NOW. The note that used to sit here said the C#
    // original took a type override that nothing ever passed, so it was not carried across. Hover
    // over a member of a CONSTRUCTED generic is that caller: `list.ToArray()` is resolved on the
    // generic DEFINITION, so its `T` has to be mapped back to the receiver's real type argument or
    // the answer is a confident lie (`object[]` for a `List<WeatherForecast>`).
    static func ConvertProperty(property: PropertyInfo): TypeInfo {
        return ConvertPropertyWithOverride(property, null)
    }

    static func ConvertPropertyWithOverride(property: PropertyInfo, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        attributes := property.GetCustomAttributesData()
        openType := NullabilityGenericSubstitution.OpenPropertyType(property)
        converted := AnalyzerTupleElementNames.ApplyDeclared(ConvertMemberType(property.PropertyType, CreateNullabilityInfoForProperty(property), typeOverride, openType, attributes, property), attributes)
        return NullabilityMetadataCore.AttachReferencedNullabilityOrigin(ApplyFlowAttributes(converted, attributes), property)
    }

    static func ConvertField(field: FieldInfo): TypeInfo {
        return ConvertFieldWithOverride(field, null)
    }

    static func ConvertFieldWithOverride(field: FieldInfo, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        attributes := field.GetCustomAttributesData()
        openType := NullabilityGenericSubstitution.OpenFieldType(field)
        converted := AnalyzerTupleElementNames.ApplyDeclared(ConvertMemberType(field.FieldType, CreateNullabilityInfoForField(field), typeOverride, openType, attributes, field), attributes)
        return NullabilityMetadataCore.AttachReferencedNullabilityOrigin(ApplyFlowAttributes(converted, attributes), field)
    }

    static func ConvertParameter(parameter: ParameterInfo): TypeInfo {
        return ConvertParameterWithOverride(parameter, null)
    }

    static func ConvertParameterWithOverride(parameter: ParameterInfo, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        attributes := parameter.GetCustomAttributesData()
        openType := NullabilityGenericSubstitution.OpenParameterType(parameter)
        converted := AnalyzerTupleElementNames.ApplyDeclared(ConvertMemberType(parameter.ParameterType, CreateNullabilityInfoForParameter(parameter), typeOverride, openType, attributes, parameter.Member), attributes)
        return NullabilityMetadataCore.AttachReferencedParameterNullabilityOrigin(ApplyFlowAttributes(converted, attributes), parameter)
    }

    // AN EVENT'S HANDLER DELEGATE TYPE, WITH THE ANNOTATIONS THE DECLARATION WROTE.
    //
    // WHY AN EVENT NEEDS ITS OWN READER AT ALL. `EventInfo.EventHandlerType` answers a bare CLR type,
    // and reference-type nullability is not IN a CLR type — it is metadata on the MEMBER. So
    // `AssemblyLoadContext.Resolving`, declared `event Func<AssemblyLoadContext, AssemblyName,
    // Assembly?>?`, reflects as `Func`3[AssemblyLoadContext, AssemblyName, Assembly]` and a handler
    // returning `Assembly?` did not match the event it obviously implements. The annotation is right
    // there on the event (measured: `NullabilityInfoContext.Create(EventInfo)` answers
    // `Nullable`/`NotNull`/`NotNull`/`Nullable` for that one), and every other member family already
    // reads it, so the event reads it too.
    //
    // THE EVENT'S OWN MAYBE-NULL SHELL IS DROPPED, and that is a statement about what the type MEANS
    // rather than a convenience. `event Func<…>? Resolving` says the event's backing field may hold no
    // handler yet; it says nothing about the handler a subscriber attaches, which is never the null.
    // The lambda door makes the same reading for the same reason (`FunctionSignature` looks through a
    // `NullableTypeInfo` target), so answering the delegate directly keeps one rule in one place.
    static func ConvertEventHandlerType(eventMember: EventInfo): TypeInfo? {
        handlerType := eventMember.EventHandlerType
        if handlerType == null {
            return null
        }

        attributes := eventMember.GetCustomAttributesData()
        openType := NullabilityGenericSubstitution.OpenEventHandlerType(eventMember, handlerType)
        converted := NullabilityMetadataCore.AttachReferencedNullabilityOrigin(ConvertMemberType(handlerType, CreateNullabilityInfoForEvent(eventMember), null, openType, attributes, eventMember), eventMember)
        nullableShell := converted as NullableTypeInfo
        if nullableShell != null {
            return nullableShell.InnerType
        }

        return converted
    }

    static func ConvertReturn(method: MethodInfo): TypeInfo {
        return ConvertReturnWithOverride(method, null)
    }

    static func ConvertReturnWithOverride(method: MethodInfo, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        returnParameter := method.ReturnParameter
        attributes := returnParameter.GetCustomAttributesData()
        openType := NullabilityGenericSubstitution.OpenParameterType(returnParameter)
        converted := AnalyzerTupleElementNames.ApplyDeclared(ConvertMemberType(method.ReturnType, CreateNullabilityInfoForParameter(returnParameter), typeOverride, openType, attributes, method), attributes)
        return NullabilityMetadataCore.AttachReferencedNullabilityOrigin(ApplyFlowAttributes(converted, attributes), method)
    }

    static func FormatType(clrType: Type): string {
        return FormatTypeInfo(ConvertType(clrType))
    }

    static func FormatParameter(parameter: ParameterInfo): string {
        return FormatParameterWithOverride(parameter, null)
    }

    static func FormatParameterWithOverride(parameter: ParameterInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        attributePrefix := FormatFlowAttributes(parameter.GetCustomAttributesData())
        typeName := FormatTypeInfo(ConvertParameterWithOverride(parameter, typeOverride))
        parameterType := parameter.ParameterType
        return NullabilityMetadataCore.FormatParameter(parameter.IsOut, parameterType.IsByRef, parameterType.IsByRef && parameter.IsIn, IsParamsParameter(parameter), attributePrefix, typeName, parameter.Name)
    }

    static func FormatReturnType(method: MethodInfo): string {
        return FormatReturnTypeWithOverride(method, null)
    }

    static func FormatReturnTypeWithOverride(method: MethodInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        return FormatTypeInfo(ConvertReturnWithOverride(method, typeOverride))
    }

    static func FormatTypeInfo(typeInfo: TypeInfo): string {
        reflection := typeInfo as ReflectionTypeInfo
        if reflection != null {
            return FormatClrTypeName(reflection.Type)
        }

        return NullabilityMetadataCore.FormatTypeInfo(typeInfo)
    }

    static func StripMetadata(typeInfo: TypeInfo): TypeInfo {
        return NullabilityMetadataCore.StripMetadata(typeInfo)
    }

    // ONE MEMBER POSITION, WITH THE SUBSTITUTION'S SAY ON ITS READ STATE.
    //
    // `NullabilityInfoContext` answers `Nullable` for every position declared with a BARE type
    // parameter — it must, because an unconstrained `T` may be instantiated with a nullable type —
    // so taking its answer made `Lazy<string>.Value`, `Task<string>.Result`, `Tuple<string,int>.Item1`
    // and a `Predicate<string>` lambda's parameter all maybe-null. The compiler KNOWS the argument:
    // the substituted position's nullability is the type ARGUMENT's, and only an annotation the
    // MEMBER wrote (`T?`, i.e. `NullableAttribute(2)`) overrides it. `[MaybeNull]` / `[NotNull]` are
    // a separate pass and still apply on top. See `NullabilityGenericSubstitution`.
    static func ConvertMemberType(clrType: Type, nullabilityInfo: NullabilityInfo?, typeOverride: AnalyzerReflectionTypeOverride?, openType: Type?, attributes: IList<CustomAttributeData>, member: MemberInfo?): TypeInfo {
        // `NullablePublicOnly` means a non-public member can inherit an assembly/type context even
        // though the compiler deliberately omitted this member's nullable transform. Clear the
        // whole tree before converting it: an omitted nested generic argument is just as oblivious
        // as the member's outer reference type.
        if ShouldForceObliviousPosition(attributes, member) {
            return ConvertReflectedType(clrType, null, typeOverride)
        }

        if !NullabilityGenericSubstitution.IsTypeParameterPosition(openType) {
            return ConvertReflectedType(clrType, nullabilityInfo, typeOverride)
        }

        annotationFlag := NullabilityGenericSubstitution.ReadAnnotationFlag(attributes, member)
        if ShouldForceObliviousPosition(attributes, member) {
            annotationFlag = 0
        }

        return ConvertSubstitutedParameterType(clrType, nullabilityInfo, typeOverride, annotationFlag)
    }

    static func ConvertReflectedType(clrType: Type, nullabilityInfo: NullabilityInfo?, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        effectiveType := DereferenceByRef(clrType)
        if effectiveType.IsGenericParameter && typeOverride != null {
            return typeOverride.Answer(effectiveType)
        }

        readState := GetReadState(nullabilityInfo)
        converted := ConvertReflectedTypeCore(effectiveType, nullabilityInfo, typeOverride)
        return NullabilityMetadataCore.ApplyReadState(converted, IsNullableValueType(effectiveType), CanReflectedTypeCarryReferenceNullability(effectiveType, converted), readState == NullabilityState.Nullable, readState == NullabilityState.Unknown)
    }

    // THE SUBSTITUTED-PARAMETER FORM. It differs from the one above in exactly one way: the TOP-LEVEL
    // read state is SUPPLIED rather than read, because for a bare type parameter metadata's answer is
    // not the language's. Everything nested inside is converted by the ordinary walk, which is right —
    // a nested position is about a type ARGUMENT the member really did write.
    //
    // The override arm has to honour the supplied state too. `Enumerable.FirstOrDefault<TSource>`
    // returns `TSource?`, and the override alone answers the ARGUMENT verbatim, which loses the `?`.
    static func ConvertSubstitutedParameterType(clrType: Type, nullabilityInfo: NullabilityInfo?, typeOverride: AnalyzerReflectionTypeOverride?, annotationFlag: int): TypeInfo {
        effectiveType := DereferenceByRef(clrType)
        if effectiveType.IsGenericParameter && typeOverride != null {
            answered := typeOverride.Answer(effectiveType)
            if annotationFlag < 0 || annotationFlag == 1 {
                return answered
            }

            return NullabilityMetadataCore.ApplyReadState(answered, false, CanConvertedTypeCarryReferenceNullability(answered), annotationFlag == 2, annotationFlag == 0)
        }

        converted := ConvertReflectedTypeCore(effectiveType, nullabilityInfo, typeOverride)
        return NullabilityMetadataCore.ApplyReadState(converted, IsNullableValueType(effectiveType), CanReflectedTypeCarryReferenceNullability(effectiveType, converted), annotationFlag == 2, annotationFlag == 0)
    }

    static func DereferenceByRef(clrType: Type): Type {
        if !clrType.IsByRef {
            return clrType
        }

        element := clrType.GetElementType()
        if element == null {
            return clrType
        }

        return element
    }

    static func ConvertReflectedTypeCore(clrType: Type, nullabilityInfo: NullabilityInfo?, typeOverride: AnalyzerReflectionTypeOverride?): TypeInfo {
        if clrType.IsByRef {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return ConvertReflectedType(byRefElement, nullabilityInfo, typeOverride)
            }
        }

        if IsNullableValueType(clrType) {
            underlying := ExternalUserDefinedConversions.NullableUnderlyingTypeOrNull(clrType)
            if underlying != null {
                nullable: TypeInfo = new NullableTypeInfo(ConvertReflectedType(underlying, GetFirstGenericArgument(nullabilityInfo), typeOverride))
                return nullable
            }
        }

        if clrType.IsArray {
            elementType := clrType.GetElementType()
            if elementType != null {
                array: TypeInfo = new ArrayTypeInfo(ConvertReflectedType(elementType, GetElementNullability(nullabilityInfo), typeOverride))
                return array
            }
        }

        if clrType.IsGenericParameter {
            if typeOverride != null {
                return typeOverride.Answer(clrType)
            }

            genericParameter: TypeInfo = new SimpleTypeInfo(clrType.Name)
            return genericParameter
        }

        if clrType.IsGenericType {
            name := NullabilityMetadataCore.StripClrGenericArity(clrType.Name)
            typeArguments := clrType.GetGenericArguments()
            nullabilityArguments := GetGenericNullabilityArguments(nullabilityInfo)
            convertedArguments := new List<TypeInfo>()
            index := 0
            while index < typeArguments.Length {
                argumentNullability: NullabilityInfo? = null
                if index < nullabilityArguments.Length {
                    argumentNullability = nullabilityArguments[index]
                }

                convertedArguments.Add(ConvertReflectedType(typeArguments[index], argumentNullability, typeOverride))
                index = index + 1
            }

            constructed: TypeInfo = ReflectionTypeInfoFactory.FromConstructedGeneric(name, convertedArguments, clrType)
            return constructed
        }

        if typeOverride != null {
            return typeOverride.Answer(clrType)
        }

        builtIn := NullabilityMetadataCore.ConvertBuiltInType(clrType.FullName)
        if builtIn != null {
            return builtIn
        }

        reflected: TypeInfo = new ReflectionTypeInfo(clrType)
        return reflected
    }

    // NullablePublicOnly marks signatures whose nullable annotations were omitted for inaccessible
    // members. An explicit NullableAttribute on the position still wins; when it is absent, inherited
    // context must not make the omitted signature look non-nullable.
    static func ShouldForceObliviousPosition(attributes: IList<CustomAttributeData>, member: MemberInfo?): bool {
        if member == null {
            return false
        }

        moduleAttributes := member.Module.GetCustomAttributesData()
        return ShouldForceObliviousPosition(attributes, member, HasNullablePublicOnly(moduleAttributes), NullablePublicOnlyIncludesInternals(moduleAttributes))
    }

    // Kept as a fact-only overload so the public-only boundary can be tested without manufacturing
    // an assembly carrying the compiler's internal attribute.
    static func ShouldForceObliviousPosition(attributes: IList<CustomAttributeData>, member: MemberInfo, hasNullablePublicOnly: bool, includeInternals: bool): bool {
        if HasNullableAttribute(attributes) || !hasNullablePublicOnly {
            return false
        }

        return !IsInNullablePublicSurface(member, includeInternals)
    }

    static func HasNullableAttribute(attributes: IList<CustomAttributeData>): bool {
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            if string.Equals(attributes.get_Item(index).AttributeType.FullName ?? "", "System.Runtime.CompilerServices.NullableAttribute", StringComparison.Ordinal) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func HasNullablePublicOnly(attributes: IList<CustomAttributeData>): bool {
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            if string.Equals(attributes.get_Item(index).AttributeType.FullName ?? "", "System.Runtime.CompilerServices.NullablePublicOnlyAttribute", StringComparison.Ordinal) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func NullablePublicOnlyIncludesInternals(attributes: IList<CustomAttributeData>): bool {
        falseValue: object = false
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            if !string.Equals(attribute.AttributeType.FullName ?? "", "System.Runtime.CompilerServices.NullablePublicOnlyAttribute", StringComparison.Ordinal) {
                index = index + 1
                continue
            }

            arguments := attribute.ConstructorArguments
            if SequenceCount(arguments) == 1 {
                value := arguments.get_Item(0).get_Value()
                if value != null {
                    boxed: object = value
                    return boxed.Equals(falseValue) == false
                }
            }

            return false
        }

        return false
    }

    static func IsInNullablePublicSurface(member: MemberInfo, includeInternals: bool): bool {
        owner := member.DeclaringType
        if owner != null && !IsTypeInNullablePublicSurface(owner, includeInternals) {
            return false
        }

        method := member as MethodBase
        if method != null {
            return method.IsPublic || method.IsFamily || method.IsFamilyOrAssembly || (includeInternals && (method.IsAssembly || method.IsFamilyAndAssembly))
        }

        field := member as FieldInfo
        if field != null {
            return field.IsPublic || field.IsFamily || field.IsFamilyOrAssembly || (includeInternals && (field.IsAssembly || field.IsFamilyAndAssembly))
        }

        property := member as PropertyInfo
        if property != null {
            return IsIncludedAccessor(property.GetMethod, includeInternals) || IsIncludedAccessor(property.SetMethod, includeInternals)
        }

        eventMember := member as EventInfo
        if eventMember != null {
            return IsIncludedAccessor(eventMember.AddMethod, includeInternals) || IsIncludedAccessor(eventMember.RemoveMethod, includeInternals) || IsIncludedAccessor(eventMember.RaiseMethod, includeInternals)
        }

        return owner == null
    }

    static func IsTypeInNullablePublicSurface(type: Type, includeInternals: bool): bool {
        current: Type? = type
        while current != null {
            if current.IsNested {
                if !current.IsNestedPublic && !current.IsNestedFamily && !current.IsNestedFamORAssem && !(includeInternals && (current.IsNestedAssembly || current.IsNestedFamANDAssem)) {
                    return false
                }
            } else if !current.IsPublic && !(includeInternals && current.IsNotPublic) {
                return false
            }

            current = current.DeclaringType
        }

        return true
    }

    static func IsIncludedAccessor(accessor: MethodInfo?, includeInternals: bool): bool {
        return accessor != null && (accessor.IsPublic || accessor.IsFamily || accessor.IsFamilyOrAssembly || (includeInternals && (accessor.IsAssembly || accessor.IsFamilyAndAssembly)))
    }

    static func ApplyFlowAttributes(typeInfo: TypeInfo, attributes: IList<CustomAttributeData>): TypeInfo {
        return NullabilityMetadataCore.ApplyFlowAttributeFacts(typeInfo, HasAttributeKind(attributes, NullabilityMetadataCore.GetMaybeNullAttributeKind()), HasAttributeKind(attributes, NullabilityMetadataCore.GetNotNullAttributeKind()))
    }

    // `NullabilityInfoContext` caches per instance, and the C# original built a fresh one per
    // request; keeping that exactly preserves the observed answers as well as the cost profile.
    static func CreateNullabilityContext(): NullabilityInfoContext {
        return new NullabilityInfoContext()
    }

    static func CreateNullabilityInfoForProperty(property: PropertyInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(property)
    }

    static func CreateNullabilityInfoForField(field: FieldInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(field)
    }

    static func CreateNullabilityInfoForEvent(eventMember: EventInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(eventMember)
    }

    static func CreateNullabilityInfoForParameter(parameter: ParameterInfo): NullabilityInfo? {
        context := CreateNullabilityContext()
        return context.Create(parameter)
    }

    static func GetElementNullability(info: NullabilityInfo?): NullabilityInfo? {
        if info == null {
            return null
        }

        return info.ElementType
    }

    static func GetGenericNullabilityArguments(info: NullabilityInfo?): NullabilityInfo[] {
        if info == null {
            return new NullabilityInfo[](0)
        }

        arguments := info.GenericTypeArguments
        if arguments == null {
            return new NullabilityInfo[](0)
        }

        return arguments
    }

    static func GetFirstGenericArgument(info: NullabilityInfo?): NullabilityInfo? {
        arguments := GetGenericNullabilityArguments(info)
        if arguments.Length == 0 {
            return null
        }

        return arguments[0]
    }

    static func GetReadState(nullabilityInfo: NullabilityInfo?): NullabilityState {
        if nullabilityInfo == null {
            return NullabilityState.Unknown
        }

        return nullabilityInfo.ReadState
    }

    static func CanReflectedTypeCarryReferenceNullability(clrType: Type, converted: TypeInfo): bool {
        return NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(clrType.IsGenericParameter, clrType.IsValueType, CanConvertedTypeCarryReferenceNullability(converted))
    }

    // A CONSTRUCTED GENERIC IS WHATEVER ITS DEFINITION IS. `KeyValuePair<string, DateTime>` is a
    // STRUCT, and asking only the outer shape said "a reference type, so it can be annotated `?`" —
    // which is how `times.OrderBy(kvp => kvp.Value).FirstOrDefault()` came back as
    // `KeyValuePair<string, DateTime>?` while the same call over `IEnumerable<DateTime>` came back
    // as `DateTime`. The difference was never the language's: it was that a non-generic external
    // struct converts to a `ReflectionTypeInfo` the arm above answers for, and a constructed one
    // converts to a `GenericTypeInfo` whose kind lives on the DEFINITION it carries.
    //
    // This is the same question `AnalyzerConversionFacts.IsReferenceType` asks of a constructed
    // generic, and it is answered the same way, so the two owners cannot disagree about a
    // `KeyValuePair`.
    static func CanConvertedTypeCarryReferenceNullability(typeInfo: TypeInfo): bool {
        reflection := typeInfo as ReflectionTypeInfo
        if reflection != null {
            reflectedType := reflection.Type
            return !reflectedType.IsValueType
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            genericDefinition := generic.GenericDefinition
            if genericDefinition != null {
                return CanConvertedTypeCarryReferenceNullability(genericDefinition)
            }
        }

        return NullabilityMetadataCore.CanCarryReferenceNullability(typeInfo)
    }

    // `Nullable.GetUnderlyingType` IS `typeof(Nullable<>)`-BASED, AND THE ANALYZER'S TYPES ARE NOT
    // THIS PROCESS'S. Under a MetadataLoadContext the projected `System.Nullable`1` is a different
    // object from `typeof(Nullable<>)`, so the BCL helper answered null for every `int?` that came
    // from a referenced assembly: the parameter converted to a `GenericTypeInfo` named "Nullable"
    // rather than to the `NullableTypeInfo` that `int?` in N# source produces, and an `int?` argument
    // therefore did not match an `int?` parameter in either direction — with the NL402 hint printing
    // the two halves of one type as `SymbolKind?` and `Nullable<SymbolKind>` in the same sentence.
    // The by-metadata-name reader beside the external conversion table already had this exact
    // insight written down; this is the same question, so it is the same answer.
    static func IsNullableValueType(clrType: Type): bool {
        return ExternalUserDefinedConversions.NullableUnderlyingTypeOrNull(clrType) != null
    }

    // `Count` is declared on `ICollection<T>`, which a generic-interface receiver's own member
    // lookup does not reach; the non-generic `IList` reached through an `object` local is the same
    // instance and the same value.
    static func SequenceCount(sequence: object): int {
        list := (IList)sequence
        return list.Count
    }

    static func HasAttributeKind(attributes: IList<CustomAttributeData>, attributeKind: int): bool {
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.AttributeType
            if NullabilityMetadataCore.GetFlowAttributeKind(attributeType.FullName) == attributeKind {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsParamsParameter(parameter: ParameterInfo): bool {
        return HasAttributeKind(parameter.GetCustomAttributesData(), NullabilityMetadataCore.GetParamArrayAttributeKind())
    }

    static func FormatFlowAttributes(attributes: IList<CustomAttributeData>): string {
        hasNotNullWhen := false
        notNullWhenValue := false
        hasMaybeNull := false
        hasNotNull := false
        hasAllowNull := false
        hasDisallowNull := false
        falseValue: object = false
        trueValue: object = true

        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.AttributeType
            attributeKind := NullabilityMetadataCore.GetFlowAttributeKind(attributeType.FullName)
            handled := false
            if attributeKind == NullabilityMetadataCore.GetNotNullWhenAttributeKind() {
                constructorArguments := attribute.ConstructorArguments
                if SequenceCount(constructorArguments) == 1 {
                    argument := constructorArguments.get_Item(0)
                    argumentValue := argument.get_Value()
                    boxedValue: object = argumentValue ?? falseValue
                    // `is bool` over a boxed value: only a boxed bool equals a boxed bool, and the
                    // argument's own `ArgumentType` is NOT usable here — under a
                    // MetadataLoadContext it is a PROJECTED `System.Boolean` that is not
                    // `typeof(bool)`, while `Value` is still a live boxed CLR bool.
                    isTrue := argumentValue != null && boxedValue.Equals(trueValue)
                    isFalse := argumentValue != null && boxedValue.Equals(falseValue)
                    if isTrue || isFalse {
                        hasNotNullWhen = true
                        notNullWhenValue = isTrue
                        handled = true
                    }
                }
            }

            if !handled {
                if attributeKind == NullabilityMetadataCore.GetMaybeNullAttributeKind() {
                    hasMaybeNull = true
                } else if attributeKind == NullabilityMetadataCore.GetNotNullAttributeKind() {
                    hasNotNull = true
                } else if attributeKind == NullabilityMetadataCore.GetAllowNullAttributeKind() {
                    hasAllowNull = true
                } else if attributeKind == NullabilityMetadataCore.GetDisallowNullAttributeKind() {
                    hasDisallowNull = true
                }
            }

            index = index + 1
        }

        return NullabilityMetadataCore.FormatFlowAttributePrefix(hasNotNullWhen, notNullWhenValue, hasMaybeNull, hasNotNull, hasAllowNull, hasDisallowNull)
    }

    static func FormatClrTypeName(clrType: Type): string {
        if clrType.IsGenericParameter {
            return clrType.Name
        }

        if clrType.IsByRef {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return FormatClrTypeName(byRefElement)
            }
        }

        if clrType.IsArray {
            elementType := clrType.GetElementType()
            if elementType != null {
                return NullabilityMetadataCore.FormatArrayClrTypeName(FormatClrTypeName(elementType))
            }
        }

        if clrType.IsGenericType {
            name := NullabilityMetadataCore.StripClrGenericArity(clrType.Name)
            typeArguments := clrType.GetGenericArguments()
            formattedArguments := new string[](typeArguments.Length)
            index := 0
            while index < typeArguments.Length {
                formattedArguments[index] = FormatClrTypeName(typeArguments[index])
                index = index + 1
            }

            return NullabilityMetadataCore.FormatGenericClrTypeName(name, formattedArguments)
        }

        return NullabilityMetadataCore.FormatSimpleClrTypeName(clrType.Name)
    }
}
