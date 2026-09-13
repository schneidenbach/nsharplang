namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// THE IDENTITY OF A FREE FUNCTION, FOR THE EMITTER.
//
// A top-level `func` is not identified by its bare name. Two files may both declare `func Helper()`
// as long as they sit in different namespaces, exactly as two files may both declare `class Widget`
// there — so the emitter's identity for a free function is (NAMESPACE, NAME), and the CLR shape has
// to be able to hold both at once.
//
// THE CLR SHAPE. Every namespace that declares free functions gets ONE holder type named `Program`
// inside it: `func Helper()` in `namespace X` is `X.Program.Helper`, the same function in
// `namespace Y` is `Y.Program.Helper`, and a file with no namespace declaration puts its functions
// on the global `Program`. That is the shape the type machinery already gives every other
// declaration (`ExactTypeNameForFile`), it keeps reflection and cross-language interop honest — a C#
// consumer writes `X.Program.Helper()` and means it — and it is the only shape in which two
// same-named functions can coexist, since one type cannot declare the same signature twice.
//
// THE RESOLUTION. A bare call is resolved against the SAME order the analyzer resolved it with
// (`AnalyzerProjectDiscovery.TryResolveVisibleProjectFunction`), which is `SimpleNamePrecedence`:
//
//   0. a function declared in the CALLER'S OWN FILE wins outright, whatever its casing — that is the
//      lexical scope the analyzer consults before project discovery ever runs;
//   1. a file pulled in whole by `import "./other.nl"`, in import order — a file import binds the
//      imported file's exported declarations into THIS file's scope, which is the same tier, so it
//      is nearer than any namespace (two file imports supplying one name is NL702);
//   2. the file's own namespace, then each ENCLOSING namespace outward, ending at the global one;
//   3. the file's explicit namespace imports, in import order.
//
// Only EXPORTED functions are candidates from step 1 onward: a camelCase top-level function is
// file-private, so another file never sees it, not even one in the same namespace. Exported is the
// analyzer's own rule (`VisibilityConventions`) — the casing UNLESS a visibility word overrides it,
// which is why `public func buildExplicit()` is exported and `internal func Helper()` is not, and
// why `ColumnarFunctionInput` carries that word in its own column.
//
// There is deliberately no project-wide auto-discovery tier for functions — the analyzer has none,
// and an emitter that resolved a name the analyzer rejected would be inventing a program.
class ColumnarFreeFunctionScope {
    program: ColumnarProgramInput
    rootTypeName: string
    definitions: List<ColumnarSiblingMethodDefinition>
    names: List<string>
    namespaceNames: List<string>
    sourceFileIds: List<int>
    exportedFlags: List<bool>
    returnLabeledCanonicals: List<string>
    viewsByFile: Dictionary<int, Dictionary<string, ColumnarSiblingMethodDefinition>>
    labeledViewsByFile: Dictionary<int, Dictionary<string, string>>

    constructor(programInput: ColumnarProgramInput, rootHolderTypeName: string) {
        program = programInput
        rootTypeName = rootHolderTypeName
        definitions = new List<ColumnarSiblingMethodDefinition>()
        names = new List<string>()
        namespaceNames = new List<string>()
        sourceFileIds = new List<int>()
        exportedFlags = new List<bool>()
        returnLabeledCanonicals = new List<string>()
        viewsByFile = new Dictionary<int, Dictionary<string, ColumnarSiblingMethodDefinition>>()
        labeledViewsByFile = new Dictionary<int, Dictionary<string, string>>()
    }

    // The CLR name of the holder type a namespace's free functions are declared on. The global
    // namespace keeps the bare root name, so a single-file script is unchanged.
    static func HolderTypeName(namespaceName: string, rootHolderTypeName: string): string {
        if namespaceName == null || namespaceName.Length == 0 {
            return rootHolderTypeName
        }

        return namespaceName + "." + rootHolderTypeName
    }

    func HolderTypeNameForFile(sourceFileId: int): string {
        return HolderTypeName(program.NamespaceNameForFile(sourceFileId), rootTypeName)
    }

    // One declared top-level function. Declaration order is preserved, because it is what settles a
    // tie the precedence order cannot: two candidates at the same rank keep the first one declared.
    func Declare(function: ColumnarFunctionInput, definition: ColumnarSiblingMethodDefinition) {
        definitions.Add(definition)
        names.Add(function.Name)
        namespaceNames.Add(program.NamespaceNameForFile(function.SourceFileId))
        sourceFileIds.Add(function.SourceFileId)
        exportedFlags.Add(VisibilityConventions.IsExportedIdentifierWithFlags(function.Name, function.VisibilityModifierFlags))
        returnLabeledCanonicals.Add(function.ReturnLabeledCanonical ?? "")
    }

    // THE SIBLING MAP AS ONE FILE SEES IT. Every body emitted out of `sourceFileId` reads this, so a
    // bare `Helper()` in `X` and a bare `Helper()` in `Y` reach different methods.
    func ViewFor(sourceFileId: int): Dictionary<string, ColumnarSiblingMethodDefinition> {
        BuildViews(sourceFileId)
        return viewsByFile[sourceFileId]
    }

    // The return tuple element labels of the same functions, keyed the same way, because `t := mk()`
    // derives its element names from whichever `mk` the call actually reached.
    func ReturnLabeledCanonicalsFor(sourceFileId: int): Dictionary<string, string> {
        BuildViews(sourceFileId)
        return labeledViewsByFile[sourceFileId]
    }

