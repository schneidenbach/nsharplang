namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import NSharpLang.Compiler.Ast

class ReflectionTypeInfoFactory {
    static func FromConstructedGeneric(name: string, arguments: List<TypeInfo>, constructedType: Type): GenericTypeInfo {
        return new GenericTypeInfo(name, arguments, new ReflectionTypeInfo(constructedType.GetGenericTypeDefinition()))
    }
}

class NominalTypeInfoFactory {
    static func FromClassDeclaration(declaration: object): ClassTypeInfo {
        primaryConstructorParameters := GetParameterArray(declaration, "PrimaryConstructorParameters")
        declaredMembers := GetDeclaredMemberArray(declaration)
        nestedTypes := GetNestedTypeArray(declaration)
        return new ClassTypeInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"), HasModifier(declaration, 128), GetOptionalTypeReference(declaration, "BaseClass"), GetTypeReferenceArray(declaration, "Interfaces"), GetTypeParameterArray(declaration), primaryConstructorParameters, declaredMembers, nestedTypes, HasParameterlessClassConstructor(primaryConstructorParameters, declaredMembers))
    }

    static func FromStructDeclaration(declaration: object): StructTypeInfo {
        primaryConstructorParameters := GetParameterArray(declaration, "PrimaryConstructorParameters")
        declaredMembers := GetDeclaredMemberArray(declaration)
        return new StructTypeInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"), GetTypeReferenceArray(declaration, "Interfaces"), GetTypeParameterArray(declaration), primaryConstructorParameters, declaredMembers, GetNestedTypeArray(declaration))
    }

    static func FromRecordDeclaration(declaration: object): RecordTypeInfo {
        primaryConstructorParameters := GetParameterArray(declaration, "PrimaryConstructorParameters")
        declaredMembers := GetDeclaredMemberArray(declaration)
        return new RecordTypeInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"), TypeInfoFactoryReflection.GetRequiredBool(declaration, "IsStruct"), GetTypeReferenceArray(declaration, "Interfaces"), GetTypeParameterArray(declaration), primaryConstructorParameters, declaredMembers, GetNestedTypeArray(declaration))
    }

    static func FromInterfaceDeclaration(declaration: object): InterfaceTypeInfo {
        declaredMembers := GetDeclaredMemberArray(declaration)
        return new InterfaceTypeInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"), TypeInfoFactoryReflection.GetRequiredBool(declaration, "IsDuckInterface"), GetTypeReferenceArray(declaration, "BaseInterfaces"), GetTypeParameterArray(declaration), declaredMembers, GetNestedTypeArray(declaration))
    }

    static func HasModifier(declaration: object, flag: int): bool {
        modifiers := TypeInfoFactoryReflection.GetRequiredProperty(declaration, "Modifiers")
        value := Convert.ToInt32(modifiers)
        return (value & flag) == flag
    }

    static func GetOptionalTypeReference(owner: object, propertyName: string): TypeReference? {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        if value == null {
            return null
        }

        typeReference := value as TypeReference
        if typeReference == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a type reference.")
        }

