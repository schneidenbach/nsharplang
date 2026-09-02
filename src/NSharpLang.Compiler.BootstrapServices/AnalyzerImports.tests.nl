namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHAT AN `import` MEANS.
//
// The fifteen members this replaces were all `private` in `Analyzer.cs` (one was `public` with no
// caller) and nothing in `src/`, `tests/` or `editors/` named any of them, so their behaviour was
// pinned only through whichever end-to-end diagnostic a bad import happened to produce. This is
// their first DIRECT pinning, and it is written around the six things this family is easy to get
// wrong.
//
// (1) THE ASSEMBLY LOAD AND THE EXISTENCE CHECK INTERLEAVE. A namespace import asks the driver to
// load what it implies BEFORE its own existence check runs, because that check scans the loaded
// assemblies and CACHES ITS NEGATIVE ANSWER. A pre-pass that loaded everything first would let a
// later import satisfy an earlier one and would flip a cached `false`.
//
// (2) THE TWO NAMESPACE REPORTS ARE ORDERED. A spelling that names a TYPE is told so first and by
// name, with the type's own namespace offered as the fix; only a spelling that names nothing gets
// "I can't find namespace".
//
// (3) AN ALIAS DECIDES WHERE AN IMPORT'S SYMBOLS LAND, IN BOTH FORMS. An aliased namespace import
// fills the alias map and never touches the ordered using list; an aliased FILE import fills its own
// two tables and puts nothing in scope.
//
// (4) THE ORDERED USING LIST IS APPENDED TO ONCE PER NAMESPACE. That list is the external type
// probe's probe ORDER, so a duplicate append would be invisible and a reorder would not.
//
// (5) THE COLLISION REPORT'S ORDER IS FIRST-IMPORT ORDER OF THE SYMBOL, and the report itself points
// at the SECOND import — the one that made the name ambiguous — and lists every source, deduplicated
// case-insensitively on the quoted spelling and in first-occurrence order.
//
// (6) A CYCLE IS TWO SHAPES, NOT ONE: a file that imports itself, and a file whose import imports it
// back one level out.
//
// ONE HONEST LIMIT OF A CONTRACT HARNESS, INHERITED FROM SLICES 63 AND 64: the file-import walk is
// driven entirely through the project's SOURCE SNAPSHOT rather than through disk. That is production
// behaviour, not a stand-in — an unsaved editor buffer resolves exactly this way — and it makes every
// contract here deterministic and free of temporary files.
class ImportHarness {
    Owner: AnalyzerImports
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Provider: AnalyzerProjectSourceProvider
    Assemblies: List<Assembly>
    Namespaces: List<string>
    Aliases: Dictionary<string, string>
    SymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>
    DeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    DeclarationFiles: Dictionary<string, string>
    Packages: HashSet<string>
    Model: SemanticModel
    Bindings: BindingMap

    constructor(
        owner: AnalyzerImports,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        provider: AnalyzerProjectSourceProvider,
        assemblies: List<Assembly>,
        namespaces: List<string>,
        aliases: Dictionary<string, string>,
        symbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>,
        declarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>,
        declarationFiles: Dictionary<string, string>,
        packages: HashSet<string>,
        model: SemanticModel,
        bindings: BindingMap
    ) {
        Owner = owner
        Errors = errors
        Scopes = scopes
        Provider = provider
        Assemblies = assemblies
        Namespaces = namespaces
        Aliases = aliases
        SymbolsByAlias = symbolsByAlias
        DeclarationsByAlias = declarationsByAlias
        DeclarationFiles = declarationFiles
        Packages = packages
        Model = model
        Bindings = bindings
    }
}

func ImportRoot(): string {
    return Path.GetFullPath("import-contract-root")
}

func ImportEntryPath(): string {
    return Path.Combine(ImportRoot(), "Program.nl")
}

func ImportFilePath(name: string): string {
    return Path.Combine(ImportRoot(), name)
}

