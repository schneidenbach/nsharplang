namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler.Ast

public enum DeclaredMemberKind {
    Unknown,
    Field,
    Property,
    Function,
    Class,
    Struct,
    Record,
    SoaRecord,
    Interface,
    Enum,
    Union,
    TypeAlias,
    Newtype,
    Constructor
}

public class DeclaredMemberInfo {
    nameValue: string
    containingTypeValue: string
    kindValue: DeclaredMemberKind
    kindNameValue: string
    typeValue: TypeReference?
    isStaticValue: bool
    isReadonlyValue: bool
    hasSetterValue: bool
    isExportedValue: bool
    parameterCountValue: int
    parameterNamesValue: string[]
    parameterTypesValue: TypeReference[]
    parameterModifiersValue: ParameterModifier[]
    requiredParameterCountValue: int
    hasParamsParameterValue: bool
    returnTypeValue: TypeReference?
    typeParameterCountValue: int
    typeParametersValue: TypeParameter[]
    genericConstraintsValue: GenericConstraint[]
    attributeCountValue: int
    hasMustUseAttributeValue: bool
    isAsyncValue: bool
    isGeneratorValue: bool
    isOperatorOverloadValue: bool
    operatorSymbolValue: string
    isConversionOperatorValue: bool
    isImplicitConversionValue: bool
    lineValue: int
    columnValue: int

    Name: string => nameValue
    ContainingType: string => containingTypeValue
    Kind: DeclaredMemberKind => kindValue
    KindName: string => kindNameValue
    Type: TypeReference? => typeValue
    IsStatic: bool => isStaticValue
    IsReadonly: bool => isReadonlyValue
    HasSetter: bool => hasSetterValue
    IsExported: bool => isExportedValue
    ParameterCount: int => parameterCountValue
    ParameterNames: string[] => parameterNamesValue
    ParameterTypes: TypeReference[] => parameterTypesValue
    ParameterModifiers: ParameterModifier[] => parameterModifiersValue
    RequiredParameterCount: int => requiredParameterCountValue
    HasParamsParameter: bool => hasParamsParameterValue
    ReturnType: TypeReference? => returnTypeValue
    TypeParameterCount: int => typeParameterCountValue
    TypeParameters: TypeParameter[] => typeParametersValue
    GenericConstraints: GenericConstraint[] => genericConstraintsValue
    AttributeCount: int => attributeCountValue
    HasMustUseAttribute: bool => hasMustUseAttributeValue
    IsAsync: bool => isAsyncValue
    IsGenerator: bool => isGeneratorValue
    IsOperatorOverload: bool => isOperatorOverloadValue
    OperatorSymbol: string => operatorSymbolValue
    IsConversionOperator: bool => isConversionOperatorValue
    IsImplicitConversion: bool => isImplicitConversionValue
    Line: int => lineValue
    Column: int => columnValue

    constructor(
        name: string,
        containingType: string,
        kind: DeclaredMemberKind,
        kindName: string,
        typeReference: TypeReference?,
        isStatic: bool,
        isReadonly: bool,
        hasSetter: bool,
        isExported: bool,
        parameterCount: int,
        parameterNames: string[],
        parameterTypes: TypeReference[],
        parameterModifiers: ParameterModifier[],
        requiredParameterCount: int,
        hasParamsParameter: bool,
        returnType: TypeReference?,
        typeParameterCount: int,
        typeParameters: TypeParameter[],
        genericConstraints: GenericConstraint[],
        attributeCount: int,
        hasMustUseAttribute: bool,
        isAsync: bool,
        isGenerator: bool,
        isOperatorOverload: bool,
        operatorSymbol: string,
        isConversionOperator: bool,
        isImplicitConversion: bool,
        line: int,
        column: int) {
        nameValue = name
        containingTypeValue = containingType
        kindValue = kind
        kindNameValue = kindName
        typeValue = typeReference
        isStaticValue = isStatic
        isReadonlyValue = isReadonly
        hasSetterValue = hasSetter
        isExportedValue = isExported
        parameterCountValue = parameterCount
        parameterNamesValue = parameterNames
        parameterTypesValue = parameterTypes
        parameterModifiersValue = parameterModifiers
        requiredParameterCountValue = requiredParameterCount
        hasParamsParameterValue = hasParamsParameter
        returnTypeValue = returnType
        typeParameterCountValue = typeParameterCount
        typeParametersValue = typeParameters
        genericConstraintsValue = genericConstraints
        attributeCountValue = attributeCount
        hasMustUseAttributeValue = hasMustUseAttribute
        isAsyncValue = isAsync
        isGeneratorValue = isGenerator
        isOperatorOverloadValue = isOperatorOverload
        operatorSymbolValue = operatorSymbol
        isConversionOperatorValue = isConversionOperator
        isImplicitConversionValue = isImplicitConversion
        lineValue = line
        columnValue = column
    }
}

