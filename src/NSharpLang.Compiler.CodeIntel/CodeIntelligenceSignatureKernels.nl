namespace NSharpLang.Compiler.CodeIntelligence

import System.Reflection
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE ONE LINE A HOVER PRINTS, AND THE TWO WAYS IT IS BUILT.
//
// A symbol the PROJECT declares is named by its kind and its type and nothing else — `field Count:
// int` — because the declaration itself is one click away and the hover's job is to save that click,
// not to restate the file. A symbol METADATA declares has no file to jump to, so the hover is the
// only place its shape is ever shown, and it carries the whole signature: the return type, the
// parameters with their names and their nullability, and the type that declares it.
//
// THAT SECOND HALF IS WHAT IDE DEFECT D2 WAS. It was deleted from the language server on 2026-06-24
// ("Delete hover reflection member fallback") together with its tests, and the CLI never had it at
// all, so both surfaces had been rendering the ANALYZER'S INTERNAL PLACEHOLDER — `ToUpper(...)`, the
// text a method group carries so a diagnostic can name it — as though it were a signature. The
// rendering below is the deleted one, restored in the owner both surfaces share.
//
// EVERY REFLECTED READ IS INSIDE A `try`, AND THE DECLINE IS THE POINT. These members arrive from
// two different type universes — a `MetadataLoadContext` on the CLI, the live runtime in the
// language server — and they do not fail the same way. A hover that throws is a broken editor, so a
// member this file cannot read answers null and the caller falls back to the bare rendering, which
// is always available because it is a function of text alone.
class CodeIntelligenceSignatureKernels {
    static func GetFallbackSignatureText(kind: string, name: string, typeName: string?): string {
        if typeName != null {
            return kind + " " + name + ": " + typeName
        }

        return kind + " " + name
    }

    // A source member's binding says WHICH declaration the caret denotes. The parsed declaration then
    // supplies the words the generic type result cannot carry — `required`, `init`, accessibility and
    // the other member modifiers. This is not a name search: the binding's owning file, line and exact
    // identifier span must all agree before a signature is projected, so a same-spelled member in another
    // type — even on the same line — cannot donate its modifiers to this hover.
    static func GetSourceMemberSignature(snapshot: ProjectSnapshot, declaration: SymbolDeclaration?, resolvedType: string?): SourceMemberSignature? {
        if declaration == null {
            return null
        }

        declarationFile := declaration.File
        if declarationFile == null {
            return null
        }

        unitMatch := CodeIntelligenceNavigation.FindCompilationUnit(snapshot, declarationFile ?? "")
        unit := unitMatch.Unit
        if unit == null {
            return null
        }

        sourceText := CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, unitMatch.FilePath)
        declarations := unit.Declarations
        for declarationItem in declarations {
            signature := SourceMemberSignatureInDeclaration(declarationItem, declaration, resolvedType, false, sourceText)
            if signature != null {
                return signature
            }
        }

