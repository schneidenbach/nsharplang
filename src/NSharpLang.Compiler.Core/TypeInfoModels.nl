namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast

enum DeclaredMemberKind {
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

class DeclaredMemberInfo {
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
    hasReceiverParameterValue: bool
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
    declaredModifiersValue: int
    hasBodyValue: bool

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
    HasReceiverParameter: bool => hasReceiverParameterValue
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

    // THE MEMBER'S RAW MODIFIER BITS, exactly as the declaration spelled them. `IsStatic`,
    // `IsReadonly`, `IsAsync` and `IsGenerator` above are single bits this factory already decoded;
    // this field carries the WHOLE word so a question nobody has asked yet — is this member
    // `virtual`, `abstract`, `sealed`? — does not need another constructor parameter. It defaults to
    // zero (`Modifiers.None`) so every existing caller keeps its 30-argument spelling; only the
    // production factory that reads a real declaration supplies it.
    DeclaredModifiers: int => declaredModifiersValue

    // WHETHER A DERIVED MEMBER MAY OVERRIDE THIS ONE. `virtual` and `abstract` introduce a slot;
    // `override` re-implements one and stays overridable unless it is also `sealed`. Anything else —
    // a plain method — has no slot to take. The bits are `Modifiers.Virtual` (32),
    // `Modifiers.Abstract` (64), `Modifiers.Sealed` (128) and `Modifiers.Override` (65536), read
    // arithmetically for the same reason the factory above reads 16, 512, 2048 and 4096 that way.
    IsOverridable: bool => (declaredModifiersValue & 32) == 32 || (declaredModifiersValue & 64) == 64 || ((declaredModifiersValue & 65536) == 65536 && (declaredModifiersValue & 128) != 128)

    // WHETHER THE MEMBER CARRIES CODE. A slot and a default implementation look identical in every
    // other field this model has — same name, same kind, same modifiers — and only the presence of a
    // BODY tells them apart. An interface member written `func Describe(): string { … }` is a DEFAULT
    // IMPLEMENTATION that an implementer may inherit; one written `func Greet(): string` is a slot the
    // implementer must fill. Without this bit the interface rule demanded both, and it accused
    // `examples/06-classes-and-records/RecordsAndInterfaces.nl` — correct N# — of not implementing the
    // very member its interface had already written out. Defaults to false so every existing caller
    // keeps its spelling; only the production factory that reads a real declaration supplies it.
    HasBody: bool => hasBodyValue

    constructor(name: string, containingType: string, kind: DeclaredMemberKind, kindName: string, typeReference: TypeReference?, isStatic: bool, isReadonly: bool, hasSetter: bool, isExported: bool, parameterCount: int, parameterNames: string[], parameterTypes: TypeReference[], parameterModifiers: ParameterModifier[], requiredParameterCount: int, hasParamsParameter: bool, hasReceiverParameter: bool, returnType: TypeReference?, typeParameterCount: int, typeParameters: TypeParameter[], genericConstraints: GenericConstraint[], attributeCount: int, hasMustUseAttribute: bool, isAsync: bool, isGenerator: bool, isOperatorOverload: bool, operatorSymbol: string, isConversionOperator: bool, isImplicitConversion: bool, line: int, column: int, declaredModifiers: int = 0, hasBody: bool = false) {
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
        hasReceiverParameterValue = hasReceiverParameter
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
        declaredModifiersValue = declaredModifiers
        hasBodyValue = hasBody
    }
}

class ParameterDeclarationInfo {
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

class NestedTypeInfo {
    nameValue: string
    typeValue: TypeInfo
    isExportedValue: bool

    Name: string => nameValue
    Type: TypeInfo => typeValue
    IsExported: bool => isExportedValue

    constructor(name: string, nestedType: TypeInfo) {
        nameValue = name
        typeValue = nestedType
        isExportedValue = VisibilityConventions.IsExportedIdentifier(name)
    }

    constructor(name: string, nestedType: TypeInfo, isExported: bool) {
        nameValue = name
        typeValue = nestedType
        isExportedValue = isExported
    }
}

class TypeInfo {
}

class ClassTypeInfo: TypeInfo {
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

    constraintsValue: GenericConstraint[]
    isAbstractValue: bool

