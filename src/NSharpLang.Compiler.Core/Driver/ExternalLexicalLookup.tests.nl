namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import NSharpLang.Compiler.Columnar


// A NAMESPACE'S MEMBERS ARE ITS TYPES, WHICHEVER ASSEMBLY COMPILED THEM — over real projects.
//
// `SimpleNamePrecedence.Select` decides which namespace a bare name binds in; what is asserted here is
// that the ANALYZER, the EMITTER on its own (the emit-only path the compiler's own source is built
// through) and code intelligence all reach that decision when the enclosing namespace's types come
// from a REFERENCED ASSEMBLY rather than from source — the shape every slice of `Compiler.Core` takes
// once it is carved into its own project. A library is emitted here and referenced by the consumer
// under test, because the reference set is part of the question.
func LexlookRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-lexical-lookup-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func LexlookWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, source)
}

// `Lexlook.Lib` declares `TypeInfo` (spelled like `System.Reflection.TypeInfo` on purpose); its child
// `Lexlook.Lib.Ast` declares `Node`; `Lexlook.Lib.Left` and `Lexlook.Lib.Right` each declare `Widget`.
func LexlookEmitLibrary(root: string): string {
    libraryRoot := Path.Combine(root, "library")
    Directory.CreateDirectory(libraryRoot)
    LexlookWrite(libraryRoot, "project.yml", "name: LexlookLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    LexlookWrite(libraryRoot, "Lib.nl", "namespace Lexlook.Lib\n\nclass TypeInfo {\n    static func Make(): TypeInfo {\n        return new TypeInfo()\n    }\n\n    func Side(): string {\n        return \"lib\"\n    }\n}\n")
    LexlookWrite(libraryRoot, "Ast.nl", "namespace Lexlook.Lib.Ast\n\nclass Node {\n    func Kind(): string {\n        return \"node\"\n    }\n}\n")
    LexlookWrite(libraryRoot, "Left.nl", "namespace Lexlook.Lib.Left\n\nclass Widget {\n    func Who(): string {\n        return \"left\"\n    }\n}\n")
    LexlookWrite(libraryRoot, "Right.nl", "namespace Lexlook.Lib.Right\n\nclass Widget {\n    func Who(): string {\n        return \"right\"\n    }\n}\n")

    config := ProjectFileParser.Parse(Path.Combine(libraryRoot, "project.yml"))
    compiler := new MultiFileCompiler(libraryRoot, config)
    compiler.AotMode = false
    outputPath := Path.Combine(libraryRoot, "LexlookLib.dll")
    result := compiler.CompileToIlAssembly("LexlookLib", outputPath, false, true)
    assert result.Success
    assert File.Exists(outputPath)
    return outputPath
}

// A consumer project referencing the emitted library, with one source file. It is a SIBLING of the
// library's directory, never its parent: a project compiles every `.nl` file under its root, so a
// consumer above the library would compile the library's source into itself and meet every type as
// a SOURCE type -- and no row here would be asking about a referenced assembly at all.
func LexlookConsumer(tag: string, source: string): string {
    workspace := LexlookRoot(tag)
    libraryPath := LexlookEmitLibrary(workspace)
    root := Path.Combine(workspace, "consumer")
    Directory.CreateDirectory(root)
    LexlookWrite(root, "project.yml", "name: LexlookConsumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + libraryPath + "\n")
    LexlookWrite(root, "Consumer.nl", source)
    return root
}

// The emitted library beside a consumer.
func LexlookLibraryPath(root: string): string {
    return Path.Combine(Path.Combine(Path.GetDirectoryName(root) ?? root, "library"), "LexlookLib.dll")
}

// Analysis AND the lint rules, the way `nlc build` validates a project: NL010 and NL002 are answered
// from the analyzer's import-usage facts, so they are part of what a binding decides.
func LexlookErrors(root: string): List<CompilerError> {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    result := compiler.CompileToIlAssembly("LexlookConsumer", Path.Combine(root, "analysed", "LexlookConsumer.dll"), true, true)
    errors := new List<CompilerError>()
    for error in result.Errors {
        errors.Add(error)
    }
    return errors
}

// Every diagnostic as `CODE message`, one per line, so a failing assertion shows the whole answer.
func LexlookText(errors: IEnumerable<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + error.Message + "\n"
    }
    return text
}

func LexlookCount(errors: List<CompilerError>, diagnosticId: string): int {
    count := 0
    for error in errors {
        if error.DiagnosticId == diagnosticId {
            count = count + 1
        }
    }
    return count
}

// The consumer emitted WITHOUT analysis — `CompileToIlAssembly(..., validateWithLegacyAnalysis:
// false)`, the path the compiler's own source takes — so only the emitter's binding walk decides.
func LexlookEmitOnly(root: string): MultiFileCompilationResult {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    return compiler.CompileToIlAssembly("LexlookConsumer", Path.Combine(root, "out", "LexlookConsumer.dll"), false, false)
}

// A parameter's type in the emitted consumer as `<full name> @ <declaring assembly>`, read through a
// metadata-only load context so nothing is loaded into the test process. The assembly is part of the
// answer: a library type must come from the LIBRARY, or the row was not about a referenced assembly.
func LexlookParameterType(root: string, typeName: string, methodName: string): string {
    paths := new List<string>()
    paths.Add(Path.Combine(root, "out", "LexlookConsumer.dll"))
    paths.Add(LexlookLibraryPath(root))
    for runtimeAssembly in Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll") {
        paths.Add(runtimeAssembly)
    }
    context := new MetadataLoadContext(new PathAssemblyResolver(paths), "System.Private.CoreLib")
    try {
        assembly := context.LoadFromAssemblyPath(Path.Combine(root, "out", "LexlookConsumer.dll"))
        owner := assembly.GetType(typeName)
        if owner == null {
            return "<no type " + typeName + ">"
        }
        method := owner.GetMethod(methodName)
        if method == null {
            return "<no method " + methodName + ">"
        }
        parameterType := method.GetParameters()[0].ParameterType
        return (parameterType.FullName ?? "<unnamed>") + " @ " + (parameterType.Assembly.GetName().Name ?? "<unnamed>")
    } finally {
        context.Dispose()
    }
}

// A type's base in the emitted consumer, `<full name> @ <declaring assembly>`, read the same way.
func LexlookBaseType(root: string, typeName: string): string {
    paths := new List<string>()
    paths.Add(Path.Combine(root, "out", "LexlookConsumer.dll"))
    paths.Add(LexlookLibraryPath(root))
    for runtimeAssembly in Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll") {
        paths.Add(runtimeAssembly)
    }
    context := new MetadataLoadContext(new PathAssemblyResolver(paths), "System.Private.CoreLib")
    try {
        assembly := context.LoadFromAssemblyPath(Path.Combine(root, "out", "LexlookConsumer.dll"))
        owner := assembly.GetType(typeName)
        if owner == null {
            return "<no type " + typeName + ">"
        }
        baseType := owner.BaseType
        if baseType == null {
            return "<no base>"
        }
        return (baseType.FullName ?? "<unnamed>") + " @ " + (baseType.Assembly.GetName().Name ?? "<unnamed>")
    } finally {
        context.Dispose()
    }
}

