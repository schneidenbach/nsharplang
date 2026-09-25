namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// CONTRACTS FOR THE THREE TABLES THE EDITOR BUILDS PER KEYSTROKE.
//
// These came out of `DocumentManager.cs`, where `ExtractSymbols`, `ExtractSymbolsInfo` and
// `ExtractSymbolLocations` and their eleven private helpers were six hundred lines of C# that
// nothing could assert against: they were private, they ran only inside `UpdateDocument`, and the
// only way to observe them was to open a file in a real editor and click on something.
//
// THE SOURCE IS PARSED RATHER THAN HAND-BUILT, because the columns these tables report are indexes
// into real source lines. A hand-built declaration can be given any line and column, and would
// prove the walk agrees with the fixture rather than with the file the reader is looking at.
func EstParse(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "table.nl").CompilationUnit
}

func EstInfo(rows: List<EditorSymbolInfoRow>, name: string): EditorSymbolInfoRow? {
    // The LAST row wins, exactly as the caller's dictionary does.
    found: EditorSymbolInfoRow? = null
    for row in rows {
        if row.Name == name {
            found = row
        }
    }

    return found
}

func EstLocations(rows: List<EditorSymbolLocationRow>, name: string): List<EditorSymbolLocationRow> {
    matches := new List<EditorSymbolLocationRow>()
    for row in rows {
        if row.Name == name {
            matches.Add(row)
        }
    }

    return matches
}

// THE TYPE CATALOG IS NOMINAL TYPES ONLY, and every one of them is the analyzer's own `TypeInfo`.
test "the symbol table's type catalog names every nominal type and no function" {
    unit := EstParse("namespace T\n\nfunc Free(): int {\n    return 1\n}\n\nclass Box {\n}\n\nstruct Vec {\n}\n\nrecord Point(X: int) {\n}\n\ninterface IShape {\n}\n\nenum Color {\n    Red\n}\n\nunion Shape {\n    Circle { radius: int }\n}\n")

    catalog := EditorSymbolTableFacts.TypeCatalog(unit)
    assert catalog.Count == 6
    assert catalog.ContainsKey("Box")
    assert catalog.ContainsKey("Vec")
    assert catalog.ContainsKey("Point")
    assert catalog.ContainsKey("IShape")
    assert catalog.ContainsKey("Color")
    assert catalog.ContainsKey("Shape")
    assert catalog.ContainsKey("Free") == false
    // Each entry is the analyzer's own `TypeInfo` for that declaration, not a description of one.
    boxInfo := catalog["Box"] as ClassTypeInfo
    assert boxInfo != null
    assert boxInfo.Name == "Box"
    assert (catalog["Color"] as EnumTypeInfo) != null
    assert (catalog["Shape"] as UnionTypeInfo) != null
}

test "the symbol table of nothing at all is empty rather than absent" {
    assert EditorSymbolTableFacts.TypeCatalog(null).Count == 0
    assert EditorSymbolTableFacts.SymbolInfoRows(null, "x").Count == 0
    assert EditorSymbolTableFacts.SymbolLocationRows(null, "x").Count == 0
}

// A FUNCTION CARRIES ITS RETURN TYPE, ITS PARAMETERS AND THE COMMENT ABOVE IT.
test "the symbol table row for a function carries its return type, parameters and leading documentation" {
    source := "namespace T\n\n/// Adds two numbers.\n/// Returns the sum.\nfunc Add(left: int, right: int = 2): int {\n    return left\n}\n"
    rows := EditorSymbolTableFacts.SymbolInfoRows(EstParse(source), source)

    add := EstInfo(rows, "Add")
    assert add != null
    assert add.Kind == EditorSymbolTableKind.Function
    assert add.TypeName == "int"
    assert add.Documentation == "Adds two numbers.\nReturns the sum."
    assert add.Parameters.Count == 2
    assert add.Parameters[0].Name == "left"
    assert add.Parameters[0].TypeName == "int"
    assert add.Parameters[0].HasDefaultValue == false
    assert add.Parameters[1].Name == "right"
    assert add.Parameters[1].HasDefaultValue == true
    assert add.Members.Count == 0
}

// LOCAL FUNCTIONS ARE CALLABLE BY NAME, so the table carries them beside their owner — at any
// nesting depth, and through the statements that can contain them.
test "the symbol table carries local functions beside the function that declares them" {
    source := "namespace T\n\nfunc Outer() {\n    func Inner(): int {\n        func Deepest(): int {\n            return 1\n        }\n        return Deepest()\n    }\n    if true {\n        func InBranch() {\n        }\n    }\n    while true {\n        func InLoop() {\n        }\n    }\n}\n"
    rows := EditorSymbolTableFacts.SymbolInfoRows(EstParse(source), source)

    assert EstInfo(rows, "Outer") != null
    assert EstInfo(rows, "Inner") != null
    assert EstInfo(rows, "Deepest") != null
    assert EstInfo(rows, "InBranch") != null
    assert EstInfo(rows, "InLoop") != null

    // Source order: the owner first, then what it declares.
    assert rows[0].Name == "Outer"
    assert rows[1].Name == "Inner"
    assert rows[2].Name == "Deepest"
}