    // The declaration's `where` clauses, in written order. Empty when it has none, never null, so a
    // caller never has to distinguish "no clause" from "not carried".
    Constraints: GenericConstraint[] => constraintsValue

    // WHETHER THE DECLARATION CARRIES `abstract`. `IsSealed` had been here since the type was first
    // written and its opposite had not, so the one question `new` has to ask — may this type have a
    // direct instance — could not be asked of a resolved type at all. It is a DEFAULTED trailing
    // constructor parameter so that every hand-built shape in the estate keeps its own arity.
    IsAbstract: bool => isAbstractValue

    constructor(name: string, line: int, column: int, isSealed: bool, baseClass: TypeReference?, interfaces: TypeReference[], typeParameters: TypeParameter[], primaryConstructorParameters: ParameterDeclarationInfo[], declaredMembers: DeclaredMemberInfo[], nestedTypes: NestedTypeInfo[], hasParameterlessConstructor: bool, constraints: GenericConstraint[]? = null, isAbstract: bool = false) {
        constraintsValue = constraints ?? new GenericConstraint[](0)
        isAbstractValue = isAbstract
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

class StructTypeInfo: TypeInfo {
    nameValue: string
    lineValue: int
    columnValue: int
    interfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    primaryConstructorParametersValue: ParameterDeclarationInfo[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    Interfaces: TypeReference[] => interfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    PrimaryConstructorParameters: ParameterDeclarationInfo[] => primaryConstructorParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constraintsValue: GenericConstraint[]

    // The declaration's `where` clauses, in written order. Empty when it has none, never null, so a
    // caller never has to distinguish "no clause" from "not carried".
    Constraints: GenericConstraint[] => constraintsValue

    constructor(name: string, line: int, column: int, interfaces: TypeReference[], typeParameters: TypeParameter[], primaryConstructorParameters: ParameterDeclarationInfo[], declaredMembers: DeclaredMemberInfo[], nestedTypes: NestedTypeInfo[], constraints: GenericConstraint[]? = null) {
        constraintsValue = constraints ?? new GenericConstraint[](0)
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

class RecordTypeInfo: TypeInfo {
    nameValue: string
    lineValue: int
    columnValue: int
    isStructValue: bool
    interfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    primaryConstructorParametersValue: ParameterDeclarationInfo[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    IsStruct: bool => isStructValue
    Interfaces: TypeReference[] => interfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    PrimaryConstructorParameters: ParameterDeclarationInfo[] => primaryConstructorParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constraintsValue: GenericConstraint[]

    // The declaration's `where` clauses, in written order. Empty when it has none, never null, so a
    // caller never has to distinguish "no clause" from "not carried".
    Constraints: GenericConstraint[] => constraintsValue

    constructor(name: string, line: int, column: int, isStruct: bool, interfaces: TypeReference[], typeParameters: TypeParameter[], primaryConstructorParameters: ParameterDeclarationInfo[], declaredMembers: DeclaredMemberInfo[], nestedTypes: NestedTypeInfo[], constraints: GenericConstraint[]? = null) {
        constraintsValue = constraints ?? new GenericConstraint[](0)
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

class InterfaceTypeInfo: TypeInfo {
    nameValue: string
    lineValue: int
    columnValue: int
    isDuckInterfaceValue: bool
    baseInterfacesValue: TypeReference[]
    typeParametersValue: TypeParameter[]
    declaredMembersValue: DeclaredMemberInfo[]
    nestedTypesValue: NestedTypeInfo[]

    Name: string => nameValue
    Line: int => lineValue
    Column: int => columnValue
    IsDuckInterface: bool => isDuckInterfaceValue
    BaseInterfaces: TypeReference[] => baseInterfacesValue
    TypeParameters: TypeParameter[] => typeParametersValue
    DeclaredMembers: DeclaredMemberInfo[] => declaredMembersValue
    NestedTypes: NestedTypeInfo[] => nestedTypesValue

    constraintsValue: GenericConstraint[]

    // The declaration's `where` clauses, in written order. Empty when it has none, never null, so a
    // caller never has to distinguish "no clause" from "not carried".
    Constraints: GenericConstraint[] => constraintsValue

    constructor(name: string, line: int, column: int, isDuckInterface: bool, baseInterfaces: TypeReference[], typeParameters: TypeParameter[], declaredMembers: DeclaredMemberInfo[], nestedTypes: NestedTypeInfo[], constraints: GenericConstraint[]? = null) {
        constraintsValue = constraints ?? new GenericConstraint[](0)
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

class SimpleTypeInfo: TypeInfo {
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

class UnknownTypeInfo: TypeInfo {
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

class NewtypeInfo: TypeInfo {
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

class ExternalTypeInfo: TypeInfo {
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

class ReflectionTypeInfo: TypeInfo {
    clrTypeValue: Type

    Type: Type => clrTypeValue

    constructor(clrType: Type) {
        clrTypeValue = clrType
    }

    override func ToString(): string {
        return clrTypeValue.Name
    }
}

class BuiltInTypes {
    static Int: SimpleTypeInfo => new SimpleTypeInfo("int")
    static Long: SimpleTypeInfo => new SimpleTypeInfo("long")
    static Float: SimpleTypeInfo => new SimpleTypeInfo("float")
    static Double: SimpleTypeInfo => new SimpleTypeInfo("double")
    static Decimal: SimpleTypeInfo => new SimpleTypeInfo("decimal")
    static Byte: SimpleTypeInfo => new SimpleTypeInfo("byte")
    static SByte: SimpleTypeInfo => new SimpleTypeInfo("sbyte")
    static Short: SimpleTypeInfo => new SimpleTypeInfo("short")
    static UShort: SimpleTypeInfo => new SimpleTypeInfo("ushort")
    static UInt: SimpleTypeInfo => new SimpleTypeInfo("uint")
    static ULong: SimpleTypeInfo => new SimpleTypeInfo("ulong")
    static Char: SimpleTypeInfo => new SimpleTypeInfo("char")
    static Bool: SimpleTypeInfo => new SimpleTypeInfo("bool")
    static String: SimpleTypeInfo => new SimpleTypeInfo("string")
    static Void: SimpleTypeInfo => new SimpleTypeInfo("void")
    static Object: SimpleTypeInfo => new SimpleTypeInfo("object")
    static Null: SimpleTypeInfo => new SimpleTypeInfo("null")
    static Never: SimpleTypeInfo => new SimpleTypeInfo("never")
    static Unknown: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.ErrorRecovery)
    static InferenceHole: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.InferenceHole)
    static DeferredExternal: UnknownTypeInfo => new UnknownTypeInfo(UnknownKind.DeferredExternal)

    static func Is(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        if typeInfo == null {
            return false
        }

        simple := typeInfo as SimpleTypeInfo
        if simple == null {
            return false
        }

        return simple.Equals(builtIn)
    }

    static func IsNot(typeInfo: TypeInfo?, builtIn: SimpleTypeInfo): bool {
        return !Is(typeInfo, builtIn)
    }

    static func IsUnknown(typeInfo: TypeInfo): bool {
        unknown := typeInfo as UnknownTypeInfo
        return unknown != null
    }
}

class TupleTypeElementInfo {
    Name: string?
    Type: TypeInfo

    constructor(name: string?, elementType: TypeInfo) {
        Name = name
        Type = elementType
    }

    func Deconstruct(out name: string?, out elementType: TypeInfo) {
        name = Name
        elementType = Type
    }
}

class TupleTypeInfo: TypeInfo {
    Elements: List<TupleTypeElementInfo>

    constructor(elements: List<TupleTypeElementInfo>) {
        Elements = elements
    }
}

class AnonymousUnionTypeInfo: TypeInfo {
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

class AliasTypeInfo: TypeInfo {
    aliasedTypeValue: TypeReference

    AliasedType: TypeReference => aliasedTypeValue

    constructor(aliasedType: TypeReference) {
        aliasedTypeValue = aliasedType
    }
}

class GenericTypeInfo: TypeInfo {
    nameValue: string
    typeArgumentsValue: List<TypeInfo>
    genericDefinitionValue: TypeInfo?

    Name: string => nameValue
    TypeArguments: List<TypeInfo> => typeArgumentsValue
    GenericDefinition: TypeInfo? => genericDefinitionValue

    constructor(name: string, typeArguments: List<TypeInfo>) {
        nameValue = name
        typeArgumentsValue = typeArguments
        genericDefinitionValue = null
    }

    constructor(name: string, typeArguments: List<TypeInfo>, genericDefinition: TypeInfo?) {
        nameValue = name
        typeArgumentsValue = typeArguments
        genericDefinitionValue = genericDefinition
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

class ArrayTypeInfo: TypeInfo {
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

class NullableTypeInfo: TypeInfo {
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

class FunctionTypeInfo: TypeInfo {
    SyntheticName: string?
    SourceName: string?
    SourceContainingType: string?
    SourceLine: int
    SourceColumn: int
    SourceParameterCount: int
    SourceHasReceiverParameter: bool
    ParameterNames: List<string>?
    ParameterTypes: List<TypeInfo>?
    SourceParameterTypes: List<TypeReference>?
    SourceReturnType: TypeReference?
    ParameterModifiers: List<ParameterModifier>?
    RequiredParameterCount: int?
    HasParamsParameter: bool
    TypeParameters: List<TypeParameter>?
    GenericConstraints: List<GenericConstraint>?
    ResolvedGenericConstraintTypes: Dictionary<string, List<TypeInfo>>?
    HasMustUseAttribute: bool
    ReturnType: TypeInfo?

    constructor() {
        HasParamsParameter = false
        HasMustUseAttribute = false
        SourceLine = 0
        SourceColumn = 0
        SourceParameterCount = -1
        SourceHasReceiverParameter = false
    }
}

class NSharpMethodGroupInfo: TypeInfo {
    Functions: List<FunctionTypeInfo>

    constructor(functions: List<FunctionTypeInfo>) {
        Functions = functions
    }

    override func ToString(): string {
        return "method group"
    }
}

class ObliviousTypeInfo: TypeInfo {
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

class ByRefTypeInfo: TypeInfo {
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

class SoaColumnInfo {
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

class SoaRecordDeclarationInfo {
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

class SoaRecordTypeInfo: TypeInfo {
    declarationValue: SoaRecordDeclarationInfo

    Declaration: SoaRecordDeclarationInfo => declarationValue

    constructor(declaration: SoaRecordDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}

class SoaRowTypeInfo: TypeInfo {
    declarationValue: SoaRecordDeclarationInfo

    Declaration: SoaRecordDeclarationInfo => declarationValue

    constructor(declaration: SoaRecordDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return $"{declarationValue.Name}.Row"
    }
}

class UnionDeclarationInfo {
    Name: string
    TypeParameters: List<TypeParameter>?
    Cases: List<UnionCase>
    Line: int
    Column: int
    // The `where` clauses, as on every other declaration's TypeInfo. Empty when there are none.
    Constraints: GenericConstraint[]

    constructor(name: string, typeParameters: List<TypeParameter>?, cases: List<UnionCase>, line: int = 0, column: int = 0, constraints: GenericConstraint[]? = null) {
        Name = name
        TypeParameters = typeParameters
        Cases = cases
        Line = line
        Column = column
        Constraints = constraints ?? new GenericConstraint[](0)
    }
}

class UnionTypeInfo: TypeInfo {
    declarationValue: UnionDeclarationInfo

    Declaration: UnionDeclarationInfo => declarationValue

    constructor(declaration: UnionDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}

enum EnumMemberValueKind {
    None,
    String,
    Integer
}

class EnumMemberInfo {
    Name: string
    Line: int
    Column: int
    ValueKind: EnumMemberValueKind
    ValueText: string?

    constructor(name: string, line: int = 0, column: int = 0, valueKind: EnumMemberValueKind = 0, valueText: string? = null) {
        Name = name
        Line = line
        Column = column
        ValueKind = valueKind
        ValueText = valueText
    }
}

class EnumDeclarationInfo {
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

class EnumTypeInfo: TypeInfo {
    declarationValue: EnumDeclarationInfo

    Declaration: EnumDeclarationInfo => declarationValue

    constructor(declaration: EnumDeclarationInfo) {
        declarationValue = declaration
    }

    override func ToString(): string {
        return declarationValue.Name
    }
}