func LexlookFailureText(result: MultiFileCompilationResult): string {
    text := LexlookText(result.Errors)
    for error in result.Errors {
        text = text + (error.HumanExplanation ?? "") + "\n"
    }
    return text
}

// `Lexlook.Lib.Consumer` sits inside `Lexlook.Lib`, so the library's `TypeInfo` is an ENCLOSING
// namespace's member; `import System.Reflection` supplies `System.Reflection.TypeInfo`.
func LexlookEnclosingSource(): string {
    return "namespace Lexlook.Lib.Consumer\n\nimport System.Reflection\n\nclass Consumer {\n    static func Describe(info: TypeInfo): string {\n        return info.Side()\n    }\n\n    static func Make(): string {\n        return TypeInfo.Make().Side()\n    }\n\n    static func Kind(node: Ast.Node): string {\n        return node.Kind()\n    }\n}\n"
}

test "analysis binds an enclosing namespace's referenced-assembly type over an import of the same name" {
    errors := LexlookErrors(LexlookConsumer("analysis-enclosing", LexlookEnclosingSource()))

    // No NL303 (`Side` is not a member of System.Reflection.TypeInfo), no NL209 and no NL002: the
    // bare name, the static receiver and the relative `Ast.Node` all bound the library's types.
    assert LexlookCount(errors, "NL303") == 0, LexlookText(errors)
    assert LexlookCount(errors, "NL209") == 0, LexlookText(errors)
    assert LexlookCount(errors, "NL002") == 0, LexlookText(errors)
    // And the import supplied NOTHING, which NL010 is right to say — it is the only finding.
    assert LexlookCount(errors, "NL010") == 1, LexlookText(errors)
    assert errors.Count == 1, LexlookText(errors)
}

