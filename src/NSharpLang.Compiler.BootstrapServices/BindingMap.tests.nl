namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CANONICAL CONTRACTS FOR `BindingMap`, IN N#.
//
// These replace `tests/BindingMapTests.cs`, the last canonical C# assertion layer over the
// `BindingMap` data structure itself. (`tests/AnalyzerBindingMapTests.cs` drives the same structure
// THROUGH the analyser and is a different subject; it survives untouched, exactly as the deleted
// file's own header said.) The map is what "go to definition" and "find all references" are: every
// name the analyser bound, indexed by the position it was USED at and by the position it was
// DECLARED at, in both directions.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. Every argument is a constructed
// `SymbolDeclaration` and every answer is a `SymbolDeclaration?` or a `List<SymbolUsage>` — all
// dependency-assembly types, which decline at emit from a `tests/native` project.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) THE TWO INDEXES ARE SEPARATE AND THE DECLARATION INDEX WINS. A position can be BOTH a
// declaration and a usage; `GetBindingAt` consults the declaration index first, then the binding
// index, then — only when the caller named a file — the FILE-LESS key. That last fallback is what
// makes a position recorded with no file findable from a file, and it is invisible to any test
// that always passes the same file.
//
// (2) A FILE PATH IS MATCHED LOOSELY, AND `null` MATCHES EVERYTHING. `FilesMatch` normalises
// backslashes, accepts either side as a SUFFIX of the other, and treats a missing path as a
// wildcard — so an absolute path from the language server and a relative path from the CLI reach
// the same declaration.
//
// (3) RE-BINDING A POSITION IS A MOVE, NOT AN ADD. Recording a second binding at a position that
// already has one replaces the forward answer AND withdraws that usage from the OLD declaration's
// reference list — otherwise "find all references" would report a stale usage forever.
//
// (4) A TYPE DECLARATION OUTRANKS AN INTERNAL ONE AT THE SAME POSITION. `this` and `value` are
// synthesised at the type's own position; recording one must not evict the type. The guard is
// two-sided — it fires only when the EXISTING declaration is a type kind and the incoming NAME is
// internal — so an ordinary re-record still overwrites.

func BindingMapContractUsageAt(usages: List<SymbolUsage>, line: int, column: int): bool {
    for usage in usages {
        if usage.Line == line && usage.Column == column {
            return true
        }
    }

    return false
}

func BindingMapContractNames(declarations: List<SymbolDeclaration>): string {
    names := ""
    for declaration in declarations {
        names = names + declaration.Name + "|"
    }

    return names
}

func BindingMapContractFiles(usages: List<SymbolUsage>): string {
    files := ""
    for usage in usages {
        files = files + (usage.File ?? "?") + "|"
    }

    return files
}

func BindingMapContractEntryText(entries: BindingEntryCollection): string {
    walked := ""
    enumerator := entries.GetEnumerator()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        walked = walked + entry.Value.Name + "@" + entry.Key.Line.ToString() + ":" + entry.Key.Col.ToString() + "|"
    }

    return walked
}

func BindingMapContractDeclaration(name: string, line: int, column: int): SymbolDeclaration {
    return new SymbolDeclaration(name, "test.nl", line, column, "variable")
}

// ---- Recording and looking up bindings -------------------------------------------------------

// Successor to RecordBinding_CanLookUpByUsagePosition.
test "binding map records a binding that can be looked up by usage position" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("x", "test.nl", 1, 5, "variable")

    bindings.RecordBinding("test.nl", 3, 10, 1, declaration)

    result := bindings.GetBindingAt("test.nl", 3, 10)

    assert result != null
    if result != null {
        assert result.Name == "x"
        assert result.Line == 1
        assert result.Column == 5

        // NOT IN THE DELETED FILE: the other two members of the answer survive the round trip too.
        assert result.Kind == "variable"
        assert result.File == "test.nl"
    }
}

