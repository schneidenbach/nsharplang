namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// THE ONE PLACE THAT ORDERS THE NAMESPACES A SIMPLE TYPE NAME IS LOOKED UP IN.
//
// N# reads a bare type name the way C# reads a namespace-or-type-name (C# §7.8): the lookup climbs
// OUTWARD through the lexical namespace nesting before it ever consults a `import`, and only after
// every import has been asked does project-wide auto-discovery get a turn. Written out, for a name
// that no local scope, file alias or built-in claimed:
//
//   1. the file's OWN namespace — a declaration there wins outright;
//   2. each ENCLOSING namespace outward (`A.B.C` -> `A.B` -> `A` -> the global namespace) — an
//      EXPORTED declaration there wins outright, because it is lexically nearer than any import;
//   3. the file's explicit namespace imports, in import order — exactly one supplying the name wins
//      (over auto-discovery); two or more is NL209 and the developer must qualify;
//   4. project-wide auto-discovery of a unique exported project type, which never overrides 2 or 3.
//
// TWO WALKS DEPEND ON THIS ORDER AND MUST NOT DISAGREE: the analyzer's type resolver
// (`AnalyzerTypeReferenceFacts.VisibleTypeNamespaces` -> `AnalyzerProjectTypeDiscovery`) and the
// emitter's binding scope (`ColumnarBindingScopeFacts`). They used to spell the order separately and
// drifted — the analyzer resolved `ParameterModifier` to a source enum while the binding scope
// resolved the same spelling to an imported CLR type and then declined the program. So the ordering
// lives HERE, as a total function of its arguments, and both walks read it.
//
// A `null` namespace is the GLOBAL namespace and is a genuine candidate, not an absence: it is the
// outermost enclosing namespace of every file, so a file in `A.B` sees a global exported declaration
// without importing anything, and that declaration outranks an import of the same spelling.
class SimpleNamePrecedence {

    // Rules 1 and 2, in order: the file's own namespace, then each enclosing namespace outward,
    // ending at the global namespace (`null`). A file that declares no namespace IS in the global
    // namespace, so its chain is the single entry `null`.
    static func LexicalNamespaces(currentNamespace: string?): List<string?> {
        chain := new List<string?>()
        if currentNamespace == null || currentNamespace.Length == 0 {
            chain.Add(null)
            return chain
        }

        chain.Add(currentNamespace)
        remaining := currentNamespace
        while remaining.Length > 0 {
            separatorIndex := remaining.Length - 1
            while separatorIndex >= 0 && remaining[separatorIndex] != '.' {
                separatorIndex = separatorIndex - 1
            }
            if separatorIndex <= 0 {
                remaining = ""
            } else {
                remaining = remaining.Substring(0, separatorIndex)
                chain.Add(remaining)
            }
        }

        chain.Add(null)
        return chain
    }

    // Rules 1, 2 and 3 as one ordered candidate list: the lexical chain first, then the file's
    // explicit namespace imports in import order. Deduplicated with the FIRST occurrence winning, so
    // an import that names an enclosing namespace stays where the lexical chain put it rather than
    // becoming a second, competing candidate.
    static func CandidateNamespaces(currentNamespace: string?, importedNamespaces: List<string>): List<string?> {
        candidates := new List<string?>()
        seen := new HashSet<string>(StringComparer.Ordinal)
        sawGlobal := false

        lexical := LexicalNamespaces(currentNamespace)
        for lexicalNamespace in lexical {
            if lexicalNamespace == null {
                if !sawGlobal {
                    sawGlobal = true
                    candidates.Add(null)
                }
            } else if seen.Add(lexicalNamespace) {
                candidates.Add(lexicalNamespace)
            }
        }

        for importedNamespace in importedNamespaces {
            if seen.Add(importedNamespace) {
                candidates.Add(importedNamespace)
            }
        }

        return candidates
    }

    // True when this namespace is the file's own or one of its enclosing namespaces — that is, when a
    // declaration there wins by rule 1 or 2 and is therefore NOT one of the competing imports rule 3
    // arbitrates between. An `import` that names an enclosing namespace is redundant, not a rival.
    static func IsLexicalNamespace(currentNamespace: string?, candidateNamespace: string?): bool {
        lexical := LexicalNamespaces(currentNamespace)
        for lexicalItem in lexical {
            if string.Equals(lexicalItem, candidateNamespace, StringComparison.Ordinal) {
                return true
            }
        }
        return false
    }