        return null
    }

    static func SourceMemberSignatureInDeclaration(candidate: Declaration, declaration: SymbolDeclaration, resolvedType: string?, ownerIsInterface: bool, sourceText: string?): SourceMemberSignature? {
        field := candidate as FieldDeclaration
        if field != null && SourceMemberMatches(field.Name, field.Line, field.Column, declaration, sourceText) {
            kind := "field"
            if ownerIsInterface && !CodeIntelligenceDisplayText.HasModifier(CodeIntelligenceDisplayText.ModifierMask(field.Modifiers), 16) {
                kind = "property"
            }

            return new SourceMemberSignature(kind, FormatSourceMemberLine(kind, field.Name, field.Modifiers, resolvedType ?? TypeReferenceFacts.GetDisplayNameOrVoid(field.Type)))
        }

        property := candidate as PropertyDeclaration
        if property != null && SourceMemberMatches(property.Name, property.Line, property.Column, declaration, sourceText) {
            return new SourceMemberSignature("property", FormatSourceMemberLine("property", property.Name, property.Modifiers, resolvedType ?? TypeReferenceFacts.GetDisplayNameOrVoid(property.Type)))
        }

        members := DeclarationFacts.GetDeclarationMembers(candidate)
        if members == null {
            return null
        }

        candidateIsInterface := candidate as InterfaceDeclaration
        childOwnerIsInterface := candidateIsInterface != null
        for memberItem in members {
            member := memberItem as Declaration
            if member != null {
                signature := SourceMemberSignatureInDeclaration(member, declaration, resolvedType, childOwnerIsInterface, sourceText)
                if signature != null {
                    return signature
                }
            }
        }

        return null
    }

    static func SourceMemberMatches(name: string, line: int, candidateColumn: int, declaration: SymbolDeclaration, sourceText: string?): bool {
        if name != declaration.Name || line != declaration.Line {
            return false
        }

        // The AST's member column is the declaration start, which may be the `required` word rather
        // than the name. The binding instead records the canonical name span. Deriving that same span
        // from this AST candidate's start is what separates `class A { required init Name: string }
        // class B { Name: string }` on one line, including the same shape under nested owners.
        nameColumn := AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, name, line, candidateColumn)
        return nameColumn == declaration.Column
    }

    static func FormatSourceMemberLine(kind: string, name: string, modifiers: Modifiers, typeName: string): string {
        builder := new StringBuilder()
        builder.Append(kind)
        builder.Append(" ")

        modifierWords := CodeIntelligenceDisplayText.FormatModifiers(modifiers)
        if modifierWords != null {
            for modifierWord in modifierWords {
                builder.Append(modifierWord)
                builder.Append(" ")
            }
        }

        builder.Append(name)
        builder.Append(": ")
        builder.Append(typeName)
        return builder.ToString()
    }

    // The whole line for a reflected member, or null to decline to the fallback above.
    static func GetReflectedMemberLineText(handle: ReflectedMemberHandle): string? {
        signature := GetReflectedMemberSignatureText(handle)
        if signature == null {
            return null
        }

        return GetReflectedMemberKind(handle) + " " + handle.Name + ": " + (signature ?? "")
    }

    // WHICH WORD THE HOVER LEADS WITH. The reflected sorts are three, and `member` is the honest
    // answer for a handle carrying none rather than a guess that reads like a fact.
    static func GetReflectedMemberKind(handle: ReflectedMemberHandle): string {
        if handle.Property != null {
            return "property"
        }

        if handle.Field != null {
            return "field"
        }

        if handle.Method != null {
            return "method"
        }

        return "member"
    }

    // THE DECLARED LEVEL OF A REFLECTED MEMBER, IN THE WORD THE LANGUAGE USES FOR IT — and nothing
    // at all for the ordinary public case, so the editor decorates only the members whose presence
    // needs explaining. `MemberAccessibility` owns both the level and the word, which is why a
    // granted `internal` member is labelled with the same term the refusal for a non-friend quotes.
    //
    // A PROPERTY HAS NO LEVEL OF ITS OWN in CLR metadata; its accessors carry it, and the widest of
    // the two is the property's effective level — the same reading `MemberAccessibility` applies
    // everywhere else a property is asked about.
    static func GetReflectedMemberAccessibility(handle: ReflectedMemberHandle): string? {
        level := MemberAccessibility.Public

        field := handle.Field
        property := handle.Property
        method := handle.Method
        if field != null {
            level = MemberAccessibility.LevelOfField(field)
        } else if property != null {
            level = ReflectedPropertyAccessibilityLevel(property)
        } else if method != null {
            level = MemberAccessibility.LevelOfMethod(method)
        } else {
            return null
        }

        if level == MemberAccessibility.Public {
            return null
        }

        return MemberAccessibility.LevelWord(level)
    }

    static func ReflectedPropertyAccessibilityLevel(property: PropertyInfo): int {
        level := MemberAccessibility.Private
        getter := property.GetGetMethod(true)
        if getter != null {
            level = MemberAccessibility.LevelOfMethod(getter)
        }

        setter := property.GetSetMethod(true)
        if setter != null {
            setterLevel := MemberAccessibility.LevelOfMethod(setter)
            if getter == null || setterLevel > level {
                level = setterLevel
            }
        }

        return level
    }

    static func GetReflectedMemberSignatureText(handle: ReflectedMemberHandle): string? {
        typeOverride := handle.TypeOverride
        try {
            method := handle.Method
            if method != null {
                return GetReflectedMethodText(method, typeOverride) + GetOverloadSuffixText(handle.OverloadCount)
            }

            property := handle.Property
            if property != null {
                return GetReflectedPropertyText(property, typeOverride)
            }

            field := handle.Field
            if field != null {
                return GetReflectedFieldText(field, typeOverride)
            }
        } catch {
            return null
        }

        return null
    }

    // ONE SIGNATURE IS SHOWN AND THE REST ARE COUNTED. Printing five signatures makes the hover a
    // wall the reader has to parse; printing one without saying there are others makes it a claim
    // that is false. The count is free — the resolver already had the list in its hand.
    static func GetOverloadSuffixText(overloadCount: int): string {
        if overloadCount < 2 {
            return ""
        }

        others := overloadCount - 1
        if others == 1 {
            return " (+1 overload)"
        }

        return " (+" + others.ToString() + " overloads)"
    }

    // `string ToUpper()`, `DateTime AddDays(double value)` — the C# spelling, because that is what
    // the metadata says and inventing an N# transliteration would be inventing a fact. The return
    // type and each parameter go through `NullabilityMetadataReflection`, which is the same owner
    // the analyzer's own diagnostics use, so the nullability annotations agree with the errors.
    static func GetReflectedMethodText(method: MethodInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        builder := new StringBuilder()
        builder.Append(NullabilityMetadataReflection.FormatReturnTypeWithOverride(method, typeOverride))
        builder.Append(" ")
        builder.Append(method.Name)
        builder.Append("(")

        parameters := method.GetParameters()
        index := 0
        while index < parameters.Length {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(NullabilityMetadataReflection.FormatParameterWithOverride(parameters[index], typeOverride))
            index = index + 1
        }

        builder.Append(")")
        return builder.ToString()
    }

    // The accessors are the property's whole remaining shape, and a write-only property is a real
    // thing, so all three combinations are spelled rather than assuming `get`.
    static func GetReflectedPropertyText(property: PropertyInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        accessors := ""
        if property.CanRead && property.CanWrite {
            accessors = " { get; set; }"
        } else if property.CanRead {
            accessors = " { get; }"
        } else if property.CanWrite {
            accessors = " { set; }"
        }

        return NullabilityMetadataReflection.FormatTypeInfo(NullabilityMetadataReflection.ConvertPropertyWithOverride(property, typeOverride)) + accessors
    }

    static func GetReflectedFieldText(field: FieldInfo, typeOverride: AnalyzerReflectionTypeOverride?): string {
        modifiers := ""
        if field.IsStatic {
            modifiers = "static "
        }

        if field.IsInitOnly {
            modifiers = modifiers + "readonly "
        }

        return modifiers + NullabilityMetadataReflection.FormatTypeInfo(NullabilityMetadataReflection.ConvertFieldWithOverride(field, typeOverride))
    }
}

// The source hover needs to replace both the fallback line and its kind: a field declaration is
// recorded as a lexical `variable` at its own name, while its reader-facing member surface is a
// field (or an interface property). Keeping the two values together prevents a corrected line from
// being paired with the old variable kind in the JSON and LSP projections.
class SourceMemberSignature {
    kindValue: string
    lineTextValue: string

    Kind: string => kindValue
    LineText: string => lineTextValue

    constructor(kind: string, lineText: string) {
        kindValue = kind
        lineTextValue = lineText
    }
}