// Successor to RecordDeclaration_CanLookUpByDeclarationPosition.
test "binding map records a declaration that can be looked up by its own position" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("myFunc", "test.nl", 5, 1, "function")

    bindings.RecordDeclaration(declaration)

    result := bindings.GetBindingAt("test.nl", 5, 1)

    assert result != null
    if result != null {
        assert result.Name == "myFunc"
        assert result.Kind == "function"
    }

    // NOT IN THE DELETED FILE: recording a declaration records no BINDING, so the two counters
    // stay honest — a declaration is not a usage of itself.
    assert bindings.BindingCount == 0
    assert bindings.AllDeclarations.Count == 1
}

// Successor to GetBindingAt_ReturnsNull_ForUnrecordedPosition.
test "binding map answers nothing for an unrecorded position" {
    bindings := new BindingMap()

    assert bindings.GetBindingAt("test.nl", 99, 99) == null

    // NOT IN THE DELETED FILE: a populated map still answers nothing OFF the recorded position,
    // which an empty map cannot distinguish from a map that answers everything.
    bindings.RecordBinding("test.nl", 3, 10, 1, BindingMapContractDeclaration("x", 1, 5))
    assert bindings.GetBindingAt("test.nl", 3, 11) == null
    assert bindings.GetBindingAt("test.nl", 4, 10) == null
    assert bindings.GetBindingAt("test.nl", 3, 10) != null
}

// Successor to RecordBinding_MultipleUsages_AllResolveToSameDeclaration.
test "binding map resolves every usage to the same declaration" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("count", "test.nl", 1, 5, "variable")

    bindings.RecordBinding("test.nl", 3, 5, 5, declaration)
    bindings.RecordBinding("test.nl", 5, 10, 5, declaration)
    bindings.RecordBinding("test.nl", 8, 2, 5, declaration)

    assert bindings.GetBindingAt("test.nl", 3, 5) == declaration
    assert bindings.GetBindingAt("test.nl", 5, 10) == declaration
    assert bindings.GetBindingAt("test.nl", 8, 2) == declaration

    // NOT IN THE DELETED FILE: three usages of one declaration are three bindings and ONE
    // declaration, not three of each.
    assert bindings.BindingCount == 3
    assert bindings.AllDeclarations.Count == 1
}

// Successor to RecordBinding_StoredDeclaration_RetrievableRegardlessOfLineOrder.
test "binding map retrieves a forward reference regardless of line order" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("laterFunc", "test.nl", 10, 1, "function")

    bindings.RecordBinding("test.nl", 3, 5, 9, declaration)

    result := bindings.GetBindingAt("test.nl", 3, 5)

    assert result != null
    if result != null {
        assert result.Name == "laterFunc"
        assert result.Line == 10
    }

    // NOT IN THE DELETED FILE: the forward reference also registers the declaration ITSELF, so the
    // declaration position resolves even though nothing declared it explicitly.
    declared := bindings.GetBindingAt("test.nl", 10, 1)
    assert declared != null
    if declared != null {
        assert declared.Name == "laterFunc"
    }
}

// ---- Reverse lookup -------------------------------------------------------------------------

// Successor to GetReferences_ReturnsAllUsagesOfDeclaration.
test "binding map returns all usages of a declaration" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("name", "test.nl", 1, 5, "variable")

    bindings.RecordBinding("test.nl", 3, 5, 4, declaration)
    bindings.RecordBinding("test.nl", 7, 12, 4, declaration)

    usages := bindings.GetReferences(declaration)

    assert usages.Count == 2
    assert BindingMapContractUsageAt(usages, 3, 5)
    assert BindingMapContractUsageAt(usages, 7, 12)

    // NOT IN THE DELETED FILE: the LENGTH recorded with each usage is carried, which is what an
    // editor highlights, and the file too.
    for usage in usages {
        assert usage.Length == 4
        assert usage.File == "test.nl"
    }
}