func ImportHarnessOf(sourceLine: string?): ImportHarness {
    errors := new List<CompilerError>()
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(ImportRoot(), assemblies)
    scopes := new AnalyzerScopeStack()
    model := new SemanticModel()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    bindings := new BindingMap()
    provider := new AnalyzerProjectSourceProvider()
    provider.BeginAnalysis(ImportRoot())
    namespaces := new List<string>()
    aliases := new Dictionary<string, string>(StringComparer.Ordinal)
    symbolsByAlias := new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal)
    declarationsByAlias := new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal)
    declarationFiles := new Dictionary<string, string>(StringComparer.Ordinal)
    packages := new HashSet<string>(StringComparer.Ordinal)
    probe := new AnalyzerExternalTypeProbe(assemblies, namespaces)
    sink := new AnalyzerDiagnosticSink(errors, provider)
    sink.BeginAnalysis(ImportEntryPath(), sourceLine)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, namespaces, declarationFiles)
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, sink, aliases, symbolsByAlias, declarationsByAlias, model, bindings)
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    functionTypes := new AnalyzerFunctionTypeFactory(context, substitution)
    owner := new AnalyzerImports(sink, scopes, context, provider, probe, functionTypes, assemblies, namespaces, aliases, symbolsByAlias, declarationsByAlias, declarationFiles, packages)
    owner.BeginAnalysis(model, bindings)
    return new ImportHarness(owner, errors, scopes, provider, assemblies, namespaces, aliases, symbolsByAlias, declarationsByAlias, declarationFiles, packages, model, bindings)
}

func ImportHarnessNew(): ImportHarness {
    return ImportHarnessOf(null)
}

// THE DRIVER, EXACTLY AS `Analyzer.cs` WRITES IT: relay every request's assembly names and resume.
// The names are collected rather than loaded, which is what makes the protocol itself observable.
func DriveImports(harness: ImportHarness, state: ImportWalkState): List<string> {
    loaded := new List<string>()
    step := harness.Owner.NextStep(state)
    while step != null {
        assert step.Kind == 1
        index := 0
        while index < step.AssemblyNames.Length {
            loaded.Add(step.AssemblyNames[index])
            index = index + 1
        }

        harness.Owner.Supply(state)
        step = harness.Owner.NextStep(state)
    }

    return loaded
}

func DriveNamespaceImport(harness: ImportHarness, namespaceName: string, aliasName: string?, line: int, column: int): List<string> {
    return DriveImports(harness, harness.Owner.BeginNamespaceImport(namespaceName, aliasName, line, column))
}

func DriveFileImports(harness: ImportHarness, statements: List<Statement>): List<string> {
    return DriveImports(harness, harness.Owner.BeginFileImports(statements))
}

// ── source and AST builders ────────────────────────────────────────────────────

func ImportStatements(): List<Statement> {
    return new List<Statement>()
}

func AddFileImport(statements: List<Statement>, path: string, aliasName: string?, line: int, column: int): FileImport {
    node := new FileImport(path, aliasName, line, column)
    statements.Add(node)
    return node
}

func AddNamespaceImportStatement(statements: List<Statement>, namespaceName: string, aliasName: string?, line: int, column: int) {
    statements.Add(new NamespaceImport(namespaceName, aliasName, line, column))
}

// A file the project snapshot knows about. Registering the text is what makes the path resolve, so
// every file-import contract below is a pure in-memory project.
func AddProjectFile(harness: ImportHarness, name: string, body: string): string {
    fullPath := ImportFilePath(name)
    harness.Provider.AddSourceText(fullPath, body)
    return fullPath
}

func WidgetSource(memberName: string): string {
    return "class Widget {\n    " + memberName + ": int\n\n    constructor(value: int) {\n        " + memberName + " = value\n    }\n}\n"
}

func NamedClassSource(typeName: string): string {
    return "class " + typeName + " {\n    Value: int\n\n    constructor(value: int) {\n        Value = value\n    }\n}\n"
}

func HelperSource(functionName: string): string {
    return "func " + functionName + "(): int {\n    return 1\n}\n"
}

func ErrorsWithCode(harness: ImportHarness, code: ErrorCode): List<CompilerError> {
    matched := new List<CompilerError>()
    index := 0
    while index < harness.Errors.Count {
        candidate := harness.Errors[index]
        if candidate.Code == code {
            matched.Add(candidate)
        }

        index = index + 1
    }

    return matched
}

func ImportReferences(paths: List<string>): List<ImportedSymbolReference> {
    references := new List<ImportedSymbolReference>()
    index := 0
    while index < paths.Count {
        references.Add(new ImportedSymbolReference("/resolved/" + paths[index], paths[index], index + 1, 8, 4))
        index = index + 1
    }

    return references
}

func PathList(): List<string> {
    return new List<string>()
}

// ── THE MAPPING TABLE AND THE PROTOCOL ─────────────────────────────────────────

