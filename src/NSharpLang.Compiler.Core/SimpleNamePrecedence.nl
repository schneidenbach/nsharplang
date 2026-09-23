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
}
