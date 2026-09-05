namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// ONE STEP THE IMPORT WALK CANNOT TAKE FOR ITSELF.
//
// There is exactly ONE kind, and it is the arc's first request that asks for an EFFECT rather than
// for an answer:
//
//   1  load the reference assemblies this namespace import implies, by simple name, in the order
//      `AssemblyNames` gives them.
//
// The load itself is the MetadataLoadContext surface — task 021's subject and nothing this family
// owns — so the driver performs it and the walk resumes. What the walk owns is the POLICY half: WHICH
// assemblies a written namespace implies. That table lives here (`MappedAssemblies`), and it is why
// the request carries names rather than the namespace: the driver's step is then a pure host action
// with no decision left in it.
//
// The round trip cannot be flattened into a pre-pass. The load must happen before the SAME import's
// existence check, because `NamespaceExists` scans the loaded assemblies AND CACHES ITS NEGATIVE
// ANSWER: hoisting every load ahead of every check would let a later import's assembly satisfy an
// earlier import's namespace, and would flip a cached `false` to `true`. The interleaving is what a
// developer sees, so it is preserved by a protocol rather than by a reordering.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class ImportWalkRequest {
    Kind: int
    AssemblyNames: string[]

    constructor(kind: int, assemblyNames: string[]) {
        Kind = kind
        AssemblyNames = assemblyNames
    }
}

// THE WHOLE STATE OF ONE IMPORT WALK, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which of the two this is — 0 a single NAMESPACE import written in the file's preamble,
// 1 the FILE-IMPORT statement list — and the two occupy DISJOINT phase ranges (0-9 and 10-19) rather
// than sharing a numbering, which is this arc's standing rule: a phase number that means two things
// in two forms is a fall-through waiting to happen.
//
// The namespace triple is a FIELD rather than a constructor value because form 1 fills it per
// statement: a `NamespaceImport` inside the file-import list registers through exactly the same two
// phases form 0 uses, and copying the triple into the state is how the two forms share them without
// sharing a phase number.
class ImportWalkState {
    formValue: int

    Form: int => formValue

    Phase: int
    Pending: int

    // Form 1's cursor over the statement list, and the resolver it resolves every path against — one
    // resolver for the whole list, exactly as the shell built one before its loop.
    Statements: List<Statement>?
    Index: int
    Resolver: FileResolver?

    // The namespace import currently being registered, in either form.
    NamespaceName: string
    AliasName: string?
    Line: int
    Column: int

    constructor(form: int, phase: int, statements: List<Statement>?, namespaceName: string, aliasName: string?, line: int, column: int) {
        formValue = form
        Phase = phase
        Pending = 0
        Statements = statements
        Index = 0
        Resolver = null
        NamespaceName = namespaceName
        AliasName = aliasName
        Line = line
        Column = column
    }
}

// WHAT AN `import` MEANS — every question a written import raises, in both of the language's forms.
//
// The NAMESPACE form (`import System.Text [as Alias]`) decides whether the name is a namespace at
// all, whether it is a TYPE written where a namespace belongs, whether any referenced assembly or
// any project source declares it, and where in the line the squiggle points. The FILE form
// (`import "./other.nl" [as Alias]`) decides which file on disk the path names, whether that file
// imports this one back — directly or one level out — what its exported declarations are, and where
// each of those exported names lands: an aliased import fills its own two tables, an unaliased one
// fills the global scope, the semantic model and the binding map, and records enough about every
// unaliased name to say later that two imports brought in the same one.
//
// STATE. Two collections live HERE and nowhere else, and they live here for the same reason: this
// family is their only reader and writer.
//   * the imported-symbol references, keyed by symbol, WITH an explicit first-insertion order list;
//   * the external namespace-existence cache.
// Both are per-analysis and both are cleared by `BeginAnalysis`. Everything else the walk mutates —
// the using-namespace list, the alias map, the two by-alias symbol tables, the type-declaration file
// map — stays an analyzer field, because those are handed LIVE to owners that are never rebuilt
// (`AnalyzerExternalTypeProbe`, `AnalyzerProjectTypeDiscovery`, `AnalyzerTypeResolver`,
// `AnalyzerMemberAccess`, `AnalyzerExtensionMethodResolution`); a copy here would fork the moment the
// shell cleared its own.
//
// THE COLLISION REPORT'S ORDER IS A RULE HERE, NOT AN INHERITED DETAIL. `importedSymbolOrder` is an
// explicit first-insertion key list and the collision walk iterates IT. A `Dictionary` that is only
// added to and cleared enumerates in that same order today, but the order decides which colliding
// symbol a developer is told about first, and a user-visible order should be written down.
//
// This owner is NOT rebuilt when the metadata load context opens or closes: everything it holds —
// the sink, the scope stack, the declaration context, the project sources, the external type probe,
// the function-type factory — is constructed once, and the two collections it owns must survive the
// whole analysis.
class AnalyzerImports {
    diagnostics: AnalyzerDiagnosticSink
    scopes: AnalyzerScopeStack
    declarationContext: AnalyzerDeclarationContext
    projectSources: AnalyzerProjectSourceProvider
    externalTypeProbe: AnalyzerExternalTypeProbe
    functionTypeFactory: AnalyzerFunctionTypeFactory

