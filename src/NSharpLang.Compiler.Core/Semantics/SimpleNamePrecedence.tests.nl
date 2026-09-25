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

// ── THE SELECTION: which namespace a name binds in, from per-namespace answers ──────────────────
//
// A selection is driven by its caller with one (source, metadata) answer per candidate. These rows
// answer from two tiny tables — the namespaces that declare the name in SOURCE and the ones whose
// referenced assemblies do — so what is pinned is the rule alone.
func PrecedenceDrive(selection: SimpleNameSelection, sourceNamespaces: string[], metadataNamespaces: string[]): string {
    asked := ""
    while !selection.IsSettled {
        candidate := selection.Current
        spelled := candidate.Namespace ?? "<global>"
        asked = asked + (asked.Length == 0 ? "" : ",") + spelled + (candidate.IsImport ? "(import)" : "")
        declaresSource := false
        for sourceNamespace in sourceNamespaces {
            if sourceNamespace == spelled {
                declaresSource = true
            }
        }
        declaresMetadata := false
        if !declaresSource {
            for metadataNamespace in metadataNamespaces {
                if metadataNamespace == spelled {
                    declaresMetadata = true
                }
            }
        }
        selection.Answer(declaresSource, declaresMetadata)
    }
    return asked
}

func PrecedenceOutcome(selection: SimpleNameSelection): string {
    kind := "not-found"
    if selection.Kind == SimpleNameSelectionKind.Source {
        kind = "source"
    } else if selection.Kind == SimpleNameSelectionKind.Metadata {
        kind = "metadata"
    } else if selection.Kind == SimpleNameSelectionKind.Ambiguous {
        kind = "ambiguous"
    }
    text := kind + ":" + (selection.Namespace ?? "<global>")
    if selection.FromImport {
        text = text + "(import)"
    }
    if selection.Kind == SimpleNameSelectionKind.Ambiguous {
        text = text + "|" + (selection.SecondNamespace ?? "<global>")
    }
    return text
}

test "a referenced assembly's type in an enclosing namespace outranks every import" {
    // `TypeInfo` inside `NSharpLang.Compiler.Columnar`, once `NSharpLang.Compiler` is another
    // assembly: the chain answers from metadata before `System.Reflection` is asked at all.
    selection := SimpleNamePrecedence.Select("NSharpLang.Compiler.Columnar", PrecedenceImports(["System.Reflection"]))
    asked := PrecedenceDrive(selection, [], ["NSharpLang.Compiler", "System.Reflection"])
    assert asked == "NSharpLang.Compiler.Columnar,NSharpLang.Compiler", asked
    assert PrecedenceOutcome(selection) == "metadata:NSharpLang.Compiler"
    assert selection.IsLexicalMetadata
}

test "a nearer namespace wins whichever assembly declares it, and at one namespace source wins" {
    // Metadata in the file's OWN namespace outranks source in an enclosing one.
    nearer := SimpleNamePrecedence.Select("App.Models", PrecedenceImports([]))
    PrecedenceDrive(nearer, ["App"], ["App.Models"])
    assert PrecedenceOutcome(nearer) == "metadata:App.Models"

    // Source in an enclosing namespace outranks metadata farther out and in the imports.
    farther := SimpleNamePrecedence.Select("App.Models", PrecedenceImports(["System"]))
    PrecedenceDrive(farther, ["App"], ["System"])
    assert PrecedenceOutcome(farther) == "source:App"
    assert !farther.IsLexicalMetadata

    // At ONE namespace both answer: the source declaration is the member.
    same := SimpleNamePrecedence.Select("App", PrecedenceImports([]))
    PrecedenceDrive(same, ["App"], ["App"])
    assert PrecedenceOutcome(same) == "source:App"
}

test "the import tier is one tier: two imports that supply the name tie in any mix and any order" {
    metadataPair := SimpleNamePrecedence.Select("App", PrecedenceImports(["Left", "Right"]))
    PrecedenceDrive(metadataPair, [], ["Left", "Right"])
    assert PrecedenceOutcome(metadataPair) == "ambiguous:Left(import)|Right"
    assert !metadataPair.FirstIsSource
    assert !metadataPair.SecondIsSource

    reversed := SimpleNamePrecedence.Select("App", PrecedenceImports(["Right", "Left"]))
    PrecedenceDrive(reversed, [], ["Left", "Right"])
    assert PrecedenceOutcome(reversed) == "ambiguous:Right(import)|Left"

    mixed := SimpleNamePrecedence.Select("App", PrecedenceImports(["Left", "Right"]))
    PrecedenceDrive(mixed, ["Right"], ["Left"])
    assert PrecedenceOutcome(mixed) == "ambiguous:Left(import)|Right"
    assert !mixed.FirstIsSource
    assert mixed.SecondIsSource

    // One import supplying it is the answer; every import is still asked, to prove no rival.
    single := SimpleNamePrecedence.Select("App", PrecedenceImports(["Left", "Right", "Other"]))
    asked := PrecedenceDrive(single, [], ["Left"])
    assert asked == "App,<global>,Left(import),Right(import),Other(import)", asked
    assert PrecedenceOutcome(single) == "metadata:Left(import)"
    assert !single.IsLexicalMetadata

    nothing := SimpleNamePrecedence.Select("App", PrecedenceImports(["Left"]))
    PrecedenceDrive(nothing, [], [])
    assert PrecedenceOutcome(nothing) == "not-found:<global>"
}

test "an import of a lexical namespace is not a rival and an import is asked once" {
    selection := SimpleNamePrecedence.Select("App.Models", PrecedenceImports(["App", "Left", "Left", "App.Models"]))
    asked := PrecedenceDrive(selection, [], ["Left"])
    assert asked == "App.Models,App,<global>,Left(import)", asked
    assert PrecedenceOutcome(selection) == "metadata:Left(import)"
}

test "a candidate carries the export rule: only the file's own namespace needs none" {
    selection := SimpleNamePrecedence.Select("App.Models", PrecedenceImports(["Left"]))
    exportRules := ""
    while !selection.IsSettled {
        exportRules = exportRules + (selection.Current.RequiresExport ? "E" : "-")
        selection.Answer(false, false)
    }
    assert exportRules == "-EEE", exportRules
}

test "a qualified name's candidates climb the chain and keep where each was read" {
    selection := SimpleNamePrecedence.SelectQualified("NSharpLang.Compiler.Columnar", "Ast")
    trail := ""
    while !selection.IsSettled {
        candidate := selection.Current
        trail = trail + (trail.Length == 0 ? "" : ",") + (candidate.Namespace ?? "?") + "@" + (candidate.LexicalBase ?? "<global>") + (candidate.IsWrittenSpelling ? "!" : "")
        selection.Answer(false, false)
    }
    assert trail == "NSharpLang.Compiler.Columnar.Ast@NSharpLang.Compiler.Columnar,NSharpLang.Compiler.Ast@NSharpLang.Compiler,NSharpLang.Ast@NSharpLang,Ast@<global>!", trail

    found := SimpleNamePrecedence.SelectQualified("NSharpLang.Compiler.Columnar", "Ast")
    PrecedenceDrive(found, [], ["NSharpLang.Compiler.Ast"])
    assert PrecedenceOutcome(found) == "metadata:NSharpLang.Compiler.Ast"
    assert found.LexicalBase == "NSharpLang.Compiler"

    empty := SimpleNamePrecedence.SelectQualified("App", "")
    assert empty.IsSettled
    assert empty.Kind == SimpleNameSelectionKind.NotFound
}
