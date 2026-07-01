namespace NSharpLang.Compiler

import System
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
}