// Successor to GetReferences_ReturnsEmpty_ForDeclarationWithNoUsages.
test "binding map returns no usages for a declaration nothing references" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("unused", "test.nl", 1, 1, "variable")

    bindings.RecordDeclaration(declaration)

    assert bindings.GetReferences(declaration).Count == 0
}

// NOT IN THE DELETED FILE. Two refusals it never asked for: a `null` declaration answers an EMPTY
// list rather than throwing, and a declaration this map never saw answers empty too.
test "binding map returns no usages for a null or unknown declaration" {
    bindings := new BindingMap()
    bindings.RecordBinding("test.nl", 3, 5, 1, BindingMapContractDeclaration("x", 1, 5))

    assert bindings.GetReferences(null).Count == 0
    assert bindings.GetReferences(BindingMapContractDeclaration("other", 40, 40)).Count == 0
}

// NOT IN THE DELETED FILE. References are found through an EQUAL but distinct declaration object —
// the language server rebuilds its `SymbolDeclaration` from a position rather than holding the
// analyser's instance, so identity is not available to it.
test "binding map finds usages through an equal but distinct declaration" {
    bindings := new BindingMap()
    stored := new SymbolDeclaration("total", "test.nl", 2, 5, "variable")
    bindings.RecordBinding("test.nl", 5, 10, 5, stored)

    rebuilt := new SymbolDeclaration("total", "test.nl", 2, 5, "variable")

    assert rebuilt.Equals(stored)
    assert rebuilt.GetHashCode() == stored.GetHashCode()
    assert bindings.GetReferences(rebuilt).Count == 1
}

// Successor to FindAllReferences_FromUsagePosition_FindsDeclarationAndAllUsages.
test "binding map finds all references from a usage position" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("total", "test.nl", 2, 5, "variable")

    bindings.RecordDeclaration(declaration)
    bindings.RecordBinding("test.nl", 5, 10, 5, declaration)
    bindings.RecordBinding("test.nl", 8, 3, 5, declaration)

    result := bindings.FindAllReferences("test.nl", 5, 10)

    assert result.Declaration != null
    if result.Declaration != null {
        assert result.Declaration.Name == "total"
    }

    assert result.Usages.Count == 2

    // NOT IN THE DELETED FILE: it is the two RECORDED usages that come back, not any two.
    assert BindingMapContractUsageAt(result.Usages, 5, 10)
    assert BindingMapContractUsageAt(result.Usages, 8, 3)
}

// Successor to FindAllReferences_FromDeclarationPosition_FindsAllUsages.
test "binding map finds all references from the declaration position" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("total", "test.nl", 2, 5, "variable")

    bindings.RecordDeclaration(declaration)
    bindings.RecordBinding("test.nl", 5, 10, 5, declaration)

    result := bindings.FindAllReferences("test.nl", 2, 5)

    assert result.Declaration != null
    if result.Declaration != null {
        assert result.Declaration.Name == "total"
    }

    assert result.Usages.Count == 1
}

// Successor to FindAllReferences_NoBinding_ReturnsNullDeclaration.
test "binding map answers a null declaration when nothing is bound" {
    bindings := new BindingMap()

    result := bindings.FindAllReferences("test.nl", 99, 99)

    assert result.Declaration == null
    assert result.Usages.Count == 0
}

// NOT IN THE DELETED FILE. `FindAllReferences` does not need to land on the declaration's exact
// column: anywhere INSIDE the declared name answers it, the nearest declaration on the same line
// answers when nothing contains the column, and a different LINE answers nothing at all.
test "binding map finds a declaration near a position on the same line" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("counter", "test.nl", 4, 5, "variable")
    bindings.RecordDeclaration(declaration)

    inside := bindings.FindAllReferences("test.nl", 4, 9)
    assert inside.Declaration != null
    if inside.Declaration != null {
        assert inside.Declaration.Name == "counter"
    }

    lastCharacter := bindings.FindAllReferences("test.nl", 4, 11)
    assert lastCharacter.Declaration != null

    justPast := bindings.FindAllReferences("test.nl", 4, 40)
    assert justPast.Declaration != null

    otherLine := bindings.FindAllReferences("test.nl", 5, 5)
    assert otherLine.Declaration == null
}

