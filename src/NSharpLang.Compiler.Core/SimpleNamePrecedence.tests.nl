namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// Contracts for the ONE owner of simple-name precedence. Both walks that resolve a bare type name —
// the analyzer's `VisibleTypeNamespaces` and the emitter's `ColumnarBindingScopeFacts` — read their
// namespace order from here, so what these tests pin is the order BOTH of them take.
func PrecedenceText(namespaces: List<string?>): string {
    text := ""
    index := 0
    while index < namespaces.Count {
        if index > 0 {
            text = text + ","
        }
        entry := namespaces[index]
        if entry == null {
            text = text + "<global>"
        } else {
            text = text + entry
        }
        index = index + 1
    }
    return text
}

func PrecedenceNameText(names: List<string>): string {
    text := ""
    index := 0
    while index < names.Count {
        if index > 0 {
            text = text + ","
        }
        entry := names[index]
        if entry.Length == 0 {
            text = text + "<global>"
        } else {
            text = text + entry
        }
        index = index + 1
    }
    return text
}

func PrecedenceImports(names: string[]): List<string> {
    imports := new List<string>()
    index := 0
    while index < names.Length {
        imports.Add(names[index])
        index = index + 1
    }
    return imports
}

test "the lexical chain climbs outward from the file's own namespace to the global one" {
    // A file that declares no namespace IS in the global namespace, and that is its whole chain.
    assert PrecedenceText(SimpleNamePrecedence.LexicalNamespaces(null)) == "<global>"
    assert PrecedenceText(SimpleNamePrecedence.LexicalNamespaces("")) == "<global>"

    // One segment: itself, then the global namespace that encloses it.
    assert PrecedenceText(SimpleNamePrecedence.LexicalNamespaces("App")) == "App,<global>"

    // Every enclosing namespace is a step, in order, and the global namespace is the last one. This
    // is the whole of C# §7.8's outward climb, and it is what makes an enclosing declaration win.
    assert PrecedenceText(
        SimpleNamePrecedence.LexicalNamespaces("App.Models.Internal")
    ) == "App.Models.Internal,App.Models,App,<global>"
}

test "a namespace is lexical when it encloses the file, and an import of it is not a rival" {
    assert SimpleNamePrecedence.IsLexicalNamespace("App.Models", "App.Models")
    assert SimpleNamePrecedence.IsLexicalNamespace("App.Models", "App")
    assert SimpleNamePrecedence.IsLexicalNamespace("App.Models", null)

    // A SIBLING or CHILD namespace is not lexical: `App.Ast` does not enclose `App.Models`, and
    // `App.Models.Deep` is inside it rather than around it. Those reach the file only by import, and
    // an import is what rule 3 arbitrates between.
    assert !SimpleNamePrecedence.IsLexicalNamespace("App.Models", "App.Ast")
    assert !SimpleNamePrecedence.IsLexicalNamespace("App.Models", "App.Models.Deep")

    // Matching is ordinal: a namespace that differs only in case is a different namespace.
    assert !SimpleNamePrecedence.IsLexicalNamespace("App.Models", "app")
    assert SimpleNamePrecedence.IsLexicalNamespace(null, null)
    assert !SimpleNamePrecedence.IsLexicalNamespace(null, "App")
}

test "the candidate list puts the whole lexical chain ahead of every import" {
    // THE RULE IN ONE LINE: own namespace, each enclosing one outward, the global namespace, then the
    // imports in import order.
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces("App.Models", PrecedenceImports(["System", "System.Text"]))
    ) == "App.Models,App,<global>,System,System.Text"

    // A file in the global namespace has a one-entry chain, and its imports follow it.
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces(null, PrecedenceImports(["System"]))
    ) == "<global>,System"

    // AN IMPORT OF A LEXICAL NAMESPACE KEEPS THE CHAIN'S POSITION, wherever it is written. Importing
    // your own or an enclosing namespace is redundant, not a way to reorder the rule.
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces("App.Models", PrecedenceImports(["App", "System"]))
    ) == "App.Models,App,<global>,System"
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces("App.Models", PrecedenceImports(["System", "App.Models"]))
    ) == "App.Models,App,<global>,System"

    // Duplicate imports collapse to their FIRST occurrence, which is what keeps the order stable.
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces("App", PrecedenceImports(["System", "System", "System.Text", "System"]))
    ) == "App,<global>,System,System.Text"

    // Deduplication is case-SENSITIVE, and an empty import name is a real (if useless) candidate
    // rather than being silently folded into the global namespace.
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces("Alpha", PrecedenceImports(["alpha", "ALPHA", "Alpha"]))
    ) == "Alpha,<global>,alpha,ALPHA"
    assert PrecedenceText(
        SimpleNamePrecedence.CandidateNamespaces(null, PrecedenceImports(["", "System"]))
    ) == "<global>,,System"
}

test "the enclosing-namespace list drops the file's own namespace and spells global as empty" {
    // The emitter's binding scope holds a namespace as a string, with `""` for the global one, and
    // every caller there has already asked about the file's OWN namespace.
    assert PrecedenceNameText(SimpleNamePrecedence.EnclosingNamespaceNames("App.Models.Internal")) == "App.Models,App,<global>"
    assert PrecedenceNameText(SimpleNamePrecedence.EnclosingNamespaceNames("App")) == "<global>"

    // A file already in the global namespace has nothing outside it.
    assert SimpleNamePrecedence.EnclosingNamespaceNames("").Count == 0
}

test "a written qualifier is expanded through the lexical chain, never through an import" {
    // `Ast.Node` inside `App.Models` can mean `App.Models.Ast.Node`, then `App.Ast.Node`, and finally
    // the absolute `Ast.Node` — the leftmost segment is looked up exactly as a simple name is.
    assert PrecedenceNameText(
        SimpleNamePrecedence.QualifierNamespaces("App.Models", "Ast")
    ) == "App.Models.Ast,App.Ast,Ast"

    // The written spelling is ALWAYS the last candidate, so an absolute qualifier still resolves.
    assert PrecedenceNameText(SimpleNamePrecedence.QualifierNamespaces(null, "App.Ast")) == "App.Ast"

    // A multi-segment qualifier is expanded whole, which is how `Models.Person` reaches
    // `App.Models.Person` from inside `App`.
    assert PrecedenceNameText(
        SimpleNamePrecedence.QualifierNamespaces("App", "Models.Deep")
    ) == "App.Models.Deep,Models.Deep"

    // A qualifier that already repeats the chain collapses rather than being offered twice.
    assert PrecedenceNameText(SimpleNamePrecedence.QualifierNamespaces("App", "App")) == "App.App,App"

    // Nothing written, nothing to expand.
    assert SimpleNamePrecedence.QualifierNamespaces("App", "").Count == 0
}