public class ParameterDeclarationInfo {
    nameValue: string
    typeValue: TypeReference
    lineValue: int
    columnValue: int

    Name: string => nameValue
    Type: TypeReference => typeValue
    Line: int => lineValue
    Column: int => columnValue

    constructor(name: string, typeReference: TypeReference, line: int, column: int) {
        nameValue = name
        typeValue = typeReference
        lineValue = line
        columnValue = column
    }
}

public class NestedTypeInfo {
    nameValue: string
    typeValue: TypeInfo

    Name: string => nameValue
    Type: TypeInfo => typeValue

    constructor(name: string, nestedType: TypeInfo) {
        nameValue = name
        typeValue = nestedType
    }
}

public class TypeInfo {
}

public class ClassTypeInfo: TypeInfo {
    declarationValue: object
    nameValue: string
    lineValue: int
    columnValue: int
    isSealedValue: bool
    baseClassValue: TypeReference?
    interfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    primaryConstructorParametersValue: ParameterDeclarationInfo[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]
    hasParameterlessConstructorValue: bool

    Declaration: object => declarationValue
    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    IsSealed: bool => isSealedValue
    BaseClass: TypeReference? => baseClassValue
    Interfaces: TypeReference[] => interfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    PrimaryConstructorParameters: ParameterDeclarationInfo[] => primaryConstructorParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue
    HasParameterlessConstructor: bool => hasParameterlessConstructorValue

    constructor(
        declaration: object,
        name: string,
        line: int,
        column: int,
        isSealed: bool,
        baseClass: TypeReference?,
        interfaces: TypeReference[],
        typeParameters: TypeParameter[],
        primaryConstructorParameters: ParameterDeclarationInfo[],
        declaredMembers: DeclaredMemberInfo[],
        nestedTypes: NestedTypeInfo[],
        hasParameterlessConstructor: bool) {
        declarationValue = declaration
        nameValue = name
        lineValue = line
        columnValue = column
        isSealedValue = isSealed
        baseClassValue = baseClass
        interfacesValue = interfaces
        typeParametersValue = typeParameters
        primaryConstructorParametersValue = primaryConstructorParameters
        declaredMembersValue = declaredMembers
        nestedTypesValue = nestedTypes
        hasParameterlessConstructorValue = hasParameterlessConstructor
    }

    override func ToString(): string {
        return nameValue
    }
}