        return typeReference
    }

    static func GetTypeReferenceArray(owner: object, propertyName: string): TypeReference[] {
        source := TypeInfoFactoryReflection.GetRequiredList(owner, propertyName)
        result := new TypeReference[](source.Count)

        index := 0
        while index < source.Count {
            item := source[index]
            typeReference := item as TypeReference
            if typeReference == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' entries to be type references.")
            }

            result[index] = typeReference
            index = index + 1
        }

        return result
    }

    static func GetTypeParameterArray(owner: object): TypeParameter[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "TypeParameters")
        if value == null {
            return new TypeParameter[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".TypeParameters' to be a list.")
        }

        result := new TypeParameter[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            typeParameter := item as TypeParameter
            if typeParameter == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".TypeParameters' entries to be type parameters.")
            }

            result[index] = typeParameter
            index = index + 1
        }

        return result
    }

    static func GetParameterArray(owner: object, propertyName: string): ParameterDeclarationInfo[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        if value == null {
            return new ParameterDeclarationInfo[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a list.")
        }

        result := new ParameterDeclarationInfo[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' entries to be parameters.")
            }

            parameterTypeValue := TypeInfoFactoryReflection.GetRequiredProperty(item, "Type")
            parameterType := parameterTypeValue as TypeReference
            if parameterType == null {
                throw new InvalidOperationException("Expected '" + item.GetType().Name + ".Type' to be a type reference.")
            }

            result[index] = new ParameterDeclarationInfo(TypeInfoFactoryReflection.GetRequiredString(item, "Name"), parameterType, TypeInfoFactoryReflection.GetRequiredInt(item, "Line"), TypeInfoFactoryReflection.GetRequiredInt(item, "Column"))
            index = index + 1
        }

        return result
    }

    static func GetDeclaredMemberArray(owner: object): DeclaredMemberInfo[] {
        source := TypeInfoFactoryReflection.GetRequiredList(owner, "Members")
        result := new DeclaredMemberInfo[](source.Count)
        containingType := TypeInfoFactoryReflection.GetRequiredString(owner, "Name")

        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Members' entries to be declarations.")
            }

            result[index] = CreateDeclaredMemberInfo(containingType, item)
            index = index + 1
        }

        return result
    }

    static func GetNestedTypeArray(owner: object): NestedTypeInfo[] {
        source := TypeInfoFactoryReflection.GetRequiredList(owner, "Members")

        count := 0
        index := 0
        while index < source.Count {
            item := source[index]
            if item != null && IsNestedTypeDeclarationName(item.GetType().Name) {
                count = count + 1
            }

            index = index + 1
        }

        result := new NestedTypeInfo[](count)
        resultIndex := 0
        index = 0
        while index < source.Count {
            item := source[index]
            if item != null && IsNestedTypeDeclarationName(item.GetType().Name) {
                result[resultIndex] = CreateNestedTypeInfo(item)
                resultIndex = resultIndex + 1
            }

            index = index + 1
        }

        return result
    }

    static func CreateDeclaredMemberInfo(containingType: string, member: object): DeclaredMemberInfo {
        typeName := member.GetType().Name
        name := GetOptionalString(member, "Name")
        kind := GetDeclaredMemberKind(typeName)
        typeParameters := GetTypeParameterArray(member)
        genericConstraints := GetGenericConstraintArray(member)
        return new DeclaredMemberInfo(name, containingType, kind, GetDeclaredMemberKindName(kind), GetDeclaredMemberTypeReference(member, kind), HasOptionalModifier(member, 16), HasOptionalModifier(member, 512), HasOptionalPropertyValue(member, "SetBody"), IsExportedMember(member, name), GetOptionalListCount(member, "Parameters"), GetParameterNameArray(member), GetParameterTypeArray(member), GetParameterModifierArray(member), GetRequiredParameterCount(member), HasParamsParameter(member), HasReceiverParameter(member), GetOptionalTypeReference(member, "ReturnType"), typeParameters.Length, typeParameters, genericConstraints, GetOptionalListCount(member, "Attributes"), HasMustUseAttribute(member), HasOptionalModifier(member, 2048), HasOptionalModifier(member, 4096), GetOptionalBool(member, "IsOperatorOverload"), GetOptionalString(member, "OperatorSymbol"), GetOptionalBool(member, "IsConversionOperator"), GetOptionalBool(member, "IsImplicitConversion"), TypeInfoFactoryReflection.GetRequiredInt(member, "Line"), TypeInfoFactoryReflection.GetRequiredInt(member, "Column"))
    }

    static func GetGenericConstraintArray(owner: object): GenericConstraint[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Constraints")
        if value == null {
            return new GenericConstraint[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Constraints' to be a list.")
        }

        result := new GenericConstraint[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            constraint := item as GenericConstraint
            if constraint == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Constraints' entries to be generic constraints.")
            }

            result[index] = constraint
            index = index + 1
        }

        return result
    }

    static func GetDeclaredMemberTypeReference(member: object, kind: DeclaredMemberKind): TypeReference? {
        if kind == DeclaredMemberKind.Field || kind == DeclaredMemberKind.Property || kind == DeclaredMemberKind.TypeAlias {
            return GetOptionalTypeReference(member, "Type")
        }

        if kind == DeclaredMemberKind.Newtype {
            return GetOptionalTypeReference(member, "UnderlyingType")
        }

        return null
    }

    static func HasOptionalModifier(declaration: object, flag: int): bool {
        modifiers := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Modifiers")
        if modifiers == null {
            return false
        }

        value := Convert.ToInt32(modifiers)
        return (value & flag) == flag
    }

    static func HasOptionalPropertyValue(owner: object, propertyName: string): bool {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        return value != null
    }

    static func IsExportedMember(member: object, name: string): bool {
        modifiers := TypeInfoFactoryReflection.GetOptionalProperty(member, "Modifiers")
        if modifiers == null {
            return VisibilityConventions.IsExportedIdentifier(name)
        }

        return VisibilityConventions.IsExportedIdentifier(name, modifiers)
    }

    static func GetOptionalListCount(owner: object, propertyName: string): int {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        if value == null {
            return -1
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a list.")
        }

        return source.Count
    }

    static func GetParameterNameArray(owner: object): string[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return new string[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        result := new string[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
            }

            result[index] = TypeInfoFactoryReflection.GetRequiredString(item, "Name")
            index = index + 1
        }

        return result
    }

    static func GetParameterTypeArray(owner: object): TypeReference[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return new TypeReference[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        result := new TypeReference[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
            }

            parameterTypeValue := TypeInfoFactoryReflection.GetRequiredProperty(item, "Type")
            parameterType := parameterTypeValue as TypeReference
            if parameterType == null {
                throw new InvalidOperationException("Expected '" + item.GetType().Name + ".Type' to be a type reference.")
            }

            result[index] = parameterType
            index = index + 1
        }

        return result
    }

    static func GetParameterModifierArray(owner: object): ParameterModifier[] {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return new ParameterModifier[](0)
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        result := new ParameterModifier[](source.Count)
        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
            }

            result[index] = GetParameterModifier(item)
            index = index + 1
        }

        return result
    }

    static func GetRequiredParameterCount(owner: object): int {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return -1
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        count := 0
        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
            }

            if GetParameterModifier(item) != ParameterModifier.Params && TypeInfoFactoryReflection.GetOptionalProperty(item, "DefaultValue") == null {
                count = count + 1
            }

            index = index + 1
        }

        return count
    }

    static func HasParamsParameter(owner: object): bool {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return false
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
            }

            if GetParameterModifier(item) == ParameterModifier.Params {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func HasReceiverParameter(owner: object): bool {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Parameters")
        if value == null {
            return false
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' to be a list.")
        }

        if source.Count == 0 {
            return false
        }

        first := source[0]
        if first == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Parameters' entries to be parameters.")
        }

        return GetOptionalBool(first, "IsThis")
    }

    static func HasMustUseAttribute(owner: object): bool {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, "Attributes")
        if value == null {
            return false
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Attributes' to be a list.")
        }

        index := 0
        while index < source.Count {
            item := source[index]
            if item == null {
                throw new InvalidOperationException("Expected '" + owner.GetType().Name + ".Attributes' entries to be attributes.")
            }

            name := TypeInfoFactoryReflection.GetRequiredString(item, "Name")
            if IsMustUseAttributeName(name) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // Public because the analyzer's function-type factory answers the same question for a
    // DECLARED attribute list and the analyzer's reflection arm for a CLR attribute name; the rule
    // is stated once, here.
    static func IsMustUseAttributeName(name: string): bool {
        return AttributeNameEquals(name, "MustUse") || AttributeNameEquals(name, "MustUseAttribute") || AttributeNameEndsWith(name, ".MustUse") || AttributeNameEndsWith(name, ".MustUseAttribute")
    }

    static func AttributeNameEquals(name: string, expected: string): bool {
        if name.Length != expected.Length {
            return false
        }

        return String.Compare(name, expected, StringComparison.Ordinal) == 0
    }

    static func AttributeNameEndsWith(name: string, suffix: string): bool {
        if name.Length < suffix.Length {
            return false
        }

        start := name.Length - suffix.Length
        return String.Compare(name, start, suffix, 0, suffix.Length, StringComparison.Ordinal) == 0
    }

    static func GetParameterModifier(parameter: object): ParameterModifier {
        value := TypeInfoFactoryReflection.GetRequiredProperty(parameter, "Modifier")
        modifier := Convert.ToInt32(value)
        if modifier == 1 {
            return ParameterModifier.Ref
        }
        if modifier == 2 {
            return ParameterModifier.Out
        }
        if modifier == 3 {
            return ParameterModifier.Params
        }

        return ParameterModifier.None
    }

    static func GetOptionalString(owner: object, propertyName: string): string {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        if value == null {
            return ""
        }

        text := value as string
        if text == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be text.")
        }

        return text
    }

    static func GetOptionalBool(owner: object, propertyName: string): bool {
        value := TypeInfoFactoryReflection.GetOptionalProperty(owner, propertyName)
        if value == null {
            return false
        }

        return Convert.ToInt32(value) != 0
    }

    static func GetDeclaredMemberKind(typeName: string): DeclaredMemberKind {
        if typeName == "FieldDeclaration" {
            return DeclaredMemberKind.Field
        }
        if typeName == "PropertyDeclaration" {
            return DeclaredMemberKind.Property
        }
        if typeName == "FunctionDeclaration" {
            return DeclaredMemberKind.Function
        }
        if typeName == "ClassDeclaration" {
            return DeclaredMemberKind.Class
        }
        if typeName == "StructDeclaration" {
            return DeclaredMemberKind.Struct
        }
        if typeName == "RecordDeclaration" {
            return DeclaredMemberKind.Record
        }
        if typeName == "SoaRecordDeclaration" {
            return DeclaredMemberKind.SoaRecord
        }
        if typeName == "InterfaceDeclaration" {
            return DeclaredMemberKind.Interface
        }
        if typeName == "EnumDeclaration" {
            return DeclaredMemberKind.Enum
        }
        if typeName == "UnionDeclaration" {
            return DeclaredMemberKind.Union
        }
        if typeName == "TypeAliasDeclaration" {
            return DeclaredMemberKind.TypeAlias
        }
        if typeName == "NewtypeDeclaration" {
            return DeclaredMemberKind.Newtype
        }
        if typeName == "ConstructorDeclaration" {
            return DeclaredMemberKind.Constructor
        }

        return DeclaredMemberKind.Unknown
    }

    static func IsNestedTypeDeclarationName(typeName: string): bool {
        return typeName == "ClassDeclaration" || typeName == "StructDeclaration" || typeName == "RecordDeclaration" || typeName == "SoaRecordDeclaration" || typeName == "InterfaceDeclaration" || typeName == "EnumDeclaration" || typeName == "UnionDeclaration" || typeName == "TypeAliasDeclaration" || typeName == "NewtypeDeclaration"
    }

    static func CreateNestedTypeInfo(declaration: object): NestedTypeInfo {
        name := TypeInfoFactoryReflection.GetRequiredString(declaration, "Name")
        typeName := declaration.GetType().Name
        isExported := IsExportedMember(declaration, name)

        if typeName == "ClassDeclaration" {
            return new NestedTypeInfo(name, FromClassDeclaration(declaration), isExported)
        }
        if typeName == "StructDeclaration" {
            return new NestedTypeInfo(name, FromStructDeclaration(declaration), isExported)
        }
        if typeName == "RecordDeclaration" {
            return new NestedTypeInfo(name, FromRecordDeclaration(declaration), isExported)
        }
        if typeName == "SoaRecordDeclaration" {
            return new NestedTypeInfo(name, SoaTypeInfoFactory.FromDeclaration(declaration), isExported)
        }
        if typeName == "InterfaceDeclaration" {
            return new NestedTypeInfo(name, FromInterfaceDeclaration(declaration), isExported)
        }
        if typeName == "EnumDeclaration" {
            return new NestedTypeInfo(name, EnumTypeInfoFactory.FromDeclaration(declaration), isExported)
        }
        if typeName == "UnionDeclaration" {
            return new NestedTypeInfo(name, UnionTypeInfoFactory.FromDeclaration(declaration), isExported)
        }
        if typeName == "TypeAliasDeclaration" {
            aliasType := GetOptionalTypeReference(declaration, "Type")
            if aliasType == null {
                throw new InvalidOperationException("Expected '" + declaration.GetType().Name + ".Type' to be a type reference.")
            }

            return new NestedTypeInfo(name, new AliasTypeInfo(aliasType), isExported)
        }
        if typeName == "NewtypeDeclaration" {
            underlyingType := GetOptionalTypeReference(declaration, "UnderlyingType")
            if underlyingType == null {
                throw new InvalidOperationException("Expected '" + declaration.GetType().Name + ".UnderlyingType' to be a type reference.")
            }

            return new NestedTypeInfo(name, new NewtypeInfo(name, underlyingType), isExported)
        }

        throw new InvalidOperationException("Expected '" + typeName + "' to be a nested type declaration.")
    }

    static func GetDeclaredMemberKindName(kind: DeclaredMemberKind): string {
        if kind == DeclaredMemberKind.Field {
            return "field"
        }
        if kind == DeclaredMemberKind.Property {
            return "property"
        }
        if kind == DeclaredMemberKind.Function {
            return "function"
        }
        if kind == DeclaredMemberKind.Class {
            return "class"
        }
        if kind == DeclaredMemberKind.Struct {
            return "struct"
        }
        if kind == DeclaredMemberKind.Record {
            return "record"
        }
        if kind == DeclaredMemberKind.SoaRecord {
            return "soaRecord"
        }
        if kind == DeclaredMemberKind.Interface {
            return "interface"
        }
        if kind == DeclaredMemberKind.Enum {
            return "enum"
        }
        if kind == DeclaredMemberKind.Union {
            return "union"
        }
        if kind == DeclaredMemberKind.TypeAlias {
            return "typeAlias"
        }
        if kind == DeclaredMemberKind.Newtype {
            return "newtype"
        }
        if kind == DeclaredMemberKind.Constructor {
            return "constructor"
        }

        return "variable"
    }

    static func HasParameterlessClassConstructor(primaryConstructorParameters: ParameterDeclarationInfo[], members: DeclaredMemberInfo[]): bool {
        if primaryConstructorParameters.Length > 0 {
            return false
        }

        hasConstructor := false
        index := 0
        while index < members.Length {
            member := members[index]
            if member.Kind == DeclaredMemberKind.Constructor {
                hasConstructor = true
                if member.ParameterCount == 0 {
                    return true
                }
            }

            index = index + 1
        }

        return !hasConstructor
    }
}

