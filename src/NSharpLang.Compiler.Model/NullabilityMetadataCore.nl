namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

class NullabilityMetadataCore {
    static func ConvertBuiltInType(fullName: string?): TypeInfo? {
        if fullName == "System.Int32" {
            return BuiltInTypes.Int
        }

        if fullName == "System.Int64" {
            return BuiltInTypes.Long
        }

        if fullName == "System.Single" {
            return BuiltInTypes.Float
        }

        if fullName == "System.Double" {
            return BuiltInTypes.Double
        }

        if fullName == "System.Decimal" {
            return BuiltInTypes.Decimal
        }

        if fullName == "System.Byte" {
            return BuiltInTypes.Byte
        }

        if fullName == "System.SByte" {
            return BuiltInTypes.SByte
        }

        if fullName == "System.Int16" {
            return BuiltInTypes.Short
        }

        if fullName == "System.UInt16" {
            return BuiltInTypes.UShort
        }

        if fullName == "System.UInt32" {
            return BuiltInTypes.UInt
        }

        if fullName == "System.UInt64" {
            return BuiltInTypes.ULong
        }

        if fullName == "System.Char" {
            return BuiltInTypes.Char
        }

        if fullName == "System.Boolean" {
            return BuiltInTypes.Bool
        }

        if fullName == "System.String" {
            return BuiltInTypes.String
        }

        if fullName == "System.Void" {
            return BuiltInTypes.Void
        }

        if fullName == "System.Object" {
            return BuiltInTypes.Object
        }

        return null
    }

    static func FormatTypeInfo(typeInfo: TypeInfo): string {
        return NullabilityTypeDisplay.FormatTypeInfo(typeInfo)
    }

    // Preserve the source member of every nullable CLR position on that position and its parent
    // shape. The one transfer owner below carries it as types are narrowed, joined, substituted,
    // stored in locals, and read back out of collections.
    static func AttachReferencedNullabilityOrigin(typeInfo: TypeInfo, member: MemberInfo?): TypeInfo {
        if member == null || !ContainsReferencedNullablePosition(typeInfo) {
            return typeInfo
        }

        declaringType := member.DeclaringType
        if declaringType == null {
            return typeInfo
        }

        assemblyName := member.Module.Assembly.GetName().Name ?? "referenced assembly"
        origin := new ReferencedNullabilityOrigin(FormatMemberName(member), assemblyName, PositionForMember(member), FormatTypeInfo(typeInfo))
        AddOriginToTypeShape(typeInfo, origin)
        return typeInfo
    }

    static func AttachReferencedParameterNullabilityOrigin(typeInfo: TypeInfo, parameter: ParameterInfo): TypeInfo {
        if !ContainsReferencedNullablePosition(typeInfo) {
            return typeInfo
        }

        member := parameter.Member
        if member == null {
            return typeInfo
        }

        declaringType := member.DeclaringType
        if declaringType == null {
            return typeInfo
        }

        typeName := declaringType.FullName ?? declaringType.Name
        assemblyName := member.Module.Assembly.GetName().Name ?? "referenced assembly"
        memberName := typeName + "." + member.Name
        method := member as MethodBase
        if method != null {
            memberName = FormatMethodName(method)
        }

        parameterName := parameter.Name ?? "#" + parameter.Position.ToString()
        origin := new ReferencedNullabilityOrigin(memberName, assemblyName, "parameter " + parameterName, FormatTypeInfo(typeInfo))
        AddOriginToTypeShape(typeInfo, origin)
        return typeInfo
    }

    // Transfer the full set of member origins when an expression's type is reconstructed. Nullable
    // leaves receive the fact too, so an array or generic collection can hand it to an element read.
    static func TransferReferencedNullabilityOrigins(source: TypeInfo, target: TypeInfo): TypeInfo {
        if !ContainsReferencedNullablePosition(target) {
            return target
        }

        origins := new List<ReferencedNullabilityOrigin>()
        CollectReferencedNullabilityOrigins(source, origins)
        for origin in origins {
            AddOriginToTypeShape(target, origin)
        }

        return target
    }