public class StructTypeInfo: TypeInfo {
    declarationValue: object
    nameValue: string
    lineValue: int
    columnValue: int
    interfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    primaryConstructorParametersValue: ParameterDeclarationInfo[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Declaration: object => declarationValue
    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    Interfaces: TypeReference[] => interfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    PrimaryConstructorParameters: ParameterDeclarationInfo[] => primaryConstructorParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constructor(
        declaration: object,
        name: string,
        line: int,
        column: int,
        interfaces: TypeReference[],
        typeParameters: TypeParameter[],
        primaryConstructorParameters: ParameterDeclarationInfo[],
        declaredMembers: DeclaredMemberInfo[],
        nestedTypes: NestedTypeInfo[]) {
        declarationValue = declaration
        nameValue = name
        lineValue = line
        columnValue = column
        interfacesValue = interfaces
        typeParametersValue = typeParameters
        primaryConstructorParametersValue = primaryConstructorParameters
        declaredMembersValue = declaredMembers
        nestedTypesValue = nestedTypes
    }

    override func ToString(): string {
        return nameValue
    }
}

public class RecordTypeInfo: TypeInfo {
    declarationValue: object
    nameValue: string
    lineValue: int
    columnValue: int
    isStructValue: bool
    interfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    primaryConstructorParametersValue: ParameterDeclarationInfo[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Declaration: object => declarationValue
    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    IsStruct: bool => isStructValue
    Interfaces: TypeReference[] => interfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    PrimaryConstructorParameters: ParameterDeclarationInfo[] => primaryConstructorParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constructor(
        declaration: object,
        name: string,
        line: int,
        column: int,
        isStruct: bool,
        interfaces: TypeReference[],
        typeParameters: TypeParameter[],
        primaryConstructorParameters: ParameterDeclarationInfo[],
        declaredMembers: DeclaredMemberInfo[],
        nestedTypes: NestedTypeInfo[]) {
        declarationValue = declaration
        nameValue = name
        lineValue = line
        columnValue = column
        isStructValue = isStruct
        interfacesValue = interfaces
        typeParametersValue = typeParameters
        primaryConstructorParametersValue = primaryConstructorParameters
        declaredMembersValue = declaredMembers
        nestedTypesValue = nestedTypes
    }

    override func ToString(): string {
        return nameValue
    }
}

public class InterfaceTypeInfo: TypeInfo {
    declarationValue: object
    nameValue: string
    lineValue: int
    columnValue: int
    isDuckInterfaceValue: bool
    baseInterfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Declaration: object => declarationValue
    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    IsDuckInterface: bool => isDuckInterfaceValue
    BaseInterfaces: TypeReference[] => baseInterfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constructor(
        declaration: object,
        name: string,
        line: int,
        column: int,
        isDuckInterface: bool,
        baseInterfaces: TypeReference[],
        typeParameters: TypeParameter[],
        declaredMembers: DeclaredMemberInfo[],
        nestedTypes: NestedTypeInfo[]) {
        declarationValue = declaration
        nameValue = name
        lineValue = line
        columnValue = column
        isDuckInterfaceValue = isDuckInterface
        baseInterfacesValue = baseInterfaces
        typeParametersValue = typeParameters
        declaredMembersValue = declaredMembers
        nestedTypesValue = nestedTypes
    }

    override func ToString(): string {
        return nameValue
    }
}

public class SimpleTypeInfo: TypeInfo {
    nameValue: string

    Name: string => nameValue

    constructor(name: string) {
        nameValue = name
    }

    override func ToString(): string {
        return nameValue
    }

    override func Equals(value: object): bool {
        other := value as SimpleTypeInfo
        if other == null {
            return false
        }

        return nameValue == other.Name
    }

    override func GetHashCode(): int {
        return nameValue.GetHashCode()
    }
}

public class UnknownTypeInfo: TypeInfo {
    kindValue: UnknownKind

    Kind: UnknownKind => kindValue

    constructor(kind: UnknownKind) {
        kindValue = kind
    }

    override func ToString(): string {
        return "unknown"
    }

    override func Equals(value: object): bool {
        other := value as UnknownTypeInfo
        if other == null {
            return false
        }

        return kindValue == other.Kind
    }

    override func GetHashCode(): int {
        return Convert.ToInt32(kindValue)
    }
}

public class NewtypeInfo: TypeInfo {
    nameValue: string
    underlyingTypeValue: TypeReference

    Name: string => nameValue
    UnderlyingType: TypeReference => underlyingTypeValue

    constructor(name: string, underlyingType: TypeReference) {
        nameValue = name
        underlyingTypeValue = underlyingType
    }

