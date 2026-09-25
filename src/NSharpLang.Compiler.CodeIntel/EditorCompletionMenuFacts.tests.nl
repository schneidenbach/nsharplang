namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// CONTRACTS FOR THE IDENTIFIER COMPLETION MENU.
//
// These came out of `CompletionHandler.cs`, where the language's own word list, the five snippets,
// the six sort ranks, the grey signature line and the caret questions were private statics behind
// an LSP handler — reachable only by starting a language server and pressing Ctrl+Space.
func EcmParse(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "menu.nl").CompilationUnit
}

func EcmRow(rows: List<EditorCompletionMenuRow>, label: string): EditorCompletionMenuRow? {
    for row in rows {
        if row.Label == label {
            return row
        }
    }

    return null
}

// THE LANGUAGE'S OWN WORDS, ALL OF THEM, IN ONE ORDER: keywords, then snippets, then primitives.
test "the completion menu offers every keyword, snippet and primitive in one order" {
    rows := EditorCompletionMenuFacts.LanguageRows()

    keywords := EditorCompletionMenuFacts.Keywords()
    snippets := EditorCompletionMenuFacts.SnippetLabels()
    primitives := EditorCompletionMenuFacts.PrimitiveTypes()
    assert rows.Count == keywords.Length + snippets.Length + primitives.Length

    assert rows[0].Label == "func"
    assert rows[0].Kind == 14
    assert rows[0].Detail == "keyword"
    assert rows[0].IsSnippet == false
    assert rows[0].Key == "keyword:func"
    assert rows[0].SortText == "0500_func_keyword"

    assert rows[keywords.Length].Label == "func"
    assert rows[keywords.Length].Kind == 15
    assert rows[keywords.Length].IsSnippet
    assert rows[keywords.Length].Key == "snippet:func"
    assert rows[keywords.Length].Detail == "func declaration"
    assert rows[keywords.Length].SortText == "0500_func_snippet"

    last := rows[rows.Count - 1]
    assert last.Label == "sbyte"
    assert last.Detail == "primitive type"
    assert last.Key == "primitive:sbyte"
    assert last.SortText == "0500_sbyte_primitive"

    // Nothing in the language list carries documentation; a keyword is its own explanation.
    assert rows[0].Documentation == null
}

// THE SNIPPET TABLES ARE PARALLEL, and a menu that read past the end of one would offer a skeleton
// with the wrong body.
test "the completion menu's snippet tables are the same length" {
    labels := EditorCompletionMenuFacts.SnippetLabels()
    assert labels.Length == EditorCompletionMenuFacts.SnippetDetails().Length
    assert labels.Length == EditorCompletionMenuFacts.SnippetBodies().Length
    assert EditorCompletionMenuFacts.SnippetBodies()[0].Contains("${1:name}")
}

// THE SIX RANKS PUT THE READER'S OWN NAMES FIRST AND AUTO-IMPORTS LAST.
test "the completion menu ranks local names above the language and imports below it" {
    local := EditorCompletionMenuFacts.SortText(EditorCompletionMenuFacts.SortLocal, "Widget", "document")
    language := EditorCompletionMenuFacts.SortText(EditorCompletionMenuFacts.SortLanguage, "Widget", "keyword")
    importable := EditorCompletionMenuFacts.ExternalSortText(false, "Widget", "System.Text")
    inScope := EditorCompletionMenuFacts.ExternalSortText(true, "Widget", "System.Text")

    assert local == "0000_widget_document"
    assert language == "0500_widget_keyword"
    assert inScope == "0600_widget_system.text"
    assert importable == "0900_widget_system.text"

    assert String.CompareOrdinal(local, language) < 0
    assert String.CompareOrdinal(language, inScope) < 0
    assert String.CompareOrdinal(inScope, importable) < 0
}

// THE GREY LINE BESIDE A NAME: modifiers in one fixed order, the kind word, the name, and for
// anything callable its parameters and return type.
test "the completion menu's grey line spells modifiers, kind, name and signature" {
    source := "namespace T\n\n/// Adds.\npublic static func Add(left: int, right: int): int {\n    return left\n}\n\nclass Box {\n    Width: int\n}\n\nsoa record Points {\n    X: int\n}\n"
    rows := EditorCompletionMenuFacts.DocumentSymbolRows(EcmParse(source), source)

    add := EcmRow(rows, "Add")
    assert add != null
    assert add.Detail == "public static function Add (left: int, right: int) : int"
    assert add.Kind == 3
    assert add.SortText == "0000_add_document"
    assert add.Key == "scope:Add"
    assert add.InsertText == "Add"
    assert add.Documentation == "Adds."

    box := EcmRow(rows, "Box")
    assert box != null
    assert box.Detail == "class Box"
    assert box.Kind == 7
    assert box.Documentation == null
}

