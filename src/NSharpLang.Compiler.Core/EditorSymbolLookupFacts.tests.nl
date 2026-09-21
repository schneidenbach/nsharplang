namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

class EditorSymbolLookupFixture {
    static func Kinds(values: EditorSymbolTableKind[]): List<EditorSymbolTableKind> {
        list := new List<EditorSymbolTableKind>()
        index := 0
        while index < values.Length {
            list.Add(values[index])
            index = index + 1
        }

        return list
    }
}

test "callable means a function or a method, and nothing else" {
    assert EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.Function)
    assert EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.Method)

    assert !EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.Property)
    assert !EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.Class)
    assert !EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.Field)
    assert !EditorSymbolLookupFacts.IsCallable(EditorSymbolTableKind.LocalVariable)
}

test "the first callable entry under a name is the earliest declaration" {
    kinds := EditorSymbolLookupFixture.Kinds([
        EditorSymbolTableKind.Property,
        EditorSymbolTableKind.Method,
        EditorSymbolTableKind.Function
    ])

    assert EditorSymbolLookupFacts.FirstCallableIndex(kinds) == 1
}

test "a name with no callable entry has no index" {
    kinds := EditorSymbolLookupFixture.Kinds([
        EditorSymbolTableKind.Property,
        EditorSymbolTableKind.Field
    ])

    assert EditorSymbolLookupFacts.FirstCallableIndex(kinds) == -1
    assert EditorSymbolLookupFacts.FirstCallableIndex(new List<EditorSymbolTableKind>()) == -1
}

// THE TYPED TABLE IS AUTHORITATIVE WHEN IT HAS THE NAME. This is the half a fallback chain would
// get wrong: a name the typed table holds as a PROPERTY is not callable, and the location table
// must not be asked a second time to overturn that.
test "a name the typed table calls a property is not callable, whatever the locations say" {
    locations := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Function])

    assert !EditorSymbolLookupFacts.IsCallableSymbol(true, EditorSymbolTableKind.Property, locations)
}

test "a name the typed table calls a function is callable" {
    assert EditorSymbolLookupFacts.IsCallableSymbol(true, EditorSymbolTableKind.Function, null)
    assert EditorSymbolLookupFacts.IsCallableSymbol(true, EditorSymbolTableKind.Method, null)
}

// ONLY A NAME THE TYPED TABLE DOES NOT HOLD falls through to the locations — the tier that answers
// for a buffer whose symbol info was never built.
test "a name missing from the typed table is decided by its locations" {
    callable := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Field, EditorSymbolTableKind.Method])
    inert := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Field])

    assert EditorSymbolLookupFacts.IsCallableSymbol(false, EditorSymbolTableKind.Class, callable)
    assert !EditorSymbolLookupFacts.IsCallableSymbol(false, EditorSymbolTableKind.Class, inert)
}

test "a name in neither table is not callable" {
    assert !EditorSymbolLookupFacts.IsCallableSymbol(false, EditorSymbolTableKind.Class, null)
    assert !EditorSymbolLookupFacts.IsCallableSymbol(false, EditorSymbolTableKind.Class, new List<EditorSymbolTableKind>())
}

// THE ORIGIN DOCUMENT IS ASKED FIRST AND ITS ANSWER STANDS, so a call inside a file opens that
// file's own declaration rather than jumping the reader out of the buffer they are reading — and
// the workspace walk, which visits every open document, is never paid for when the origin places
// the callee.
test "the origin tier answers on its own when it holds a callable entry" {
    origin := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Class, EditorSymbolTableKind.Function])

    assert EditorSymbolLookupFacts.FirstCallableIndex(origin) == 1
}

test "the origin tier declines, and only then is the workspace tier asked" {
    origin := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Property])
    workspace := EditorSymbolLookupFixture.Kinds([EditorSymbolTableKind.Class, EditorSymbolTableKind.Method])

    assert EditorSymbolLookupFacts.FirstCallableIndex(origin) == -1
    assert EditorSymbolLookupFacts.FirstCallableIndex(workspace) == 1
}

// A ZERO-WIDTH HIGHLIGHT IS A CARET, WHICH NO EDITOR RENDERS. The shipped floor is one character.
test "a recorded length below one still highlights one character" {
    assert EditorSymbolLookupFacts.SelectionWidth(0) == 1
    assert EditorSymbolLookupFacts.SelectionWidth(-3) == 1
}

test "a real recorded length is used as it stands" {
    assert EditorSymbolLookupFacts.SelectionWidth(1) == 1
    assert EditorSymbolLookupFacts.SelectionWidth(12) == 12
}
