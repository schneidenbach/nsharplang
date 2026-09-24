namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE WRITING HALF OF THE FRIEND RULE, pinned where it is decided.
//
// What an EMITTED assembly's metadata actually carries, and a friend consumer actually running
// against it, is asserted in `tests/native/census-internals-visible-to`. What is asserted here is
// everything that does not need an emitted assembly: which declared spellings become rows, which
// are dropped, and that the attribute and blob this owner writes are the ones a reader reads.
func IvtEmitDeclared(values: string?[]): List<string> {
    declared := new List<string>()
    index := 0
    while index < values.Length {
        declared.Add(values[index] ?? "")
        index = index + 1
    }

    return ColumnarInternalsVisibleToEmitter.ResolveDeclaredNames(declared)
}

func IvtEmitJoin(names: List<string>): string {
    joined := ""
    index := 0
    while index < names.Count {
        if index > 0 {
            joined = joined + "|"
        }

        joined = joined + names[index]
        index = index + 1
    }

    return joined
}

func IvtEmitBlobText(blob: byte[]): string {
    text := ""
    index := 0
    while index < blob.Length {
        if index > 0 {
            text = text + " "
        }

        text = text + Convert.ToInt32(blob[index]).ToString()
        index = index + 1
    }

    return text
}

// A DECLARED GRANT IS WRITTEN AS THE DEVELOPER SPELLED IT, minus surrounding whitespace. The
// strong-name key after a comma is PART of the display name and is kept; only the reader
// (`InternalsVisibleToGrants.FriendSimpleName`) narrows to the simple name in front of it.
test "a declared grant keeps its display name and loses only its surrounding whitespace" {
    assert InternalsVisibleToGrants.NormalizeDeclaredName("Tests") == "Tests"
    assert InternalsVisibleToGrants.NormalizeDeclaredName("  Tests\t") == "Tests"
    assert InternalsVisibleToGrants.NormalizeDeclaredName("Tests, PublicKey=0024") == "Tests, PublicKey=0024"
    assert InternalsVisibleToGrants.NormalizeDeclaredName(null) == ""
}

// AN ENTRY THAT NAMES NO ASSEMBLY IS NOT A GRANT. It would emit a row whose argument the reader's
// own simple-name rule can never match, so the project file refuses it rather than emitting it.
test "an entry with no simple name in front of the comma is not a usable grant" {
    assert InternalsVisibleToGrants.IsUsableDeclaredName("Tests")
    assert InternalsVisibleToGrants.IsUsableDeclaredName("  Contoso.Widgets.Tests, PublicKey=0024  ")

    assert !InternalsVisibleToGrants.IsUsableDeclaredName(null)
    assert !InternalsVisibleToGrants.IsUsableDeclaredName("")
    assert !InternalsVisibleToGrants.IsUsableDeclaredName("   ")
    assert !InternalsVisibleToGrants.IsUsableDeclaredName(", PublicKey=0024")
}

// THE ROWS, IN PROJECT ORDER. A repeated SIMPLE name is one permission however many times it is
// written — the reader stops at the first match — so the duplicate is dropped instead of writing a
// second identical metadata row. Case does not distinguish two grants, because assembly simple
// names do not compare by case.
test "the declared grants become rows in project order, once per simple name" {
    assert IvtEmitJoin(IvtEmitDeclared(["Tests"])) == "Tests"
    assert IvtEmitJoin(IvtEmitDeclared(["Beta", "Alpha"])) == "Beta|Alpha"
    assert IvtEmitJoin(IvtEmitDeclared(["  Tests  ", "Other"])) == "Tests|Other"

    assert IvtEmitJoin(IvtEmitDeclared(["Tests", "Tests"])) == "Tests"
    assert IvtEmitJoin(IvtEmitDeclared(["Tests", "TESTS"])) == "Tests"
    assert IvtEmitJoin(IvtEmitDeclared(["Tests", "Tests, PublicKey=0024"])) == "Tests"

    assert IvtEmitJoin(IvtEmitDeclared(["", "   ", ", PublicKey=0024"])) == ""
    assert ColumnarInternalsVisibleToEmitter.ResolveDeclaredNames(null).Count == 0
}

// THE ATTRIBUTE IS THE ONE THE READER READS. Both halves of the rule name the same type through
// `InternalsVisibleToGrants.InternalsVisibleToAttributeFullName`, so a writer and a reader that
// disagreed about the attribute would be a compile error rather than a silent mismatch.
test "the emitted attribute is InternalsVisibleToAttribute(string), the type the grant reader reads" {
    constructor := ColumnarInternalsVisibleToEmitter.AttributeConstructor()
    declaring := constructor.DeclaringType

    assert declaring != null
    assert declaring.FullName == InternalsVisibleToGrants.InternalsVisibleToAttributeFullName
    assert declaring.FullName == "System.Runtime.CompilerServices.InternalsVisibleToAttribute"

    parameters := constructor.GetParameters()
    assert parameters.Length == 1
    assert parameters[0].ParameterType == typeof(string)
}

// THE BLOB IS THE ONE-STRING SHAPE, BYTE FOR BYTE: prolog 0x0001, a SerString of the UTF-8 name,
// and a zero named-argument count. Nothing here is new — `ColumnarAttributeBlobs.OneString` is the
// same writer `[CompilerFeatureRequired]` uses — and pinning it means a friend row this compiler
// writes is readable by the reflection every consumer uses.
test "the grant is written as the pinned one-string attribute blob" {
    assert IvtEmitBlobText(ColumnarAttributeBlobs.OneString("Tests")) == "1 0 5 84 101 115 116 115 0 0"
    assert IvtEmitBlobText(ColumnarAttributeBlobs.OneString("")) == "1 0 0 0 0"
}