    // A NAMESPACE QUALIFIER WRITTEN IN SOURCE, EXPANDED THROUGH THE SAME LEXICAL CHAIN.
    //
    // `Ast.ParameterModifier` read from inside `NSharpLang.Compiler` means
    // `NSharpLang.Compiler.Ast.ParameterModifier`, because the LEFTMOST segment of a
    // namespace-or-type-name is looked up by the very rule a simple name is: the file's own
    // namespace, then each enclosing one outward, ending at the global namespace where the qualifier
    // is read exactly as written. That is C# §7.8 again, and it is why a child namespace can be named
    // by its last segment instead of its full path.
    //
    // IMPORTS ARE DELIBERATELY ABSENT. An `import` brings a namespace's TYPES into the file, never its
    // sub-namespaces — `import System` does not make `Reflection.TypeInfo` a name — so the qualifier
    // chain is lexical only, exactly as C# reads it.
    //
    // The candidates come back in chain order, deduplicated, and always include the written spelling
    // itself (as the global namespace's candidate), so an absolute qualifier still resolves.
    static func QualifierNamespaces(currentNamespace: string?, writtenQualifier: string): List<string> {
        candidates := new List<string>()
        if writtenQualifier == null || writtenQualifier.Length == 0 {
            return candidates
        }

        seen := new HashSet<string>(StringComparer.Ordinal)
        lexical := LexicalNamespaces(currentNamespace)
        for lexicalNamespace in lexical {
            candidate := lexicalNamespace == null || lexicalNamespace.Length == 0 ? writtenQualifier : lexicalNamespace + "." + writtenQualifier
            if seen.Add(candidate) {
                candidates.Add(candidate)
            }
        }

        return candidates
    }

    // THE EXPORT HALF OF THE SAME RULE, and it is a total function of the two namespaces.
    //
    // A declaration is reachable from its OWN namespace whatever its casing — camelCase is
    // NAMESPACE-private, not file-private, so every file of `X` sees `X`'s camelCase functions and
    // types with no import and no export. Every OTHER namespace, an ENCLOSING one included, needs the
    // declaration exported; an enclosing namespace is nearer than an import but it is still not the
    // declaration's own namespace, and a private declaration out there must not hijack a name.
    //
    // Both walks read this, for the same reason they read the ORDER above: the analyzer's project
    // discovery (`AnalyzerProjectDiscovery.TryResolveVisibleProjectFunction`) and the emitter's
    // free-function scope (`ColumnarFreeFunctionScope`) spelled it separately once and drifted — the
    // analyzer accepted a cross-file call to a camelCase function of the same namespace and the
    // emitter then refused to emit it.
    //
    // `null` and `""` are both the GLOBAL namespace, so a file with no namespace declaration sees the
    // other global files' non-exported declarations exactly as a named namespace does.
    static func RequiresExport(currentNamespace: string?, candidateNamespace: string?): bool {
        current := currentNamespace ?? ""
        candidate := candidateNamespace ?? ""
        return !string.Equals(current, candidate, StringComparison.Ordinal)
    }

    // Rule 2 on its own, spelled the way the emitter's binding scope holds a namespace: `""` is the
    // global namespace rather than `null`, and the file's OWN namespace is NOT in the list because
    // every caller has already asked about it. The order is the lexical chain's.
    static func EnclosingNamespaceNames(currentNamespace: string): List<string> {
        enclosing := new List<string>()
        lexical := LexicalNamespaces(currentNamespace)
        index := 1
        while index < lexical.Count {
            lexicalNamespace := lexical[index]
            enclosing.Add(lexicalNamespace == null ? "" : lexicalNamespace)
            index = index + 1
        }
        return enclosing
    }

