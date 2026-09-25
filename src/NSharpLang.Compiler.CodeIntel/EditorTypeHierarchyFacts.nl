namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE NODE OF THE TYPE HIERARCHY, in the editor's own 0-based numbering, carrying the file it was
// found in. The one span serves as both the node's range and its selection range — the editor
// highlights the name and nothing wider, because a type's whole body is not what a hierarchy view
// is pointing at.
class EditorTypeHierarchyRow {
    nameValue: string
    kindValue: EditorSymbolKind
    uriValue: string
    lineValue: int
    startCharacterValue: int
    endCharacterValue: int

    Name: string => nameValue
    Kind: EditorSymbolKind => kindValue
    Uri: string => uriValue
    Line: int => lineValue
    StartCharacter: int => startCharacterValue
    EndCharacter: int => endCharacterValue

    constructor(Name: string, Kind: EditorSymbolKind, Uri: string, Line: int, StartCharacter: int, EndCharacter: int) {
        nameValue = Name
        kindValue = Kind
        uriValue = Uri
        lineValue = Line
        startCharacterValue = StartCharacter
        endCharacterValue = EndCharacter
    }
}

// WHAT SITS ABOVE AND BELOW A TYPE, for the editor's type-hierarchy view.
//
// THREE QUESTIONS, ONE VOCABULARY. Preparing a node, walking up to the supertypes and walking down
// to the subtypes are asked by three different protocol requests and answered here by three
// members that agree about what a node IS — the alternative, which this replaced, was three C#
// switch statements over `TypeInfo` that had to be kept in step by hand.
//
// THE UPWARD AND DOWNWARD WALKS ARE NOT MIRRORS, and the asymmetry is deliberate:
//
//   * UPWARD reads the DECLARATION's own base and interface lists, so it says what the source
//     wrote, and then resolves each name against the open buffers. A name nothing declares is
//     dropped rather than shown as an unresolvable node.
//   * DOWNWARD tests every top-level declaration in every buffer, and reads a class's `BaseClass`
//     WHATEVER the target's kind is — unlike `EditorImplementationFacts`, which gates that arm.
//     A hierarchy view wants `class C : IFoo` under `IFoo`; go-to-implementation, asked about an
//     interface, does not read the base slot at all. Both are the shipped answers.
//   * DOWNWARD additionally counts an INTERFACE THAT EXTENDS the target, but only when the target
//     is itself an interface. Extending is not implementing, which is why go-to-implementation
//     refuses the same declaration.
class EditorTypeHierarchyFacts {

    // THE NODE FOR THE NAME UNDER THE CARET, or nothing when the document's symbol table does not
    // know that name as a type at all.
    static func PrepareRow(symbols: Dictionary<string, TypeInfo>?, word: string, uri: string): EditorTypeHierarchyRow? {
        if symbols == null {
            return null
        }

        declared: TypeInfo? = null
        if !symbols.TryGetValue(word, out declared) {
            return null
        }

        classType := declared as ClassTypeInfo
        if classType != null {
            return MakeRow(classType.Name, EditorSymbolKind.Class, uri, classType.Line, classType.Column)
        }

        interfaceType := declared as InterfaceTypeInfo
        if interfaceType != null {
            return MakeRow(interfaceType.Name, EditorSymbolKind.Interface, uri, interfaceType.Line, interfaceType.Column)
        }

        structType := declared as StructTypeInfo
        if structType != null {
            return MakeRow(structType.Name, EditorSymbolKind.Struct, uri, structType.Line, structType.Column)
        }

        recordType := declared as RecordTypeInfo
        if recordType != null {
            return MakeRow(recordType.Name, EditorSymbolKind.Class, uri, recordType.Line, recordType.Column)
        }

        enumType := declared as EnumTypeInfo
        if enumType != null {
            return MakeRow(enumType.Declaration.Name, EditorSymbolKind.Enum, uri, enumType.Declaration.Line, enumType.Declaration.Column)
        }

        return null
    }

    // A NODE FOR A NAME A SUPERTYPE LIST MENTIONED, resolved against ONE document's symbol table.
    // A type the table knows but cannot place in the file — line zero — is not a node: the editor
    // would have nowhere to take the reader.
    static func ResolveRow(symbols: Dictionary<string, TypeInfo>?, typeName: string, uri: string): EditorTypeHierarchyRow? {
        if symbols == null {
            return null
        }

        declared: TypeInfo? = null
        if !symbols.TryGetValue(typeName, out declared) {
            return null
        }

        if DeclarationLine(declared) <= 0 {
            return null
        }

        return PrepareRow(symbols, typeName, uri)
    }

    // The 1-based line a bound type says it was declared on, or 0 when it does not say.
    static func DeclarationLine(declared: TypeInfo?): int {
        if declared == null {
            return 0
        }

        classType := declared as ClassTypeInfo
        if classType != null {
            return classType.Line
        }

        interfaceType := declared as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Line
        }

        structType := declared as StructTypeInfo
        if structType != null {
            return structType.Line
        }