class SoaTypeInfoFactory {
    static func FromDeclaration(declaration: object): SoaRecordTypeInfo {
        return new SoaRecordTypeInfo(CreateDeclarationInfo(declaration))
    }

    static func CreateDeclarationInfo(declaration: object): SoaRecordDeclarationInfo {
        columns := new List<SoaColumnInfo>()
        sourceColumns := GetRequiredList(declaration, "Columns")

        index := 0
        while index < sourceColumns.Count {
            column := sourceColumns[index]
            if column != null {
                columns.Add(new SoaColumnInfo(GetRequiredString(column, "Name"), GetRequiredTypeReference(column, "Type"), GetRequiredInt(column, "Line"), GetRequiredInt(column, "Column")))
            }

            index = index + 1
        }

        return new SoaRecordDeclarationInfo(GetRequiredString(declaration, "Name"), columns, GetRequiredInt(declaration, "Line"), GetRequiredInt(declaration, "Column"))
    }

    static func GetRequiredTypeReference(owner: object, propertyName: string): TypeReference {
        value := TypeInfoFactoryReflection.GetRequiredProperty(owner, propertyName)
        typeReference := value as TypeReference
        if typeReference == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a type reference.")
        }

        return typeReference
    }

    static func GetRequiredList(owner: object, propertyName: string): IList {
        return TypeInfoFactoryReflection.GetRequiredList(owner, propertyName)
    }

    static func GetRequiredString(owner: object, propertyName: string): string {
        return TypeInfoFactoryReflection.GetRequiredString(owner, propertyName)
    }

    static func GetRequiredInt(owner: object, propertyName: string): int {
        return TypeInfoFactoryReflection.GetRequiredInt(owner, propertyName)
    }
}

