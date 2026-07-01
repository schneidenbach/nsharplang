namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import NSharpLang.Compiler.Ast

public class NominalTypeInfoFactory {
    public static func FromClassDeclaration(declaration: object): ClassTypeInfo {
        return new ClassTypeInfo(
            declaration,
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"),
            HasModifier(declaration, 128),
            GetOptionalTypeReference(declaration, "BaseClass"),
            GetTypeReferenceArray(declaration, "Interfaces"),
            GetTypeParameterArray(declaration),
            GetParameterArray(declaration, "PrimaryConstructorParameters"))
    }

    public static func FromStructDeclaration(declaration: object): StructTypeInfo {
        return new StructTypeInfo(
            declaration,
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"),
            GetTypeReferenceArray(declaration, "Interfaces"),
            GetTypeParameterArray(declaration),
            GetParameterArray(declaration, "PrimaryConstructorParameters"))
    }

    public static func FromRecordDeclaration(declaration: object): RecordTypeInfo {
        return new RecordTypeInfo(
            declaration,
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"),
            TypeInfoFactoryReflection.GetRequiredBool(declaration, "IsStruct"),
            GetTypeReferenceArray(declaration, "Interfaces"),
            GetTypeParameterArray(declaration),
            GetParameterArray(declaration, "PrimaryConstructorParameters"))
    }

    public static func FromInterfaceDeclaration(declaration: object): InterfaceTypeInfo {
        return new InterfaceTypeInfo(
            declaration,
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column"),
            TypeInfoFactoryReflection.GetRequiredBool(declaration, "IsDuckInterface"),
            GetTypeReferenceArray(declaration, "BaseInterfaces"),
            GetTypeParameterArray(declaration))
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

            result[index] = new ParameterDeclarationInfo(
                TypeInfoFactoryReflection.GetRequiredString(item, "Name"),
                parameterType,
                TypeInfoFactoryReflection.GetRequiredInt(item, "Line"),
                TypeInfoFactoryReflection.GetRequiredInt(item, "Column"))
            index = index + 1
        }

        return result
    }
}

public class SoaTypeInfoFactory {
    public static func FromDeclaration(declaration: object): SoaRecordTypeInfo {
        return new SoaRecordTypeInfo(CreateDeclarationInfo(declaration))
    }

    public static func CreateDeclarationInfo(declaration: object): SoaRecordDeclarationInfo {
        columns := new List<SoaColumnInfo>()
        sourceColumns := GetRequiredList(declaration, "Columns")

        index := 0
        while index < sourceColumns.Count {
            column := sourceColumns[index]
            if column != null {
                columns.Add(new SoaColumnInfo(
                    GetRequiredString(column, "Name"),
                    GetRequiredTypeReference(column, "Type"),
                    GetRequiredInt(column, "Line"),
                    GetRequiredInt(column, "Column")))
            }

            index = index + 1
        }

        return new SoaRecordDeclarationInfo(
            GetRequiredString(declaration, "Name"),
            columns,
            GetRequiredInt(declaration, "Line"),
            GetRequiredInt(declaration, "Column"))
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

public class UnionTypeInfoFactory {
    public static func FromDeclaration(declaration: object): UnionTypeInfo {
        typeParametersValue := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "TypeParameters")
        typeParameters := CreateTypeParameterList(typeParametersValue)
        cases := CreateUnionCaseList(TypeInfoFactoryReflection.GetRequiredList(declaration, "Cases"))

        return new UnionTypeInfo(new UnionDeclarationInfo(
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            typeParameters,
            cases,
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column")))
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

public class EnumTypeInfoFactory {
    public static func FromDeclaration(declaration: object): EnumTypeInfo {
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

        return new EnumTypeInfo(new EnumDeclarationInfo(
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            members,
            GetRequiredEnumType(declaration, "Type"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(declaration, "Column")))
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

        return new EnumMemberInfo(
            TypeInfoFactoryReflection.GetRequiredString(member, "Name"),
            TypeInfoFactoryReflection.GetRequiredInt(member, "Line"),
            TypeInfoFactoryReflection.GetRequiredInt(member, "Column"),
            valueKind,
            valueText)
    }

    static func GetRequiredEnumType(owner: object, propertyName: string): EnumType {
        value := TypeInfoFactoryReflection.GetRequiredProperty(owner, propertyName)
        return (EnumType)Convert.ToInt32(value)
    }
}

class TypeInfoFactoryReflection {
    public static func GetRequiredProperty(owner: object, propertyName: string): object {
        value := GetOptionalProperty(owner, propertyName)
        if value == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be present.")
        }

        return value
    }

    public static func GetOptionalProperty(owner: object, propertyName: string): object? {
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

    public static func GetRequiredList(owner: object, propertyName: string): IList {
        value := GetRequiredProperty(owner, propertyName)
        list := value as IList
        if list == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be a list.")
        }

        return list
    }

    public static func GetRequiredString(owner: object, propertyName: string): string {
        value := GetRequiredProperty(owner, propertyName)
        text := value as string
        if text == null {
            throw new InvalidOperationException("Expected '" + owner.GetType().Name + "." + propertyName + "' to be text.")
        }

        return text
    }

    public static func GetRequiredInt(owner: object, propertyName: string): int {
        value := GetRequiredProperty(owner, propertyName)
        return Convert.ToInt32(value)
    }

    public static func GetRequiredBool(owner: object, propertyName: string): bool {
        value := GetRequiredProperty(owner, propertyName)
        return Convert.ToInt32(value) != 0
    }
}
