namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
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

    // ── WHICH MEMBERS A SOURCE-DECLARED TYPE OFFERS ─────────────────────────────────────────────
    //
    // THE RULE THE WHOLE SECTION EXISTS FOR: A TYPE THE PROJECT DECLARED ANSWERS ITS OWN MEMBERS,
    // AND NOTHING ELSE GETS TO ANSWER FOR IT. A completion for `Person.` must show the `Person` the
    // user wrote, never some unrelated `Person` that happens to be loaded from metadata — so this
    // resolution runs FIRST and, whenever it produces at least one item, the reflected read never
    // happens.
    //
    // AN EMPTY ANSWER IS NOT A WINNING ANSWER, and the distinction is deliberate. Null means "no
    // declaration explains this name" and an empty list means "one does, and it offered nothing" —
    // but the caller treats both the same and falls through to reflection, because a declared type
    // that shows nothing at all is a worse answer than a metadata type that shows something. The
    // three ways to reach empty are a declaration with no members, a declaration whose members all
    // lack a completion shape, and a name only a LATER semantic model would have explained.
    //
    // THE SEARCH WIDENS IN THREE STEPS AND STOPS AT THE FIRST THAT ANSWERS: the `TypeInfo` in hand
    // may already BE a declaration and carry its members directly; otherwise its display text is
    // looked up in each semantic model by full name and then by simple name; otherwise every type
    // name in that model is scanned for one whose tail is `.simpleName`. The scan is what lets a
    // receiver typed as `Person` reach a `Models.Person` that no import brought into scope.
    //
    // THE FIRST MODEL THAT RECOGNISES THE NAME IS THE ANSWER — including when that model's entry
    // carries no members at all. The walk does not keep looking for a better match in a later file,
    // and it must not: two files declaring the same simple name is an ambiguity the completion
    // cannot resolve, and quietly preferring whichever one had members would make the answer depend
    // on file order in a way nothing else in the engine does.

    // The declared members of the four declaration families that HAVE them; every other `TypeInfo`
    // answers null, which is the signal to fall through to reflection.
    //
    // DELIBERATELY NOT `AnalyzerStructuralAssignability.GetDeclaredMembers`, WHICH IS THE SAME NAME
    // AND A NARROWER ANSWER: that one covers class / struct / record and stops, because a duck
    // interface is compared against the three families that can satisfy one. A completion offers
    // members from an INTERFACE receiver too, so reusing it would have silently dropped every
    // interface member from every member-access completion.
    static func DeclaredMembersOfType(typeInfo: TypeInfo): DeclaredMemberInfo[]? {
        classType := typeInfo as ClassTypeInfo
        if classType != null {
            return classType.DeclaredMembers
        }

        structType := typeInfo as StructTypeInfo
        if structType != null {
            return structType.DeclaredMembers
        }

        recordType := typeInfo as RecordTypeInfo
        if recordType != null {
            return recordType.DeclaredMembers
        }

        interfaceType := typeInfo as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.DeclaredMembers
        }

        return null
    }

    // One semantic model's answer for a type name. Exact full name first, exact simple name next,
    // then the `.simpleName` tail scan — in that order, because an exact match must never lose to a
    // suffix match found earlier in the table.
    static func TryResolveSemanticType(semanticModel: SemanticModel, typeName: string, simpleName: string, out typeInfo: TypeInfo?): bool {
        types := semanticModel.Types
        if types.TryGetValue(typeName, out typeInfo) {
            return true
        }

        if types.TryGetValue(simpleName, out typeInfo) {
            return true
        }

        suffix := "." + simpleName
        for pair in types {
            candidateName := pair.Key
            if candidateName == typeName || candidateName == simpleName || candidateName.EndsWith(suffix, StringComparison.Ordinal) {
                typeInfo = pair.Value
                return true
            }
        }

        typeInfo = null
        return false
    }

    // The declared members behind a `TypeInfo`, searched across the project's semantic models.
    // `semanticModels` is the snapshot's model collection: the walk reads nothing else from a
    // snapshot, so the collection is what crosses the boundary rather than the snapshot itself.
    static func ResolveDeclaredMembers(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>): DeclaredMemberInfo[]? {
        directMembers := DeclaredMembersOfType(typeInfo)
        if directMembers != null {
            return directMembers
        }

        typeName := CompletionTypeTextFacts.FormatTypeText(typeInfo)
        simpleName := typeName
        separator := typeName.LastIndexOf(".", StringComparison.Ordinal)
        if separator >= 0 {
            simpleName = typeName.Substring(separator + 1)
        }

        for semanticModel in semanticModels {
            semanticType: TypeInfo? = null
            if TryResolveSemanticType(semanticModel, typeName, simpleName, out semanticType) {
                if semanticType == null {
                    return null
                }

                return DeclaredMembersOfType(semanticType)
            }
        }

        return null
    }

    // The completion items a source-declared type offers, in declaration order. A member with no
    // completion shape is dropped, so this list can be shorter than the member list and can be
    // empty — and an empty list still means "declared", which is the whole point of the section.
    //
    // The two-argument form asks no visibility question and offers every declared member. It is
    // the answer for a caller that cannot say which package is asking — a bare `TypeInfo` in a
    // test, an editor buffer with no project behind it — and it is deliberately kept, because a
    // filter with nothing to filter against would hide members rather than protect anyone.
    static func GetTypeMemberItems(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>): List<CompletionItem> {
        return GetTypeMemberItems(typeInfo, semanticModels, null, "")
    }

    // THE SAME LIST, MINUS WHAT THE ANALYZER WOULD REFUSE. `declaringNamespace` is where the
    // receiver's type was written and `requestingNamespace` is where the caret is; a member that
    // is not exported and does not share the caret's package is dropped, because offering it means
    // offering an NL308. `CompletionVisibilityFacts` owns the predicate and its fail-open rule.
    static func GetTypeMemberItems(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>, declaringNamespace: string?, requestingNamespace: string): List<CompletionItem> {
        items := new List<CompletionItem>()
        members := ResolveDeclaredMembers(typeInfo, semanticModels)
        if members == null {
            return items
        }

        index := 0
        while index < members.Length {
            member := members[index]
            if CompletionVisibilityFacts.IsOfferableAcrossPackages(member.IsExported, declaringNamespace, requestingNamespace) {
                item := DeclaredMemberToCompletionItem(member, true)
                if item != null {
                    items.Add(item)
                }
            }

            index = index + 1
        }

        return items
    }
}
