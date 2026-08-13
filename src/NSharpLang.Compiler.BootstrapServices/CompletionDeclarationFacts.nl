namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

class CompletionDeclarationFacts {
    static func ToCompletionItem(declaration: object): CompletionItem? {
        typeName := declaration.GetType().Name

        if typeName == "FunctionDeclaration" {
            returnType := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "ReturnType") as TypeReference
            return new CompletionItem(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), "function", TypeReferenceFacts.GetDisplayNameOrVoid(returnType), FormatParameters(TypeInfoFactoryReflection.GetRequiredList(declaration, "Parameters")), null, HasStaticModifier(DeclarationFacts.GetDeclarationModifiers(declaration)))
        }

        if typeName == "ClassDeclaration" {
            return TypeItem(declaration, "class")
        }
        if typeName == "StructDeclaration" {
            return TypeItem(declaration, "struct")
        }
        if typeName == "RecordDeclaration" {
            return TypeItem(declaration, "record")
        }
        if typeName == "InterfaceDeclaration" {
            return TypeItem(declaration, "interface")
        }
        if typeName == "EnumDeclaration" {
            return TypeItem(declaration, "enum")
        }
        if typeName == "UnionDeclaration" {
            return TypeItem(declaration, "union")
        }

        if typeName == "FieldDeclaration" || typeName == "PropertyDeclaration" {
            memberType := TypeInfoFactoryReflection.GetOptionalProperty(declaration, "Type") as TypeReference
            return new CompletionItem(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), "property", TypeReferenceFacts.GetDisplayNameOrVoid(memberType), null, null, false)
        }

        return null
    }

    static func TypeItem(declaration: object, kind: string): CompletionItem {
        return new CompletionItem(TypeInfoFactoryReflection.GetRequiredString(declaration, "Name"), kind, null, null, null, false)
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

    // THE SAME SENTENCE AS `ToCompletionItem`, SAID ABOUT A SEMANTIC MEMBER INSTEAD OF AN AST
    // DECLARATION. `ToCompletionItem` reads a parsed declaration; this reads a `DeclaredMemberInfo`
    // resolved out of a `TypeInfo` — the shape a MEMBER-ACCESS completion has to offer. The one
    // thing the two do not share is the word: the same function is a `"function"` at file scope and
    // a `"method"` after a dot, which is what `memberContext` decides.
    //
    // A kind with no completion shape at all — `Unknown`, `SoaRecord`, `TypeAlias`, `Newtype`,
    // `Constructor` — is `null`, and the caller drops it.
    static func DeclaredMemberToCompletionItem(member: DeclaredMemberInfo, memberContext: bool): CompletionItem? {
        kind := member.Kind

        if kind == DeclaredMemberKind.Function {
            kindName := "function"
            if memberContext {
                kindName = "method"
            }

            return new CompletionItem(member.Name, kindName, TypeReferenceFacts.GetDisplayNameOrVoid(member.ReturnType), FormatDeclaredMemberParameters(member), null, member.IsStatic)
        }

        if kind == DeclaredMemberKind.Class {
            return DeclaredMemberTypeItem(member, "class")
        }
        if kind == DeclaredMemberKind.Struct {
            return DeclaredMemberTypeItem(member, "struct")
        }
        if kind == DeclaredMemberKind.Record {
            return DeclaredMemberTypeItem(member, "record")
        }
        if kind == DeclaredMemberKind.Interface {
            return DeclaredMemberTypeItem(member, "interface")
        }
        if kind == DeclaredMemberKind.Enum {
            return DeclaredMemberTypeItem(member, "enum")
        }
        if kind == DeclaredMemberKind.Union {
            return DeclaredMemberTypeItem(member, "union")
        }

        // A field and a property are the same offer to whoever is typing: a named value with a
        // type. The completion says `"property"` for both.
        if kind == DeclaredMemberKind.Field || kind == DeclaredMemberKind.Property {
            return new CompletionItem(member.Name, "property", TypeReferenceFacts.GetDisplayNameOrVoid(member.Type), null, null, member.IsStatic)
        }

        return null
    }

    // A nested TYPE offered as a member carries no type text and is never static: it is a name to
    // reach through, not a value to read.
    static func DeclaredMemberTypeItem(member: DeclaredMemberInfo, kind: string): CompletionItem {
        return new CompletionItem(member.Name, kind, null, null, null, false)
    }

    // The parameter list a declared member shows. A parameter past the required count carries
    // ` = ...` unless it is `params`, and a parameter whose type list is short reads `"unknown"` —
    // the completion still names it.
    static func FormatDeclaredMemberParameters(member: DeclaredMemberInfo): string {
        parameterNames := member.ParameterNames
        parameterTypes := member.ParameterTypes
        requiredCount := member.RequiredParameterCount
        builder := new StringBuilder()
        builder.Append("(")

        index := 0
        while index < parameterNames.Length {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(parameterNames[index])
            builder.Append(" ")
            if index < parameterTypes.Length {
                builder.Append(TypeReferenceFacts.GetDisplayNameOrVoid(parameterTypes[index]))
            } else {
                builder.Append("unknown")
            }

            if index >= requiredCount && GetDeclaredMemberParameterModifier(member, index) != ParameterModifier.Params {
                builder.Append(" = ...")
            }

            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    // The declared modifier of parameter `index`, or `None` when the index falls outside the list.
    // The twin of `AnalyzerCallableReferenceFacts.GetFunctionParameterModifier`, which answers the
    // same question about a FUNCTION TYPE; both are total, and neither faults on an index a caller
    // never should have asked for.
    static func GetDeclaredMemberParameterModifier(member: DeclaredMemberInfo, index: int): ParameterModifier {
        modifiers := member.ParameterModifiers
        if index < 0 || index >= modifiers.Length {
            return ParameterModifier.None
        }

        return modifiers[index]
    }
}
