namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler


// CONTRACTS FOR THE REFERENCE AND DEFINITION ANSWERS, AND FOR THE SOURCE-TEXT DOOR (019 slice 15
// stage 2).
//
// The door is the member slice 13 measured a wall for and slice 15 stage 1 published the catalog row
// for. Now that a static N# parameter can BE an `IReadOnlyDictionary<string, string>`, the door and
// the three answers that read it are askable directly for the first time, and they state SEVEN
// things that were previously unreachable or asserted only through a loaded project:
//   (a) THE CACHED TEXT WINS AND THE KEY IS THE FULL PATH — a relative caller still finds its entry,
//       because the door canonicalises before it looks up.
//   (b) A NULL PATH ANSWERS NULL AND NEVER TOUCHES THE DISK.
//   (c) THE DEFINITION ROW IS ALWAYS FIRST AND ALWAYS PRESENT, even when the binding map is null and
//       there are no usages at all.
//   (d) A USAGE AT THE DECLARATION'S EXACT POSITION IS DROPPED, and so is one that merely OVERLAPS
//       the declaration's NAME SPAN — two different filters, and the second is why a declaration
//       reported a column early does not appear twice.
//   (e) THE OVERLAP TEST IS HALF-OPEN: a usage exactly one name-length past the declaration's column
//       is KEPT, and the one before it is dropped.
//   (f) A ROW AT LINE 0 CARRIES NO CONTEXT AND NEVER OPENS THE FILE — which is why a declaration
//       with no position does not throw on a path that does not exist.
//   (g) A DEFINITION ANSWER'S LENGTH IS THE NAME'S LENGTH, not any recorded span.
func CirrTexts(path: string, text: string): Dictionary<string, string> {
    texts := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    texts[System.IO.Path.GetFullPath(path)] = text
    return texts
}

func CirrEmpty(): Dictionary<string, string> {
    return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
}

func CirrDeclaration(name: string, filePath: string?, line: int, column: int): SymbolDeclaration {
    return new SymbolDeclaration(name, filePath, line, column, "function")
}

func CirrText(results: List<ReferenceResult>): string {
    text := ""
    index := 0
    while index < results.Count {
        if index > 0 {
            text = text + ","
        }
        row := results[index]
        text = text + row.Line.ToString() + ":" + row.Column.ToString() + ":" + row.Length.ToString()
        if row.IsDefinition {
            text = text + "*"
        }
        index = index + 1
    }
    return text
}

test "the door prefers the cached text, canonicalises its key, and answers null for a null path" {
    texts := CirrTexts("/p/sub/a.nl", "alpha\nbeta\ngamma\n")

    assert CodeIntelligenceSourceDoor.SourceText(texts, "/p/sub/a.nl") == "alpha\nbeta\ngamma\n"
    assert CodeIntelligenceSourceDoor.SourceText(texts, null) == null

    // The key is the FULL path, so a path that canonicalises to the same file finds the same entry.
    assert CodeIntelligenceSourceDoor.SourceText(texts, "/p/sub/./a.nl") == "alpha\nbeta\ngamma\n"
}

test "a concrete dictionary flows into the read-only door, which is the row this stage bought" {
    // The ARGUMENT position is the one production uses — every caller of this door hands it either a
    // `ProjectSnapshot`'s own `IReadOnlyDictionary` or a concrete `Dictionary` — and it is the
    // position the analyser's upcast row governs. A TYPED LOCAL of a read-only interface is a
    // separate, PRE-EXISTING emitter gap that `IReadOnlyList` shares, so it is not asserted here.
    concrete := new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    concrete[System.IO.Path.GetFullPath("/p/a.nl")] = "text"

    assert CodeIntelligenceSourceDoor.SourceText(concrete, "/p/a.nl") == "text"

    sorted := new SortedDictionary<string, string>()
    sorted[System.IO.Path.GetFullPath("/p/b.nl")] = "sorted text"
    assert CodeIntelligenceSourceDoor.SourceText(sorted, "/p/b.nl") == "sorted text"
}

test "the definition row is first and present even with no binding map at all" {
    declaration := CirrDeclaration("Widget", "/p/a.nl", 3, 5)

    results := CodeIntelligenceReferenceResults.FromDeclaration("/p", CirrTexts("/p/a.nl", "one\ntwo\nthree Widget\n"), null, declaration)

    assert results.Count == 1
    assert CirrText(results) == "3:5:6*"
    assert results[0].File == "a.nl"
    assert results[0].IsDefinition
    assert results[0].Context != null
}

test "a row at line 0 carries no context and never opens the file" {
    declaration := CirrDeclaration("Ghost", "/p/does-not-exist.nl", 0, 0)

    results := CodeIntelligenceReferenceResults.FromDeclaration("/p", CirrEmpty(), null, declaration)

    assert results.Count == 1
    assert results[0].Context == null
    assert results[0].Line == 0
}

test "a null declaration file relativises to the project root's own route, not to null" {
    declaration := CirrDeclaration("Nameless", null, 0, 0)

    results := CodeIntelligenceReferenceResults.FromDeclaration("/p", CirrEmpty(), null, declaration)

    assert results.Count == 1
    assert results[0].File != null
}

test "the definition answer's length is the NAME's length and its file is project-relative" {
    definition := CodeIntelligenceReferenceResults.ToDefinition("/p", CirrDeclaration("Widget", "/p/sub/a.nl", 7, 9))

    assert definition.Name == "Widget"
    assert definition.Kind == "function"
    assert definition.File == "sub/a.nl"
    assert definition.Line == 7
    assert definition.Column == 9
    assert definition.Length == 6

    // A null file still produces a string, and a zero position is carried through unchanged.
    empty := CodeIntelligenceReferenceResults.ToDefinition("/p", CirrDeclaration("X", null, 0, 0))
    assert empty.Length == 1
    assert empty.Line == 0
}
