namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// CONTRACTS FOR "GO TO SYMBOL IN WORKSPACE". These came out of `WorkspaceSymbolHandler.cs`, where
// the subsequence match, the member expansion and the coordinate arithmetic were private statics
// behind an OmniSharp request object.
//
// THE SOURCE IS PARSED RATHER THAN HAND-BUILT, because the columns these rows report are indexes
// into real source lines.
func EwsParse(source: string): CompilationUnit? {
    return ColumnarParserRecovery.ParseFileAst(source, "workspace.nl").CompilationUnit
}

func EwsNames(rows: List<EditorWorkspaceSymbolRow>): string {
    text := ""
    for row in rows {
        if text.Length > 0 {
            text = text + ","
        }

        text = text + row.Name
    }

    return text
}

func EwsRow(rows: List<EditorWorkspaceSymbolRow>, name: string): EditorWorkspaceSymbolRow? {
    for row in rows {
        if row.Name == name {
            return row
        }
    }

    return null
}

test "the workspace search matches a query as a case-insensitive subsequence" {
    assert EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "PrsNm")
    assert EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "person")
    assert EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "PERSONNAME")
    assert EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "")
    assert !EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "xyz")
    assert !EditorWorkspaceSymbolFacts.MatchesQuery("PersonName", "emaN")
    assert !EditorWorkspaceSymbolFacts.MatchesQuery("Name", "NameName")
}

test "the workspace search offers a type and then its own members" {
    unit := EwsParse("namespace W\n\nclass Person {\n    Name: string\n    func Greet(): string {\n        return Name\n    }\n}\n\nfunc Free(): int {\n    return 1\n}\n")
    source := "namespace W\n\nclass Person {\n    Name: string\n    func Greet(): string {\n        return Name\n    }\n}\n\nfunc Free(): int {\n    return 1\n}\n"

    rows := EditorWorkspaceSymbolFacts.SymbolRows(unit, source, "")
    assert EwsNames(rows) == "Person,Name,Greet,Free"

    person := EwsRow(rows, "Person")
    if person == null {
        throw new System.InvalidOperationException("expected a row for Person")
    }

    assert person.Kind == EditorSymbolTableKind.Class
    assert person.ContainerName == null

    greet := EwsRow(rows, "Greet")
    if greet == null {
        throw new System.InvalidOperationException("expected a row for Greet")
    }

    assert greet.ContainerName == "Person"
    assert greet.Kind == EditorSymbolTableKind.Method
}

// A FUNCTION'S BODY IS NOT SEARCHED. The symbol table descends one level and only into the six
// kinds that name a type, so a local is not an offer even though the location table knows it.
test "the workspace search does not offer a function's locals" {
    source := "namespace W\n\nfunc Compute(): int {\n    total := 2\n    return total\n}\n"
    rows := EditorWorkspaceSymbolFacts.SymbolRows(EwsParse(source), source, "")

    assert EwsNames(rows) == "Compute"
}

// A MEMBER IS ONLY REACHED THROUGH ITS TYPE: a query that does not match the type's own name
// never gets to look at the members, which is the shipped filter and is why "Name" alone does not
// find `Person.Name` unless "Person" matches too.
test "the workspace search reaches a member only through a matching type" {
    source := "namespace W\n\nclass Person {\n    Name: string\n}\n"
    unit := EwsParse(source)

    assert EwsNames(EditorWorkspaceSymbolFacts.SymbolRows(unit, source, "Person")) == "Person"
    assert EwsNames(EditorWorkspaceSymbolFacts.SymbolRows(unit, source, "Name")) == ""
    assert EwsNames(EditorWorkspaceSymbolFacts.SymbolRows(unit, source, "Pn")) == "Person"
    assert EwsNames(EditorWorkspaceSymbolFacts.SymbolRows(unit, source, "n")) == "Person,Name"
}

// THE SHIPPED OFF-BY-ONE, PINNED. The location table is 0-based and the row subtracts one again.
test "the workspace search reports a row one line and column before the name" {
    source := "namespace W\n\nclass Person {\n    Name: string\n}\n"
    rows := EditorWorkspaceSymbolFacts.SymbolRows(EwsParse(source), source, "")

    locations := EditorSymbolTableFacts.SymbolLocationTable(EwsParse(source), source)
    personLocation: EditorSymbolLocationRow? = null
    assert locations.TryGetValue("Person", out personLocation)
    if personLocation == null {
        throw new System.InvalidOperationException("expected a location for Person")
    }

    person := EwsRow(rows, "Person")
    if person == null {
        throw new System.InvalidOperationException("expected a row for Person")
    }

    assert personLocation.Line == 2
    assert personLocation.Column == 6
    assert person.Line == 1
    assert person.StartCharacter == 5
    assert person.EndCharacter == 5 + "Person".Length
}

// A NAME WITH NO LOCATION SITS AT THE TOP OF THE FILE, clamped to zero by the same arithmetic.
test "the workspace search clamps a name it has no location for" {
    locations := new Dictionary<string, EditorSymbolLocationRow>()
    row := EditorWorkspaceSymbolFacts.RowFor("Missing", EditorSymbolTableKind.Class, locations, null)

    assert row.Line == 0
    assert row.StartCharacter == 0
    assert row.EndCharacter == "Missing".Length
    assert row.ContainerName == null
}

test "the workspace search answers nothing for a file that did not parse" {
    rows := EditorWorkspaceSymbolFacts.SymbolRows(null, null, "")
    assert rows.Count == 0
}