    override func ToString(): string {
        return nameValue
    }
}

public class ExternalTypeInfo: TypeInfo {
    nameValue: string

    Name: string => nameValue

    constructor(name: string) {
        nameValue = name
    }

    override func ToString(): string {
        return nameValue
    }

    override func Equals(value: object): bool {
        other := value as ExternalTypeInfo
        if other == null {
            return false
        }

        return nameValue == other.Name
    }

    override func GetHashCode(): int {
        return nameValue.GetHashCode()
    }
}

public class ReflectionTypeInfo: TypeInfo {
    clrTypeValue: Type

    Type: Type => clrTypeValue

    constructor(clrType: Type) {
        clrTypeValue = clrType
    }

    override func ToString(): string {
        return clrTypeValue.Name
    }
}

public class BuiltInTypes {
    public static Int: SimpleTypeInfo => new SimpleTypeInfo("int")
    public static Long: SimpleTypeInfo => new SimpleTypeInfo("long")
    public static Float: SimpleTypeInfo => new SimpleTypeInfo("float")
    public static Double: SimpleTypeInfo => new SimpleTypeInfo("double")
    public static Decimal: SimpleTypeInfo => new SimpleTypeInfo("decimal")
    public static Byte: SimpleTypeInfo => new SimpleTypeInfo("byte")
    public static SByte: SimpleTypeInfo => new SimpleTypeInfo("sbyte")
    public static Short: SimpleTypeInfo => new SimpleTypeInfo("short")
    public static UShort: SimpleTypeInfo => new SimpleTypeInfo("ushort")
    public static UInt: SimpleTypeInfo => new SimpleTypeInfo("uint")
    public static ULong: SimpleTypeInfo => new SimpleTypeInfo("ulong")
    public static Char: SimpleTypeInfo => new SimpleTypeInfo("char")
    public static Bool: SimpleTypeInfo => new SimpleTypeInfo("bool")
    public static String: SimpleTypeInfo => new SimpleTypeInfo("string")
    public static Void: SimpleTypeInfo => new SimpleTypeInfo("void")
    public static Object: SimpleTypeInfo => new SimpleTypeInfo("object")
    public static Null: SimpleTypeInfo => new SimpleTypeInfo("null")
    public static Never: SimpleTypeInfo => new SimpleTypeInfo("never")
    public static Unknown: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.ErrorRecovery)
    public static InferenceHole: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.InferenceHole)
    public static DeferredExternal: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.DeferredExternal)

    public static func Is(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        if typeInfo == null {
            return false
        }

        simple := typeInfo as SimpleTypeInfo
        if simple == null {
            return false
        }

        return simple.Equals(builtIn)
    }

    public static func IsNot(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        return !Is(typeInfo, builtIn)
    }

    public static func IsUnknown(typeInfo: TypeInfo): bool {
        unknown := typeInfo as UnknownTypeInfo
        return unknown != null
    }
}

public class TupleTypeElementInfo {
    Name: string?
    Type: TypeInfo

    constructor(name: string?, elementType: TypeInfo) {
        Name = name
        Type = elementType
    }

    public func Deconstruct(out name: string?, out elementType: TypeInfo) {
        name = Name
        elementType = Type
    }
}

public class TupleTypeInfo: TypeInfo {
    Elements: List<TupleTypeElementInfo>

    constructor(elements: List<TupleTypeElementInfo>) {
        Elements = elements
    }
}

public class AnonymousUnionTypeInfo: TypeInfo {
    Arms: List<TypeInfo>

    constructor(arms: List<TypeInfo>) {
        Arms = arms
    }

    override func ToString(): string {
        builder := new StringBuilder()

        index := 0
        while index < Arms.Count {
            if index > 0 {
                builder.Append(" | ")
            }

            armObject := Arms[index] as object
            builder.Append(armObject.ToString())
            index = index + 1
        }

        return builder.ToString()
    }
}

public class AliasTypeInfo: TypeInfo {
    aliasedTypeValue: TypeReference