test "the mapping table answers one assembly for the single-assembly namespaces" {
    harness := ImportHarnessNew()
    system := harness.Owner.MappedAssemblies("System")
    assert system != null
    assert system.Length == 1
    assert system[0] == "System.Runtime"

    linq := harness.Owner.MappedAssemblies("System.Linq")
    assert linq != null
    assert linq.Length == 1
    assert linq[0] == "System.Linq"

    json := harness.Owner.MappedAssemblies("System.Text.Json")
    assert json != null
    assert json[0] == "System.Text.Json"

    annotations := harness.Owner.MappedAssemblies("System.ComponentModel.DataAnnotations")
    assert annotations != null
    assert annotations[0] == "System.ComponentModel.Annotations"
}

test "three namespaces all map to System.Runtime, and the collections pair both map to System.Collections" {
    harness := ImportHarnessNew()
    io := harness.Owner.MappedAssemblies("System.IO")
    text := harness.Owner.MappedAssemblies("System.Text")
    tasks := harness.Owner.MappedAssemblies("System.Threading.Tasks")
    assert io != null
    assert text != null
    assert tasks != null
    assert io[0] == "System.Runtime"
    assert text[0] == "System.Runtime"
    assert tasks[0] == "System.Runtime"

    generic := harness.Owner.MappedAssemblies("System.Collections.Generic")
    plain := harness.Owner.MappedAssemblies("System.Collections")
    assert generic != null
    assert plain != null
    assert generic[0] == "System.Collections"
    assert plain[0] == "System.Collections"
}

test "the two-assembly rows keep their load ORDER" {
    harness := ImportHarnessNew()
    builder := harness.Owner.MappedAssemblies("Microsoft.AspNetCore.Builder")
    assert builder != null
    assert builder.Length == 2
    assert builder[0] == "Microsoft.AspNetCore"
    assert builder[1] == "Microsoft.AspNetCore.Http.Abstractions"

    mvc := harness.Owner.MappedAssemblies("Microsoft.AspNetCore.Mvc")
    assert mvc != null
    assert mvc[0] == "Microsoft.AspNetCore.Mvc.Core"
    assert mvc[1] == "Microsoft.AspNetCore.Mvc.Abstractions"

    http := harness.Owner.MappedAssemblies("Microsoft.AspNetCore.Http")
    assert http != null
    assert http[0] == "Microsoft.AspNetCore.Http"
    assert http[1] == "Microsoft.AspNetCore.Http.Abstractions"

    injection := harness.Owner.MappedAssemblies("Microsoft.Extensions.DependencyInjection")
    assert injection != null
    assert injection[0] == "Microsoft.Extensions.DependencyInjection.Abstractions"
    assert injection[1] == "Microsoft.Extensions.DependencyInjection"

    hosting := harness.Owner.MappedAssemblies("Microsoft.Extensions.Hosting")
    assert hosting != null
    assert hosting[0] == "Microsoft.Extensions.Hosting.Abstractions"
    assert hosting[1] == "Microsoft.Extensions.Hosting"

    ef := harness.Owner.MappedAssemblies("Microsoft.EntityFrameworkCore")
    assert ef != null
    assert ef[0] == "Microsoft.EntityFrameworkCore"
    assert ef[1] == "Microsoft.EntityFrameworkCore.Abstractions"

    // LINQ-TO-XML IS A TWO-ASSEMBLY ROW FOR A MEASURED REASON, NOT FOR SYMMETRY. `System.Xml.Linq`
    // is a pure facade of type forwarders, and a MetadataLoadContext does not follow those: asked
    // for its exported types it answers ZERO, so a facade-only row would load an assembly and admit
    // no namespace. The 23 types are exported by `System.Private.Xml.Linq`, the second name. The
    // facade stays first because it is the assembly a project references.
    xmlLinq := harness.Owner.MappedAssemblies("System.Xml.Linq")
    assert xmlLinq != null
    assert xmlLinq.Length == 2
    assert xmlLinq[0] == "System.Xml.Linq"
    assert xmlLinq[1] == "System.Private.Xml.Linq"
}

test "a namespace the table does not name implies no assemblies at all" {
    harness := ImportHarnessNew()
    assert harness.Owner.MappedAssemblies("Totally.Not.Real") == null
    assert harness.Owner.MappedAssemblies("system") == null
    assert harness.Owner.MappedAssemblies("System.Linq.Expressions") == null
}

test "a mapped namespace import suspends exactly once, and the request carries the names" {
    harness := ImportHarnessNew()
    loaded := DriveNamespaceImport(harness, "System.Linq", null, 2, 1)
    assert loaded.Count == 1
    assert loaded[0] == "System.Linq"
}

