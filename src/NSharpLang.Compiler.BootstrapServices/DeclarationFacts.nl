namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast

public class DeclarationFacts {
    public static func GetDeclarationName(declaration: object): string? {
        value := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Name")
        text := value as string
        return text
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
}
