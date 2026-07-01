namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

public class CompletionDeclarationFacts {
    public static func ToCompletionItem(declaration: object): CompletionItem? {
        typeName := declaration.GetType().Name

        if typeName == "FunctionDeclaration" {
            returnType := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "ReturnType") as TypeReference
            return new CompletionItem(
                TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
                "function",
                TypeReferenceFacts.GetDisplayNameOrVoid(returnType),
                FormatParameters(TypeInfoFactoryReflection.GetRequiredList(declaration, "Parameters")),
                null,
                HasStaticModifier(DeclarationFacts.GetDeclarationModifiers(declaration)))
        }

        if typeName == "ClassDeclaration" { return TypeItem(declaration, "class") }
        if typeName == "StructDeclaration" { return TypeItem(declaration, "struct") }
        if typeName == "RecordDeclaration" { return TypeItem(declaration, "record") }
        if typeName == "InterfaceDeclaration" { return TypeItem(declaration, "interface") }
        if typeName == "EnumDeclaration" { return TypeItem(declaration, "enum") }
        if typeName == "UnionDeclaration" { return TypeItem(declaration, "union") }

        if typeName == "FieldDeclaration" || typeName == "PropertyDeclaration" {
            memberType := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Type") as TypeReference
            return new CompletionItem(
                TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
                "property",
                TypeReferenceFacts.GetDisplayNameOrVoid(memberType),
                null,
                null,
                false)
        }

        return null
    }

    static func TypeItem(declaration: object, kind: string): CompletionItem {
        return new CompletionItem(
            TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"),
            kind,
            null,
            null,
            null,
            false)
    }

    static func FormatParameters(parameters: IList): string {
        builder := new StringBuilder()
        builder.Append("(")

        index := 0
        while index < parameters.Count {
            if index > 0 {
                builder.Append(", ")
            }

            parameter := parameters[index]
            if parameter != null {
                builder.Append(TypeInfoFactoryReflection.GetRequiredString(parameter, "Name"))
                builder.Append(" ")
                parameterType := TypeInfoFactoryReflection.GetOptionalProperty(parameter, "Type") as TypeReference
                builder.Append(TypeReferenceFacts.GetDisplayNameOrVoid(parameterType))
                if TypeInfoFactoryReflection.GetOptionalProperty(parameter, "DefaultValue") != null {
                    builder.Append(" = ...")
                }
            }

            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    static func HasStaticModifier(modifiers: Modifiers): bool {
        value := Convert.ToInt32(modifiers)
        staticFlag := Convert.ToInt32(Modifiers.Static)
        return (value & staticFlag) == staticFlag
    }
}