class UnionTypeInfoFactory {
    static func FromDeclaration(declaration: object): UnionTypeInfo {
        typeParametersValue := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "TypeParameters")
        typeParameters := CreateTypeParameterList(typeParametersValue)
        cases := CreateUnionCaseList(TypeInfoFactoryReflection.GetRequiredList(declaration, "Cases"))

        return new UnionTypeInfo(new UnionDeclarationInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), typeParameters, cases, TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column")))
    }

    static func CreateTypeParameterList(value: object?): List<TypeParameter>? {
        if value == null {
            return null
        }

        source := value as IList
        if source == null {
            throw new InvalidOperationException("Expected union type parameters to be a list.")
        }

        result := new List<TypeParameter>()
        index := 0
        while index < source.Count {
            item := source[index]
            typeParameter := item as TypeParameter
            if typeParameter == null {
                throw new InvalidOperationException("Expected union type parameter entries to be TypeParameter values.")
            }

            result.Add(typeParameter)
            index = index + 1
        }

        return result
    }

    static func CreateUnionCaseList(source: IList): List<UnionCase> {
        result := new List<UnionCase>()
        index := 0
        while index < source.Count {
            item := source[index]
            unionCase := item as UnionCase
            if unionCase == null {
                throw new InvalidOperationException("Expected union case entries to be UnionCase values.")
            }

            result.Add(unionCase)
            index = index + 1
        }

        return result
    }
}

