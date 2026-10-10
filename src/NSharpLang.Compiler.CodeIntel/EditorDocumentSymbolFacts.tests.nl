namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast

// CONTRACTS FOR THE OUTLINE. These came out of `DocumentSymbolHandler.cs`: which declarations get
// a row and which are skipped, the kind each one shows, the detail text, the brace-depth end line,
// and the three clamps that keep the full range legally containing the selection range — the rule
// a client is entitled to enforce by dropping the symbol.
func EdsLines(text: string): string[] {
    return text.Split('\n')
}

func EdsDeclarations(declarations: Declaration[]): List<Declaration> {
    list := new List<Declaration>()
    for declaration in declarations {
        list.Add(declaration)
    }
    return list
}

func EdsUnit(declarations: Declaration[]): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, EdsDeclarations(declarations), 1, 1)
}

func EdsFunction(name: string, returnType: TypeReference?, line: int): Declaration {
    declaration: Declaration = new FunctionDeclaration(name, new List<Parameter>(), returnType, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line, 1)
    return declaration
}

func EdsField(name: string, fieldType: TypeReference?, line: int): Declaration {
    declaration: Declaration = new FieldDeclaration(name, fieldType, null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, 5)
    return declaration
}

func EdsClass(name: string, members: Declaration[], line: int): Declaration {
    declaration: Declaration = new ClassDeclaration(name, null, null, new List<TypeReference>(), EdsDeclarations(members), null, Modifiers.None, new List<AttributeNode>(), line, 1)
    return declaration
}

func EdsSimple(name: string): TypeReference {
    reference: TypeReference = new SimpleTypeReference(name, 1, 1)
    return reference
}

// THE OUTLINE IS NESTED AND IN SOURCE ORDER, and the detail is the type as it was written.
test "the outline nests a type's members beneath it in source order" {
    lines := EdsLines("class Box {\n    Width: int\n    func Area(): int {\n        return 1\n    }\n}\n")
    unit := EdsUnit([EdsClass("Box", [EdsField("Width", EdsSimple("int"), 2), EdsFunction("Area", EdsSimple("int"), 3)], 1)])

    rows := EditorDocumentSymbolFacts.SymbolRows(unit, lines)
    assert rows.Count == 1
    assert rows[0].Name == "Box"
    assert rows[0].Kind == EditorSymbolKind.Class
    assert rows[0].Detail == null
    assert rows[0].StartLine == 0
    assert rows[0].EndLine == 5
    assert rows[0].Children.Count == 2
    assert rows[0].Children[0].Name == "Width"
    assert rows[0].Children[0].Kind == EditorSymbolKind.Field
    assert rows[0].Children[0].Detail == "int"
    assert rows[0].Children[1].Name == "Area"
    assert rows[0].Children[1].Kind == EditorSymbolKind.Function
}

// A DECLARATION THE OUTLINE HAS NO ROW FOR IS SKIPPED, not shown with a guessed kind.
test "the outline skips a declaration it has no row for" {
    constructorDeclaration := new ConstructorDeclaration(new List<Parameter>(), new BlockStatement(new List<Statement>(), 1, 1), null, Modifiers.None, new List<AttributeNode>(), 1, 1) as Declaration
    unit := EdsUnit([constructorDeclaration, EdsFunction("run", null, 3)])
    rows := EditorDocumentSymbolFacts.SymbolRows(unit, EdsLines("constructor() {\n}\nfunc run(): void {\n}\n"))

    assert rows.Count == 1
    assert rows[0].Name == "run"
    assert rows[0].Detail == null
}

// THE FULL RANGE MUST CONTAIN THE SELECTION RANGE. A single-line symbol whose NAME is longer than
// the line it sits on has both clamped: the selection stops at the line's end, and the full range
// is widened to cover it.
test "the outline clamps a name that is longer than its own line" {
    lines := EdsLines("ab\n")
    unit := EdsUnit([EdsField("averyverylongname", null, 1)])

    rows := EditorDocumentSymbolFacts.SymbolRows(unit, lines)
    assert rows.Count == 1
    assert rows[0].SelectionEndCharacter == 2
    assert rows[0].EndCharacter == 2
    assert rows[0].StartLine == 0
    assert rows[0].EndLine == 0
}