    func BuildViews(sourceFileId: int) {
        cachedView: Dictionary<string, ColumnarSiblingMethodDefinition>? = null
        if viewsByFile.TryGetValue(sourceFileId, out cachedView) {
            return
        }

        view := new Dictionary<string, ColumnarSiblingMethodDefinition>(StringComparer.Ordinal)
        labeled := new Dictionary<string, string>(StringComparer.Ordinal)
        ranks := NamespaceRanks(sourceFileId)
        fileRanks := FileImportRanks(sourceFileId)
        bestRanks := new Dictionary<string, int>(StringComparer.Ordinal)
        index := 0
        while index < names.Count {
            rank := OwnFileRank()
            considered := true
            if sourceFileIds[index] != sourceFileId {
                candidateRank := 0
                fileImportRank := 0
                if !exportedFlags[index] {
                    considered = false
                } else if fileRanks.TryGetValue(sourceFileIds[index], out fileImportRank) {
                    rank = fileImportRank
                } else if !ranks.TryGetValue(namespaceNames[index], out candidateRank) {
                    considered = false
                } else {
                    rank = candidateRank
                }
            }
            if considered {
                name := names[index]
                existingRank := 0
                if !bestRanks.TryGetValue(name, out existingRank) || rank < existingRank {
                    bestRanks[name] = rank
                    view[name] = definitions[index]
                    labeledCanonical := returnLabeledCanonicals[index]
                    if labeledCanonical.Length > 0 {
                        labeled[name] = labeledCanonical
                    } else {
                        labeled.Remove(name)
                    }
                }
            }
            index = index + 1
        }

        viewsByFile[sourceFileId] = view
        labeledViewsByFile[sourceFileId] = labeled
    }

    // The caller's own file is nearer than every import and every namespace, so its rank sits below
    // the file-import band, which sits below the namespace band (which starts at 0).
    static func OwnFileRank(): int {
        return -1000000
    }

    static func FileImportRankBase(): int {
        return -1000
    }

    // The files this one imported WHOLE, ranked in import order, all of them nearer than any
    // namespace. A file that is imported twice keeps its first position.
    func FileImportRanks(sourceFileId: int): Dictionary<int, int> {
        fileRanks := new Dictionary<int, int>()
        imported := program.FileImportSourceFileIdsForFile(sourceFileId)
        index := 0
        while index < imported.Count {
            importedFileId := imported[index]
            if importedFileId != sourceFileId && !fileRanks.ContainsKey(importedFileId) {
                fileRanks[importedFileId] = FileImportRankBase() + index
            }
            index = index + 1
        }
        return fileRanks
    }

    // The candidate namespaces this file can reach a free function through, ranked nearest-first.
    // `SimpleNamePrecedence` is the one owner of that order; the global namespace rides as `""` here
    // because that is the spelling the emitter's binding scope holds a namespace in.
    func NamespaceRanks(sourceFileId: int): Dictionary<string, int> {
        ranks := new Dictionary<string, int>(StringComparer.Ordinal)
        currentNamespace := program.NamespaceNameForFile(sourceFileId)
        lookupNamespace: string? = null
        if currentNamespace.Length > 0 {
            lookupNamespace = currentNamespace
        }
        candidates := SimpleNamePrecedence.CandidateNamespaces(lookupNamespace, program.NamespaceImportsForFile(sourceFileId))
        index := 0
        while index < candidates.Count {
            candidate := candidates[index]
            key := candidate == null ? "" : candidate
            if !ranks.ContainsKey(key) {
                ranks[key] = index
            }
            index = index + 1
        }
        return ranks
    }
}

// THE HOLDER TYPES, CREATED ON DEMAND.
//
// A namespace gets its `Program` only once something is actually placed in it — a free function
// declared there, or a synthesized method (a lambda, a capture-free local function) lifted out of a
// body in one of its files. A project whose every file says `namespace App` therefore emits
// `App.Program` and nothing else, rather than an `App.Program` beside an empty global `Program`.
class ColumnarFreeFunctionHolders {
    module: ModuleBuilder
    rootTypeName: string
    program: ColumnarProgramInput
    buildersByNamespace: Dictionary<string, TypeBuilder>
    ordered: List<TypeBuilder>

    constructor(moduleBuilder: ModuleBuilder, rootHolderTypeName: string, programInput: ColumnarProgramInput) {
        module = moduleBuilder
        rootTypeName = rootHolderTypeName
        program = programInput
        buildersByNamespace = new Dictionary<string, TypeBuilder>(StringComparer.Ordinal)
        ordered = new List<TypeBuilder>()
    }

    // The holder a body emitted out of this file places its free functions and its synthesized
    // methods on. Every caller has a source file id, so nobody has to spell a namespace.
    func ForFile(sourceFileId: int): TypeBuilder {
        return For(program.NamespaceNameForFile(sourceFileId))
    }

    func For(namespaceName: string): TypeBuilder {
        existing: TypeBuilder? = null
        if buildersByNamespace.TryGetValue(namespaceName, out existing) {
            return existing
        }

        created := module.DefineType(
            ColumnarFreeFunctionScope.HolderTypeName(namespaceName, rootTypeName),
            TypeAttributes.Public | TypeAttributes.Class
        )
        buildersByNamespace[namespaceName] = created
        ordered.Add(created)
        return created
    }

    // Every holder that was actually needed, in creation order, for the final `CreateType` pass.
    func Created(): List<TypeBuilder> {
        return ordered
    }
}