        recordType := declared as RecordTypeInfo
        if recordType != null {
            return recordType.Line
        }

        enumType := declared as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Line
        }

        return 0
    }

    // WHAT THE SOURCE SAID THE TARGET SITS UNDER, in the order it wrote it: a class's base type
    // first and then its interfaces, a struct's and a record's interfaces, an interface's base
    // interfaces. A reference that names nothing simple — a nullable, an array, a union — is not a
    // supertype and contributes no name.
    static func SupertypeNames(unit: CompilationUnit?, targetName: string): List<string> {
        names := new List<string>()
        if unit == null {
            return names
        }

        for declaration in unit.Declarations {
            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null && classDeclaration.Name == targetName {
                if classDeclaration.BaseClass != null {
                    AppendName(classDeclaration.BaseClass, names)
                }

                AppendNames(classDeclaration.Interfaces, names)
                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null && structDeclaration.Name == targetName {
                AppendNames(structDeclaration.Interfaces, names)
                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null && recordDeclaration.Name == targetName {
                AppendNames(recordDeclaration.Interfaces, names)
                continue
            }

            interfaceDeclaration := declaration as InterfaceDeclaration
            if interfaceDeclaration != null && interfaceDeclaration.Name == targetName {
                AppendNames(interfaceDeclaration.BaseInterfaces, names)
            }
        }

        return names
    }

    static func AppendNames(references: List<TypeReference>, names: List<string>) {
        for reference in references {
            AppendName(reference, names)
        }
    }

    // ONLY A PLAIN NAME OR A GENERIC'S NAME IS A SUPERTYPE NAME. This is deliberately narrower than
    // `CodeIntelligenceDisplayText.GetTypeReferenceName`, which reaches through a nullable and an
    // array to the type inside: `Foo?` is not something a type can inherit from, and reaching
    // through it would put a node in the hierarchy that the source never wrote.
    static func AppendName(reference: TypeReference, names: List<string>) {
        simple := reference as SimpleTypeReference
        if simple != null {
            names.Add(simple.Name)
            return
        }

        generic := reference as GenericTypeReference
        if generic != null {
            names.Add(generic.Name)
        }
    }

    // EVERY TOP-LEVEL TYPE IN ONE FILE THAT SITS UNDER THE TARGET, appended in source order.
    static func AppendSubtypeRows(unit: CompilationUnit?, uri: string, targetName: string, targetIsInterface: bool, rows: List<EditorTypeHierarchyRow>) {
        if unit == null {
            return
        }

        for declaration in unit.Declarations {
            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                matches := false
                if classDeclaration.BaseClass != null {
                    matches = CodeIntelligenceDisplayText.InterfaceNameMatches(classDeclaration.BaseClass, targetName)
                }

                if !matches {
                    matches = MatchesAny(classDeclaration.Interfaces, targetName)
                }

                if matches {
                    rows.Add(MakeRow(classDeclaration.Name, EditorSymbolKind.Class, uri, classDeclaration.Line, classDeclaration.Column))
                }

                continue
            }

            structDeclaration := declaration as StructDeclaration
            if structDeclaration != null {
                if MatchesAny(structDeclaration.Interfaces, targetName) {
                    rows.Add(MakeRow(structDeclaration.Name, EditorSymbolKind.Struct, uri, structDeclaration.Line, structDeclaration.Column))
                }

                continue
            }

            recordDeclaration := declaration as RecordDeclaration
            if recordDeclaration != null {
                if MatchesAny(recordDeclaration.Interfaces, targetName) {
                    rows.Add(MakeRow(recordDeclaration.Name, EditorSymbolKind.Class, uri, recordDeclaration.Line, recordDeclaration.Column))
                }

                continue
            }

            interfaceDeclaration := declaration as InterfaceDeclaration
            if interfaceDeclaration != null && targetIsInterface {
                if MatchesAny(interfaceDeclaration.BaseInterfaces, targetName) {
                    rows.Add(MakeRow(interfaceDeclaration.Name, EditorSymbolKind.Interface, uri, interfaceDeclaration.Line, interfaceDeclaration.Column))
                }
            }
        }
    }

    static func MatchesAny(references: List<TypeReference>, targetName: string): bool {
        for reference in references {
            if CodeIntelligenceDisplayText.InterfaceNameMatches(reference, targetName) {
                return true
            }
        }

        return false
    }

    // The node's span: the declaration's own position, 0-based, as wide as the name — and at least
    // one column wide, so a nameless node is still selectable.
    static func MakeRow(name: string, kind: EditorSymbolKind, uri: string, oneBasedLine: int, oneBasedColumn: int): EditorTypeHierarchyRow {
        line := oneBasedLine - 1
        if line < 0 {
            line = 0
        }

        column := oneBasedColumn - 1
        if column < 0 {
            column = 0
        }

        width := name.Length
        if width < 1 {
            width = 1
        }

        return new EditorTypeHierarchyRow(name, kind, uri, line, column, column + width)
    }
}
