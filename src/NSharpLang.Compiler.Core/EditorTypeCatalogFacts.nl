namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler


// WHAT THE EDITOR OFFERS OUT OF METADATA, AND HOW IT LOOKS IT UP.
//
// The Language Server answers two questions this file decides for it — hover's "what CLR type is
// this name" and completion's "which types and namespaces may I offer, in what order". The C# that
// asked them used to spell every answer for itself: an assembly seed list, a short-name table, a
// namespace probe order, a well-known-namespace list, a ranking, an offerability filter and four
// separate rules about how a type name is spelled. All of that is here now, and the reflection
// reads it drives are all that is left on the other side.
//
// THE END-STATE THIS FILE IS NOT YET: **THE LANGUAGE SERVER HOLDS TWO DISJOINT TYPE UNIVERSES.**
// The analyzer builds a `MetadataLoadContext` over `ExternalAssemblyScan.CommonAssemblyNames()`
// AND over the project's own references, so it can see everything a program actually compiles
// against. The editor's type catalogue — `EditorUniverseSeedTypeNames` below — is four seed types
// reached by LIVE reflection over the language-server process itself, which resolves to exactly
// THREE assemblies and contains no project reference at all. So completion cannot offer a type
// from a package the user depends on, and hover cannot name one. That is a product defect, not a
// spelling one, and closing it means serving the editor from the analyzer's universe. It is out of
// this file's reach today because the analyzer's universe is a `MetadataLoadContext` and the AOT
// type-model task owns replacing it; naming it here is what keeps the next reader from "fixing"
// the seed list by adding a fifth name.
//
// TWO OWNERS ARE CONSULTED RATHER THAN COPIED. `CompletionReflectionFacts` already answers, for the
// compiler's own completion engine, which named types a completion knows how to reflect over —
// eight of the twelve spellings in the editor's roster are ITS answer, and they are derived from it
// below instead of being written down a second time. `AnalyzerMetadataLoadPolicy.CompareOrdinalText`
// already spells ordinal comparison by code unit for an emit path that does not model
// `string.CompareOrdinal`; the ordering below uses it rather than opening a second copy.
class EditorTypeCatalogFacts {

    // ── THE UNIVERSE ─────────────────────────────────────────────────────────────────────────

    // THE SEED TYPE NAMES ARE GONE (022/4c). They named FOUR types reaching THREE assemblies of the
    // language server's own process, and that was the editor's whole type universe -- which is why a
    // type from a package the user depends on could not be offered or hovered. The editor now reads
    // the ANALYZER's universe through `EditorTypeCatalog`: a metadata context over the common
    // assemblies plus every reference the project declares. There is no seed list to extend, and the
    // file's old header warning against adding a fifth name is answered by there being none.

    // ── THE ROSTER ───────────────────────────────────────────────────────────────────────────

    // THE TWELVE SPELLINGS A GENERAL COMPLETION ALWAYS VOLUNTEERS, in the order it offers them
    // before ranking. This is editor CURATION and not language policy: it decides what an empty
    // prefix is worth showing, never what a name MEANS. `AnalyzerTypeReferenceFacts` owns the
    // second question and is consulted first by every caller of this one.
    //
    // The spellings are the CLR ones a user types at a type position (`String`, not `string`) —
    // the built-in aliases are already resolved before this table is reached.
    static func CommonShortTypeNames(): string[] {
        names := new string[](12)
        names[0] = "Console"
        names[1] = "String"
        names[2] = "Math"
        names[3] = "DateTime"
        names[4] = "Guid"
        names[5] = "Exception"
        names[6] = "List"
        names[7] = "Dictionary"
        names[8] = "HashSet"
        names[9] = "IEnumerable"
        names[10] = "Task"
        names[11] = "CancellationToken"
        return names
    }