test "an unmapped namespace import never suspends, and still registers" {
    harness := ImportHarnessNew()
    loaded := DriveNamespaceImport(harness, "System.Collections.Generic", null, 2, 1)
    // System.Collections.Generic IS mapped; the unmapped case is the assertion below.
    assert loaded.Count == 1

    other := ImportHarnessNew()
    silent := DriveNamespaceImport(other, "Totally.Not.Real", null, 2, 1)
    assert silent.Count == 0
    assert other.Errors.Count == 1
}

test "the two forms are told apart by FORM and start in disjoint phase ranges" {
    harness := ImportHarnessNew()
    namespaceWalk := harness.Owner.BeginNamespaceImport("System", null, 2, 1)
    fileWalk := harness.Owner.BeginFileImports(ImportStatements())
    assert namespaceWalk.Form == 0
    assert fileWalk.Form == 1
    assert namespaceWalk.Phase == 0
    assert fileWalk.Phase == 10
    assert namespaceWalk.NamespaceName == "System"
    assert namespaceWalk.Line == 2
    assert namespaceWalk.Column == 1
}

test "an empty file-import list finishes without a single step" {
    harness := ImportHarnessNew()
    loaded := DriveFileImports(harness, ImportStatements())
    assert loaded.Count == 0
    assert harness.Errors.Count == 0
}

test "a namespace import written INSIDE the file-import list takes the same two phases" {
    harness := ImportHarnessNew()
    statements := ImportStatements()
    AddNamespaceImportStatement(statements, "System.Linq", null, 3, 1)
    AddNamespaceImportStatement(statements, "System.Text.Json", "J", 4, 1)
    loaded := DriveFileImports(harness, statements)
    assert loaded.Count == 2
    assert loaded[0] == "System.Linq"
    assert loaded[1] == "System.Text.Json"
}

// ── WHAT A NAMESPACE IMPORT REGISTERS ──────────────────────────────────────────

test "a namespace the loaded assemblies export is silent and joins the ordered using list" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "System.Collections.Generic", null, 2, 1)
    assert harness.Errors.Count == 0
    assert harness.Namespaces.Count == 1
    assert harness.Namespaces[0] == "System.Collections.Generic"
}

test "the ordered using list is appended to ONCE per namespace, however often it is written" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "System.Collections.Generic", null, 2, 1)
    DriveNamespaceImport(harness, "System.Collections.Generic", null, 3, 1)
    DriveNamespaceImport(harness, "System.Collections.Generic", null, 4, 1)
    assert harness.Namespaces.Count == 1
    assert harness.Errors.Count == 0
}

test "an ALIASED namespace import fills the alias map and never touches the using list" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "System.Collections.Generic", "G", 2, 1)
    assert harness.Errors.Count == 0
    assert harness.Namespaces.Count == 0
    assert harness.Aliases.Count == 1
    assert harness.Aliases["G"] == "System.Collections.Generic"
}

test "an INVALID namespace import registers nothing at all" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "Totally.Not.Real", null, 2, 1)
    DriveNamespaceImport(harness, "Also.Not.Real", "X", 3, 1)
    assert harness.Namespaces.Count == 0
    assert harness.Aliases.Count == 0
    assert harness.Errors.Count == 2
}

// ── THE TWO NAMESPACE REPORTS, IN ORDER ────────────────────────────────────────

test "a spelling that names a TYPE is told so by name, with the type's own namespace as the fix" {
    harness := ImportHarnessOf(null)
    DriveNamespaceImport(harness, "System.String", null, 2, 1)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.NamespaceNotFound
    assert reported.Message == "'System.String' is a type, not a namespace — you can only import namespaces"
    assert reported.Suggestion == "Import 'System' instead."
    assert reported.Line == 2
    assert reported.Length == 13
}

test "the type report wins over the not-found report even though the type is not a namespace either" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "System.StringComparison", null, 2, 1)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "'System.StringComparison' is a type, not a namespace — you can only import namespaces"
}

test "a spelling that names nothing gets the not-found sentence, and its LENGTH is the spelling's" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "Totally.Not.Real", null, 7, 1)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.NamespaceNotFound
    assert reported.Message == "I can't find namespace 'Totally.Not.Real' — check the spelling and make sure the assembly is referenced"
    assert reported.Suggestion == "Check the namespace spelling and project references."
    assert reported.Line == 7
    assert reported.Length == 16
}

test "a single-segment unknown spelling reports too" {
    harness := ImportHarnessNew()
    DriveNamespaceImport(harness, "Nope", null, 2, 1)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Length == 4
}

// ── WHERE THE SQUIGGLE GOES ────────────────────────────────────────────────────