// A RECORD AND A UNION BOTH DRAW AS CLASSES in the identifier menu, and a struct keeps its own icon.
test "the completion menu draws each declared kind in its protocol slot" {
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Class) == 7
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Record) == 7
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Union) == 7
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Struct) == 22
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Interface) == 8
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Enum) == 13
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Function) == 3
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Method) == 2
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Property) == 10
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Field) == 5
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.EnumMember) == 20
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Constructor) == 4
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.Parameter) == 6
    assert EditorCompletionMenuFacts.CompletionKind(EditorSymbolTableKind.LocalVariable) == 6
}

// ONE ROW PER NAME: the first declaration's place in the list, the last declaration's meaning.
test "the completion menu offers one row per name however often it is declared" {
    source := "namespace T\n\nfunc Same(): int {\n    return 1\n}\n\nfunc Other() {\n}\n\nclass Same {\n}\n"
    rows := EditorCompletionMenuFacts.DocumentSymbolRows(EcmParse(source), source)

    assert rows.Count == 2
    assert rows[0].Label == "Same"
    assert rows[0].Detail == "class Same"
    assert rows[1].Label == "Other"
}

// A METHOD IS OFFERED AFTER A DOT, NOT ON ITS OWN, so the menu knows which names belong to a type.
test "the completion menu names the members a type carries" {
    source := "namespace T\n\nclass Box {\n    Width: int\n    func Area(): int {\n        return 1\n    }\n}\n\nenum Color {\n    Red\n}\n"
    names := EditorCompletionMenuFacts.TypeMemberNames(EcmParse(source), source)

    assert names.Count == 2
    assert names.Contains("Width")
    assert names.Contains("Area")
    // An enum's members are not type members for this purpose; they are offered by their own name.
    assert names.Contains("Red") == false
}

// HOW MUCH OF A NAME HAS BEEN TYPED, which decides what is worth offering at all.
test "the completion menu reads the identifier prefix backwards from the caret" {
    text := "    value := Console.Wri\n"
    assert EditorCompletionMenuFacts.IdentifierPrefix(text, 0, 24) == "Wri"
    assert EditorCompletionMenuFacts.IdentifierPrefix(text, 0, 4) == ""
    assert EditorCompletionMenuFacts.IdentifierPrefix(text, 0, 9) == "value"
    // A caret past the end of the line, and a line the file has not got.
    assert EditorCompletionMenuFacts.IdentifierPrefix(text, 0, 900) == "Wri"
    assert EditorCompletionMenuFacts.IdentifierPrefix(text, 9, 2) == ""
    assert EditorCompletionMenuFacts.IdentifierPrefix(null, 0, 2) == ""
}

// AN `import` LINE NAMES A NAMESPACE, and everything else names none.
test "the completion menu tells an import line from an ordinary one" {
    assert EditorCompletionMenuFacts.ImportPrefix("import System.Col") == "System.Col"
    assert EditorCompletionMenuFacts.ImportPrefix("   import System.") == "System."
    assert EditorCompletionMenuFacts.ImportPrefix("import ") == ""
    assert EditorCompletionMenuFacts.ImportPrefix("import System.Text as Txt") == "System.Text"

    // Not an import: an ordinary line, a word that merely starts with one, and a package import.
    assert EditorCompletionMenuFacts.ImportPrefix("value := 1") == null
    assert EditorCompletionMenuFacts.ImportPrefix("imported := 1") == null
    assert EditorCompletionMenuFacts.ImportPrefix("import \"Newtonsoft.Json\"") == null

    assert EditorCompletionMenuFacts.ImportPrefixAt("import System.Col\n", 0, 17) == "System.Col"
    assert EditorCompletionMenuFacts.ImportPrefixAt("import System.Col\n", 9, 2) == null
}

