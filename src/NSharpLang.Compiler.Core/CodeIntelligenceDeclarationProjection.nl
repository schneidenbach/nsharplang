namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE DECLARATION PROJECTORS — one declaration in, one result record out.
//
// Everything `query symbols`, `query outline` and the daemon's outline method say about a file is
// decided here. Both projections are total functions of a `Declaration`: they resolve nothing, read
// no project, and touch neither the binding map nor the semantic model. The pair differs in exactly
// two ways, and both are contracts rather than accidents — the SYMBOL projection filters children by
// public surface and the OUTLINE projection does not, and the symbol arms carry parameters and
// modifier chips while the outline arms carry an end line.
class CodeIntelligenceDeclarationProjection {

    // ── The public-surface symbol list for one file ──────────────────────
    // The C# appended into a caller-supplied list; the owner returns one instead, so the order is
    // the projection's own and the caller only concatenates.
    static func Symbols(declarations: List<Declaration>, fileValue: string): List<SymbolResult> {
        results := new List<SymbolResult>()
        index := 0
        while index < declarations.Count {
            declaration := declarations[index]
            if DeclarationFacts.IsPublicSurfaceDeclaration(declaration) {
                symbol := SymbolFor(declaration, fileValue)
                if symbol != null {
                    results.Add(symbol)
                }
            }

            index = index + 1
        }

        return results
    }

    // ── The outline entries for one file ────────────────────────────────
    // Spelled once here; the two C# callers had carried identical copies of this chain.
    static func OutlineEntries(declarations: List<Declaration>): OutlineEntry[] {
        results := new List<OutlineEntry>()
        index := 0
        while index < declarations.Count {
            entry := OutlineFor(declarations[index])
            if entry != null {
                results.Add(entry)
            }

            index = index + 1
        }

        return results.ToArray()
    }

    // ── One declaration → one symbol ────────────────────────────────────
    static func SymbolFor(declaration: Declaration, fileValue: string): SymbolResult? {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            return new SymbolResult(functionDeclaration.Name, SymbolKind.Function, fileValue, functionDeclaration.Line, functionDeclaration.Column, CodeIntelligenceDisplayText.FormatTypeReference(functionDeclaration.ReturnType), CodeIntelligenceDisplayText.FormatModifiers(functionDeclaration.Modifiers), null, ParameterResults(functionDeclaration.Parameters, true))
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return new SymbolResult(classDeclaration.Name, SymbolKind.Class, fileValue, classDeclaration.Line, classDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(classDeclaration.Modifiers), MemberSymbols(classDeclaration, fileValue), null)
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return new SymbolResult(structDeclaration.Name, SymbolKind.Struct, fileValue, structDeclaration.Line, structDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(structDeclaration.Modifiers), MemberSymbols(structDeclaration, fileValue), null)
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return new SymbolResult(recordDeclaration.Name, SymbolKind.Record, fileValue, recordDeclaration.Line, recordDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(recordDeclaration.Modifiers), MemberSymbols(recordDeclaration, fileValue), null)
        }

        soaDeclaration := declaration as SoaRecordDeclaration
        if soaDeclaration != null {
            return new SymbolResult(soaDeclaration.Name, SymbolKind.Record, fileValue, soaDeclaration.Line, soaDeclaration.Column, "soa", CodeIntelligenceDisplayText.FormatModifiers(soaDeclaration.Modifiers), ColumnSymbols(soaDeclaration.Columns, fileValue), null)
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return new SymbolResult(interfaceDeclaration.Name, SymbolKind.Interface, fileValue, interfaceDeclaration.Line, interfaceDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(interfaceDeclaration.Modifiers), MemberSymbols(interfaceDeclaration, fileValue), null)
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            return new SymbolResult(enumDeclaration.Name, SymbolKind.Enum, fileValue, enumDeclaration.Line, enumDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(enumDeclaration.Modifiers), EnumMemberSymbols(enumDeclaration.Members, fileValue), null)
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            return new SymbolResult(unionDeclaration.Name, SymbolKind.Union, fileValue, unionDeclaration.Line, unionDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(unionDeclaration.Modifiers), UnionCaseSymbols(unionDeclaration.Cases, fileValue), null)
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            // A static field is a field; an instance field is reported as a property. `HasFlag` has
            // no N# spelling, so the mask slice 13 already owns answers the same question.
            fieldKind := SymbolKind.Property
            if CodeIntelligenceDisplayText.HasModifier(CodeIntelligenceDisplayText.ModifierMask(fieldDeclaration.Modifiers), 16) {
                fieldKind = SymbolKind.Field
            }

            return new SymbolResult(fieldDeclaration.Name, fieldKind, fileValue, fieldDeclaration.Line, fieldDeclaration.Column, CodeIntelligenceDisplayText.FormatTypeReference(fieldDeclaration.Type), CodeIntelligenceDisplayText.FormatModifiers(fieldDeclaration.Modifiers), null, null)
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            return new SymbolResult(propertyDeclaration.Name, SymbolKind.Property, fileValue, propertyDeclaration.Line, propertyDeclaration.Column, CodeIntelligenceDisplayText.FormatTypeReference(propertyDeclaration.Type), CodeIntelligenceDisplayText.FormatModifiers(propertyDeclaration.Modifiers), null, null)
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            // A constructor's parameters never carry their default TEXT, only the flag. That is the
            // one place the two parameter projections differ.
            return new SymbolResult("constructor", SymbolKind.Constructor, fileValue, constructorDeclaration.Line, constructorDeclaration.Column, null, CodeIntelligenceDisplayText.FormatModifiers(constructorDeclaration.Modifiers), null, ParameterResults(constructorDeclaration.Parameters, false))
        }