    AliasedType: TypeReference => aliasedTypeValue

    constructor(aliasedType: TypeReference) {
        aliasedTypeValue = aliasedType
    }
}

public class GenericTypeInfo: TypeInfo {
    nameValue: string
    typeArgumentsValue: List<TypeInfo>

    Name: string => nameValue
    TypeArguments: List<TypeInfo> => typeArgumentsValue

    constructor(name: string, typeArguments: List<TypeInfo>) {
        nameValue = name
        typeArgumentsValue = typeArguments
    }

    override func ToString(): string {
        builder := new StringBuilder()
        builder.Append(nameValue)
        builder.Append("<")

        index := 0
        while index < typeArgumentsValue.Count {
            if index > 0 {
                builder.Append(", ")
            }

            argumentObject := typeArgumentsValue[index] as object
            builder.Append(argumentObject.ToString())
            index = index + 1
        }

        builder.Append(">")
        return builder.ToString()
    }
}

public class ArrayTypeInfo: TypeInfo {
    elementTypeValue: TypeInfo

    ElementType: TypeInfo => elementTypeValue

    constructor(elementType: TypeInfo) {
        elementTypeValue = elementType
    }

    override func ToString(): string {
        elementObject := elementTypeValue as object
        return elementObject.ToString() + "[]"
    }
}

public class NullableTypeInfo: TypeInfo {
    innerTypeValue: TypeInfo

    InnerType: TypeInfo => innerTypeValue

    constructor(innerType: TypeInfo) {
        innerTypeValue = innerType
    }

    override func ToString(): string {
        innerObject := innerTypeValue as object
        return innerObject.ToString() + "?"
    }
}

public class FunctionTypeInfo: TypeInfo {
    Declaration: object?
    SyntheticName: string?
    SourceName: string?
    SourceContainingType: string?
    SourceLine: int
    SourceColumn: int
    SourceParameterCount: int
    ParameterNames: List<string>?
    ParameterTypes: List<TypeInfo>?
    SourceParameterTypes: List<TypeReference>?
    ParameterModifiers: List<ParameterModifier>?
    RequiredParameterCount: int?
    HasParamsParameter: bool
    TypeParameters: List<TypeParameter>?
    GenericConstraints: List<GenericConstraint>?
    HasMustUseAttribute: bool
    ReturnType: TypeInfo?

    constructor(declaration: object?) {
        Declaration = declaration
        HasParamsParameter = false
        HasMustUseAttribute = false
        SourceLine = 0
        SourceColumn = 0
        SourceParameterCount = -1
    }
}

public class NSharpMethodGroupInfo: TypeInfo {
    Functions: List<FunctionTypeInfo>

    constructor(functions: List<FunctionTypeInfo>) {
        Functions = functions
    }

    override func ToString(): string {
        return "method group"
    }
}

public class ObliviousTypeInfo: TypeInfo {
    innerTypeValue: TypeInfo

    InnerType: TypeInfo => innerTypeValue

    constructor(innerType: TypeInfo) {
        innerTypeValue = innerType
    }

    override func ToString(): string {
        innerObject := innerTypeValue as object
        return innerObject.ToString() + "!"
    }
}

public class ByRefTypeInfo: TypeInfo {
    innerTypeValue: TypeInfo

    InnerType: TypeInfo => innerTypeValue

    constructor(innerType: TypeInfo) {
        innerTypeValue = innerType
    }

    override func ToString(): string {
        innerObject := innerTypeValue as object
        return "&" + innerObject.ToString()
    }
}

public class SoaColumnInfo {
    Name: string
    Type: TypeReference
    Line: int
    Column: int

    constructor(name: string, columnType: TypeReference, line: int = 0, column: int = 0) {
        Name = name
        Type = columnType
        Line = line
        Column = column
    }
}

public class SoaRecordDeclarationInfo {
    Name: string
    Columns: List<SoaColumnInfo>
    Line: int
    Column: int