// THE GREY TEXT BESIDE A NAMESPACE SUGGESTION IS THE NAMESPACE THE READER WOULD END UP WITH.
test "the completion menu names the namespace an import suggestion completes to" {
    assert EditorCompletionMenuFacts.ImportSuggestionDetail("", "System") == "namespace System"
    assert EditorCompletionMenuFacts.ImportSuggestionDetail("System.", "Text") == "namespace System.Text"
    assert EditorCompletionMenuFacts.ImportSuggestionDetail("System.Col", "Collections") == "namespace System.Collections"
    assert EditorCompletionMenuFacts.ImportSuggestionDetail("Sys", "System") == "namespace System"
}

// AFTER A DOT THE MENU IS A DIFFERENT MENU, and the caret question that decides is the same one
// `nlc query completions` asks.
test "the completion menu knows when the caret is asking a receiver" {
    text := "    greeting.Comp\n    value := 1\n"
    assert EditorCompletionMenuFacts.IsMemberAccessAt(text, 0, 17)
    assert EditorCompletionMenuFacts.IsMemberAccessAt(text, 0, 13)
    assert EditorCompletionMenuFacts.IsMemberAccessAt(text, 1, 10) == false
    assert EditorCompletionMenuFacts.IsMemberAccessAt(text, 9, 1) == false
    assert EditorCompletionMenuFacts.IsMemberAccessAt(null, 0, 1) == false
}

// ── What the bound model offers ─────────────────────────────────────────
//
// `CompletionHandler.AddSemanticCompletionItems` was sixty lines of C# reachable only through an
// OmniSharp request: the widening of the visible set, the two exclusions, the grey type line and
// the two sort keys.
func EcmLabels(rows: List<EditorCompletionMenuRow>): string {
    text := ""
    for row in rows {
        if text.Length > 0 {
            text = text + ","
        }

        text = text + row.Label
    }

    return text
}

test "the menu offers the bound model's variables and functions" {
    intType: TypeInfo = new SimpleTypeInfo("int")
    model := new SemanticModel()
    variables := model.Variables
    variables["total"] = intType
    functions := model.Functions
    functions["Compute"] = intType

    rows := EditorCompletionMenuFacts.SemanticRows(model, null, null, 0, 0)
    assert EcmLabels(rows) == "total,Compute"

    variable := EcmRow(rows, "total")
    if variable == null {
        throw new InvalidOperationException("expected a row for total")
    }

    assert variable.Kind == EditorCompletionMenuFacts.VariableKind
    assert variable.Detail == "variable: int"
    assert variable.InsertText == "total"
    assert !variable.IsSnippet
    assert variable.SortText == EditorCompletionMenuFacts.SortText(EditorCompletionMenuFacts.SortLocal, "total", "variable")

    boundFunction := EcmRow(rows, "Compute")
    if boundFunction == null {
        throw new InvalidOperationException("expected a row for Compute")
    }

    assert boundFunction.Kind == EditorCompletionMenuFacts.FunctionKind
    assert boundFunction.Detail == "func: int"
    assert boundFunction.SortText == EditorCompletionMenuFacts.SortText(EditorCompletionMenuFacts.SortLocal, "Compute", "function")
}

// A NAME THAT IS BOTH IS OFFERED ONCE, as the function it is.
test "the menu does not offer a bound function as a variable too" {
    intType: TypeInfo = new SimpleTypeInfo("int")
    model := new SemanticModel()
    variables := model.Variables
    variables["Compute"] = intType
    functions := model.Functions
    functions["Compute"] = intType

    rows := EditorCompletionMenuFacts.SemanticRows(model, null, null, 0, 0)
    assert EcmLabels(rows) == "Compute"
    assert rows[0].Kind == EditorCompletionMenuFacts.FunctionKind
}

// A FUNCTION A TYPE ALREADY CARRIES IS A MEMBER, reachable after a dot and not on its own.
test "the menu drops a bound function that is a type's member" {
    source := "namespace M\n\nclass Box {\n    func Open(): int {\n        return 1\n    }\n}\n"
    unit := EcmParse(source)

    intType: TypeInfo = new SimpleTypeInfo("int")
    model := new SemanticModel()
    functions := model.Functions
    functions["Open"] = intType
    functions["Free"] = intType

    rows := EditorCompletionMenuFacts.SemanticRows(model, unit, source, 0, 0)
    assert EcmLabels(rows) == "Free"
}

test "the menu offers nothing semantic without a bound model" {
    rows := EditorCompletionMenuFacts.SemanticRows(null, null, null, 0, 0)
    assert rows.Count == 0
}