// A TYPE CARRIES ITS MEMBERS ONE LEVEL DEEP, and its constructor answers to the type's own name.
test "the symbol table row for a class carries methods, properties, fields and a constructor named after the type" {
    source := "namespace T\n\nclass Box {\n    width: int\n    Height: int\n    constructor(w: int) {\n        width = w\n    }\n    func Area(): int {\n        return 1\n    }\n}\n"
    rows := EditorSymbolTableFacts.SymbolInfoRows(EstParse(source), source)

    box := EstInfo(rows, "Box")
    assert box != null
    assert box.Kind == EditorSymbolTableKind.Class
    assert box.Members.Count == 4
    assert box.Members[0].Name == "width"
    assert box.Members[0].Kind == EditorSymbolTableKind.Field
    assert box.Members[0].TypeName == "int"
    assert box.Members[1].Name == "Height"
    assert box.Members[2].Name == "Box"
    assert box.Members[2].Kind == EditorSymbolTableKind.Constructor
    assert box.Members[2].Parameters.Count == 1
    assert box.Members[3].Name == "Area"
    assert box.Members[3].Kind == EditorSymbolTableKind.Method
}

// A RECORD IS A RECORD, A UNION IS A UNION, and an enum's members and a union's cases are typed by
// the thing that declares them.
test "the symbol table types enum members and union cases by their own declaration" {
    source := "namespace T\n\nenum Color {\n    Red,\n    Green\n}\n\nunion Shape {\n    Circle { radius: int }\n    Square { side: int }\n}\n\nrecord Point(X: int) {\n}\n"
    rows := EditorSymbolTableFacts.SymbolInfoRows(EstParse(source), source)

    color := EstInfo(rows, "Color")
    assert color != null
    assert color.Kind == EditorSymbolTableKind.Enum
    assert color.Members.Count == 2
    assert color.Members[0].Name == "Red"
    assert color.Members[0].Kind == EditorSymbolTableKind.EnumMember
    assert color.Members[0].TypeName == "Color"

    shape := EstInfo(rows, "Shape")
    assert shape != null
    assert shape.Kind == EditorSymbolTableKind.Union
    assert shape.Members.Count == 2
    assert shape.Members[0].Name == "Circle"
    assert shape.Members[0].Kind == EditorSymbolTableKind.Class
    assert shape.Members[0].TypeName == "Shape"

    point := EstInfo(rows, "Point")
    assert point != null
    assert point.Kind == EditorSymbolTableKind.Record
}

// A LATER DECLARATION OF A NAME REPLACES AN EARLIER ONE, because the table answers "what is this
// name" with one answer.
test "the symbol table lets a later declaration of a name answer for it" {
    source := "namespace T\n\nfunc Same(): int {\n    return 1\n}\n\nclass Same {\n}\n"
    rows := EditorSymbolTableFacts.SymbolInfoRows(EstParse(source), source)

    same := EstInfo(rows, "Same")
    assert same != null
    assert same.Kind == EditorSymbolTableKind.Class
}

// THE COMMENT BLOCK ABOVE A DECLARATION, and the three ways it ends.
test "the symbol table's documentation skips blank lines before the block and stops at one inside it" {
    lines := "zero\n// first\n// second\n\n// stranded\nfunc F()\n".Split('\n')

    // Line 6 is the declaration; the blank line at index 3 ends the block above it.
    assert EditorSymbolTableFacts.LeadingDocumentation(lines, 6) == "stranded"

    joined := "// first\n// second\nfunc F()\n".Split('\n')
    assert EditorSymbolTableFacts.LeadingDocumentation(joined, 3) == "first\nsecond"

    spaced := "// first\n\nfunc F()\n".Split('\n')
    assert EditorSymbolTableFacts.LeadingDocumentation(spaced, 3) == "first"

    stopped := "code := 1\nfunc F()\n".Split('\n')
    assert EditorSymbolTableFacts.LeadingDocumentation(stopped, 2) == null

    assert EditorSymbolTableFacts.LeadingDocumentation(joined, 1) == null
}

// THE LOCATION OF A DECLARED NAME IS THE NAME'S OWN COLUMN, not the construct's.
test "the symbol table's locations point at a name rather than at its keyword" {
    source := "namespace T\n\nfunc Add(left: int, right: int): int {\n    total := left\n    return total\n}\n"
    rows := EditorSymbolTableFacts.SymbolLocationRows(EstParse(source), source)

    add := EstLocations(rows, "Add")
    assert add.Count == 1
    assert add[0].Kind == EditorSymbolTableKind.Function
    assert add[0].Line == 2
    assert add[0].Column == 5
    assert add[0].Length == 3

    left := EstLocations(rows, "left")
    assert left.Count == 1
    assert left[0].Kind == EditorSymbolTableKind.Parameter
    assert left[0].Line == 2
    assert left[0].Column == 9

    right := EstLocations(rows, "right")
    assert right.Count == 1
    assert right[0].Column == 20

    total := EstLocations(rows, "total")
    assert total.Count == 1
    assert total[0].Kind == EditorSymbolTableKind.LocalVariable
    assert total[0].Line == 3
    assert total[0].Column == 4
}

