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
// A USER TYPE NAMED `Program` KEEPS ITS NAME. `class Program` beside free functions is ordinary in
// this language's own examples, so the holder YIELDS: when the namespace already declares a type of
// that name the holder is spelled `<Program>` instead, which no N# source can spell and which is
// therefore always available. Nothing is rejected and the source type's CLR name is unchanged.
// Before free functions were keyed by namespace this shape wrote TWO type rows of one name into the
// assembly whenever both were in the GLOBAL namespace (measured on 33b777917: `Assembly.GetTypes()`
// returned `Program` twice, and the program still ran) — so the fallback fixes that too.
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
// EXPORT IS REQUIRED ONLY ACROSS NAMESPACES, and `SimpleNamePrecedence.RequiresExport` is the one
// owner of that half of the rule. A camelCase top-level function is NAMESPACE-private, not
// file-private: every file of `X` reaches `X`'s camelCase functions with no import and no export,
// while every other namespace — an ENCLOSING one included — needs the declaration exported. Exported
// itself is the analyzer's rule (`VisibilityConventions`): the casing UNLESS a visibility word
// overrides it, which is why `public func buildExplicit()` is exported and `internal func Helper()`
// is not, and why `ColumnarFunctionInput` carries that word in its own column.
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

    // THE SPELLING THE HOLDER FALLS BACK TO when the namespace already declares a type of the
    // ordinary name. `<`and `>` cannot appear in an N# identifier, so this name is unclaimable by
    // source and the fallback can never need a fallback of its own. It is the same device the
    // synthesized lambda and display-class names use.
    static func ReservedHolderTypeName(rootHolderTypeName: string): string {
        return "<" + rootHolderTypeName + ">"
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

    // Whether a candidate declared in `candidateNamespace` has to be exported to be reachable from a
    // caller in `callerNamespace`. Delegated, never re-spelled — see the class comment.
    static func RequiresExport(callerNamespace: string, candidateNamespace: string): bool {
        return SimpleNamePrecedence.RequiresExport(callerNamespace, candidateNamespace)
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
        callerNamespace := program.NamespaceNameForFile(sourceFileId)
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
                if fileRanks.TryGetValue(sourceFileIds[index], out fileImportRank) {
                    // A FILE IMPORT carries only what the imported file EXPORTS, whatever namespace
                    // that file is in, so this tier always asks.
                    if exportedFlags[index] {
                        rank = fileImportRank
                    } else {
                        considered = false
                    }
                } else if !ranks.TryGetValue(namespaceNames[index], out candidateRank) {
                    considered = false
                } else if RequiresExport(callerNamespace, namespaceNames[index]) && !exportedFlags[index] {
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
//
// ON DEMAND MEANS `ColumnarFreeFunctionHolderSlot`, NOT `For`. Every body the emitter runs is handed
// a SLOT, because most bodies never place anything on a holder: a lambda written inside a type lands
// on that type, a display class and an anonymous object type are module-level, and a body with no
// lambda at all asks for nothing. Resolving the `TypeBuilder` up front instead — merely to have one
// ready in case the body lifted something — gave EVERY namespace that declared so much as one method
// an empty public `Program`, which a C# consumer referencing two such assemblies then saw as CS0433
// (measured on the tip compiler at `f369e5d22`: 11 of them in `NSharpLang.Compiler.Core` and 2 in
// `Compiler`, and `dotnet build src/NSharpLang.Cli` could not name `Program` at all).
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
    //
    // CALLING THIS CREATES THE TYPE. Ask for it only where a member is about to be declared on it;
    // a body that MIGHT lift something takes a `ColumnarFreeFunctionHolderSlot` instead.
    func ForFile(sourceFileId: int): TypeBuilder {
        return For(program.NamespaceNameForFile(sourceFileId))
    }

    // The module every synthesized type this program defines goes into — a display class, an
    // anonymous object type. Reaching it through the holder used to mean CREATING the holder.
    func Module(): ModuleBuilder {
        return module
    }

    func For(namespaceName: string): TypeBuilder {
        existing: TypeBuilder? = null
        if buildersByNamespace.TryGetValue(namespaceName, out existing) {
            return existing
        }

        created := module.DefineType(
            HolderNameFor(namespaceName),
            TypeAttributes.Public | TypeAttributes.Class
        )
        buildersByNamespace[namespaceName] = created
        ordered.Add(created)
        return created
    }

    // The ordinary name unless this namespace's source already declares a type of it, in which case
    // the reserved spelling — see `ColumnarFreeFunctionScope`'s comment for why the holder yields.
    func HolderNameFor(namespaceName: string): string {
        ordinary := ColumnarFreeFunctionScope.HolderTypeName(namespaceName, rootTypeName)
        if !program.DeclaresSourceTypeNamed(ordinary) {
            return ordinary
        }

        return ColumnarFreeFunctionScope.HolderTypeName(namespaceName, ColumnarFreeFunctionScope.ReservedHolderTypeName(rootTypeName))
    }

    // Every holder that was actually needed, in creation order, for the final `CreateType` pass.
    func Created(): List<TypeBuilder> {
        return ordered
    }
}

// ONE BODY'S HOLDER, BEFORE IT EXISTS.
//
// The emitter carries this instead of a `TypeBuilder`, so that asking WHERE a file's free functions
// and lifted methods would go is not the same act as CREATING the type they would go on. Only
// `Builder()` creates it, and only three placements ever call it: a file-level lambda, a file-level
// capture-free local function, and the free functions themselves. Everything else a body needs from
// the holder — the module a display class or an anonymous object type is defined in — is available
// without one.
class ColumnarFreeFunctionHolderSlot {
    holders: ColumnarFreeFunctionHolders
    sourceFileId: int

    constructor(freeFunctionHolders: ColumnarFreeFunctionHolders, holderSourceFileId: int) {
        if freeFunctionHolders == null {
            throw new InvalidOperationException("A free-function holder slot requires the program's holder table.")
        }
        holders = freeFunctionHolders
        sourceFileId = holderSourceFileId
    }

    // CREATES the holder if this is the first member placed on it. Call it at the point of
    // declaration, never to have one in hand.
    func Builder(): TypeBuilder {
        return holders.ForFile(sourceFileId)
    }

    func Module(): ModuleBuilder {
        return holders.Module()
    }
}