    // WHAT A ROSTER SPELLING DENOTES. EIGHT OF THE TWELVE ARE DERIVED FROM
    // `CompletionReflectionFacts`, which already answers "which named types does a completion know"
    // for the compiler's own engine — four of them through its receiver table and four through its
    // generic-definition table, which is also where the arity suffixes (`List`1`, `Dictionary`2`)
    // come from rather than being transcribed. Its keys are the N# spellings, which is why `String`
    // asks it for `string`.
    //
    // THE OTHER FOUR HAVE NO OWNER and are spelled here: `Guid` and `Exception` are not completion
    // receivers, and `Task` here is the NON-GENERIC `System.Threading.Tasks.Task` — the generic
    // `Task`1` in the other owner is a different type, which is exactly why the derivation stops.
    static func CommonShortTypeFullName(name: string): string? {
        if name == "Console" {
            return KnownReceiverFullName("Console")
        }
        if name == "String" {
            return KnownReceiverFullName("string")
        }
        if name == "Math" {
            return KnownReceiverFullName("Math")
        }
        if name == "DateTime" {
            return KnownReceiverFullName("DateTime")
        }
        if name == "List" {
            return KnownDefinitionFullName("List")
        }
        if name == "Dictionary" {
            return KnownDefinitionFullName("Dictionary")
        }
        if name == "HashSet" {
            return KnownDefinitionFullName("HashSet")
        }
        if name == "IEnumerable" {
            return KnownDefinitionFullName("IEnumerable")
        }
        if name == "Guid" {
            return "System.Guid"
        }
        if name == "Exception" {
            return "System.Exception"
        }
        if name == "Task" {
            return "System.Threading.Tasks.Task"
        }
        if name == "CancellationToken" {
            return "System.Threading.CancellationToken"
        }

        return null
    }

    static func KnownReceiverFullName(nsharpSpelling: string): string? {
        resolved := CompletionReflectionFacts.KnownReceiverType(nsharpSpelling)
        if resolved == null {
            return null
        }

        return resolved.get_FullName()
    }

    static func KnownDefinitionFullName(nsharpSpelling: string): string? {
        resolved := CompletionReflectionFacts.KnownReceiverGenericDefinition(nsharpSpelling)
        if resolved == null {
            return null
        }

        return resolved.get_FullName()
    }

    // THE FORCE-INCLUDE LIST, DEFINED FROM THE TWO ABOVE rather than written a third time. An
    // entry whose full name cannot be produced is DROPPED rather than defaulted, because a
    // completion that offers a name it cannot resolve is worse than one that offers fewer names.
    static func CommonShortTypeFullNames(): string[] {
        spellings := CommonShortTypeNames()
        resolved := new List<string>()
        index := 0
        while index < spellings.Length {
            fullName := CommonShortTypeFullName(spellings[index])
            if fullName != null {
                resolved.Add(fullName)
            }

            index = index + 1
        }

        return resolved.ToArray()
    }

    // ── HOW A NAME IS LOOKED UP ──────────────────────────────────────────────────────────────

    // THE NAMESPACES A BARE NAME IS TRIED IN, in order. This is the editor's STAND-IN for the
    // file's own imports: `AnalyzerExternalTypeProbe.ResolveExternalType` asks the same question
    // and prefixes with what the file actually imported, which is strictly better and is the shape
    // the universe unification above should arrive at. Until then a bare `Console` has to be found
    // some way, and this is the way.
    static func NamespaceProbePrefixes(): string[] {
        prefixes := new string[](7)
        prefixes[0] = "System"
        prefixes[1] = "System.Collections"
        prefixes[2] = "System.Collections.Generic"
        prefixes[3] = "System.Linq"
        prefixes[4] = "System.Text"
        prefixes[5] = "System.Threading"
        prefixes[6] = "System.Threading.Tasks"
        return prefixes
    }

    // A NAME IS ALREADY QUALIFIED WHEN IT CARRIES A DOT. Both the prefix probe and the
    // exported-type sweep are gated on this one test, so it is spelled once.
    static func IsQualifiedTypeName(typeName: string): bool {
        return typeName.Contains(".", StringComparison.Ordinal)
    }