    constructor(name: string, columns: List<SoaColumnInfo>, line: int = 0, column: int = 0) {
        Name = name
        Columns = columns
        Line = line
        Column = column
    }
}

public class SoaRecordTypeInfo: TypeInfo {
    declarationValue: SoaRecordDeclarationInfo

    Declaration: SoaRecordDeclarationInfo => declarationValue

    constructor(declaration: SoaRecordDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}

public class SoaRowTypeInfo: TypeInfo {
    declarationValue: SoaRecordDeclarationInfo

    Declaration: SoaRecordDeclarationInfo => declarationValue

    constructor(declaration: SoaRecordDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return $"{declarationValue.Name}.Row"
    }
}

public class UnionDeclarationInfo {
    Name: string
    TypeParameters: List<TypeParameter>?
    Cases: List<UnionCase>
    Line: int
    Column: int

    constructor(
        name: string,
        typeParameters: List<TypeParameter>?,
        cases: List<UnionCase>,
        line: int = 0,
        column: int = 0) {
        Name = name
        TypeParameters = typeParameters
        Cases = cases
        Line = line
        Column = column
    }
}

public class UnionTypeInfo: TypeInfo {
    declarationValue: UnionDeclarationInfo

    Declaration: UnionDeclarationInfo => declarationValue

    constructor(declaration: UnionDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}

public enum EnumMemberValueKind {
    None,
    String,
    Integer
}

public class EnumMemberInfo {
    Name: string
    Line: int
    Column: int
    ValueKind: EnumMemberValueKind
    ValueText: string?

    constructor(
        name: string,
        line: int = 0,
        column: int = 0,
        valueKind: EnumMemberValueKind = 0,
        valueText: string? = null) {
        Name = name
        Line = line
        Column = column
        ValueKind = valueKind
        ValueText = valueText
    }
}

public class EnumDeclarationInfo {
    Name: string
    Members: List<EnumMemberInfo>
    Type: EnumType
    Line: int
    Column: int

    constructor(name: string, members: List<EnumMemberInfo>, enumType: EnumType, line: int = 0, column: int = 0) {
        Name = name
        Members = members
        Type = enumType
        Line = line
        Column = column
    }
}

public class EnumTypeInfo: TypeInfo {
    declarationValue: EnumDeclarationInfo

    Declaration: EnumDeclarationInfo => declarationValue

    constructor(declaration: EnumDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}

public class ReflectionMethodInfo: TypeInfo {
    Method: MethodInfo
    displayValue: string

    constructor(method: MethodInfo) {
        Method = method
        displayValue = "method"
    }

    constructor(method: MethodInfo, displayText: string) {
        Method = method
        displayValue = displayText
    }

    override func ToString(): string {
        return displayValue
    }
}

public class ReflectionMethodGroupInfo: TypeInfo {
    Methods: MethodInfo[]
    displayValue: string

    constructor(methods: MethodInfo[]) {
        Methods = methods
        displayValue = "method group"
    }

    constructor(methods: MethodInfo[], displayText: string) {
        Methods = methods
        displayValue = displayText
    }

    override func ToString(): string {
        return displayValue
    }
}

public class ReflectionEventInfo: TypeInfo {
    Name: string
    AddMethod: MethodInfo?
    RemoveMethod: MethodInfo?
    HandlerDelegateType: Type?
    DeclaringType: Type?
    displayValue: string

    constructor(
        name: string,
        addMethod: MethodInfo?,
        removeMethod: MethodInfo?,
        handlerDelegateType: Type?,
        declaringType: Type?,
        displayText: string) {
        Name = name
        AddMethod = addMethod
        RemoveMethod = removeMethod
        HandlerDelegateType = handlerDelegateType
        DeclaringType = declaringType
        displayValue = displayText
    }

    constructor(name: string) {
        Name = name
        AddMethod = null
        RemoveMethod = null
        HandlerDelegateType = null
        DeclaringType = null
        displayValue = "event"
    }

    override func ToString(): string {
        return displayValue
    }
}
