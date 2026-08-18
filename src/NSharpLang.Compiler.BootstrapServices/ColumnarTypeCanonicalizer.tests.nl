namespace NSharpLang.Compiler.Columnar

import System


// THE CANONICAL CONTRACTS FOR `ColumnarTypeCanonicalizer`, IN N#.
//
// These replace the four non-emit cases of `tests/ColumnarTypeCanonicalizerTests.cs` (102 lines).
// The kernel normalises the TEXT of a declared type before the columnar registry looks it up: it
// strips a namespace prefix, removes whitespace, and separates a named tuple's element names from
// its structural spelling. Four N# production owners consult it (`ColumnarSemanticTypeRegistry`,
// `ColumnarConstructionPlanner`, `ColumnarTypeOfPlanner`, `ColumnarBindingScopeFacts`) plus the C#
// `ColumnarIlEmitter`. The two emit cases of the deleted file live in
// `tests/native/columnar-emit-facts`.
//
// THE FIVE THINGS THAT ARE EASY TO GET WRONG:
//
// (1) `UnqualifiedTypeName` IS NOT GENERIC-AWARE, AND CALLING IT ON A GENERIC SPELLING IS A BUG AT
// THE CALL SITE, NOT HERE. It takes everything after the LAST `.` anywhere in the string, so
// `List<Models.Point>` answers `Point>` — with the closing bracket. That is stated below as a
// contract rather than left as a trap, because the honest boundary of a helper is part of it.
//
// (2) A TRAILING DOT IS RETURNED WHOLE. `"Models."` has a last dot but nothing after it, so the
// guard `lastDot + 1 < name.Length` fails and the input comes back unchanged — the one row of the
// deleted table that was not an obvious identity.
//
// (3) `StripTupleElementNames` STRIPS ONLY THE TOP LEVEL, AND THE DELETED C# NEVER PROVED IT. Its
// "removes only top level names" case passed `"(x:List<int>,y:(string,int[]))"`, whose INNER tuple
// has no names at all — so the claim in its own name was vacuous. The successor passes an inner
// tuple that DOES carry names and states that they survive verbatim.
//
// (4) THE NAMES ARRAY IS SPARSE, NOT DENSE. A partially named tuple such as `"(x:int,string)"`
// yields a names array of the tuple's full LENGTH whose unnamed slots are NULL. A consumer that
// assumes every slot is populated reads a null.
//
// (5) AN UNNAMED TUPLE HANDS BACK THE ORIGINAL STRING AND A NULL NAMES ARRAY — not an empty array,
// and not a rebuilt-but-equal string. `Names == null` is the flag that says "nothing was stripped".

// ---- UnqualifiedTypeName -------------------------------------------------------------------------

// Successor to UnqualifiedTypeName_StripsNamespacePrefix — all five of its rows.
test "the unqualified type name is everything after the last dot" {
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("Models.Point") == "Point"
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("QueryTypeUse.Foo.Widget") == "Widget"
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("Point") == "Point"
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("Models.") == "Models."
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("") == ""
}

// The boundary the deleted rows did not state: the helper is textual, not structural.
test "the unqualified type name is textual and not generic aware" {
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("List<Models.Point>") == "Point>"
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName("a.b.c.d") == "d"
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName(".") == "."
    assert ColumnarTypeCanonicalizer.UnqualifiedTypeName(".Point") == "Point"
}

// ---- RemoveWhitespace ----------------------------------------------------------------------------

// Successor to RemoveWhitespace_StripsDeclaredTypeSpan — its one assertion.
test "removing whitespace collapses a declared type span" {
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("Func<int, (string, int[])>") == "Func<int,(string,int[])>"
}

// Every whitespace character the kernel is asked about, not only the space the deleted case used.
test "removing whitespace removes tabs newlines and returns as well as spaces" {
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("int\tstring") == "intstring"
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("int\nstring") == "intstring"
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("int\r\nstring") == "intstring"
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("  int  ") == "int"
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("int") == "int"
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("") == ""
    assert ColumnarTypeCanonicalizer.RemoveWhitespace("   ") == ""
}

// ---- StripTupleElementNames ----------------------------------------------------------------------

// Successor to StripTupleElementNames_RemovesOnlyTopLevelNames — all three of its assertions.
test "stripping tuple element names removes the top level names and reports them in order" {
    result := ColumnarTypeCanonicalizer.StripTupleElementNames("(x:List<int>,y:(string,int[]))")
    assert result.Canonical == "(List<int>,(string,int[]))"

    names := result.Names
    assert names != null
    assert names.Length == 2
    assert names[0] == "x"
    assert names[1] == "y"
}