    // THE PROBE PLAN: the name as written first, then — only when it is unqualified — the same name
    // under each probe prefix in order. DEFINED FROM `NamespaceProbePrefixes`, so the order is
    // stated once. A qualified name yields exactly one candidate, which is why a fully spelled
    // `System.Text.StringBuilder` never pays for six misses.
    static func CandidateTypeFullNames(typeName: string): string[] {
        if IsQualifiedTypeName(typeName) {
            single := new string[](1)
            single[0] = typeName
            return single
        }

        prefixes := NamespaceProbePrefixes()
        candidates := new string[](prefixes.Length + 1)
        candidates[0] = typeName
        index := 0
        while index < prefixes.Length {
            candidates[index + 1] = prefixes[index] + "." + typeName
            index = index + 1
        }

        return candidates
    }

    // ── HOW A TYPE NAME IS SPELLED ───────────────────────────────────────────────────────────

    // A TRAILING `?` IS NULLABILITY, NOT PART OF THE NAME. The trailing trim after it is what lets
    // `string ?` resolve the same as `string?`.
    static func StripNullableSuffix(typeName: string): string {
        if !typeName.EndsWith("?", StringComparison.Ordinal) {
            return typeName
        }

        return typeName.Substring(0, typeName.Length - 1).TrimEnd()
    }

    // AN ARRAY IS RESOLVED THROUGH ITS ELEMENT. Only the outermost `[]` is read here; a
    // `int[][]` peels one rank per call, which is why the caller recurses rather than looping.
    static func IsArrayTypeName(typeName: string): bool {
        return typeName.EndsWith("[]", StringComparison.Ordinal)
    }

    static func ArrayElementTypeName(typeName: string): string {
        if !IsArrayTypeName(typeName) {
            return typeName
        }

        return typeName.Substring(0, typeName.Length - 2).TrimEnd()
    }

    // A WRITTEN GENERIC RESOLVES TO ITS OPEN DEFINITION. `Task<string>` answers `Task`, and the
    // type ARGUMENTS are deliberately discarded: an editor asking "what is this name" wants the
    // definition's members, and closing the definition is a different question that
    // `CompletionReflectionFacts.CloseKnownReceiverDefinition` owns.
    static func StripGenericArgumentList(typeName: string): string {
        opening := typeName.IndexOf('<')
        if opening < 0 {
            return typeName
        }

        return typeName.Substring(0, opening).TrimEnd()
    }

    // THE NAME A COMPLETION SHOWS FOR A REFLECTED TYPE: everything before the first arity backtick,
    // so `List`1` is offered as `List`.
    //
    // `DocQueryKernels.StripGenericArity` answers the same question with a DIFFERENT total
    // function — it deletes every backtick-and-digits RUN instead of truncating at the first — and
    // the two were measured identical over all 1,391 exported types the editor's universe can
    // reach. They part only on a name carrying two runs, which a `Type.Name` does not have, and the
    // contracts pin BOTH halves of that so the divergence is a recorded fact rather than a
    // surprise. Unifying them is a language-surface change and belongs to the slice that can
    // measure `nlc query`'s side of it.
    static func CompletionTypeDisplayName(name: string): string {
        backtick := name.IndexOf('`')
        if backtick < 0 {
            return name
        }

        return name.Substring(0, backtick)
    }

    // ── WHAT MAY BE OFFERED ──────────────────────────────────────────────────────────────────

    // WHICH CLR TYPES AN EDITOR MAY OFFER AS AN IMPORTABLE NAME. Four rules and each one is a
    // decision: only PUBLIC types (a caller could not name the others), only TOP-LEVEL ones (a
    // nested name needs its enclosing type and the completion inserts a bare name), only types with
    // both a namespace and a full name (the global namespace has no import edit to write), and
    // nothing COMPILER-GENERATED — a leading `<` or an embedded `__`, which is how every language
    // on the CLR spells a name a user never wrote.
    static func IsOfferableCompletionType(name: string, namespaceName: string?, fullName: string?, isPublic: bool, isNested: bool): bool {
        if !isPublic || isNested {
            return false
        }

        if string.IsNullOrWhiteSpace(namespaceName ?? "") || string.IsNullOrWhiteSpace(fullName ?? "") {
            return false
        }

        if name.StartsWith("<", StringComparison.Ordinal) {
            return false
        }

        return !name.Contains("__", StringComparison.Ordinal)
    }