    static func MergeReferencedNullabilityOrigins(left: TypeInfo, right: TypeInfo, target: TypeInfo): TypeInfo {
        TransferReferencedNullabilityOrigins(left, target)
        TransferReferencedNullabilityOrigins(right, target)
        return target
    }

    static func AddOriginToTypeShape(typeInfo: TypeInfo, origin: ReferencedNullabilityOrigin) {
        AddOrigin(typeInfo, origin)
        AddOriginToNullablePositions(typeInfo, origin)
    }

    static func AddOriginToNullablePositions(typeInfo: TypeInfo, origin: ReferencedNullabilityOrigin) {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            AddOrigin(typeInfo, origin)
            AddOriginToNullablePositions(nullable.InnerType, origin)
            return
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            AddOriginToNullablePositions(array.ElementType, origin)
            return
        }

        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            AddOriginToNullablePositions(byRef.InnerType, origin)
            return
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            for argument in generic.TypeArguments {
                AddOriginToNullablePositions(argument, origin)
            }
            return
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            for element in tuple.Elements {
                AddOriginToNullablePositions(element.Type, origin)
            }
            return
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            if functionType.ParameterTypes != null {
                for parameterType in functionType.ParameterTypes {
                    AddOriginToNullablePositions(parameterType, origin)
                }
            }
            if functionType.ReturnType != null {
                AddOriginToNullablePositions(functionType.ReturnType, origin)
            }
        }
    }

    static func AddOrigin(typeInfo: TypeInfo, origin: ReferencedNullabilityOrigin) {
        origins := typeInfo.ReferencedNullabilityOrigins
        if origins == null {
            origins = new List<ReferencedNullabilityOrigin>()
            typeInfo.ReferencedNullabilityOrigins = origins
        }

        for existing in origins {
            if existing.MemberName == origin.MemberName && existing.AssemblyName == origin.AssemblyName && existing.Position == origin.Position && existing.TypeName == origin.TypeName {
                return
            }
        }

        origins.Add(origin)
    }

    static func CollectReferencedNullabilityOrigins(typeInfo: TypeInfo, origins: List<ReferencedNullabilityOrigin>) {
        existing := typeInfo.ReferencedNullabilityOrigins
        if existing != null {
            for origin in existing {
                AddOriginToList(origins, origin)
            }
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            CollectReferencedNullabilityOrigins(nullable.InnerType, origins)
            return
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            CollectReferencedNullabilityOrigins(array.ElementType, origins)
            return
        }

        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            CollectReferencedNullabilityOrigins(byRef.InnerType, origins)
            return
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            for argument in generic.TypeArguments {
                CollectReferencedNullabilityOrigins(argument, origins)
            }
            return
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            for element in tuple.Elements {
                CollectReferencedNullabilityOrigins(element.Type, origins)
            }
            return
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            if functionType.ParameterTypes != null {
                for parameterType in functionType.ParameterTypes {
                    CollectReferencedNullabilityOrigins(parameterType, origins)
                }
            }
            if functionType.ReturnType != null {
                CollectReferencedNullabilityOrigins(functionType.ReturnType, origins)
            }
        }
    }

    static func AddOriginToList(origins: List<ReferencedNullabilityOrigin>, origin: ReferencedNullabilityOrigin) {
        for existing in origins {
            if existing.MemberName == origin.MemberName && existing.AssemblyName == origin.AssemblyName && existing.Position == origin.Position && existing.TypeName == origin.TypeName {
                return
            }
        }

        origins.Add(origin)
    }

    static func PositionForMember(member: MemberInfo): string {
        if member as MethodInfo != null {
            return "return"
        }
        if member as PropertyInfo != null {
            return "property"
        }
        if member as FieldInfo != null {
            return "field"
        }
        if member as EventInfo != null {
            return "event"
        }
        return "member"
    }

    static func FormatMemberName(member: MemberInfo): string {
        method := member as MethodBase
        if method != null {
            return FormatMethodName(method)
        }

        declaringType := member.DeclaringType
        if declaringType == null {
            return member.Name
        }

        return (declaringType.FullName ?? declaringType.Name) + "." + member.Name
    }

    static func FormatMethodName(method: MethodBase): string {
        declaringType := method.DeclaringType
        memberPrefix := method.Name
        if declaringType != null {
            memberPrefix = (declaringType.FullName ?? declaringType.Name) + "." + method.Name
        }

        parameterNames := new List<string>()
        for parameter in method.GetParameters() {
            parameterType := parameter.ParameterType
            parameterName := parameterType.FullName ?? parameterType.Name
            parameterNames.Add(parameterName)
        }

        return memberPrefix + "(" + string.Join(", ", parameterNames) + ")"
    }

    static func ContainsReferencedNullablePosition(typeInfo: TypeInfo): bool {
        if typeInfo as NullableTypeInfo != null {
            return true
        }

        if typeInfo as ObliviousTypeInfo != null {
            return false
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            return ContainsReferencedNullablePosition(array.ElementType)
        }

        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            return ContainsReferencedNullablePosition(byRef.InnerType)
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            for argument in generic.TypeArguments {
                if ContainsReferencedNullablePosition(argument) {
                    return true
                }
            }
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            for element in tuple.Elements {
                if ContainsReferencedNullablePosition(element.Type) {
                    return true
                }
            }
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            if functionType.ParameterTypes != null {
                for parameterType in functionType.ParameterTypes {
                    if ContainsReferencedNullablePosition(parameterType) {
                        return true
                    }
                }
            }

            if functionType.ReturnType != null && ContainsReferencedNullablePosition(functionType.ReturnType) {
                return true
            }
        }

        return false
    }

    static func ReferencedNullabilityContext(typeInfo: TypeInfo): string? {
        origins := new List<ReferencedNullabilityOrigin>()
        CollectReferencedNullabilityOrigins(typeInfo, origins)
        if origins.Count == 0 {
            return null
        }

        contexts := new List<string>()
        for origin in origins {
            contexts.Add(FormatReferencedNullabilityOrigin(origin))
        }

        return string.Join(" ", contexts)
    }

    static func FormatReferencedNullabilityOrigin(origin: ReferencedNullabilityOrigin): string {
        if origin.Position == "return" {
            return "The .NET member `" + origin.MemberName + "` is annotated to return `" + origin.TypeName + "` in `" + origin.AssemblyName + "`."
        }

        if origin.Position.StartsWith("parameter ", StringComparison.Ordinal) {
            parameterName := origin.Position.Substring("parameter ".Length)
            return "The .NET member `" + origin.MemberName + "` annotates parameter `" + parameterName + "` as `" + origin.TypeName + "` in `" + origin.AssemblyName + "`."
        }

        positionName := origin.Position
        if positionName == "property" {
            positionName = "property type"
        } else if positionName == "field" {
            positionName = "field type"
        } else if positionName == "event" {
            positionName = "event handler type"
        }

        return "The .NET member `" + origin.MemberName + "` is annotated with `" + origin.TypeName + "` as its " + positionName + " in `" + origin.AssemblyName + "`."
    }

    static func StripMetadata(typeInfo: TypeInfo): TypeInfo {
        return NullabilityTypeDisplay.StripMetadata(typeInfo)
    }

    static func StripClrGenericArity(name: string): string {
        tickIndex := name.IndexOf('`')
        if tickIndex >= 0 {
            return name.Substring(0, tickIndex)
        }

        return name
    }

    static func FormatArrayClrTypeName(elementTypeName: string): string {
        return elementTypeName + "[]"
    }

    static func FormatGenericClrTypeName(name: string, formattedArguments: string[]): string {
        return name + "<" + string.Join(", ", formattedArguments) + ">"
    }

    static func ApplyFlowAttributeFacts(typeInfo: TypeInfo, hasMaybeNull: bool, hasNotNull: bool): TypeInfo {
        if hasMaybeNull {
            return EnsureNullable(typeInfo)
        }

        if hasNotNull {
            return EnsureNotNull(typeInfo)
        }

        return typeInfo
    }

    static func FormatFlowAttributePrefix(hasNotNullWhen: bool, notNullWhenValue: bool, hasMaybeNull: bool, hasNotNull: bool, hasAllowNull: bool, hasDisallowNull: bool): string {
        formatted := ""
        if hasNotNullWhen {
            valueText := "false"
            if notNullWhenValue {
                valueText = "true"
            }

            formatted = AppendFlowAttribute(formatted, "[NotNullWhen(" + valueText + ")]")
        }

        if hasMaybeNull {
            formatted = AppendFlowAttribute(formatted, "[MaybeNull]")
        }

        if hasNotNull {
            formatted = AppendFlowAttribute(formatted, "[NotNull]")
        }

        if hasAllowNull {
            formatted = AppendFlowAttribute(formatted, "[AllowNull]")
        }

        if hasDisallowNull {
            formatted = AppendFlowAttribute(formatted, "[DisallowNull]")
        }

        if formatted == "" {
            return ""
        }

        return formatted + " "
    }

    static func GetMaybeNullAttributeKind(): int {
        return 1
    }

    static func GetNotNullAttributeKind(): int {
        return 2
    }

    static func GetNotNullWhenAttributeKind(): int {
        return 3
    }

    static func GetAllowNullAttributeKind(): int {
        return 5
    }

    static func GetDisallowNullAttributeKind(): int {
        return 6
    }

    static func GetParamArrayAttributeKind(): int {
        return 4
    }

    static func GetFlowAttributeKind(attributeTypeName: string?): int {
        name := attributeTypeName ?? ""
        if string.Equals(name, "System.Diagnostics.CodeAnalysis.MaybeNullAttribute", StringComparison.Ordinal) {
            return GetMaybeNullAttributeKind()
        }

        if string.Equals(name, "System.Diagnostics.CodeAnalysis.NotNullAttribute", StringComparison.Ordinal) {
            return GetNotNullAttributeKind()
        }

        if string.Equals(name, "System.Diagnostics.CodeAnalysis.NotNullWhenAttribute", StringComparison.Ordinal) {
            return GetNotNullWhenAttributeKind()
        }

        if string.Equals(name, "System.Diagnostics.CodeAnalysis.AllowNullAttribute", StringComparison.Ordinal) {
            return GetAllowNullAttributeKind()
        }

        if string.Equals(name, "System.Diagnostics.CodeAnalysis.DisallowNullAttribute", StringComparison.Ordinal) {
            return GetDisallowNullAttributeKind()
        }

        if string.Equals(name, "System.ParamArrayAttribute", StringComparison.Ordinal) {
            return GetParamArrayAttributeKind()
        }

        return 0
    }

    static func ApplyReadState(typeInfo: TypeInfo, isNullableValueType: bool, canCarryReferenceNullability: bool, isNullableReadState: bool, isUnknownReadState: bool): TypeInfo {
        if isNullableValueType {
            return typeInfo
        }

        if !canCarryReferenceNullability {
            return typeInfo
        }

        if isNullableReadState {
            return EnsureNullable(typeInfo)
        }

        if isUnknownReadState {
            return EnsureOblivious(typeInfo)
        }

        return typeInfo
    }

    static func FormatParameter(isOut: bool, isByRef: bool, isParams: bool, attributePrefix: string, typeName: string, parameterName: string?): string {
        return FormatParameter(isOut, isByRef, false, isParams, attributePrefix, typeName, parameterName)
    }

    // `isIn` IS ASKED BEFORE `isByRef`, because an `in` parameter IS a by-reference one: reading only
    // the by-ref bit rendered every external `in` parameter as `ref` in hover and in signature help,
    // which told the reader to write a word the callee does not want.
    static func FormatParameter(isOut: bool, isByRef: bool, isIn: bool, isParams: bool, attributePrefix: string, typeName: string, parameterName: string?): string {
        modifier := ""
        if isOut {
            modifier = "out "
        } else if isIn {
            modifier = "in "
        } else if isByRef {
            modifier = "ref "
        } else if isParams {
            modifier = "params "
        }

        return attributePrefix + modifier + typeName + " " + (parameterName ?? "")
    }

    static func EnsureNullable(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return typeInfo
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            wrapped: TypeInfo = new NullableTypeInfo(oblivious.InnerType)
            return TransferReferencedNullabilityOrigins(typeInfo, wrapped)
        }

        wrapped: TypeInfo = new NullableTypeInfo(typeInfo)
        return TransferReferencedNullabilityOrigins(typeInfo, wrapped)
    }

    static func EnsureOblivious(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return typeInfo
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return typeInfo
        }

        return new ObliviousTypeInfo(typeInfo)
    }

    static func EnsureNotNull(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return TransferReferencedNullabilityOrigins(typeInfo, nullable.InnerType)
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return TransferReferencedNullabilityOrigins(typeInfo, oblivious.InnerType)
        }

        return typeInfo
    }

    // OVERLOAD CANDIDATE SELECTION SOMETIMES NEEDS TO SEE THE CLR SHAPE BEFORE NULLABILITY IS
    // REPORTED. When a referenced nullable argument is otherwise a valid candidate, the candidate
    // must survive selection so the chosen-call validator can issue NL202 at the argument and name
    // the annotated .NET member. This projection is only for that selection question; callers keep
    // the original type for diagnostics and code generation.
    static func EraseNullableAnnotations(typeInfo: TypeInfo): TypeInfo {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return EraseNullableAnnotations(nullable.InnerType)
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return new ObliviousTypeInfo(EraseNullableAnnotations(oblivious.InnerType))
        }

        array := typeInfo as ArrayTypeInfo
        if array != null {
            return new ArrayTypeInfo(EraseNullableAnnotations(array.ElementType))
        }

        generic := typeInfo as GenericTypeInfo
        if generic != null {
            arguments := new List<TypeInfo>()
            for argument in generic.TypeArguments {
                arguments.Add(EraseNullableAnnotations(argument))
            }

            return new GenericTypeInfo(generic.Name, arguments, generic.GenericDefinition)
        }

        tuple := typeInfo as TupleTypeInfo
        if tuple != null {
            elements := new List<TupleTypeElementInfo>()
            for element in tuple.Elements {
                elements.Add(new TupleTypeElementInfo(element.Name, EraseNullableAnnotations(element.Type)))
            }

            return new TupleTypeInfo(elements)
        }

        byRef := typeInfo as ByRefTypeInfo
        if byRef != null {
            return new ByRefTypeInfo(EraseNullableAnnotations(byRef.InnerType), byRef.IsOutArgument)
        }

        functionType := typeInfo as FunctionTypeInfo
        if functionType != null {
            parameters: List<TypeInfo>? = null
            if functionType.ParameterTypes != null {
                parameters = new List<TypeInfo>()
                for parameter in functionType.ParameterTypes {
                    parameters.Add(EraseNullableAnnotations(parameter))
                }
            }

            returnType: TypeInfo? = null
            if functionType.ReturnType != null {
                returnType = EraseNullableAnnotations(functionType.ReturnType)
            }

            return functionType.WithSignatureTypes(parameters, returnType)
        }

        unionValue := typeInfo as AnonymousUnionTypeInfo
        if unionValue != null {
            arms := new List<TypeInfo>()
            for arm in unionValue.Arms {
                arms.Add(EraseNullableAnnotations(arm))
            }

            return new AnonymousUnionTypeInfo(arms)
        }

        return typeInfo
    }

    // `[AllowNull]` and `[DisallowNull]` describe the value a caller may WRITE into a parameter or
    // settable member. They apply to reference annotations only: `int?` is a CLR Nullable<int>, and
    // an attribute must never manufacture or erase that distinct value type.
    static func ApplyInputFlowFacts(typeInfo: TypeInfo, facts: int): TypeInfo {
        if !CanCarryInputReferenceNullability(typeInfo) {
            return typeInfo
        }

        if NullabilityFlowFacts.Has(facts, NullabilityFlowFacts.DisallowNull()) {
            return EnsureNotNull(typeInfo)
        }

        if NullabilityFlowFacts.Has(facts, NullabilityFlowFacts.AllowNull()) {
            return EnsureNullable(typeInfo)
        }

        return typeInfo
    }

    static func CanCarryInputReferenceNullability(typeInfo: TypeInfo): bool {
        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return CanCarryInputReferenceNullability(nullable.InnerType)
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return CanCarryInputReferenceNullability(oblivious.InnerType)
        }

        return CanCarryReferenceNullability(typeInfo)
    }

    static func CanCarryReferenceNullability(typeInfo: TypeInfo): bool {
        simple := typeInfo as SimpleTypeInfo
        if simple != null {
            return !IsNonNullableSimpleType(simple.Name)
        }

        nullable := typeInfo as NullableTypeInfo
        if nullable != null {
            return false
        }

        oblivious := typeInfo as ObliviousTypeInfo
        if oblivious != null {
            return CanCarryReferenceNullability(oblivious.InnerType)
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return false
        }

        enumType := typeInfo as EnumTypeInfo
        if enumType != null {
            return false
        }

        soaType := typeInfo as SoaRecordTypeInfo
        if soaType != null {
            return false
        }

        // A TUPLE IS A `ValueTuple`, AND A `ValueTuple` IS A STRUCT. `(string, int)?` names the
        // lifted VALUE type, so the reference annotation this answers about has nothing to attach
        // to — the same answer the struct, enum and struct-record arms above give.
        tupleType := typeInfo as TupleTypeInfo
        if tupleType != null {
            return false
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return !recordType.IsStruct
        }

        unknown := typeInfo as UnknownTypeInfo
        if unknown != null {
            return false
        }

        return true
    }

    static func CanReflectedTypeCarryReferenceNullability(isGenericParameter: bool, isValueType: bool, convertedCanCarryReferenceNullability: bool): bool {
        if !isGenericParameter {
            return !isValueType
        }

        return convertedCanCarryReferenceNullability
    }

    static func AppendFlowAttribute(current: string, next: string): string {
        if current == "" {
            return next
        }

        return current + " " + next
    }

    static func FormatSimpleClrTypeName(name: string): string {
        if name == "Boolean" {
            return "bool"
        }

        if name == "Byte" {
            return "byte"
        }

        if name == "SByte" {
            return "sbyte"
        }

        if name == "Int16" {
            return "short"
        }

        if name == "UInt16" {
            return "ushort"
        }

        if name == "Int32" {
            return "int"
        }

        if name == "UInt32" {
            return "uint"
        }

        if name == "Int64" {
            return "long"
        }

        if name == "UInt64" {
            return "ulong"
        }

        if name == "Single" {
            return "float"
        }

        if name == "Double" {
            return "double"
        }

        if name == "Decimal" {
            return "decimal"
        }

        if name == "Char" {
            return "char"
        }

        if name == "String" {
            return "string"
        }

        if name == "Object" {
            return "object"
        }

        if name == "Void" {
            return "void"
        }

        return name
    }

    static func IsNonNullableSimpleType(name: string): bool {
        if name == "int" {
            return true
        }

        if name == "long" {
            return true
        }

        if name == "float" {
            return true
        }

        if name == "double" {
            return true
        }

        if name == "decimal" {
            return true
        }

        if name == "byte" {
            return true
        }

        if name == "sbyte" {
            return true
        }

        if name == "short" {
            return true
        }

        if name == "ushort" {
            return true
        }

        if name == "uint" {
            return true
        }

        if name == "ulong" {
            return true
        }

        if name == "char" {
            return true
        }

        if name == "bool" {
            return true
        }

        if name == "void" {
            return true
        }

        if name == "null" {
            return true
        }

        if name == "never" {
            return true
        }

        return false
    }
}