test "the column lands on the namespace, not on the keyword" {
    harness := ImportHarnessOf("import Totally.Not.Real\n")
    assert harness.Owner.FindNamespaceImportColumn("Totally.Not.Real", 1, 99) == 8
}

test "extra spacing after the keyword moves the column with it" {
    harness := ImportHarnessOf("import    Totally.Not.Real\n")
    assert harness.Owner.FindNamespaceImportColumn("Totally.Not.Real", 1, 99) == 11
}

test "a namespace that CONTAINS the keyword cannot steal the keyword's own match" {
    harness := ImportHarnessOf("import Importers.Not.Real\n")
    assert harness.Owner.FindNamespaceImportColumn("Importers.Not.Real", 1, 99) == 8
}

test "a namespace absent from the line falls back to the caller's column" {
    harness := ImportHarnessOf("import Something.Else\n")
    assert harness.Owner.FindNamespaceImportColumn("Totally.Not.Real", 1, 42) == 42
}

test "no source at all falls back to the caller's column" {
    harness := ImportHarnessOf(null)
    assert harness.Owner.FindNamespaceImportColumn("Totally.Not.Real", 1, 17) == 17
}

test "a line the source does not have falls back to the caller's column" {
    harness := ImportHarnessOf("import Totally.Not.Real\n")
    assert harness.Owner.FindNamespaceImportColumn("Totally.Not.Real", 9, 5) == 5
}

// ── DOES ANYTHING DECLARE THIS NAMESPACE ───────────────────────────────────────

test "a namespace a loaded assembly exports exists" {
    harness := ImportHarnessNew()
    assert harness.Owner.NamespaceExists("System.Collections.Generic")
    assert !harness.Owner.NamespaceExists("Totally.Not.Real")
}

test "the external answer is CACHED, both ways, and the cache is what survives the assemblies going away" {
    harness := ImportHarnessNew()
    assert harness.Owner.NamespaceExists("System.Collections.Generic")
    assert !harness.Owner.NamespaceExists("Totally.Not.Real")

    // Drop every assembly. A live scan would now answer false for both; the cache answers as before.
    harness.Assemblies.Clear()
    assert harness.Owner.NamespaceExists("System.Collections.Generic")
    assert !harness.Owner.NamespaceExists("Totally.Not.Real")
}

test "the project's OWN namespaces are asked first, from DISK, and are not gated on any assembly" {
    harness := ImportHarnessNew()
    harness.Assemblies.Clear()
    directory := Path.Combine(Path.GetTempPath(), "nsharp-import-ns-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "Other.nl"), "namespace Fx.Root\n\nfunc Helper(): int {\n    return 1\n}\n")
    harness.Provider.BeginAnalysis(directory)

    // The project's own namespace answers YES with no assembly loaded at all; anything else answers
    // NO, because the external scan has nothing to scan.
    assert harness.Owner.NamespaceExists("Fx.Root")
    assert !harness.Owner.NamespaceExists("Fx.Missing")

    Directory.Delete(directory, true)
}

test "a referenced package covers a namespace it IS or lives under, and never a single segment" {
    harness := ImportHarnessNew()
    harness.Packages.Add("Some.Package")
    harness.Packages.Add("Other.Package.Core")
    assert harness.Owner.NamespaceMatchesReferencedPackage("Some.Package")
    assert harness.Owner.NamespaceMatchesReferencedPackage("Other.Package")
    assert !harness.Owner.NamespaceMatchesReferencedPackage("Some")
    assert !harness.Owner.NamespaceMatchesReferencedPackage("Some.Other")
    assert !harness.Owner.NamespaceMatchesReferencedPackage("Some.Packages")
}

test "a package match makes an otherwise unknown namespace silent" {
    harness := ImportHarnessNew()
    harness.Packages.Add("Vendor.Widgets.Core")
    DriveNamespaceImport(harness, "Vendor.Widgets", null, 2, 1)
    assert harness.Errors.Count == 0
    assert harness.Namespaces.Count == 1
}

test "dots are counted, and a spelling with none is never package-covered" {
    assert AnalyzerImports.DotCount("System") == 0
    assert AnalyzerImports.DotCount("System.Text") == 1
    assert AnalyzerImports.DotCount("System.Text.Json") == 2
    assert AnalyzerImports.DotCount("") == 0
    assert AnalyzerImports.DotCount("...") == 3
}

// ── WHAT A FILE IMPORT RESOLVES TO ─────────────────────────────────────────────

test "a path the project snapshot knows resolves, and an unknown one reports where it looked" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 0

    missing := ImportHarnessNew()
    missingStatements := ImportStatements()
    AddFileImport(missingStatements, "./Missing.nl", null, 1, 1)
    DriveFileImports(missing, missingStatements)
    assert missing.Errors.Count == 1
    reported := missing.Errors[0]
    assert reported.Code == ErrorCode.ImportNotFound
    assert reported.Message.StartsWith("Imported file not found: ./Missing.nl", StringComparison.Ordinal)
}