    // A TYPE PREFIX MATCHES CASE-INSENSITIVELY, so `cons` still offers `Console`. An EMPTY prefix
    // matches everything — the caller's roster pass depends on it.
    //
    // NOTE THE ASYMMETRY WITH `MatchesNamespaceSegmentPrefix` BELOW, which is case-SENSITIVE. It is
    // deliberate and it is the platform's own convention: a type name a user half-types is a guess,
    // and a namespace segment inside an `import` line is being spelled exactly.
    static func MatchesCompletionPrefix(name: string, prefix: string): bool {
        if prefix.Length == 0 {
            return true
        }

        return name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
    }

    // HOW MANY IMPORTABLE TYPES ONE COMPLETION MAY CARRY. The cap exists so a one-letter prefix
    // does not post ten thousand items into an editor that will render all of them.
    static func MaxImportableTypeResults(): int {
        return 200
    }

    // ── THE ORDER THEY COME OUT IN ───────────────────────────────────────────────────────────

    // WHICH NAMESPACES RANK ABOVE WHICH. The four a user reaches for constantly are named one by
    // one, every other `System.` namespace shares one rank, and everything else shares the last.
    // The gap between 3 and 10 and between 10 and 20 is headroom, not meaning.
    static func NamespacePriority(namespaceName: string): int {
        if namespaceName == "System" {
            return 0
        }
        if namespaceName == "System.Collections.Generic" {
            return 1
        }
        if namespaceName == "System.Threading.Tasks" {
            return 2
        }
        if namespaceName == "System.Linq" {
            return 3
        }
        if namespaceName.StartsWith("System.", StringComparison.Ordinal) {
            return 10
        }

        return 20
    }

    // THE COMPLETION ORDER: rank first, then the offered NAME, then the namespace it comes from.
    // Both tie-breaks are ORDINAL — a completion list must not reorder itself under a Turkish
    // locale — and both are spelled through `AnalyzerMetadataLoadPolicy.CompareOrdinalText`, which
    // already owns "compare two strings by code unit" for an emit path that does not model
    // `string.CompareOrdinal`. Only the SIGN is consumed.
    static func CompareImportableTypes(leftName: string, leftNamespace: string, rightName: string, rightNamespace: string): int {
        leftRank := NamespacePriority(leftNamespace)
        rightRank := NamespacePriority(rightNamespace)
        if leftRank < rightRank {
            return -1
        }
        if leftRank > rightRank {
            return 1
        }

        byName := AnalyzerMetadataLoadPolicy.CompareOrdinalText(leftName, rightName)
        if byName != 0 {
            return byName
        }

        return AnalyzerMetadataLoadPolicy.CompareOrdinalText(leftNamespace, rightNamespace)
    }

    // ── NAMESPACES ───────────────────────────────────────────────────────────────────────────