// PARAMETERS ARE FOUND LEFT TO RIGHT, so two parameters whose names share a prefix do not collide.
test "the symbol table finds each parameter after the one before it" {
    source := "namespace T\n\nfunc F(a: int, ab: int, a2: int) {\n}\n"
    rows := EditorSymbolTableFacts.SymbolLocationRows(EstParse(source), source)

    assert EstLocations(rows, "a")[0].Column == 7
    assert EstLocations(rows, "ab")[0].Column == 15
    assert EstLocations(rows, "a2")[0].Column == 24
}

// THE NAMES A BODY DECLARES, including the ones no symbol-table entry exists for.
test "the symbol table locates loop variables, tuple elements and catch variables" {
    source := "namespace T\n\nimport System\n\nfunc F() {\n    for item in [1, 2] {\n        print item\n    }\n    left, _, right := Three()\n    try {\n        print 1\n    } catch (ex: Exception) {\n        print ex\n    }\n}\n"
    rows := EditorSymbolTableFacts.SymbolLocationRows(EstParse(source), source)

    item := EstLocations(rows, "item")
    assert item.Count == 1
    assert item[0].Kind == EditorSymbolTableKind.LocalVariable
    assert item[0].Line == 5
    assert item[0].Column == 8

    assert EstLocations(rows, "left").Count == 1
    assert EstLocations(rows, "right").Count == 1
    assert EstLocations(rows, "_").Count == 0

    assert EstLocations(rows, "left")[0].Column == 4
    assert EstLocations(rows, "right")[0].Column == 13

    // A CATCH CLAUSE IS LOCATED ONE LINE ABOVE ITS OWN BLOCK, and that is the shipped behaviour
    // rather than a good one: the clause carries no position, so the search is run on the line
    // before the block's, which for `} catch (ex: Exception) {` is the line ABOVE the one the name
    // is actually written on. The search therefore fails, the fallback column zero stands, and the
    // row points at the start of that line. Recorded exactly as it behaves, because navigation has
    // shipped on it; moving it is a behaviour change and belongs to whoever wants it.
    ex := EstLocations(rows, "ex")
    assert ex.Count == 1
    assert ex[0].Kind == EditorSymbolTableKind.LocalVariable
    assert ex[0].Line == 10
    assert ex[0].Column == 0
}

// A NAME DECLARED TWICE HAS TWO LOCATIONS, IN SOURCE ORDER, because navigation should offer both.
test "the symbol table keeps both locations of one name in source order" {
    source := "namespace T\n\nfunc F() {\n    value := 1\n    if true {\n        value := 2\n        print value\n    }\n}\n"
    rows := EditorSymbolTableFacts.SymbolLocationRows(EstParse(source), source)

    value := EstLocations(rows, "value")
    assert value.Count == 2
    assert value[0].Line == 3
    assert value[1].Line == 5
}

// NESTED TYPE MEMBERS AND LOCAL FUNCTIONS ARE REACHED, so the whole file is navigable.
test "the symbol table locates members and local functions wherever they are declared" {
    source := "namespace T\n\nclass Box {\n    Width: int\n    func Area(): int {\n        func Helper(): int {\n            return 2\n        }\n        return Helper()\n    }\n}\n"
    rows := EditorSymbolTableFacts.SymbolLocationRows(EstParse(source), source)

    assert EstLocations(rows, "Box")[0].Kind == EditorSymbolTableKind.Class
    assert EstLocations(rows, "Box")[0].Column == 6
    assert EstLocations(rows, "Width")[0].Kind == EditorSymbolTableKind.Field
    assert EstLocations(rows, "Area")[0].Kind == EditorSymbolTableKind.Function
    assert EstLocations(rows, "Helper").Count == 1
    assert EstLocations(rows, "Helper")[0].Line == 5
}

// WHEN THE NAME IS NOT ON THE LINE THE SEARCH FALLS BACK, first to the whole line and then to the
// column the caller handed in. Neither fallback may report a negative column.
test "the symbol table's name search falls back to the whole line and then to the caller's column" {
    lines := "func Wrapped(\n    value: int)\n".Split('\n')

    assert EditorSymbolTableFacts.FindNameColumn(lines, 0, 0, "Wrapped") == 5
    // Searching past the name still finds it, by rescanning the line from its start.
    assert EditorSymbolTableFacts.FindNameColumn(lines, 0, 9, "Wrapped") == 5
    // A name that is nowhere on the line leaves the caller's own column standing.
    assert EditorSymbolTableFacts.FindNameColumn(lines, 0, 3, "absent") == 3
    // So does a line that does not exist, and an empty one.
    assert EditorSymbolTableFacts.FindNameColumn(lines, 9, 2, "Wrapped") == 2
    assert EditorSymbolTableFacts.FindNameColumn(lines, 2, 4, "Wrapped") == 4
}