    // The analyzer's LIVE collections, held by reference and never resnapshotted.
    mlcAssemblies: List<Assembly>
    usingNamespaces: List<string>
    usingAliases: Dictionary<string, string>
    importedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>
    importedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    typeDeclarationFiles: Dictionary<string, string>
    referencedPackageNames: HashSet<string>

    // This owner's own per-analysis state.
    importedSymbols: Dictionary<string, List<ImportedSymbolReference>>
    importedSymbolOrder: List<string>
    externalNamespaceCache: Dictionary<string, bool>

    // Recreated per `Analyze` by the shell, so they arrive at `BeginAnalysis` rather than at
    // construction. A held one would be the previous file's.
    semanticModel: SemanticModel?
    bindingMap: BindingMap?

    // WHICH ASSEMBLIES A WRITTEN NAMESPACE IMPLIES. Built once; a pure table.
    assemblyMappings: Dictionary<string, string[]>

    constructor(diagnosticSink: AnalyzerDiagnosticSink, scopeStack: AnalyzerScopeStack, context: AnalyzerDeclarationContext, sources: AnalyzerProjectSourceProvider, typeProbe: AnalyzerExternalTypeProbe, typeFactory: AnalyzerFunctionTypeFactory, assemblies: List<Assembly>, importedNamespaces: List<string>, aliases: Dictionary<string, string>, symbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>, declarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>, declarationFiles: Dictionary<string, string>, packageNames: HashSet<string>) {
        diagnostics = diagnosticSink
        scopes = scopeStack
        declarationContext = context
        projectSources = sources
        externalTypeProbe = typeProbe
        functionTypeFactory = typeFactory
        mlcAssemblies = assemblies
        usingNamespaces = importedNamespaces
        usingAliases = aliases
        importedSymbolsByAlias = symbolsByAlias
        importedDeclarationsByAlias = declarationsByAlias
        typeDeclarationFiles = declarationFiles
        referencedPackageNames = packageNames
        importedSymbols = new Dictionary<string, List<ImportedSymbolReference>>()
        importedSymbolOrder = new List<string>()
        externalNamespaceCache = new Dictionary<string, bool>()
        semanticModel = null
        bindingMap = null
        assemblyMappings = BuildAssemblyMappings()
    }

    // One call per analysis, from the reset block, AFTER the semantic model and the binding map have
    // been recreated and BEFORE the first import is walked. This family sits on the entry path, so
    // the reset order is part of its contract rather than an implementation detail.
    func BeginAnalysis(model: SemanticModel, bindings: BindingMap) {
        semanticModel = model
        bindingMap = bindings
        importedSymbols.Clear()
        importedSymbolOrder.Clear()
        externalNamespaceCache.Clear()
    }

    // ------------------------------------------------------------------------------------------
    // THE PROTOCOL
    // ------------------------------------------------------------------------------------------

    // A namespace import written in the file's preamble.
    func BeginNamespaceImport(namespaceName: string, aliasName: string?, line: int, column: int): ImportWalkState {
        return new ImportWalkState(0, 0, null, namespaceName, aliasName, line, column)
    }