test "the emitter alone binds the same enclosing type and reads a relative qualifier into metadata" {
    root := LexlookConsumer("emit-enclosing", LexlookEnclosingSource())
    result := LexlookEmitOnly(root)
    assert result.Success, LexlookFailureText(result)

    assert LexlookParameterType(root, "Lexlook.Lib.Consumer.Consumer", "Describe") == "Lexlook.Lib.TypeInfo @ LexlookLib"
    assert LexlookParameterType(root, "Lexlook.Lib.Consumer.Consumer", "Kind") == "Lexlook.Lib.Ast.Node @ LexlookLib"
}

// Two imports that each supply `Widget` from a referenced assembly, in the order given.
func LexlookTieSource(firstImport: string, secondImport: string): string {
    return "namespace Lexlook.Consumer\n\nimport " + firstImport + "\nimport " + secondImport + "\n\nclass Consumer {\n    static func Who(widget: Widget): string {\n        return widget.Who()\n    }\n}\n"
}

test "two imports of one referenced-assembly name are NL209 whichever order they are written in" {
    sorted := LexlookErrors(LexlookConsumer("tie-sorted", LexlookTieSource("Lexlook.Lib.Left", "Lexlook.Lib.Right")))
    reversed := LexlookErrors(LexlookConsumer("tie-reversed", LexlookTieSource("Lexlook.Lib.Right", "Lexlook.Lib.Left")))

    assert LexlookCount(sorted, "NL209") == 1, LexlookText(sorted)
    assert LexlookCount(reversed, "NL209") == 1, LexlookText(reversed)
    // The candidates are named in import order, so each order names both.
    sortedText := LexlookText(sorted)
    reversedText := LexlookText(reversed)
    assert sortedText.Contains("'Widget' is ambiguous between 'Lexlook.Lib.Left.Widget' and 'Lexlook.Lib.Right.Widget'"), sortedText
    assert reversedText.Contains("'Widget' is ambiguous between 'Lexlook.Lib.Right.Widget' and 'Lexlook.Lib.Left.Widget'"), reversedText
}

test "the emitter alone refuses a tie between two imports and names both candidates" {
    result := LexlookEmitOnly(LexlookConsumer("emit-tie", LexlookTieSource("Lexlook.Lib.Right", "Lexlook.Lib.Left")))

    // Emitting whichever import was written first is exactly the silent re-binding `nlc format`'s
    // import sort would turn into a behaviour change, so the emit-only path declines and says why.
    assert !result.Success
    text := LexlookFailureText(result)
    assert text.Contains("'Widget' is ambiguous between 'Lexlook.Lib.Right.Widget' and 'Lexlook.Lib.Left.Widget'"), text
}