test "an unresolved import points at the import's own diagnostic span" {
    harness := ImportHarnessNew()
    statements := ImportStatements()
    AddFileImport(statements, "./Missing.nl", null, 4, 3)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Line == 4
    assert harness.Errors[0].Column == 3
    assert harness.Errors[0].Length == 1
}

test "a file that imports ITSELF is a cycle of length one, reported richly when the line renders" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Program.nl", "import \"./Program.nl\"\n\nfunc Answer(): int {\n    return 1\n}\n")
    statements := ImportStatements()
    AddFileImport(statements, "./Program.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.CircularImport
    // The RICH builder owns its own wording; the family supplies the position and the path.
    assert reported.Message == "Circular import: './Program.nl' creates a cycle"
    assert reported.SourceSnippet != null
}

// The plain arm is reachable when the import RESOLVES but the analysed file renders no line — an
// empty snapshot entry is exactly that, and it is the only shape that separates the two arms.
test "a self-import with no renderable line falls back to the family's own sentence" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Program.nl", "")
    statements := ImportStatements()
    AddFileImport(statements, "./Program.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.CircularImport
    assert reported.Message == "'./Program.nl' imports itself — circular imports aren't allowed"
}

test "a file whose import imports this one BACK is the other cycle shape" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Program.nl", "import \"./Other.nl\"\n\nfunc Answer(): int {\n    return 1\n}\n")
    AddProjectFile(harness, "Other.nl", "import \"./Program.nl\"\n\nfunc Other(): int {\n    return 2\n}\n")
    statements := ImportStatements()
    AddFileImport(statements, "./Other.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.CircularImport
    assert reported.Message == "Circular import: './Other.nl' creates a cycle"
}

test "the nested cycle's own sentence names BOTH files when no line renders" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Program.nl", "")
    AddProjectFile(harness, "Other.nl", "import \"./Program.nl\"\n\nfunc Other(): int {\n    return 2\n}\n")
    statements := ImportStatements()
    AddFileImport(statements, "./Other.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Code == ErrorCode.CircularImport
    assert reported.Message == "Circular import: './Other.nl' imports './Program.nl' which imports this file back — break the cycle by restructuring your imports"
}

test "an import chain that does NOT come back is silent" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Program.nl", "func Answer(): int {\n    return 1\n}\n")
    AddProjectFile(harness, "Middle.nl", "import \"./Leaf.nl\"\n\nfunc Middle(): int {\n    return 2\n}\n")
    AddProjectFile(harness, "Leaf.nl", HelperSource("Leaf"))
    statements := ImportStatements()
    AddFileImport(statements, "./Middle.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 0
}

test "a syntax error in an imported file is reported AT THE IMPORT" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Broken.nl", "func Broken(: int {\n    return 1\n")
    statements := ImportStatements()
    AddFileImport(statements, "./Broken.nl", null, 6, 2)
    DriveFileImports(harness, statements)
    syntax := ErrorsWithCode(harness, ErrorCode.InvalidSyntax)
    assert syntax.Count > 0
    assert syntax[0].Line == 6
    assert syntax[0].Column == 2
    assert syntax[0].Message.StartsWith("The imported file './Broken.nl' has a syntax error — ", StringComparison.Ordinal)
}

// ── WHAT AN IMPORTED FILE EXPORTS, AND WHERE IT LANDS ──────────────────────────

test "an unaliased import puts an exported TYPE in the global scope and in the semantic model" {
    harness := ImportHarnessNew()
    resolvedPath := AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", null, 1, 1)
    DriveFileImports(harness, statements)

    globalScope := harness.Scopes.GlobalScope()
    assert globalScope.Types.ContainsKey("Widget")
    assert !globalScope.Symbols.ContainsKey("Widget")
    assert harness.DeclarationFiles.ContainsKey("Widget")
    assert harness.DeclarationFiles["Widget"] == resolvedPath
    assert globalScope.GetDeclarationLocation("Widget") != null
}

test "an unaliased import puts an exported FUNC in the symbol table rather than the type table" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Helpers.nl", HelperSource("Helper"))
    statements := ImportStatements()
    AddFileImport(statements, "./Helpers.nl", null, 1, 1)
    DriveFileImports(harness, statements)

    globalScope := harness.Scopes.GlobalScope()
    assert globalScope.Symbols.ContainsKey("Helper")
    assert !globalScope.Types.ContainsKey("Helper")
    // A function is not a type declaration, so it never joins the declaring-file map.
    assert !harness.DeclarationFiles.ContainsKey("Helper")
}