    // The file-import statement list.
    func BeginFileImports(statements: List<Statement>): ImportWalkState {
        return new ImportWalkState(1, 10, statements, "", null, 0, 0)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when the walk is finished.
    func NextStep(state: ImportWalkState): ImportWalkRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. The one kind answers NOTHING — it is an effect on the
    // analyzer's loaded-assembly list, which this owner reads live — so the walk records only that
    // the step is done.
    func Supply(state: ImportWalkState) {
        state.Pending = 0
    }

    func Advance(state: ImportWalkState): ImportWalkRequest? {
        if state.Phase < 10 {
            return AdvanceNamespaceImport(state)
        }

        return AdvanceFileImports(state)
    }

    // ------------------------------------------------------------------------------------------
    // THE NAMESPACE-IMPORT WALK — phases 0 and 1.
    // ------------------------------------------------------------------------------------------
    func AdvanceNamespaceImport(state: ImportWalkState): ImportWalkRequest? {
        if state.Phase == 0 {
            state.Phase = 1
            return LoadStep(state)
        }

        RegisterNamespaceImport(state.NamespaceName, state.AliasName, state.Line, state.Column)
        state.Phase = 99
        return null
    }

    // ------------------------------------------------------------------------------------------
    // THE FILE-IMPORT WALK — phases 10 through 13.
    // ------------------------------------------------------------------------------------------
    func AdvanceFileImports(state: ImportWalkState): ImportWalkRequest? {
        phase := state.Phase
        if phase == 10 {
            projectRoot := projectSources.ProjectRoot
            currentFilePath := diagnostics.CurrentFilePath
            if currentFilePath == null || projectRoot == null {
                state.Phase = 99
                return null
            }

            state.Resolver = new FileResolver(projectRoot, currentFilePath)
            state.Index = 0
            state.Phase = 11
            return null
        }

        if phase == 11 {
            statements := state.Statements
            if statements == null || state.Index >= statements.Count {
                state.Phase = 99
                return null
            }

            statement := statements[state.Index]
            fileImport := statement as FileImport
            if fileImport != null {
                resolver := state.Resolver
                if resolver != null {
                    ProcessFileImport(fileImport, resolver)
                }

                state.Index = state.Index + 1
                return null
            }

            namespaceImport := statement as NamespaceImport
            if namespaceImport != null {
                state.NamespaceName = namespaceImport.Namespace
                state.AliasName = namespaceImport.Alias
                state.Line = namespaceImport.Line
                state.Column = namespaceImport.Column
                state.Phase = 12
                return null
            }

            state.Index = state.Index + 1
            return null
        }

        if phase == 12 {
            state.Phase = 13
            return LoadStep(state)
        }

        RegisterNamespaceImport(state.NamespaceName, state.AliasName, state.Line, state.Column)
        state.Index = state.Index + 1
        state.Phase = 11
        return null
    }

    // The suspension both forms share: ask the driver to load what this namespace implies, or take
    // no step at all when it implies nothing.
    func LoadStep(state: ImportWalkState): ImportWalkRequest? {
        names := MappedAssemblies(state.NamespaceName)
        if names == null {
            return null
        }

        state.Pending = 1
        return new ImportWalkRequest(1, names)
    }

    // ------------------------------------------------------------------------------------------
    // THE NAMESPACE IMPORT
    // ------------------------------------------------------------------------------------------

    // WHAT A NAMESPACE IMPORT DOES ONCE ITS ASSEMBLIES ARE LOADED: it is validated, and only a valid
    // one is registered. An alias replaces the namespace in the alias map; an unaliased import is
    // appended to the ordered using-namespace list, and only once — that list's ORDER is the external
    // type probe's probe order, so a duplicate would change nothing but a re-append would.
    func RegisterNamespaceImport(namespaceName: string, aliasName: string?, line: int, column: int) {
        if !ValidateNamespaceImport(namespaceName, line, column) {
            return
        }

        if aliasName != null {
            usingAliases[aliasName] = namespaceName
            return
        }

        if !usingNamespaces.Contains(namespaceName) {
            usingNamespaces.Add(namespaceName)
        }
    }

    // THE TWO WAYS A NAMESPACE IMPORT IS WRONG, IN ORDER. A spelling that names a TYPE is told so
    // FIRST and by name, with the type's own namespace offered as the fix — that is the mistake a
    // developer actually makes, and reporting "namespace not found" for it would be true and useless.
    // Otherwise the namespace must EXIST: declared by this project's own sources, exported by a loaded
    // reference assembly, or covered by a referenced package whose name the namespace prefixes.
    func ValidateNamespaceImport(namespaceName: string, line: int, column: int): bool {
        diagnosticColumn := FindNamespaceImportColumn(namespaceName, line, column)

        importedType := externalTypeProbe.ResolveExactExternalType(namespaceName)
        if importedType != null {
            typeNamespace := importedType.get_Namespace()
            suggestion := "Import a namespace instead of a type name."
            if !string.IsNullOrWhiteSpace(typeNamespace) {
                suggestion = "Import '" + typeNamespace + "' instead."
            }

            diagnostics.Report(ErrorCode.NamespaceNotFound, "'" + namespaceName + "' is a type, not a namespace — you can only import namespaces", line, diagnosticColumn, suggestion, namespaceName.Length)
            return false
        }

        if NamespaceExists(namespaceName) {
            return true
        }

        if NamespaceMatchesReferencedPackage(namespaceName) {
            return true
        }

        diagnostics.Report(ErrorCode.NamespaceNotFound, "I can't find namespace '" + namespaceName + "' — check the spelling and make sure the assembly is referenced", line, diagnosticColumn, "Check the namespace spelling and project references.", namespaceName.Length)
        return false
    }

    // WHERE THE SQUIGGLE GOES. The namespace's own start column on the import line, found after the
    // `import` keyword so that a namespace which happens to contain the word cannot steal the match.
    // The analysed file's snapshot is preferred; a file that has one only on disk is read from disk.
    func FindNamespaceImportColumn(namespaceName: string, line: int, fallbackColumn: int): int {
        sourceLine := diagnostics.SourceSnippet(line)
        if sourceLine == null {
            currentFilePath := diagnostics.CurrentFilePath
            if !string.IsNullOrWhiteSpace(currentFilePath) && File.Exists(currentFilePath) {
                lines := File.ReadAllLines(currentFilePath)
                // `Skip(n).FirstOrDefault()` over a negative count is the whole sequence, so a line
                // number below 1 answers the FIRST line rather than nothing. Reproduced, not fixed.
                skip := line - 1
                if skip < 0 {
                    skip = 0
                }

                if skip < lines.Length {
                    sourceLine = lines[skip]
                }
            }
        }

        if sourceLine == null {
            return fallbackColumn
        }

        if sourceLine.Length == 0 {
            return fallbackColumn
        }

        importIndex := sourceLine.IndexOf("import", StringComparison.Ordinal)
        searchStart := 0
        if importIndex >= 0 {
            searchStart = importIndex + 6
        }

        namespaceIndex := sourceLine.IndexOf(namespaceName, searchStart, StringComparison.Ordinal)
        if namespaceIndex >= 0 {
            return namespaceIndex + 1
        }

        return fallbackColumn
    }

    // DOES ANYTHING DECLARE THIS NAMESPACE? The project's own sources are asked first and their answer
    // is cached POSITIVE only; the external answer is cached either way, and that cache is why the
    // assembly loads must interleave with these questions rather than all run first.
    //
    // The loaded assemblies are deduplicated by identity as they are scanned, lazily: a match returns
    // before the rest of the list is ever considered, exactly as the generator the shell wrote did.
    func NamespaceExists(namespaceName: string): bool {
        if projectSources.ProjectNamespaceExists(namespaceName) {
            externalNamespaceCache[namespaceName] = true
            return true
        }

        cached := false
        if externalNamespaceCache.TryGetValue(namespaceName, out cached) {
            return cached
        }

        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < mlcAssemblies.Count {
            assembly := mlcAssemblies[index]
            assemblyName := assembly.get_FullName()
            if assemblyName == null {
                identity := assembly.GetName()
                assemblyName = identity.get_Name()
            }

            if assemblyName != null {
                if assemblyName.Length > 0 && seen.Add(assemblyName) {
                    if AssemblyExportsNamespace(assembly, namespaceName) {
                        externalNamespaceCache[namespaceName] = true
                        return true
                    }
                }
            }

            index = index + 1
        }

        externalNamespaceCache[namespaceName] = false
        return false
    }

    func AssemblyExportsNamespace(assembly: Assembly, namespaceName: string): bool {
        exported := assembly.GetExportedTypes()
        index := 0
        while index < exported.Length {
            exportedType := exported[index]
            exportedNamespace := exportedType.get_Namespace()
            if string.Equals(exportedNamespace, namespaceName, StringComparison.Ordinal) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // A REFERENCED PACKAGE COVERS A NAMESPACE when the package IS the namespace or lives under it.
    // A single-segment spelling is never covered: `import Foo` is a mistake worth reporting even when
    // a package named `Foo.Bar` is referenced, because a one-word namespace is almost always a type.
    func NamespaceMatchesReferencedPackage(namespaceName: string): bool {
        if DotCount(namespaceName) < 1 {
            return false
        }

        prefix := namespaceName + "."
        for packageName in referencedPackageNames {
            if string.Equals(packageName, namespaceName, StringComparison.Ordinal) {
                return true
            }

            if packageName.StartsWith(prefix, StringComparison.Ordinal) {
                return true
            }
        }

        return false
    }

    static func DotCount(namespaceName: string): int {
        count := 0
        index := 0
        while index < namespaceName.Length {
            if namespaceName[index] == '.' {
                count = count + 1
            }

            index = index + 1
        }

        return count
    }

    // ------------------------------------------------------------------------------------------
    // THE FILE IMPORT
    // ------------------------------------------------------------------------------------------

    // WHAT A FILE IMPORT MEANS, in the order the questions have to be asked.
    //
    //   1  the path must resolve to a file — reported richly when the import line can be rendered,
    //      plainly when it cannot;
    //   2  it must not be THIS file — a file that imports itself is a cycle of length one;
    //   3  it must parse, and every syntax error in it is reported AT THE IMPORT, because that is
    //      where the reader can act on it;
    //   4  it must not import this file back — one level out, which is the cycle a two-file project
    //      actually writes;
    //   5  its exported declarations become symbols, and WHERE they land is decided by the alias.
    //
    // An aliased import fills its own two tables and nothing else: nothing it exports is in scope
    // unqualified. An unaliased one fills the global scope, records the declaration's location so the
    // IDE can jump to it, records the type in the semantic model and the declaration in the binding
    // map — and records the import reference itself, so that a second unaliased import of the same
    // name can be told about later.
    func ProcessFileImport(fileImport: FileImport, resolver: FileResolver) {
        errorMessage: string? = null
        resolvedPath := ResolveFileImportPath(resolver, fileImport.Path, out errorMessage)
        currentFilePath := diagnostics.CurrentFilePath
        if resolvedPath == null {
            reported := false
            sourceSnippet := diagnostics.SourceSnippet(fileImport.Line)
            if sourceSnippet != null {
                if currentFilePath != null {
                    diagnostics.ReportBuilt(ErrorMessageBuilder.ImportNotFound(currentFilePath, fileImport.Line, fileImport.DiagnosticColumn, sourceSnippet, fileImport.DiagnosticLength, fileImport.Path))
                    reported = true
                }
            }

            if !reported {
                message := ""
                if errorMessage != null {
                    message = errorMessage
                }

                diagnostics.Report(ErrorCode.ImportNotFound, message, fileImport.Line, fileImport.DiagnosticColumn, ErrorSuggestions.GetSuggestion(ErrorCode.ImportNotFound, null, null), fileImport.DiagnosticLength)
            }

            return
        }

        if currentFilePath != null {
            if string.Equals(Path.GetFullPath(resolvedPath), Path.GetFullPath(currentFilePath), StringComparison.OrdinalIgnoreCase) {
                ReportCircularImport(fileImport, currentFilePath, SelfImportMessage(fileImport))
                return
            }
        }

        importedSource := ""
        importedUnit: CompilationUnit? = null
        try {
            fromProject := projectSources.TryGetProjectSourceText(resolvedPath)
            if fromProject != null {
                importedSource = fromProject
            } else {
                importedSource = File.ReadAllText(resolvedPath)
            }

            parseResult := ColumnarParserRecovery.ParseFileAst(importedSource, resolvedPath)
            importedUnit = parseResult.CompilationUnit

            parseErrors := parseResult.Errors
            errorIndex := 0
            while errorIndex < parseErrors.Count {
                parseError := parseErrors[errorIndex]
                diagnostics.Report(ErrorCode.InvalidSyntax, "The imported file '" + fileImport.Path + "' has a syntax error — " + parseError.Message, fileImport.Line, fileImport.DiagnosticColumn, null, fileImport.DiagnosticLength)
                errorIndex = errorIndex + 1
            }

            if importedUnit == null {
                // Can't continue without compilation unit
                return
            }
        } catch ex: Exception {
            diagnostics.Report(ErrorCode.InvalidSyntax, "I couldn't read the imported file '" + fileImport.Path + "' — " + ex.Message, fileImport.Line, fileImport.DiagnosticColumn, null, fileImport.DiagnosticLength)
            return
        }

        resolvedUnit := importedUnit
        if resolvedUnit == null {
            return
        }

        declarationContext.AddCompilationUnit(resolvedPath, resolvedUnit)

        if HasNestedCircularImport(fileImport, resolvedPath, resolvedUnit, currentFilePath) {
            return
        }

        symbols := ExtractPublicSymbols(resolvedUnit, resolvedPath, importedSource)

        aliasName := fileImport.Alias
        if aliasName != null {
            RegisterAliasedSymbols(aliasName, symbols)
            return
        }

        RegisterGlobalSymbols(fileImport, resolvedPath, symbols)
    }

    static func SelfImportMessage(fileImport: FileImport): string {
        return "'" + fileImport.Path + "' imports itself — circular imports aren't allowed"
    }

    // DOES THE IMPORTED FILE IMPORT THIS ONE BACK? One level out only, and only when this analysis
    // knows a project root and a current file. The report points at THIS file's import line, because
    // that is the one the reader can break.
    func HasNestedCircularImport(fileImport: FileImport, resolvedPath: string, importedUnit: CompilationUnit, currentFilePath: string?): bool {
        if importedUnit.FileImports.Count == 0 {
            return false
        }

        projectRoot := projectSources.ProjectRoot
        if projectRoot == null || currentFilePath == null {
            return false
        }

        currentNormalized := Path.GetFullPath(currentFilePath)
        importedFileResolver := new FileResolver(projectRoot, resolvedPath)
        index := 0
        while index < importedUnit.FileImports.Count {
            nestedStatement := importedUnit.FileImports[index]
            nestedFileImport := nestedStatement as FileImport
            if nestedFileImport != null {
                nestedError: string? = null
                nestedPath := ResolveFileImportPath(importedFileResolver, nestedFileImport.Path, out nestedError)
                if nestedPath != null {
                    if string.Equals(Path.GetFullPath(nestedPath), currentNormalized, StringComparison.OrdinalIgnoreCase) {
                        ReportCircularImport(fileImport, currentFilePath, NestedImportMessage(fileImport, nestedFileImport))
                        return true
                    }
                }
            }

            index = index + 1
        }

        return false
    }

    static func NestedImportMessage(fileImport: FileImport, nestedFileImport: FileImport): string {
        return "Circular import: '" + fileImport.Path + "' imports '" + nestedFileImport.Path + "' which imports this file back — break the cycle by restructuring your imports"
    }

    // BOTH CYCLE SHAPES REPORT THE SAME WAY: richly when the import line renders, plainly when it does
    // not, and the plain form is the only one that carries the sentence — the rich builder writes its
    // own. That is the shell's behaviour and it is deliberate: the rich report is a template, and its
    // wording belongs to the message builder.
    func ReportCircularImport(fileImport: FileImport, currentFilePath: string, plainMessage: string) {
        sourceSnippet := diagnostics.SourceSnippet(fileImport.Line)
        if sourceSnippet != null {
            diagnostics.ReportBuilt(ErrorMessageBuilder.CircularImport(currentFilePath, fileImport.Line, fileImport.DiagnosticColumn, sourceSnippet, fileImport.DiagnosticLength, fileImport.Path))
            return
        }

        diagnostics.Report(ErrorCode.CircularImport, plainMessage, fileImport.Line, fileImport.DiagnosticColumn, ErrorSuggestions.GetSuggestion(ErrorCode.CircularImport, null, null), fileImport.DiagnosticLength)
    }

    // WHICH FILE A WRITTEN IMPORT PATH NAMES. The project snapshot is authoritative — an unsaved
    // editor buffer counts as existing — and disk is the fall-back.
    func ResolveFileImportPath(resolver: FileResolver, importPath: string, out errorMessage: string?): string? {
        resolvedPath := Path.GetFullPath(resolver.ResolveFilePath(importPath))
        if projectSources.ContainsSourceText(resolvedPath) || File.Exists(resolvedPath) {
            errorMessage = null
            return resolvedPath
        }

        errorMessage = "Imported file not found: " + importPath + " (resolved to " + resolvedPath + ")"
        return null
    }

    // WHAT AN IMPORTED FILE EXPORTS. A declaration is exported when its own kind and name say so; a
    // top-level type resolves through the declaration context, a `func` through the function-type
    // factory, and anything else contributes nothing. The declaration's COLUMN is the identifier's
    // column rather than the declaration keyword's, so that a jump-to-definition lands on the name.
    func ExtractPublicSymbols(unit: CompilationUnit, filePath: string, sourceText: string?): List<ImportedSymbolInfo> {
        symbols := new List<ImportedSymbolInfo>()

        index := 0
        while index < unit.Declarations.Count {
            declaration := unit.Declarations[index]
            index = index + 1
            name := DeclarationFacts.GetDeclarationName(declaration)
            if name != null {
                symbol := TryExtractPublicSymbol(declaration, name, filePath, sourceText)
                if symbol != null {
                    symbols.Add(symbol)
                }
            }
        }

        return symbols
    }

    // ONE DECLARATION'S EXPORTED SYMBOL, or null when it exports nothing. Split out of the walk
    // because the exported NAME has to be non-nullable at every use below it, and the analyzer's own
    // check follows a positive narrowing but not a `continue` guard.
    func TryExtractPublicSymbol(declaration: Declaration, name: string, filePath: string, sourceText: string?): ImportedSymbolInfo? {
        if !DeclarationFacts.IsExportedDeclaration(declaration, name) {
            return null
        }

        typeInfo: TypeInfo? = null
        if AnalyzerProjectTypeDiscovery.IsTopLevelTypeDeclaration(declaration) {
            typeInfo = declarationContext.ResolveDeclarationType(declaration, filePath)
        } else {
            functionDeclaration := declaration as FunctionDeclaration
            if functionDeclaration != null {
                typeInfo = functionTypeFactory.CreateFromDeclarationInFile(functionDeclaration, filePath)
            }
        }

        if typeInfo == null {
            return null
        }

        declarationColumn := AnalyzerDiagnosticSpanFacts.FindIdentifierNameColumn(sourceText, name, declaration.Line, declaration.Column)
        return new ImportedSymbolInfo(name, typeInfo, new SymbolDeclaration(name, filePath, declaration.Line, declarationColumn, DeclarationFacts.GetDeclarationKind(declaration)))
    }

    // AN ALIASED IMPORT PUTS NOTHING IN SCOPE. Its symbols are reachable only through the alias, so
    // they fill the two by-alias tables and the type-declaration file map — and nothing else.
    func RegisterAliasedSymbols(aliasName: string, symbols: List<ImportedSymbolInfo>) {
        if !importedSymbolsByAlias.ContainsKey(aliasName) {
            importedSymbolsByAlias[aliasName] = new Dictionary<string, TypeInfo>()
        }

        if !importedDeclarationsByAlias.ContainsKey(aliasName) {
            importedDeclarationsByAlias[aliasName] = new Dictionary<string, SymbolDeclaration>()
        }

        aliasedSymbols := importedSymbolsByAlias[aliasName]
        aliasedDeclarations := importedDeclarationsByAlias[aliasName]
        index := 0
        while index < symbols.Count {
            symbol := symbols[index]
            index = index + 1
            aliasedSymbols[symbol.Name] = symbol.Type
            aliasedDeclarations[symbol.Name] = symbol.Declaration
            if AnalyzerBindingFacts.IsTypeDeclarationKind(symbol.Declaration.Kind) {
                RecordDeclarationFile(symbol)
            }
        }
    }

    // AN UNALIASED IMPORT PUTS EVERYTHING IN SCOPE, and records that it did — the import reference is
    // what makes a later collision reportable, and it is recorded for EVERY symbol, not only for the
    // ones that collide, because the collision is only visible once every import has been processed.
    //
    // A `func` becomes a SYMBOL; everything else becomes a TYPE and is additionally recorded in the
    // semantic model, which is what the IDE reads. Both record a declaration location and a binding.
    func RegisterGlobalSymbols(fileImport: FileImport, resolvedPath: string, symbols: List<ImportedSymbolInfo>) {
        index := 0
        while index < symbols.Count {
            symbol := symbols[index]
            index = index + 1
            RecordImportReference(symbol.Name, resolvedPath, fileImport, AnalyzerBindingFacts.IsTypeDeclarationKind(symbol.Declaration.Kind))

            globalScope := scopes.GlobalScope()
            if symbol.Declaration.Kind == "function" {
                globalScope.Symbols[symbol.Name] = symbol.Type
            } else {
                globalScope.Types[symbol.Name] = symbol.Type
                model := semanticModel
                if model != null {
                    model.RecordType(symbol.Name, symbol.Type)
                }

                if AnalyzerBindingFacts.IsTypeDeclarationKind(symbol.Declaration.Kind) {
                    RecordDeclarationFile(symbol)
                }
            }

            globalScope.RecordDeclarationLocation(symbol.Name, symbol.Declaration.File, symbol.Declaration.Line, symbol.Declaration.Column, symbol.Declaration.Kind)

            bindings := bindingMap
            if bindings != null {
                bindings.RecordDeclaration(symbol.Declaration)
            }
        }
    }

    // The declaring file of an imported TYPE, which is what jump-to-definition across a file import
    // reads. The null guard is unreachable by construction — every declaration this family builds
    // carries the resolved import path — and it is written rather than asserted away because a
    // dictionary of non-null strings should not be handed one on a path nobody proved.
    func RecordDeclarationFile(symbol: ImportedSymbolInfo) {
        declarationFile := symbol.Declaration.File
        if declarationFile != null {
            typeDeclarationFiles[symbol.Name] = declarationFile
        }
    }

    // ONE UNALIASED IMPORT OF ONE NAME, REMEMBERED IN FIRST-INSERTION ORDER. The order list is the
    // collision report's iteration order and therefore user-visible; see the type comment.
    func RecordImportReference(symbolName: string, resolvedPath: string, fileImport: FileImport, declaresType: bool) {
        if !importedSymbols.ContainsKey(symbolName) {
            importedSymbols[symbolName] = new List<ImportedSymbolReference>()
            importedSymbolOrder.Add(symbolName)
        }

        importedSymbols[symbolName].Add(new ImportedSymbolReference(resolvedPath, fileImport.Path, fileImport.Line, fileImport.DiagnosticColumn, fileImport.DiagnosticLength, declaresType))
    }

    // ------------------------------------------------------------------------------------------
    // THE COLLISION REPORT
    // ------------------------------------------------------------------------------------------

    // TWO UNALIASED IMPORTS BROUGHT IN THE SAME NAME. Reported once per colliding symbol, at the
    // SECOND import — the one that made it ambiguous — and naming every import the name came from so
    // the reader can choose which one to alias.
    func CheckImportCollisions() {
        index := 0
        while index < importedSymbolOrder.Count {
            symbol := importedSymbolOrder[index]
            index = index + 1
            references := importedSymbols[symbol]
            if references.Count <= 1 {
                continue
            }

            duplicate := references[1]
            importList := FormatImportCollisionSources(references)
            message := "Imported symbol '" + symbol + "' is defined by multiple file imports"
            humanExplanation := "The symbol '" + symbol + "' is imported more than once, so N# cannot choose which definition to use."
            contextualHint := "N# found '" + symbol + "' in these file imports: " + importList + ".\n" + ImportCollisionAdvice(symbol, duplicate)
            suggestion := ImportCollisionSuggestion(symbol, duplicate)

            sourceSnippet := diagnostics.SourceSnippet(duplicate.Line)
            diagnostics.ReportBuilt(AnalyzerDiagnostics.CreateImportCollision(message, diagnostics.CurrentFilePath, duplicate.SourcePath, duplicate.Line, duplicate.Column, sourceSnippet, duplicate.Length, suggestion, humanExplanation, contextualHint))
        }
    }

    // THE FIX THAT COMPILES, WHICH IS NOT THE SAME FIX FOR BOTH KINDS OF SYMBOL. This used to say
    // "Add an alias to one import … and qualify the symbol" for everything, and for a colliding
    // FUNCTION that is a spelling the compiler refuses: the alias clears NL702 and then
    // `Alias.Format(value)` stops the build at NL103 `emit.call.static-member-unmodeled`. Measured on
    // the shipped CLI: an alias-qualified TYPE (`Alias.Tag` as a type and `new Alias.Tag(...)`)
    // resolves and emits; an alias-qualified CALL does not; a fully-qualified `Lib.Money.Format(v)`
    // reports NL301; renaming one of the two declarations always works. So the type arm keeps the
    // alias and the function arm says rename.
    static func ImportCollisionSuggestion(symbol: string, duplicate: ImportedSymbolReference): string {
        if duplicate.DeclaresType {
            return "Add an alias to one import, such as `import \"" + duplicate.ImportPath + "\" as Alias`, and write the type as `Alias." + symbol + "`."
        }

        return "Rename one of the two '" + symbol + "' declarations so each name means one thing — an alias clears the collision but an alias-qualified CALL does not compile yet."
    }

    static func ImportCollisionAdvice(symbol: string, duplicate: ImportedSymbolReference): string {
        if duplicate.DeclaresType {
            return "Unaliased file imports place their exported symbols directly in scope. Use an alias on one import to make the reference explicit."
        }

        return "Unaliased file imports place their exported symbols directly in scope. An alias on one import silences this, but a call through an alias (`Alias." + symbol + "(...)`) is not yet lowered — renaming one declaration is the fix that builds."
    }

    // THE IMPORTS A COLLIDING NAME CAME FROM, quoted as written, deduplicated case-insensitively and
    // in first-occurrence order. The dedupe is on the QUOTED spelling, which is what the shell wrote
    // and what the reader sees.
    static func FormatImportCollisionSources(references: List<ImportedSymbolReference>): string {
        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        ordered := new List<string>()
        index := 0
        while index < references.Count {
            quoted := "\"" + references[index].ImportPath + "\""
            if seen.Add(quoted) {
                ordered.Add(quoted)
            }

            index = index + 1
        }

        return string.Join(", ", ordered)
    }

    // ------------------------------------------------------------------------------------------
    // WHICH ASSEMBLIES A NAMESPACE IMPLIES
    // ------------------------------------------------------------------------------------------

    // THE TABLE. A written namespace whose types live in an assembly the project has not otherwise
    // referenced would resolve to nothing; this is the list of namespaces the language guarantees are
    // usable after a bare `import`, and the assemblies each one needs. The ORDER inside a row is the
    // load order.
    static func BuildAssemblyMappings(): Dictionary<string, string[]> {
        mappings := new Dictionary<string, string[]>()
        mappings["System"] = OneAssembly("System.Runtime")
        mappings["System.Collections.Generic"] = OneAssembly("System.Collections")
        mappings["System.Collections"] = OneAssembly("System.Collections")
        mappings["System.Threading.Tasks"] = OneAssembly("System.Runtime")
        mappings["System.Linq"] = OneAssembly("System.Linq")
        mappings["System.IO"] = OneAssembly("System.Runtime")
        mappings["System.Text"] = OneAssembly("System.Runtime")
        mappings["System.Net.Http"] = OneAssembly("System.Net.Http")
        mappings["System.Text.Json"] = OneAssembly("System.Text.Json")
        // LINQ-to-XML, and it needs BOTH names for a measured reason. `System.Xml.Linq` is a pure
        // FACADE: a MetadataLoadContext does not follow its type forwarders, so
        // `GetExportedTypes()` on it answers ZERO types and a facade-only row admits nothing. The 23
        // types in this namespace are exported by `System.Private.Xml.Linq`, which is the second
        // name. The facade stays FIRST because it is the assembly a project references.
        mappings["System.Xml.Linq"] = TwoAssemblies("System.Xml.Linq", "System.Private.Xml.Linq")
        mappings["System.ComponentModel.DataAnnotations"] = OneAssembly("System.ComponentModel.Annotations")
        mappings["Microsoft.AspNetCore.Builder"] = TwoAssemblies("Microsoft.AspNetCore", "Microsoft.AspNetCore.Http.Abstractions")
        mappings["Microsoft.AspNetCore.Mvc"] = TwoAssemblies("Microsoft.AspNetCore.Mvc.Core", "Microsoft.AspNetCore.Mvc.Abstractions")
        mappings["Microsoft.AspNetCore.Http"] = TwoAssemblies("Microsoft.AspNetCore.Http", "Microsoft.AspNetCore.Http.Abstractions")
        mappings["Microsoft.Extensions.DependencyInjection"] = TwoAssemblies("Microsoft.Extensions.DependencyInjection.Abstractions", "Microsoft.Extensions.DependencyInjection")
        mappings["Microsoft.Extensions.Hosting"] = TwoAssemblies("Microsoft.Extensions.Hosting.Abstractions", "Microsoft.Extensions.Hosting")
        mappings["Microsoft.EntityFrameworkCore"] = TwoAssemblies("Microsoft.EntityFrameworkCore", "Microsoft.EntityFrameworkCore.Abstractions")
        return mappings
    }

    static func OneAssembly(name: string): string[] {
        names := new string[](1)
        names[0] = name
        return names
    }

    static func TwoAssemblies(first: string, second: string): string[] {
        names := new string[](2)
        names[0] = first
        names[1] = second
        return names
    }

    func MappedAssemblies(namespaceName: string): string[]? {
        names := new string[](0)
        if assemblyMappings.TryGetValue(namespaceName, out names) {
            return names
        }

        return null
    }
}
