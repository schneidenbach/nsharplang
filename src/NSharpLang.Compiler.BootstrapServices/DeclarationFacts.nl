namespace NSharpLang.Compiler

import System
import System.Collections
import NSharpLang.Compiler.Ast

public class DeclarationFacts {
    public static func GetDeclarationName(declaration: object): string? {
        value := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Name")
        text := value as string
        if text != null {
            return text
        }

        typeName := declaration.GetType().Name
        if typeName == "TestDeclaration" {
            description := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Description")
            return description as string
        }
        if typeName == "SetupDeclaration" {
            return "setup"
        }

        return null
    }

    public static func GetDeclarationKind(declaration: object): string {
        typeName := declaration.GetType().Name

        if typeName == "FunctionDeclaration" { return "function" }
        if typeName == "FieldDeclaration" { return "field" }
        if typeName == "PropertyDeclaration" { return "property" }
        if typeName == "ClassDeclaration" { return "class" }
        if typeName == "StructDeclaration" { return "struct" }
        if typeName == "RecordDeclaration" { return "record" }
        if typeName == "SoaRecordDeclaration" { return "soaRecord" }
        if typeName == "InterfaceDeclaration" { return "interface" }
        if typeName == "EnumDeclaration" { return "enum" }
        if typeName == "UnionDeclaration" { return "union" }
        if typeName == "TypeAliasDeclaration" { return "typeAlias" }
        if typeName == "NewtypeDeclaration" { return "newtype" }

        return "variable"
    }

    public static func GetDeclarationModifiers(declaration: object): Modifiers {
        value := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Modifiers")
        if value == null {
            return Modifiers.None
        }

        return (Modifiers)Convert.ToInt32(value)
    }

    public static func IsExportedDeclaration(declaration: object, name: string): bool {
        return VisibilityConventions.IsExportedIdentifier(name, GetDeclarationModifiers(declaration))
    }

    public static func IsPublicSurfaceDeclaration(declaration: object): bool {
        name := GetDeclarationName(declaration)
        if name == null {
            return false
        }

        return IsExportedDeclaration(declaration, name)
    }

    public static func GetDeclarationMembers(declaration: object): IList? {
        typeName := declaration.GetType().Name
        if typeName != "ClassDeclaration"
            && typeName != "StructDeclaration"
            && typeName != "RecordDeclaration"
            && typeName != "InterfaceDeclaration" {
            return null
        }

        value := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Members")
        return value as IList
    }

    public static func EstimateDeclarationEndLine(declaration: object): int {
        members := GetDeclarationMembers(declaration)
        if members != null && members.Count > 0 {
            return MaxItemLine(members) + 1
        }

        typeName := declaration.GetType().Name
        if typeName == "FunctionDeclaration" {
            body := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Body")
            if body != null {
                statementsValue := TypeInfoFactoryReflection.GetOptionalProperty(body, "Statements")
                statements := statementsValue as IList
                if statements != null && statements.Count > 0 {
                    return MaxItemLine(statements) + 1
                }
            }
        }

        if typeName == "SoaRecordDeclaration" {
            columnsValue := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Columns")
            columns := columnsValue as IList
            if columns != null && columns.Count > 0 {
                return MaxItemLine(columns) + 1
            }
        }

        return TypeInfoFactoryReflection.GetRequiredInt(declaration, "Line")
    }

    static func MaxItemLine(items: IList): int {
        maxLine := 0
        index := 0
        while index < items.Count {
            item := items[index]
            if item != null {
                lineValue := TypeInfoFactoryReflection.GetOptionalProperty(item, "Line")
                if lineValue != null {
                    line := Convert.ToInt32(lineValue)
                    if line > maxLine {
                        maxLine = line
                    }
                }
            }

            index = index + 1
        }

        return maxLine
    }
}