class EnumTypeInfoFactory {
    static func FromDeclaration(declaration: object): EnumTypeInfo {
        members := new List<EnumMemberInfo>()
        sourceMembers := TypeInfoFactoryReflection.GetRequiredList(declaration, "Members")

        index := 0
        while index < sourceMembers.Count {
            member := sourceMembers[index]
            if member != null {
                members.Add(CreateMemberInfo(member))
            }

            index = index + 1
        }

        return new EnumTypeInfo(new EnumDeclarationInfo(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), members, GetRequiredEnumType(declaration, "Type"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"), TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column")))
    }

    static func CreateMemberInfo(member: object): EnumMemberInfo {
        valueKind := EnumMemberValueKind.None
        valueText: string? = null

        value := TypeInfoFactoryReflection.GetOptionalProperty(member, "Value")
        if value != null {
            valueTypeName := value.GetType().Name
            if valueTypeName == "StringLiteralExpression" {
                valueKind = EnumMemberValueKind.String
                valueText = TypeInfoFactoryReflection.GetRequiredString(value, "Value")
            } else if valueTypeName == "IntLiteralExpression" {
                valueKind = EnumMemberValueKind.Integer
                valueText = TypeInfoFactoryReflection.GetRequiredString(value, "Value")
            }
        }

        return new EnumMemberInfo(TypeInfoFactoryReflection.GetRequiredString(member, "Name"), TypeInfoFactoryReflection.GetRequiredInt(member, "Line"), TypeInfoFactoryReflection.GetRequiredInt(member, "Column"), valueKind, valueText)
    }

    static func GetRequiredEnumType(owner: object, propertyName: string): EnumType {
        value := TypeInfoFactoryReflection.GetRequiredProperty(owner, propertyName)
        return (EnumType)Convert.ToInt32(value)
    }
}

class TypeInfoFactoryReflection {
    static func GetRequiredProperty(owner: object, propertyName: string): object {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be present.")
        }

        return value
    }

    static func GetOptionalProperty(owner: object, propertyName: string): object? {
        property := owner.GetType().GetProperty(propertyName)
        if property != null {
            return property.GetValue(owner)
        }

        field := owner.GetType().GetField(propertyName)
        if field != null {
            return field.GetValue(owner)
        }

        return null
    }

    static func GetRequiredList(owner: object, propertyName: string): IList {
        value := GetRequiredProperty(owner, propertyName)
        list := value as IList
        if list == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a list.")
        }

        return list
    }

    static func GetRequiredString(owner: object, propertyName: string): string {
        value := GetRequiredProperty(owner, propertyName)
        text := value as string
        if text == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be text.")
        }

        return text
    }

    static func GetRequiredInt(owner: object, propertyName: string): int {
        value := GetRequiredProperty(owner, propertyName)
        return Convert.ToInt32(value)
    }

    static func GetRequiredBool(owner: object, propertyName: string): bool {
        value := GetRequiredProperty(owner, propertyName)
        return Convert.ToInt32(value) != 0
    }
}