// ---- Independence of same-named declarations -------------------------------------------------

// Successor to Bindings_SameNameDifferentPositions_AreIndependent.
test "binding map keeps same-named declarations at different positions independent" {
    bindings := new BindingMap()
    outer := new SymbolDeclaration("x", "test.nl", 2, 5, "variable")
    inner := new SymbolDeclaration("x", "test.nl", 5, 9, "variable")

    bindings.RecordDeclaration(outer)
    bindings.RecordDeclaration(inner)
    bindings.RecordBinding("test.nl", 3, 5, 1, outer)
    bindings.RecordBinding("test.nl", 6, 9, 1, inner)

    outerResult := bindings.GetBindingAt("test.nl", 3, 5)
    innerResult := bindings.GetBindingAt("test.nl", 6, 9)

    assert outerResult != null
    assert innerResult != null
    if outerResult != null {
        assert outerResult.Line == 2
    }
    if innerResult != null {
        assert innerResult.Line == 5
    }
}

// Successor to GetReferences_InnerScope_DoesNotLeakToOuter.
test "binding map keeps inner scope references out of the outer scope" {
    bindings := new BindingMap()
    outer := new SymbolDeclaration("x", "test.nl", 1, 5, "variable")
    inner := new SymbolDeclaration("x", "test.nl", 4, 9, "variable")

    bindings.RecordDeclaration(outer)
    bindings.RecordDeclaration(inner)
    bindings.RecordBinding("test.nl", 2, 5, 1, outer)
    bindings.RecordBinding("test.nl", 5, 9, 1, inner)

    outerUsages := bindings.GetReferences(outer)
    innerUsages := bindings.GetReferences(inner)

    assert outerUsages.Count == 1
    assert outerUsages[0].Line == 2

    assert innerUsages.Count == 1
    assert innerUsages[0].Line == 5
}

// ---- Overwriting ----------------------------------------------------------------------------

// Successor to RecordBinding_OverwriteAtSamePosition_UsesLatestBinding.
test "binding map uses the latest binding when a position is overwritten" {
    bindings := new BindingMap()
    oldDeclaration := new SymbolDeclaration("oldX", "test.nl", 1, 5, "variable")
    newDeclaration := new SymbolDeclaration("newX", "test.nl", 3, 5, "variable")

    bindings.RecordBinding("test.nl", 5, 10, 1, oldDeclaration)
    bindings.RecordBinding("test.nl", 5, 10, 1, newDeclaration)

    result := bindings.GetBindingAt("test.nl", 5, 10)
    assert result != null
    if result != null {
        assert result.Name == "newX"
    }

    assert BindingMapContractUsageAt(bindings.GetReferences(newDeclaration), 5, 10)
    assert !BindingMapContractUsageAt(bindings.GetReferences(oldDeclaration), 5, 10)

    // NOT IN THE DELETED FILE: the overwrite MOVES one usage and does not grow the map — the
    // binding count stays at one — and it withdraws only that position.
    assert bindings.BindingCount == 1
    assert bindings.GetReferences(oldDeclaration).Count == 0
}

// NOT IN THE DELETED FILE. The withdrawal is surgical: an old declaration keeps every OTHER usage
// it had, so re-binding one occurrence of a shadowed name does not empty its reference list.
test "binding map keeps the other usages of an overwritten declaration" {
    bindings := new BindingMap()
    oldDeclaration := new SymbolDeclaration("oldX", "test.nl", 1, 5, "variable")
    newDeclaration := new SymbolDeclaration("newX", "test.nl", 3, 5, "variable")

    bindings.RecordBinding("test.nl", 5, 10, 1, oldDeclaration)
    bindings.RecordBinding("test.nl", 6, 10, 1, oldDeclaration)
    bindings.RecordBinding("test.nl", 5, 10, 1, newDeclaration)

    oldUsages := bindings.GetReferences(oldDeclaration)
    assert oldUsages.Count == 1
    assert BindingMapContractUsageAt(oldUsages, 6, 10)
    assert !BindingMapContractUsageAt(oldUsages, 5, 10)
    assert bindings.BindingCount == 2
}