// The claim the deleted case's NAME made and its fixture could not: an inner tuple's names survive.
test "stripping tuple element names leaves a nested tuples own names in place" {
    result := ColumnarTypeCanonicalizer.StripTupleElementNames("(x:List<int>,y:(a:string,b:int[]))")
    assert result.Canonical == "(List<int>,(a:string,b:int[]))"

    names := result.Names
    assert names != null
    assert names.Length == 2
    assert names[0] == "x"
    assert names[1] == "y"
}

// Successor to StripTupleElementNames_LeavesPositionalTupleUnchanged — both of its assertions.
test "a positional tuple is returned unchanged with no names" {
    result := ColumnarTypeCanonicalizer.StripTupleElementNames("(int,(string,int[]))")
    assert result.Canonical == "(int,(string,int[]))"
    assert result.Names == null
}

// The sparse-array fact: an unnamed slot in a partly named tuple is NULL, not blank.
test "a partly named tuple reports a names array with a null in the unnamed slot" {
    result := ColumnarTypeCanonicalizer.StripTupleElementNames("(x:int,string)")
    assert result.Canonical == "(int,string)"

    names := result.Names
    assert names != null
    assert names.Length == 2
    assert names[0] == "x"
    assert names[1] == null
}

// Anything that is not parenthesised is handed straight back, names and all.
test "a non tuple spelling is returned untouched with no names" {
    plain := ColumnarTypeCanonicalizer.StripTupleElementNames("Models.Point")
    assert plain.Canonical == "Models.Point"
    assert plain.Names == null

    empty := ColumnarTypeCanonicalizer.StripTupleElementNames("")
    assert empty.Canonical == ""
    assert empty.Names == null

    generic := ColumnarTypeCanonicalizer.StripTupleElementNames("Func<int,string>")
    assert generic.Canonical == "Func<int,string>"
    assert generic.Names == null
}

// A colon that is not preceded by a bare identifier is not an element name. This is what keeps a
// nested generic or an already-stripped spelling from being mangled.
test "a colon that no bare identifier precedes is not an element name" {
    numeric := ColumnarTypeCanonicalizer.StripTupleElementNames("(1x:int,string)")
    assert numeric.Canonical == "(1x:int,string)"
    assert numeric.Names == null

    qualified := ColumnarTypeCanonicalizer.StripTupleElementNames("(a.b:int,string)")
    assert qualified.Canonical == "(a.b:int,string)"
    assert qualified.Names == null
}

// ---- the two helpers the deleted file never reached -----------------------------------------------

// `SplitTopLevelCommas` is what makes "top level" mean anything: it counts `(`, `<` and `[` as
// openers and their partners as closers, so a comma inside any of the three is not a separator.
test "splitting on top-level commas ignores commas nested in brackets angles or parens" {
    parts := ColumnarTypeCanonicalizer.SplitTopLevelCommas("int,Func<int,string>,(a,b),int[]")
    assert parts.Count == 4
    assert parts[0] == "int"
    assert parts[1] == "Func<int,string>"
    assert parts[2] == "(a,b)"
    assert parts[3] == "int[]"
}

// The empty and single-element cases both answer ONE part, which is why an unnamed one-element
// spelling round-trips rather than vanishing.
test "splitting on top-level commas always reports at least one part" {
    single := ColumnarTypeCanonicalizer.SplitTopLevelCommas("int")
    assert single.Count == 1
    assert single[0] == "int"

    empty := ColumnarTypeCanonicalizer.SplitTopLevelCommas("")
    assert empty.Count == 1
    assert empty[0] == ""

    trailing := ColumnarTypeCanonicalizer.SplitTopLevelCommas("int,")
    assert trailing.Count == 2
    assert trailing[0] == "int"
    assert trailing[1] == ""
}

// `IsBareIdentifier` is the gate that decides whether a colon introduces an element NAME.
test "a bare identifier is letters digits and underscores that do not start with a digit" {
    assert ColumnarTypeCanonicalizer.IsBareIdentifier("x")
    assert ColumnarTypeCanonicalizer.IsBareIdentifier("x1")
    assert ColumnarTypeCanonicalizer.IsBareIdentifier("_x")
    assert ColumnarTypeCanonicalizer.IsBareIdentifier("_")
    assert ColumnarTypeCanonicalizer.IsBareIdentifier("Item1")

    assert !ColumnarTypeCanonicalizer.IsBareIdentifier("")
    assert !ColumnarTypeCanonicalizer.IsBareIdentifier("1x")
    assert !ColumnarTypeCanonicalizer.IsBareIdentifier("a.b")
    assert !ColumnarTypeCanonicalizer.IsBareIdentifier("List<int>")
    assert !ColumnarTypeCanonicalizer.IsBareIdentifier("a b")
}