test "sorting a file's imports cannot change what it binds" {
    // The formatter sorts imports. With the tie an error and a lexical declaration a win, no order of
    // the same imports can mean a different program: the file below writes them unsorted, the
    // formatter reorders them, and analysis of both texts reports the same diagnostics.
    unsorted := "namespace Lexlook.Lib.Consumer\n\nimport System.Reflection\nimport Lexlook.Lib.Right\nimport Lexlook.Lib.Left\n\nclass Consumer {\n    static func Describe(info: TypeInfo): string {\n        return info.Side()\n    }\n\n    static func Who(widget: Widget): string {\n        return widget.Who()\n    }\n}\n"
    formatted := ""
    unit := ColumnarParserRecovery.ParseFileAst(unsorted, "Consumer.nl").CompilationUnit
    if unit != null {
        formatter := new Formatter(new FormatterConfig())
        formatted = formatter.Format(unit, null)
    }
    assert formatted.Length > 0
    assert formatted != unsorted
    assert formatted.IndexOf("import Lexlook.Lib.Left", StringComparison.Ordinal) < formatted.IndexOf("import Lexlook.Lib.Right", StringComparison.Ordinal), formatted

    before := LexlookText(LexlookErrors(LexlookConsumer("format-before", unsorted)))
    after := LexlookText(LexlookErrors(LexlookConsumer("format-after", formatted)))
    assert before.Replace("Lexlook.Lib.Right.Widget' and 'Lexlook.Lib.Left.Widget", "Lexlook.Lib.Left.Widget' and 'Lexlook.Lib.Right.Widget") == after, before + "----\n" + after
    assert after.Contains("'Widget' is ambiguous"), after
    assert !after.Contains("'Side' not found"), after
}

test "code intelligence treats an enclosing namespace as in scope and offers no import for it" {
    unit := ColumnarParserRecovery.ParseFileAst(LexlookEnclosingSource(), "Consumer.nl").CompilationUnit
    assert unit != null

    // The file's own namespace and every enclosing one need no import; a sibling still does.
    assert ImportEditPlanner.IsNamespaceInScope(unit, "Lexlook.Lib.Consumer")
    assert ImportEditPlanner.IsNamespaceInScope(unit, "Lexlook.Lib")
    assert ImportEditPlanner.IsNamespaceInScope(unit, "Lexlook")
    assert ImportEditPlanner.IsNamespaceInScope(unit, "System.Reflection")
    assert !ImportEditPlanner.IsNamespaceInScope(unit, "Lexlook.Lib.Left")
    assert !ImportEditPlanner.IsNamespaceInScope(unit, "Lexlook.Li")
}

test "a class base named by a bare name binds the enclosing namespace's referenced-assembly type over an imported source one" {
    // The base is decided while the emitter's scope is built, before any referenced assembly can be
    // asked; the precedence rule is asked again once it can. `Lexlook.Rival.TypeInfo` is SOURCE and
    // imported, `Lexlook.Lib.TypeInfo` is metadata in the enclosing namespace — the enclosing one wins,
    // in the emitted parent AND in the member scope: the rival declares a member named `Environment`,
    // which would shadow `System.Environment` inside `Derived` if the rival were its base.
    root := LexlookConsumer("emit-base", "namespace Lexlook.Lib.Consumer\n\nimport System\nimport Lexlook.Rival\n\nclass Derived: TypeInfo {\n    func Twice(): string {\n        return Side() + Side()\n    }\n\n    func Line(): string {\n        return Environment.NewLine\n    }\n\n    static func Take(value: Derived): string {\n        return value.Twice() + value.Line()\n    }\n}\n")
    LexlookWrite(root, "Rival.nl", "namespace Lexlook.Rival\n\nclass TypeInfo {\n    func Environment(): string {\n        return \"rival\"\n    }\n}\n")

    analysed := LexlookErrors(root)
    assert LexlookCount(analysed, "NL301") == 0, LexlookText(analysed)
    assert LexlookCount(analysed, "NL303") == 0, LexlookText(analysed)
    assert LexlookCount(analysed, "NL209") == 0, LexlookText(analysed)

    result := LexlookEmitOnly(root)
    assert result.Success, LexlookFailureText(result)
    assert LexlookParameterType(root, "Lexlook.Lib.Consumer.Derived", "Take") == "Lexlook.Lib.Consumer.Derived @ LexlookConsumer"
    assert LexlookBaseType(root, "Lexlook.Lib.Consumer.Derived") == "Lexlook.Lib.TypeInfo @ LexlookLib"
}