test "a file-private name is not exported at all" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Helpers.nl", HelperSource("helper"))
    statements := ImportStatements()
    AddFileImport(statements, "./Helpers.nl", null, 1, 1)
    DriveFileImports(harness, statements)

    globalScope := harness.Scopes.GlobalScope()
    assert !globalScope.Symbols.ContainsKey("helper")
    assert !globalScope.Types.ContainsKey("helper")
}

test "an ALIASED import fills its own two tables and puts nothing in scope" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", "W", 1, 1)
    DriveFileImports(harness, statements)

    globalScope := harness.Scopes.GlobalScope()
    assert !globalScope.Types.ContainsKey("Widget")
    assert harness.SymbolsByAlias.ContainsKey("W")
    assert harness.SymbolsByAlias["W"].ContainsKey("Widget")
    assert harness.DeclarationsByAlias.ContainsKey("W")
    assert harness.DeclarationsByAlias["W"].ContainsKey("Widget")
    // A type still records its declaring file, so a jump-to-definition works through the alias.
    assert harness.DeclarationFiles.ContainsKey("Widget")
}

test "two aliases of ONE file fill two tables and still put nothing in scope" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", "W", 1, 1)
    AddFileImport(statements, "./Widgets.nl", "V", 2, 1)
    DriveFileImports(harness, statements)

    assert harness.SymbolsByAlias.Count == 2
    assert harness.SymbolsByAlias["W"].ContainsKey("Widget")
    assert harness.SymbolsByAlias["V"].ContainsKey("Widget")
    assert !harness.Scopes.GlobalScope().Types.ContainsKey("Widget")
    assert harness.Errors.Count == 0
}

test "an aliased import beside an unaliased one does not collide with it" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "WidgetsA.nl", WidgetSource("Size"))
    AddProjectFile(harness, "WidgetsB.nl", WidgetSource("Weight"))
    statements := ImportStatements()
    AddFileImport(statements, "./WidgetsA.nl", "W", 1, 1)
    AddFileImport(statements, "./WidgetsB.nl", null, 2, 1)
    DriveFileImports(harness, statements)
    assert harness.Errors.Count == 0

    harness.Owner.CheckImportCollisions()
    assert harness.Errors.Count == 0
}

// ── THE COLLISION REPORT ───────────────────────────────────────────────────────

test "one import of a name never collides with itself" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", null, 1, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()
    assert harness.Errors.Count == 0
}

test "two unaliased imports of one name collide, and the report points at the SECOND import" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "WidgetsA.nl", WidgetSource("Size"))
    AddProjectFile(harness, "WidgetsB.nl", WidgetSource("Weight"))
    statements := ImportStatements()
    AddFileImport(statements, "./WidgetsA.nl", null, 1, 1)
    AddFileImport(statements, "./WidgetsB.nl", null, 2, 5)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()

    assert harness.Errors.Count == 1
    reported := harness.Errors[0]
    assert reported.Message == "Imported symbol 'Widget' is defined by multiple file imports"
    assert reported.Line == 2
    assert reported.Column == 5
    assert reported.Suggestion == "Add an alias to one import, such as `import \"./WidgetsB.nl\" as Alias`, and qualify the symbol."
}

test "three imports of one name still report ONCE, and the hint names every source in order" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "WidgetsA.nl", WidgetSource("Size"))
    AddProjectFile(harness, "WidgetsB.nl", WidgetSource("Weight"))
    AddProjectFile(harness, "WidgetsC.nl", WidgetSource("Depth"))
    statements := ImportStatements()
    AddFileImport(statements, "./WidgetsA.nl", null, 1, 1)
    AddFileImport(statements, "./WidgetsB.nl", null, 2, 1)
    AddFileImport(statements, "./WidgetsC.nl", null, 3, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()

    assert harness.Errors.Count == 1
    hint := harness.Errors[0].ContextualHint
    assert hint != null
    assert hint.StartsWith("N# found 'Widget' in these file imports: \"./WidgetsA.nl\", \"./WidgetsB.nl\", \"./WidgetsC.nl\".", StringComparison.Ordinal)
}