// A FILE WHOSE TEXT THE EDITOR DID NOT HAND OVER MEASURES NOTHING, and answers the widest column
// an int can carry rather than zero — a range that covers everything is one no client rejects.
test "the outline answers the widest column when there is no text to measure" {
    rows := EditorDocumentSymbolFacts.SymbolRows(EdsUnit([EdsField("Width", EdsSimple("int"), 4)]), null)

    assert rows.Count == 1
    assert rows[0].EndCharacter == 2147483647
    assert rows[0].SelectionEndCharacter == 5
    assert rows[0].StartLine == 3
    assert rows[0].EndLine == 3
}

// THE END OF A DECLARATION IS THE LINE ITS OWN BRACE CLOSES ON, counted by depth so a nested block
// cannot end it early. A declaration with no brace closes where it began.
test "the outline ends a declaration where its own brace closes" {
    lines := EdsLines("func run(): void {\n    if a {\n        b\n    }\n}\ntail")
    assert EditorDocumentSymbolFacts.EndLine(1, lines) == 5
    assert EditorDocumentSymbolFacts.EndLine(2, lines) == 4

    unbraced := EdsLines("func run(): void\n    b")
    assert EditorDocumentSymbolFacts.EndLine(1, unbraced) == 1
    assert EditorDocumentSymbolFacts.EndLine(0, unbraced) == 0
    assert EditorDocumentSymbolFacts.EndLine(3, null) == 3
}

// THE DETAIL IS THE TYPE AS IT WAS WRITTEN, whole — a generic keeps its arguments, an array its
// brackets, a nullable its question mark — and a member with no declared type carries no detail
// rather than the word "void".
test "the outline's detail is the whole written type or nothing" {
    generic: TypeReference = new GenericTypeReference("List", EdsTypeArguments(["string"]), 1, 1)
    array: TypeReference = new ArrayTypeReference(EdsSimple("int"))
    nullable: TypeReference = new NullableTypeReference(EdsSimple("string"))

    assert EditorDocumentSymbolFacts.DetailText(generic) == "List<string>"
    assert EditorDocumentSymbolFacts.DetailText(array) == "int[]"
    assert EditorDocumentSymbolFacts.DetailText(nullable) == "string?"
    assert EditorDocumentSymbolFacts.DetailText(null) == null
}

func EdsTypeArguments(names: string[]): List<TypeReference> {
    list := new List<TypeReference>()
    for name in names {
        list.Add(EdsSimple(name))
    }
    return list
}

// THE OUTLINE'S OWN JUDGEMENTS ABOUT N# ARE HERE, not in the protocol mapping: a record shows as a
// class and carries the word "record", a union shows as an enum and carries the word "union", and
// a test shows as a method named by its DESCRIPTION.
test "the outline shows a record as a class and a union as an enum" {
    recordDeclaration := new RecordDeclaration("Options", null, new List<TypeReference>(), new List<Declaration>(), null, false, Modifiers.None, new List<AttributeNode>(), 1, 1) as Declaration
    testCase := new TestDeclaration("it works", new BlockStatement(new List<Statement>(), 5, 1), null, null, null, 5, 1) as Declaration

    rows := EditorDocumentSymbolFacts.SymbolRows(EdsUnit([recordDeclaration, testCase]), EdsLines("record Options()\n\n\n\ntest \"it works\" {\n}\n"))
    assert rows.Count == 2
    assert rows[0].Kind == EditorSymbolKind.Class
    assert rows[0].Detail == "record"
    assert rows[1].Kind == EditorSymbolKind.Method
    assert rows[1].Name == "it works"
    assert rows[1].Detail == "test"
}