        aliasDeclaration := declaration as TypeAliasDeclaration
        if aliasDeclaration != null {
            return new SymbolResult(aliasDeclaration.Name, SymbolKind.TypeAlias, fileValue, aliasDeclaration.Line, aliasDeclaration.Column, CodeIntelligenceDisplayText.FormatTypeReference(aliasDeclaration.Type), null, null, null)
        }

        newtypeDeclaration := declaration as NewtypeDeclaration
        if newtypeDeclaration != null {
            return new SymbolResult(newtypeDeclaration.Name, SymbolKind.Struct, fileValue, newtypeDeclaration.Line, newtypeDeclaration.Column, CodeIntelligenceDisplayText.FormatTypeReference(newtypeDeclaration.UnderlyingType), null, null, null)
        }

        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            // A test is named by its DESCRIPTION, which is the only arm whose name is not `Name`.
            return new SymbolResult(testDeclaration.Description, SymbolKind.Test, fileValue, testDeclaration.Line, testDeclaration.Column, null, null, null, null)
        }

        return null
    }

    // ── One declaration → one outline entry ─────────────────────────────
    static func OutlineFor(declaration: Declaration): OutlineEntry? {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            return new OutlineEntry(functionDeclaration.Name, SymbolKind.Function, functionDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(functionDeclaration), CodeIntelligenceDisplayText.FormatTypeReference(functionDeclaration.ReturnType), null, null)
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            return new OutlineEntry(classDeclaration.Name, SymbolKind.Class, classDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(classDeclaration), null, null, MemberOutlineEntries(classDeclaration))
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            return new OutlineEntry(structDeclaration.Name, SymbolKind.Struct, structDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(structDeclaration), null, null, MemberOutlineEntries(structDeclaration))
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            return new OutlineEntry(recordDeclaration.Name, SymbolKind.Record, recordDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(recordDeclaration), null, null, MemberOutlineEntries(recordDeclaration))
        }

        soaDeclaration := declaration as SoaRecordDeclaration
        if soaDeclaration != null {
            return new OutlineEntry(soaDeclaration.Name, SymbolKind.Record, soaDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(soaDeclaration), null, "soa", ColumnOutlineEntries(soaDeclaration.Columns))
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            return new OutlineEntry(interfaceDeclaration.Name, SymbolKind.Interface, interfaceDeclaration.Line, DeclarationFacts.EstimateDeclarationEndLine(interfaceDeclaration), null, null, MemberOutlineEntries(interfaceDeclaration))
        }

        // An enum, a union, a field, a property and a test all end on the line they start on. The
        // symbol projection lists an enum's members and a union's exported cases; the outline does
        // NOT, and that difference is the contract.
        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            return new OutlineEntry(enumDeclaration.Name, SymbolKind.Enum, enumDeclaration.Line, enumDeclaration.Line, null, null, null)
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            return new OutlineEntry(unionDeclaration.Name, SymbolKind.Union, unionDeclaration.Line, unionDeclaration.Line, null, null, null)
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            // The outline calls every field a property, static or not — the symbol projection is the
            // one that splits them.
            return new OutlineEntry(fieldDeclaration.Name, SymbolKind.Property, fieldDeclaration.Line, fieldDeclaration.Line, null, CodeIntelligenceDisplayText.FormatTypeReference(fieldDeclaration.Type), null)
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            return new OutlineEntry(propertyDeclaration.Name, SymbolKind.Property, propertyDeclaration.Line, propertyDeclaration.Line, null, CodeIntelligenceDisplayText.FormatTypeReference(propertyDeclaration.Type), null)
        }

        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            return new OutlineEntry(testDeclaration.Description, SymbolKind.Test, testDeclaration.Line, testDeclaration.Line, null, null, null)
        }

        return null
    }

    // ── The child projections ───────────────────────────────────────────
    // `DeclarationFacts.GetDeclarationMembers` answers only for the four member-bearing arms and
    // hands back a non-generic `IList`, so both walks index it and cast.
    static func MemberSymbols(declaration: Declaration, fileValue: string): SymbolResult[] {
        results := new List<SymbolResult>()
        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members == null {
            return results.ToArray()
        }

        index := 0
        while index < members.Count {
            member := members[index] as Declaration
            if member != null && DeclarationFacts.IsPublicSurfaceDeclaration(member) {
                symbol := SymbolFor(member, fileValue)
                if symbol != null {
                    results.Add(symbol)
                }
            }

            index = index + 1
        }

        return results.ToArray()
    }

    static func MemberOutlineEntries(declaration: Declaration): OutlineEntry[] {
        results := new List<OutlineEntry>()
        members := DeclarationFacts.GetDeclarationMembers(declaration)
        if members == null {
            return results.ToArray()
        }

        index := 0
        while index < members.Count {
            member := members[index] as Declaration
            if member != null {
                entry := OutlineFor(member)
                if entry != null {
                    results.Add(entry)
                }
            }

            index = index + 1
        }

        return results.ToArray()
    }

    static func ColumnSymbols(columns: List<SoaColumnDeclaration>, fileValue: string): SymbolResult[] {
        results := new List<SymbolResult>()
        index := 0
        while index < columns.Count {
            column := columns[index]
            results.Add(new SymbolResult(column.Name, SymbolKind.Field, fileValue, column.Line, column.Column, CodeIntelligenceDisplayText.FormatTypeReference(column.Type), null, null, null))
            index = index + 1
        }

        return results.ToArray()
    }

    static func ColumnOutlineEntries(columns: List<SoaColumnDeclaration>): OutlineEntry[] {
        results := new List<OutlineEntry>()
        index := 0
        while index < columns.Count {
            column := columns[index]
            results.Add(new OutlineEntry(column.Name, SymbolKind.Field, column.Line, column.Line, null, CodeIntelligenceDisplayText.FormatTypeReference(column.Type), null))
            index = index + 1
        }

        return results.ToArray()
    }

    // An enum member is reported at line 0, column 0 — it carries no position of its own in the
    // answer even though the AST node has one.
    static func EnumMemberSymbols(members: List<EnumMember>, fileValue: string): SymbolResult[] {
        results := new List<SymbolResult>()
        index := 0
        while index < members.Count {
            results.Add(new SymbolResult(members[index].Name, SymbolKind.EnumMember, fileValue, 0, 0, null, null, null, null))
            index = index + 1
        }

        return results.ToArray()
    }

    // A union's cases are filtered by the EXPORTED-identifier convention with no modifiers of their
    // own, so a lowercase case is private to the file and never appears in `query symbols`.
    static func UnionCaseSymbols(cases: List<UnionCase>, fileValue: string): SymbolResult[] {
        results := new List<SymbolResult>()
        index := 0
        while index < cases.Count {
            unionCase := cases[index]
            if VisibilityConventions.IsExportedIdentifier(unionCase.Name, Modifiers.None) {
                results.Add(new SymbolResult(unionCase.Name, SymbolKind.EnumMember, fileValue, 0, 0, null, null, null, null))
            }

            index = index + 1
        }

        return results.ToArray()
    }

    // `withDefaultText` is the whole difference between a function's parameters and a constructor's.
    static func ParameterResults(parameters: List<Parameter>, withDefaultText: bool): ParameterResult[] {
        results := new List<ParameterResult>()
        index := 0
        while index < parameters.Count {
            parameter := parameters[index]
            defaultText: string? = null
            if withDefaultText && parameter.DefaultValue != null {
                defaultText = DefaultValueText(parameter.DefaultValue)
            }

            results.Add(new ParameterResult(parameter.Name, CodeIntelligenceDisplayText.FormatTypeReference(parameter.Type), parameter.DefaultValue != null, defaultText))
            index = index + 1
        }

        return results.ToArray()
    }

    // A default value is printed by its EXPRESSION NODE's `ToString()`, which no AST arm overrides,
    // so what a consumer actually reads is the node's runtime type name. That is the shipped
    // contract and it is preserved rather than improved.
    //
    // `ToString()` on a user-declared N# class does not emit — the columnar backend declines the
    // whole statement. Boxing to `object` first is the same virtual call and it does emit.
    static func DefaultValueText(defaultValue: Expression): string? {
        boxed := defaultValue as object
        if boxed == null {
            return null
        }

        return boxed.ToString()
    }
}