// Successor to RecordDeclaration_TypeDeclaration_NotOverwrittenByThis.
test "binding map keeps a type declaration when this is recorded at the same position" {
    bindings := new BindingMap()
    typeDeclaration := new SymbolDeclaration("Person", "test.nl", 1, 1, "class")
    thisDeclaration := new SymbolDeclaration("this", "test.nl", 1, 1, "variable")

    bindings.RecordDeclaration(typeDeclaration)
    bindings.RecordDeclaration(thisDeclaration)

    result := bindings.GetBindingAt("test.nl", 1, 1)

    assert result != null
    if result != null {
        assert result.Name == "Person"
        assert result.Kind == "class"
    }
}

// NOT IN THE DELETED FILE. The guard's other three quadrants: `value` is internal too; the guard
// needs a TYPE on the existing side, so an ordinary declaration IS overwritten by `this`; and an
// ordinary NAME still overwrites a type, because only synthesised names are held back.
test "binding map holds back only internal names over a type declaration" {
    valueOverType := new BindingMap()
    valueOverType.RecordDeclaration(new SymbolDeclaration("Person", "test.nl", 1, 1, "class"))
    valueOverType.RecordDeclaration(new SymbolDeclaration("value", "test.nl", 1, 1, "variable"))
    kept := valueOverType.GetBindingAt("test.nl", 1, 1)
    assert kept != null
    if kept != null {
        assert kept.Name == "Person"
    }

    thisOverVariable := new BindingMap()
    thisOverVariable.RecordDeclaration(new SymbolDeclaration("x", "test.nl", 1, 1, "variable"))
    thisOverVariable.RecordDeclaration(new SymbolDeclaration("this", "test.nl", 1, 1, "variable"))
    replaced := thisOverVariable.GetBindingAt("test.nl", 1, 1)
    assert replaced != null
    if replaced != null {
        assert replaced.Name == "this"
    }

    nameOverType := new BindingMap()
    nameOverType.RecordDeclaration(new SymbolDeclaration("Person", "test.nl", 1, 1, "class"))
    nameOverType.RecordDeclaration(new SymbolDeclaration("Renamed", "test.nl", 1, 1, "class"))
    overwritten := nameOverType.GetBindingAt("test.nl", 1, 1)
    assert overwritten != null
    if overwritten != null {
        assert overwritten.Name == "Renamed"
    }
}

// NOT IN THE DELETED FILE. Every kind the type guard recognises, and two it must not: the arm is a
// fixed list of seven declaration kinds, and `function`/`variable` are not among them.
test "binding map classifies every type declaration kind" {
    assert BindingMap.IsTypeDeclaration("class")
    assert BindingMap.IsTypeDeclaration("struct")
    assert BindingMap.IsTypeDeclaration("record")
    assert BindingMap.IsTypeDeclaration("soaRecord")
    assert BindingMap.IsTypeDeclaration("interface")
    assert BindingMap.IsTypeDeclaration("enum")
    assert BindingMap.IsTypeDeclaration("union")
    assert !BindingMap.IsTypeDeclaration("function")
    assert !BindingMap.IsTypeDeclaration("variable")
    assert !BindingMap.IsTypeDeclaration("Class")

    assert BindingMap.IsInternalDeclaration("this")
    assert BindingMap.IsInternalDeclaration("value")
    assert !BindingMap.IsInternalDeclaration("This")
    assert !BindingMap.IsInternalDeclaration("x")
}

// ---- Merge ----------------------------------------------------------------------------------