    // THE RULE ITSELF, NOT ONLY ITS ORDER: which namespace a bare type name BINDS in.
    //
    // A namespace's members are its types, wherever they were compiled. `NSharpLang.Compiler`'s
    // `TypeInfo` is a member of `NSharpLang.Compiler` whether this project declares it or a
    // referenced assembly does, so rules 1 and 2 ask BOTH at every step of the lexical chain, and a
    // referenced assembly's type in an enclosing namespace outranks an imported one exactly as a
    // source type does. Until this owner existed the two walks applied rules 1 and 2 to SOURCE
    // declarations only, so carving a slice of this compiler into its own assembly would have
    // re-bound 3,552 bare `TypeInfo`s to `System.Reflection.TypeInfo` through an import.
    //
    // At ONE namespace a source declaration outranks a metadata type of the same full name (the
    // shape C# warns about with CS0436 and resolves the same way). The import tier is ONE tier: two
    // imports that each supply the name — source or metadata, in any mix — are a tie, and a tie is
    // NL209, never "the first import written wins", because `nlc format` sorts imports and a reorder
    // must never change what a file means.
    //
    // THE CALLER ANSWERS, THIS OWNER DECIDES. Each walk knows how to ask ONE namespace about ONE
    // spelling — the analyzer asks its project index and its metadata probe, the emitter its source
    // name tables and its assembly scan — and nothing else. So the selection hands out candidates in
    // order, takes a (source, metadata) answer for each, and settles as soon as the rule can:
    //
    //     selection := SimpleNamePrecedence.Select(currentNamespace, imports)
    //     while !selection.IsSettled {
    //         candidate := selection.Current
    //         source := <does candidate.Namespace declare it in source, honouring RequiresExport>
    //         metadata := !source && <does a referenced assembly declare it there>
    //         selection.Answer(source, metadata)
    //     }
    static func Select(currentNamespace: string?, importedNamespaces: List<string>): SimpleNameSelection {
        candidates := new List<SimpleNameCandidate>()
        lexical := LexicalNamespaces(currentNamespace)
        for lexicalNamespace in lexical {
            candidates.Add(new SimpleNameCandidate(lexicalNamespace, lexicalNamespace, false, RequiresExport(currentNamespace, lexicalNamespace), false))
        }

        seen := new HashSet<string>(StringComparer.Ordinal)
        for importedNamespace in importedNamespaces {
            // An import of a lexical namespace is redundant, not a rival: the chain already asked it.
            if importedNamespace == null || importedNamespace.Length == 0 || IsLexicalNamespace(currentNamespace, importedNamespace) || !seen.Add(importedNamespace) {
                continue
            }

            candidates.Add(new SimpleNameCandidate(importedNamespace, importedNamespace, true, true, false))
        }

        return new SimpleNameSelection(candidates)
    }

    // THE SAME RULE FOR A QUALIFIED NAME: `Ast.Node` read inside `NSharpLang.Compiler` means
    // `NSharpLang.Compiler.Ast.Node` when that namespace declares `Node` — in source OR in a
    // referenced assembly — because the qualifier's leftmost segment climbs the lexical chain
    // (`QualifierNamespaces`). The chain's last candidate is the written qualifier itself, read as an
    // absolute namespace; it is marked `IsWrittenSpelling` so a caller that already owns the absolute
    // reading elsewhere can leave it there. There is no import tier: an import brings in types, not
    // sub-namespaces.
    static func SelectQualified(currentNamespace: string?, writtenQualifier: string): SimpleNameSelection {
        candidates := new List<SimpleNameCandidate>()
        if writtenQualifier == null || writtenQualifier.Length == 0 {
            return new SimpleNameSelection(candidates)
        }

        seen := new HashSet<string>(StringComparer.Ordinal)
        lexical := LexicalNamespaces(currentNamespace)
        for lexicalNamespace in lexical {
            isWritten := lexicalNamespace == null || lexicalNamespace.Length == 0
            qualifier := isWritten ? writtenQualifier : lexicalNamespace + "." + writtenQualifier
            if seen.Add(qualifier) {
                candidates.Add(new SimpleNameCandidate(qualifier, lexicalNamespace, false, RequiresExport(currentNamespace, qualifier), isWritten))
            }
        }

        return new SimpleNameSelection(candidates)
    }
}

// Which tier a settled selection landed in, and whether a source declaration or a referenced
// assembly supplied it.
enum SimpleNameSelectionKind {
    NotFound,
    Source,
    Metadata,
    Ambiguous
}