test "THE COLLISION ORDER IS FIRST-IMPORT ORDER OF THE SYMBOL, not alphabetical and not file order" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "One.nl", NamedClassSource("Zeta") + "\n" + NamedClassSource("Alpha"))
    AddProjectFile(harness, "Two.nl", NamedClassSource("Zeta") + "\n" + NamedClassSource("Alpha"))
    statements := ImportStatements()
    AddFileImport(statements, "./One.nl", null, 1, 1)
    AddFileImport(statements, "./Two.nl", null, 2, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()

    assert harness.Errors.Count == 2
    assert harness.Errors[0].Message == "Imported symbol 'Zeta' is defined by multiple file imports"
    assert harness.Errors[1].Message == "Imported symbol 'Alpha' is defined by multiple file imports"
}

test "the same file imported twice collides, and the source list DEDUPES to one entry" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "Widgets.nl", WidgetSource("Size"))
    statements := ImportStatements()
    AddFileImport(statements, "./Widgets.nl", null, 1, 1)
    AddFileImport(statements, "./Widgets.nl", null, 2, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()

    assert harness.Errors.Count == 1
    hint := harness.Errors[0].ContextualHint
    assert hint != null
    assert hint.StartsWith("N# found 'Widget' in these file imports: \"./Widgets.nl\".", StringComparison.Ordinal)
}

test "the source list quotes, dedupes case-insensitively and keeps FIRST-occurrence order" {
    paths := PathList()
    paths.Add("./b.nl")
    paths.Add("./A.nl")
    paths.Add("./B.NL")
    paths.Add("./a.nl")
    paths.Add("./c.nl")
    assert AnalyzerImports.FormatImportCollisionSources(ImportReferences(paths)) == "\"./b.nl\", \"./A.nl\", \"./c.nl\""
}

test "a single source list is a single quoted entry with no separator" {
    paths := PathList()
    paths.Add("./only.nl")
    assert AnalyzerImports.FormatImportCollisionSources(ImportReferences(paths)) == "\"./only.nl\""
}

test "an empty source list formats to the empty string" {
    assert AnalyzerImports.FormatImportCollisionSources(ImportReferences(PathList())) == ""
}

test "the collision report carries the human explanation and the hint's second sentence" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "WidgetsA.nl", WidgetSource("Size"))
    AddProjectFile(harness, "WidgetsB.nl", WidgetSource("Weight"))
    statements := ImportStatements()
    AddFileImport(statements, "./WidgetsA.nl", null, 1, 1)
    AddFileImport(statements, "./WidgetsB.nl", null, 2, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()

    reported := harness.Errors[0]
    assert reported.HumanExplanation == "The symbol 'Widget' is imported more than once, so N# cannot choose which definition to use."
    hint := reported.ContextualHint
    assert hint != null
    assert hint.EndsWith("Unaliased file imports place their exported symbols directly in scope. Use an alias on one import to make the reference explicit.", StringComparison.Ordinal)
}

test "colliding FUNCTIONS collide exactly as colliding types do" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "HelpersA.nl", HelperSource("Helper"))
    AddProjectFile(harness, "HelpersB.nl", HelperSource("Helper"))
    statements := ImportStatements()
    AddFileImport(statements, "./HelpersA.nl", null, 1, 1)
    AddFileImport(statements, "./HelpersB.nl", null, 2, 1)
    DriveFileImports(harness, statements)
    harness.Owner.CheckImportCollisions()
    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Imported symbol 'Helper' is defined by multiple file imports"
}

// ── THE RESET ──────────────────────────────────────────────────────────────────

test "beginning an analysis forgets the previous file's imported symbols and its namespace cache" {
    harness := ImportHarnessNew()
    AddProjectFile(harness, "WidgetsA.nl", WidgetSource("Size"))
    AddProjectFile(harness, "WidgetsB.nl", WidgetSource("Weight"))
    statements := ImportStatements()
    AddFileImport(statements, "./WidgetsA.nl", null, 1, 1)
    AddFileImport(statements, "./WidgetsB.nl", null, 2, 1)
    DriveFileImports(harness, statements)

    harness.Owner.BeginAnalysis(harness.Model, harness.Bindings)
    harness.Owner.CheckImportCollisions()
    assert harness.Errors.Count == 0

    // The namespace cache went with it: the answer is recomputed against the live assemblies.
    harness.Assemblies.Clear()
    assert !harness.Owner.NamespaceExists("System.Collections.Generic")
}