// Successor to Merge_CombinesDeclarationsFromBothMaps.
test "binding map merges declarations from both maps" {
    first := new BindingMap()
    second := new BindingMap()

    first.RecordDeclaration(new SymbolDeclaration("Foo", "a.nl", 1, 1, "class"))
    second.RecordDeclaration(new SymbolDeclaration("Bar", "b.nl", 1, 1, "class"))

    first.Merge(second)

    assert first.AllDeclarations.Count == 2
    assert BindingMapContractNames(first.AllDeclarations) == "Foo|Bar|"

    // NOT IN THE DELETED FILE: the merge is ONE-WAY — the source map is not grown by it.
    assert second.AllDeclarations.Count == 1
}

// Successor to Merge_CombinesBindingsAndReferences.
test "binding map merges bindings and references" {
    first := new BindingMap()
    second := new BindingMap()

    declaration := new SymbolDeclaration("shared", "a.nl", 1, 1, "variable")
    first.RecordDeclaration(declaration)
    first.RecordBinding("a.nl", 3, 5, 6, declaration)
    second.RecordBinding("b.nl", 2, 3, 6, declaration)

    first.Merge(second)

    usages := first.GetReferences(declaration)

    assert usages.Count == 2

    files := BindingMapContractFiles(usages)
    assert files.Contains("a.nl|")
    assert files.Contains("b.nl|")

    // NOT IN THE DELETED FILE: the merged BINDING is reachable by its own position too, which
    // "the reference list has two entries" cannot prove.
    merged := first.GetBindingAt("b.nl", 2, 3)
    assert merged != null
    if merged != null {
        assert merged.Name == "shared"
    }

    assert first.BindingCount == 2
}

// NOT IN THE DELETED FILE. `Version` is what the language server invalidates on. Every recording
// bumps it, a merge that carries something bumps it exactly once, and a merge of an EMPTY map does
// not bump it at all.
test "binding map versions every change and only real ones" {
    bindings := new BindingMap()
    assert bindings.Version == 0

    bindings.RecordDeclaration(BindingMapContractDeclaration("x", 1, 1))
    assert bindings.Version == 1

    bindings.RecordBinding("test.nl", 3, 1, 1, BindingMapContractDeclaration("x", 1, 1))
    assert bindings.Version == 2

    bindings.Merge(new BindingMap())
    assert bindings.Version == 2

    carrier := new BindingMap()
    carrier.RecordDeclaration(BindingMapContractDeclaration("y", 9, 1))
    bindings.Merge(carrier)
    assert bindings.Version == 3
}

// ---- Counting and files ----------------------------------------------------------------------

// Successor to BindingCount_ReflectsNumberOfRecordedBindings.
test "binding map counts recorded bindings" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("x", "test.nl", 1, 1, "variable")

    assert bindings.BindingCount == 0

    bindings.RecordBinding("test.nl", 3, 5, 1, declaration)
    assert bindings.BindingCount == 1

    bindings.RecordBinding("test.nl", 5, 5, 1, declaration)
    assert bindings.BindingCount == 2
}

// Successor to RecordBinding_CrossFile_ResolvesToCorrectDeclaration.
test "binding map resolves a cross file binding" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("Person", "models.nl", 1, 1, "class")

    bindings.RecordDeclaration(declaration)
    bindings.RecordBinding("program.nl", 5, 10, 6, declaration)

    result := bindings.GetBindingAt("program.nl", 5, 10)

    assert result != null
    if result != null {
        assert result.Name == "Person"
        assert result.File == "models.nl"
    }
}