// ONE namespace a selection asks about. `Namespace` null is the global namespace. `RequiresExport`
// is `SimpleNamePrecedence.RequiresExport`'s answer for it, so a caller never re-derives the export
// rule; it only matters to a SOURCE answer, since a referenced assembly exposes what it made public.
//
// `LexicalBase` is the namespace of the lexical chain the candidate was read INSIDE: the candidate
// itself for a simple name, and for a qualified one the namespace the written qualifier was appended
// to (null for the written spelling read absolutely). A metadata answer asks it for
// `<qualifier>.<name>`, because the qualifier may name a TYPE rather than a namespace
// (`Outer.Inner` is `Outer+Inner` in metadata) and only the written part can be read as nesting.
class SimpleNameCandidate {
    Namespace: string?
    LexicalBase: string?
    IsImport: bool
    RequiresExport: bool
    IsWrittenSpelling: bool

    constructor(namespaceName: string?, lexicalBase: string?, isImport: bool, requiresExport: bool, isWrittenSpelling: bool) {
        Namespace = namespaceName
        LexicalBase = lexicalBase
        IsImport = isImport
        RequiresExport = requiresExport
        IsWrittenSpelling = isWrittenSpelling
    }
}

// The decision `SimpleNamePrecedence.Select` drives. It is settled as soon as the rule can settle:
// at the first lexical candidate that declares the name, at the SECOND import that does, or when the
// candidates run out. Until then `Current` is the next namespace to ask about.
class SimpleNameSelection {
    candidates: List<SimpleNameCandidate>
    index: int
    Kind: SimpleNameSelectionKind
    // The namespace that supplied the name; for an ambiguity, the first import that did. Its
    // `LexicalBase` is the winning candidate's, for a caller that reads a qualified name there.
    Namespace: string?
    LexicalBase: string?
    FromImport: bool
    // The rival import of an ambiguity, and whether each side is a source declaration.
    SecondNamespace: string?
    FirstIsSource: bool
    SecondIsSource: bool
    IsSettled: bool
    importMatched: bool

    constructor(candidateList: List<SimpleNameCandidate>) {
        candidates = candidateList
        index = 0
        Kind = SimpleNameSelectionKind.NotFound
        Namespace = null
        LexicalBase = null
        FromImport = false
        SecondNamespace = null
        FirstIsSource = false
        SecondIsSource = false
        IsSettled = candidateList.Count == 0
        importMatched = false
    }

    Current: SimpleNameCandidate => candidates[index]

    // Rules 1 and 2 settled it: a lexical namespace declares the name in a referenced assembly and
    // no nearer namespace declares it in source.
    IsLexicalMetadata: bool => Kind == SimpleNameSelectionKind.Metadata && !FromImport

    // The answer for `Current`: does its namespace declare the name in source, and (asked only when
    // it does not) in a referenced assembly.
    func Answer(declaresSource: bool, declaresMetadata: bool) {
        if IsSettled {
            return
        }

        candidate := candidates[index]
        found := declaresSource || declaresMetadata
        if found && !candidate.IsImport {
            Kind = declaresSource ? SimpleNameSelectionKind.Source : SimpleNameSelectionKind.Metadata
            Namespace = candidate.Namespace
            LexicalBase = candidate.LexicalBase
            FirstIsSource = declaresSource
            IsSettled = true
            return
        }

        if found {
            if importMatched {
                SecondNamespace = candidate.Namespace
                SecondIsSource = declaresSource
                Kind = SimpleNameSelectionKind.Ambiguous
                IsSettled = true
                return
            }

            importMatched = true
            Kind = declaresSource ? SimpleNameSelectionKind.Source : SimpleNameSelectionKind.Metadata
            Namespace = candidate.Namespace
            LexicalBase = candidate.LexicalBase
            FromImport = true
            FirstIsSource = declaresSource
        }

        index = index + 1
        if index >= candidates.Count {
            IsSettled = true
        }
    }

    // The full name the selection bound, or the first candidate of an ambiguity.
    func QualifiedName(name: string): string {
        selected := Namespace
        if selected == null || selected.Length == 0 {
            return name
        }

        return selected + "." + name
    }

    func SecondQualifiedName(name: string): string {
        second := SecondNamespace
        if second == null || second.Length == 0 {
            return name
        }

        return second + "." + name
    }
}
