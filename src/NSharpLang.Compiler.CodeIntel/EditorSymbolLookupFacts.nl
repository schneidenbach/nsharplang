namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic

// WHICH NAME IN THE EDITOR'S SYMBOL TABLES IS A CALLABLE ONE, AND WHICH ENTRY ANSWERS FOR IT.
//
// The call-hierarchy handlers used to ask these questions three times, inline, against the two
// tables `DocumentManager` keeps — a name-to-`SymbolInfo` map and a name-to-`SymbolLocation` list.
// Each site spelled the same two decisions slightly differently: what counts as callable, and
// which of several entries under one name is the one to stand on.
//
// THE KIND IS PASSED AS `EditorSymbolTableKind`, the owner that already names every symbol kind
// the editor's tables can hold, so nothing here learns what an LSP `SymbolKind` number is. The
// handler maps the two enums at its own edge, exactly as it already does when it FILLS the tables.
class EditorSymbolLookupFacts {

    // CALLABLE MEANS A FUNCTION OR A METHOD, and nothing else. A property with a getter is not a
    // call-hierarchy node in this server, and never has been.
    static func IsCallable(kind: EditorSymbolTableKind): bool {
        if kind == EditorSymbolTableKind.Function {
            return true
        }

        return kind == EditorSymbolTableKind.Method
    }

    // THE FIRST CALLABLE ENTRY UNDER A NAME, as an INDEX into the caller's kinds, or -1.
    //
    // FIRST, not best: the tables are filled in declaration order, so the first callable entry is
    // the earliest declaration, which is the node the editor has always opened.
    static func FirstCallableIndex(kinds: List<EditorSymbolTableKind>): int {
        index := 0
        while index < kinds.Count {
            if IsCallable(kinds[index]) {
                return index
            }

            index = index + 1
        }

        return -1
    }

    // WHETHER A NAME IS A CALLABLE SYMBOL, over the TWO tables in the order the handler consults
    // them.
    //
    // THE ORDER IS THE DECISION AND IT IS NOT A FALLBACK CHAIN. The typed table is authoritative
    // WHEN IT HAS THE NAME: a name it holds as a `Property` is not callable, and the location
    // table must not be asked a second time to overturn that. Only a name the typed table does
    // NOT hold falls through to the locations, which is the tier that answers for a buffer whose
    // symbol info was never built.
    //
    // WHETHER THE TYPED TABLE HOLDS THE NAME IS ITS OWN PARAMETER rather than a nullable kind,
    // because the two questions really are separate — "is it there" and "what is it" — and a
    // caller that answers the first with `false` is saying nothing at all about the second.
    static func IsCallableSymbol(typedTableHasName: bool, typedKind: EditorSymbolTableKind, locationKinds: List<EditorSymbolTableKind>?): bool {
        if typedTableHasName {
            return IsCallable(typedKind)
        }

        if locationKinds == null {
            return false
        }

        return FirstCallableIndex(locationKinds) >= 0
    }

    // WHICH DOCUMENT'S TABLE ANSWERS FOR A CALLEE: the origin document first, then the workspace.
    //
    // The origin's own entry wins even when a workspace-wide search would find another, because a
    // call inside a file most often means that file's own declaration, and following the workspace
    // first would jump the reader out of the buffer they are reading. The caller asks the two
    // tiers in that order and STOPS at the first answer — the workspace tier walks every open
    // document, so a callee the origin places must not pay for it.

    // THE HIGHLIGHT A SYMBOL LOCATION NAMES, in the protocol's 0-based coordinates.
    //
    // A recorded length of zero or less would collapse the range onto a caret, which no editor
    // renders, so the width is at least one character — the shipped `Math.Max(1, Length)`.
    static func SelectionWidth(length: int): int {
        if length < 1 {
            return 1
        }

        return length
    }
}