// NOT IN THE DELETED FILE. The loose file match, one arm at a time: identical paths, a `null` on
// either side, a backslash spelling of the same path, and a plain suffix. This is the rule that
// lets the language server's absolute path meet the CLI's relative one.
test "binding map matches file paths loosely" {
    assert BindingMap.FilesMatch("a.nl", "a.nl")
    assert BindingMap.FilesMatch(null, "a.nl")
    assert BindingMap.FilesMatch("a.nl", null)
    assert BindingMap.FilesMatch(null, null)
    assert BindingMap.FilesMatch("src\\a.nl", "src/a.nl")
    assert BindingMap.FilesMatch("/repo/src/a.nl", "src/a.nl")
    assert BindingMap.FilesMatch("src/a.nl", "/repo/src/a.nl")
    assert !BindingMap.FilesMatch("a.nl", "b.nl")
    assert !BindingMap.FilesMatch("src/ab.nl", "b.nl")
}

// NOT IN THE DELETED FILE. `GetBindingAt` falls back to the FILE-LESS key when the caller named a
// file — the arm that makes a position recorded with no file findable — and the fallback is
// one-directional: a file-less query does not reach a file-keyed entry through it.
test "binding map falls back to the file-less key" {
    bindings := new BindingMap()
    bindings.RecordDeclaration(new SymbolDeclaration("Anywhere", null, 7, 3, "class"))

    fromFile := bindings.GetBindingAt("any.nl", 7, 3)
    assert fromFile != null
    if fromFile != null {
        assert fromFile.Name == "Anywhere"
    }

    assert bindings.GetBindingAt(null, 7, 3) != null
    assert bindings.GetBindingAt("any.nl", 7, 4) == null
}

// NOT IN THE DELETED FILE. The index key is TEXT, and the encoding is length-prefixed precisely so
// two different triples cannot spell the same key — the classic collision being a file whose name
// contains the separator, and a line/column pair that reads the same when concatenated.
test "binding map keys cannot collide across positions" {
    plain := BindingMap.KeyText(BindingMap.MakeBindingKey("a.nl", 1, 23))
    shifted := BindingMap.KeyText(BindingMap.MakeBindingKey("a.nl", 12, 3))
    fileLess := BindingMap.KeyText(BindingMap.MakeBindingKey(null, 1, 23))
    separatorInName := BindingMap.KeyText(BindingMap.MakeBindingKey("a|1", 1, 1))
    trickyPair := BindingMap.KeyText(BindingMap.MakeBindingKey("a", 11, 1))

    assert plain != shifted
    assert plain != fileLess
    assert separatorInName != trickyPair
    assert plain == BindingMap.KeyText(BindingMap.MakeBindingKey("a.nl", 1, 23))

    assert BindingMap.KeysEqual(BindingMap.MakeBindingKey("a.nl", 1, 2), BindingMap.MakeBindingKey("a.nl", 1, 2))
    assert !BindingMap.KeysEqual(BindingMap.MakeBindingKey("a.nl", 1, 2), BindingMap.MakeBindingKey("b.nl", 1, 2))
    assert !BindingMap.KeysEqual(BindingMap.MakeBindingKey("a.nl", 1, 2), BindingMap.MakeBindingKey("a.nl", 2, 2))
    assert !BindingMap.KeysEqual(BindingMap.MakeBindingKey("a.nl", 1, 2), BindingMap.MakeBindingKey("a.nl", 1, 3))
}

// NOT IN THE DELETED FILE. The two projections the language server reads the whole map through:
// `BindingEntries` pairs every usage position with its declaration, `DeclarationEntries` carries
// the declarations alone, and both are SNAPSHOTS — growing the map afterwards does not grow them.
test "binding map projects its entries" {
    bindings := new BindingMap()
    declaration := new SymbolDeclaration("x", "test.nl", 1, 5, "variable")
    bindings.RecordBinding("test.nl", 3, 10, 1, declaration)

    entries := bindings.BindingEntries
    assert entries.Count == 1
    assert BindingMapContractEntryText(entries) == "x@3:10|"

    declarationEntries := bindings.DeclarationEntries
    assert declarationEntries.Count == 1
    assert BindingMapContractNames(declarationEntries.Values) == "x|"

    bindings.RecordBinding("test.nl", 4, 10, 1, declaration)
    assert entries.Count == 1
    assert bindings.BindingEntries.Count == 2
}
