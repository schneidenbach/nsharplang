namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// WHAT KIND OF THING THE CARET IS ON, as far as "go to implementation" is concerned. Only two
// kinds have implementations to go to; everything else — a method, an enum, a local, a name the
// file never declared — is `None`, and `None` is an ANSWER, not a failure.
enum EditorImplementationTarget {
    None,
    Interface,
    Class
}

// ONE TYPE THAT IMPLEMENTS OR EXTENDS THE TARGET, already in the editor's 0-based numbering and
// already carrying the file it was found in, so a caller has only the protocol's Location left to
// build.
//
// The span covers the DECLARATION KEYWORD's position, not the name's: the AST records where the
// declaration begins, and the editor highlights a name's width from there. That is the shipped
// answer and the reason `EndCharacter` is a width rather than a second lookup.
class EditorImplementorRow {
    uriValue: string
    nameValue: string
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int

    Uri: string => uriValue
    Name: string => nameValue
    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue

    constructor(Uri: string, Name: string, Line: int, StartCharacter: int, EndCharacter: int) {
        uriValue = Uri
        nameValue = Name
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
    }
}

// WHO IMPLEMENTS WHAT, for the editor's go-to-implementation.
//
// THIS IS NOT `CodeIntelligenceImplementors`, AND THE DIFFERENCE IS THE POINT. That owner answers
// `query implementors`, which is always asked about an interface and answers from a project
// snapshot. This one is asked about whatever the caret happens to be on, answers from the buffers
// the editor has open, and carries TWO rules the query does not:
//
//   * THE TARGET'S OWN KIND GATES THE BASE-CLASS ARM. The parser puts the first colon-separated
//     type in `BaseClass` whether it is a base class or an interface, so `class C : IFoo` records
//     `IFoo` as the base. Asking about a CLASS reads `BaseClass`; asking about an INTERFACE does
//     not, and therefore does not find `class C : IFoo` — only `class C : Base, IFoo`, where the
//     interface reaches the `Interfaces` list. That is the shipped answer.
//   * EVERY HIT IS VERIFIED AGAINST THE FINDING DOCUMENT'S OWN SYMBOL TABLE, so a same-spelled
//     name in an unrelated file is not offered as an implementation.
class EditorImplementationFacts {

    // WHETHER THE CARET IS ON SOMETHING THAT HAS IMPLEMENTATIONS. A name the document's symbol
    // table does not know, or knows as something other than an interface or a class, is `None`.
    static func TargetKind(symbols: Dictionary<string, TypeInfo>?, word: string): EditorImplementationTarget {
        if symbols == null {
            return EditorImplementationTarget.None
        }

        declared: TypeInfo? = null
        if !symbols.TryGetValue(word, out declared) {
            return EditorImplementationTarget.None
        }

        if declared as InterfaceTypeInfo != null {
            return EditorImplementationTarget.Interface
        }

        if declared as ClassTypeInfo != null {
            return EditorImplementationTarget.Class
        }

        return EditorImplementationTarget.None
    }

    // EVERY TOP-LEVEL TYPE IN ONE FILE THAT IMPLEMENTS OR EXTENDS THE TARGET, appended in source
    // order. The walk does NOT descend into members, so a nested type is never offered — that is
    // the shipped answer.
    static func AppendImplementorRows(unit: CompilationUnit?, symbols: Dictionary<string, TypeInfo>?, uri: string, targetName: string, targetKind: EditorImplementationTarget, rows: List<EditorImplementorRow>) {
        if unit == null {
            return
        }

        for declaration in unit.Declarations {
            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                matches := false
                if targetKind == EditorImplementationTarget.Class && classDeclaration.BaseClass != null {
                    matches = CodeIntelligenceDisplayText.InterfaceNameMatches(classDeclaration.BaseClass, targetName)
                }

                if !matches {
                    matches = MatchesAnyInterface(classDeclaration.Interfaces, targetName)
                }

                if matches {
                    AppendRow(symbols, uri, classDeclaration.Name, targetName, classDeclaration.Line, classDeclaration.Column, rows)
                }

                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                if MatchesAnyInterface(structDeclaration.Interfaces, targetName) {
                    AppendRow(symbols, uri, structDeclaration.Name, targetName, structDeclaration.Line, structDeclaration.Column, rows)
                }

                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null {
                if MatchesAnyInterface(recordDeclaration.Interfaces, targetName) {
                    AppendRow(symbols, uri, recordDeclaration.Name, targetName, recordDeclaration.Line, recordDeclaration.Column, rows)
                }
            }
        }
    }

    static func MatchesAnyInterface(interfaces: List<TypeReference>, targetName: string): bool {
        for candidate in interfaces {
            if CodeIntelligenceDisplayText.InterfaceNameMatches(candidate, targetName) {
                return true
            }
        }

        return false
    }

    // THE SEMANTIC CHECK IS WHAT KEEPS A COINCIDENCE OUT. The file that spells the implementing
    // type must itself know both names: the implementor as a type that is NOT an interface — an
    // interface that extends another interface is not an implementation of it — and the target as
    // an interface or a class. A file that knows neither is not offering an implementation of
    // THIS target, whatever its text happens to say.
    static func AppendRow(symbols: Dictionary<string, TypeInfo>?, uri: string, implementorName: string, targetName: string, oneBasedLine: int, oneBasedColumn: int, rows: List<EditorImplementorRow>) {
        if symbols == null {
            return
        }

        implementor: TypeInfo? = null
        if !symbols.TryGetValue(implementorName, out implementor) {
            return
        }

        if implementor as InterfaceTypeInfo != null {
            return
        }

        target: TypeInfo? = null
        if !symbols.TryGetValue(targetName, out target) {
            return
        }

        if target as InterfaceTypeInfo == null && target as ClassTypeInfo == null {
            return
        }

        line := oneBasedLine - 1
        if line < 0 {
            line = 0
        }

        column := oneBasedColumn - 1
        if column < 0 {
            column = 0
        }

        width := implementorName.Length
        if width < 1 {
            width = 1
        }

        rows.Add(new EditorImplementorRow(uri, implementorName, line, column, column + width))
    }
}