    // THE NAMESPACES AN `import` LINE IS OFFERED BEFORE ANY ASSEMBLY IS SCANNED. This is a SEED and
    // not a closed set: the caller unions it with every namespace of every assembly its universe
    // reaches, so a name missing here costs nothing once the scan has run. It exists so the first
    // keystroke after `import` answers without paying for the scan.
    static func WellKnownNamespaceSeeds(): string[] {
        seeds := new string[](20)
        seeds[0] = "System"
        seeds[1] = "System.Collections"
        seeds[2] = "System.Collections.Generic"
        seeds[3] = "System.Collections.Concurrent"
        seeds[4] = "System.Linq"
        seeds[5] = "System.Text"
        seeds[6] = "System.Text.RegularExpressions"
        seeds[7] = "System.Threading"
        seeds[8] = "System.Threading.Tasks"
        seeds[9] = "System.IO"
        seeds[10] = "System.Net"
        seeds[11] = "System.Net.Http"
        seeds[12] = "System.Reflection"
        seeds[13] = "System.Runtime"
        seeds[14] = "System.Diagnostics"
        seeds[15] = "System.Globalization"
        seeds[16] = "System.ComponentModel"
        seeds[17] = "Microsoft.Extensions.DependencyInjection"
        seeds[18] = "Microsoft.Extensions.Logging"
        seeds[19] = "Microsoft.AspNetCore.Mvc"
        return seeds
    }

    // WHICH NAMESPACE THE USER IS ALREADY INSIDE. A prefix ENDING IN A DOT means "show me what is
    // under this one"; anything else is a partly typed segment whose parent is everything before
    // its last dot. An empty prefix is inside the global namespace, which is a real place and not
    // an absence.
    static func NamespacePrefixParent(prefix: string): string {
        normalized := prefix.Trim()
        if normalized.Length == 0 {
            return ""
        }

        if normalized.EndsWith(".", StringComparison.Ordinal) {
            return normalized.Substring(0, normalized.Length - 1)
        }

        lastDot := normalized.LastIndexOf(".", StringComparison.Ordinal)
        if lastDot < 0 {
            return ""
        }

        return normalized.Substring(0, lastDot)
    }

    // WHICH SEGMENT THE USER IS PART-WAY THROUGH. Empty whenever the prefix ends in a dot, because
    // no character of the next segment has been typed yet.
    static func NamespacePrefixSegment(prefix: string): string {
        normalized := prefix.Trim()
        if normalized.Length == 0 {
            return ""
        }

        if normalized.EndsWith(".", StringComparison.Ordinal) {
            return ""
        }

        lastDot := normalized.LastIndexOf(".", StringComparison.Ordinal)
        if lastDot < 0 {
            return normalized
        }

        return normalized.Substring(lastDot + 1)
    }

    // THE ONE SEGMENT A CANDIDATE NAMESPACE CONTRIBUTES UNDER A GIVEN PARENT, or `""` when it
    // contributes none. `System.Collections.Generic` under `System` is `Collections` — the tree is
    // offered ONE LEVEL AT A TIME, never flattened. A candidate equal to its parent contributes
    // nothing, which is why a namespace is not offered as a child of itself.
    static func NextNamespaceSegment(candidateNamespace: string, parentNamespace: string): string {
        if parentNamespace.Length == 0 {
            firstDot := candidateNamespace.IndexOf('.')
            if firstDot < 0 {
                return candidateNamespace
            }

            return candidateNamespace.Substring(0, firstDot)
        }

        prefix := parentNamespace + "."
        if !candidateNamespace.StartsWith(prefix, StringComparison.Ordinal) {
            return ""
        }

        remainder := candidateNamespace.Substring(prefix.Length)
        if remainder.Length == 0 {
            return ""
        }

        nextDot := remainder.IndexOf('.')
        if nextDot < 0 {
            return remainder
        }

        return remainder.Substring(0, nextDot)
    }

    // A NAMESPACE SEGMENT MATCHES CASE-SENSITIVELY — see `MatchesCompletionPrefix` for why the two
    // prefixes differ.
    static func MatchesNamespaceSegmentPrefix(segment: string, segmentPrefix: string): bool {
        return segment.StartsWith(segmentPrefix, StringComparison.Ordinal)
    }

    // THE ORDER OFFERED NAMESPACE SEGMENTS COME OUT IN — ordinal, for the same reason
    // `CompareImportableTypes` is, and through the same owner so the file spells no comparison of
    // its own.
    static func CompareNamespaceSegments(left: string, right: string): int {
        return AnalyzerMetadataLoadPolicy.CompareOrdinalText(left, right)
    }
}
