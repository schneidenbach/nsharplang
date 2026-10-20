namespace NSharpLang.AsyncDefaultType.Tests

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Threading.Tasks
import NSharpLang.Cli
import NSharpLang.Compiler

// `language.asyncDefaultType` IS HONOURED, BY THE ANALYZER AND THE EMITTER ALIKE (issue #199).
//
// The RUNTIME half is this project's own source: its `project.yml` says `asyncDefaultType: Task`, so
// the typed locals below only analyse if the analyzer wrapped in `Task`, and the reflection reads
// only pass if the emitter did too. The COMPILE half builds fixture projects in a temp directory
// through `MultiFileCompiler`, the way `nlc build` does, for the ASP.NET shapes the issue names.
async func loadUser(id: int): string {
    await Task.Delay(1)
    return "user" + id.ToString()
}

async func touch() {
    await Task.Delay(1)
}

// A written task type is never re-wrapped, whatever the default.
async func cached(): ValueTask<int> {
    await Task.Delay(1)
    return 3
}

class Counter {
    Total: int

    async func AddAsync(amount: int): int {
        await Task.Delay(1)
        Total = Total + amount
        return Total
    }

    static async func ZeroAsync(): int {
        await Task.Delay(1)
        return 0
    }
}

// The slot wins over the project default in BOTH directions: `IAsyncDisposable.DisposeAsync`
// returns `ValueTask`, so this member does too in a `Task` project.
class Lease: IAsyncDisposable {
    Released: bool

    async func DisposeAsync() {
        await Task.Delay(1)
        Released = true
    }
}

func DeclaredReturn(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
    assert method != null, name
    return method.ReturnType
}

test "an unannotated async function returns Task of T in a Task project" {
    pending: Task<string> = loadUser(7)
    assert pending.Result == "user7"

    unit: Task = touch()
    unit.Wait()
    assert unit.IsCompleted
}

test "an unannotated async method, instance or static, returns the Task family" {
    counter := new Counter()
    added: Task<int> = counter.AddAsync(4)
    assert added.Result == 4
    zero: Task<int> = Counter.ZeroAsync()
    assert zero.Result == 0
    assert DeclaredReturn(typeof(Counter), "AddAsync") == typeof(Task<int>)
    assert DeclaredReturn(typeof(Counter), "ZeroAsync") == typeof(Task<int>)
}

func runTwice(): int {
    async func twice(value: int): int {
        await Task.Delay(1)
        return value * 2
    }

    local: Task<int> = twice(21)
    return local.Result
}

test "a local async function follows the project default too" {
    assert runTwice() == 42
}

test "a written ValueTask stays a ValueTask in a Task project" {
    written: ValueTask<int> = cached()
    assert written.AsTask().Result == 3
}

test "an implementation of a ValueTask interface slot keeps ValueTask in a Task project" {
    assert DeclaredReturn(typeof(Lease), "DisposeAsync") == typeof(ValueTask)

    lease := new Lease()
    disposable: IAsyncDisposable = lease
    disposable.DisposeAsync().AsTask().Wait()
    assert lease.Released
}

// ── the compile half ─────────────────────────────────────────────────────────────────────────────

func AdtRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-async-default-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

// A web project, because both issue shapes live in the ASP.NET shared framework.
func AdtWebProject(root: string, name: string, languageSection: string, source: string) {
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\nsdk: Microsoft.NET.Sdk.Web\ndependencies:\n  - framework: Microsoft.AspNetCore.App\n" + languageSection)
    File.WriteAllText(Path.Combine(root, "Worker.nl"), source)
}

func AdtCompile(root: string, name: string, out errors: List<CompilerError>): string {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    // `nlc build` resolves the `framework:` reference to its shared-framework assemblies first.
    CompilationReferenceResolver.AddResolvedDllReferences(root, config, new ReferenceResolutionOptions { Quiet: true })
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    outputPath := Path.Combine(Path.Combine(root, "out"), name + ".dll")
    result := compiler.CompileToIlAssembly(name, outputPath, true, true)
    errors = new List<CompilerError>()
    for error in result.Errors {
        errors.Add(error)
    }
    return outputPath
}

func AdtErrorText(errors: List<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + error.Line.ToString() + ":" + error.Column.ToString() + " " + error.Message + "\n"
    }
    return text
}

// The ASP.NET shared framework beside the running runtime, at the runtime's own version.
func AdtAspNetDirectory(): string {
    runtimeDirectory := Path.TrimEndingDirectorySeparator(RuntimeEnvironment.GetRuntimeDirectory())
    version := Path.GetFileName(runtimeDirectory)
    shared := Path.GetDirectoryName(Path.GetDirectoryName(runtimeDirectory) ?? "") ?? ""
    candidate := Path.Combine(Path.Combine(shared, "Microsoft.AspNetCore.App"), version)
    assert Directory.Exists(candidate), candidate
    return candidate
}

// What the emitted assembly's method returns, read as metadata: `nlc test`'s host does not load the
// ASP.NET shared framework, and a signature is a metadata fact anyway.
func AdtEmittedReturn(assemblyPath: string, typeName: string, methodName: string): string {
    paths := new List<string>()
    paths.AddRange(Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll"))
    paths.AddRange(Directory.GetFiles(AdtAspNetDirectory(), "*.dll"))
    paths.Add(assemblyPath)
    context := new MetadataLoadContext(new PathAssemblyResolver(paths))
    try {
        assembly := context.LoadFromAssemblyPath(assemblyPath)
        owner := assembly.GetType(typeName)
        assert owner != null, typeName
        method := owner.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly)
        assert method != null, methodName
        return method.ReturnType.FullName ?? ""
    } finally {
        context.Dispose()
    }
}

func AdtTickerSource(returnAnnotation: string): string {
    return "namespace Fixture\n\nimport System.Threading\nimport System.Threading.Tasks\nimport Microsoft.Extensions.Hosting\n\nclass Ticker: BackgroundService {\n    Ticks: int\n\n    override async func ExecuteAsync(stoppingToken: CancellationToken)" + returnAnnotation + " {\n        while !stoppingToken.IsCancellationRequested && Ticks < 3 {\n            Ticks = Ticks + 1\n            await Task.Delay(1)\n        }\n    }\n}\n"
}

func AdtMiddlewareSource(): string {
    return "namespace Fixture\n\nimport Microsoft.AspNetCore.Http\n\nclass Stamp {\n    next: RequestDelegate\n\n    constructor(next: RequestDelegate) {\n        this.next = next\n    }\n\n    async func InvokeAsync(context: HttpContext) {\n        context.Response.Headers[\"X-Stamp\"] = \"stamped\"\n        await next(context)\n    }\n}\n"
}

test "an unannotated BackgroundService.ExecuteAsync override builds and returns Task under the ValueTask default" {
    root := AdtRoot("ticker")
    try {
        AdtWebProject(root, "TickerFixture", "", AdtTickerSource(""))
        errors: List<CompilerError> = null
        output := AdtCompile(root, "TickerFixture", out errors)
        assert errors.Count == 0, AdtErrorText(errors)
        assert AdtEmittedReturn(output, "Fixture.Ticker", "ExecuteAsync") == "System.Threading.Tasks.Task"
    } finally {
        Directory.Delete(root, true)
    }
}

test "an override that writes the other task family is told which family its base returns" {
    root := AdtRoot("ticker-mismatch")
    try {
        AdtWebProject(root, "TickerMismatch", "", AdtTickerSource(": ValueTask"))
        errors: List<CompilerError> = null
        AdtCompile(root, "TickerMismatch", out errors)
        assert errors.Count == 1, AdtErrorText(errors)
        error := errors[0]
        assert error.DiagnosticId == "NL202", AdtErrorText(errors)
        assert error.Line == 10 && error.Column == 25, AdtErrorText(errors)
        assert error.Message == "'ExecuteAsync' returns 'ValueTask', but the base member it overrides, 'BackgroundService.ExecuteAsync', returns 'Task'", error.Message
        suggestion := error.Suggestion ?? ""
        assert suggestion.StartsWith("Declare the return as ': Task' to match.", StringComparison.Ordinal), suggestion
        assert suggestion.Contains("N# then takes 'Task' from 'BackgroundService.ExecuteAsync'", StringComparison.Ordinal), suggestion
    } finally {
        Directory.Delete(root, true)
    }
}

// Middleware is DUCK-TYPED: ASP.NET finds `InvokeAsync` by name at startup, so there is no slot to
// infer from. The project default decides, and `asyncDefaultType: Task` is the fix the docs name.
test "middleware InvokeAsync returns Task under asyncDefaultType Task and ValueTask under the default" {
    taskRoot := AdtRoot("middleware-task")
    valueTaskRoot := AdtRoot("middleware-valuetask")
    try {
        AdtWebProject(taskRoot, "StampTask", "language:\n  asyncDefaultType: Task\n", AdtMiddlewareSource())
        taskErrors: List<CompilerError> = null
        taskOutput := AdtCompile(taskRoot, "StampTask", out taskErrors)
        assert taskErrors.Count == 0, AdtErrorText(taskErrors)
        assert AdtEmittedReturn(taskOutput, "Fixture.Stamp", "InvokeAsync") == "System.Threading.Tasks.Task"

        AdtWebProject(valueTaskRoot, "StampValueTask", "", AdtMiddlewareSource())
        valueTaskErrors: List<CompilerError> = null
        valueTaskOutput := AdtCompile(valueTaskRoot, "StampValueTask", out valueTaskErrors)
        assert valueTaskErrors.Count == 0, AdtErrorText(valueTaskErrors)
        assert AdtEmittedReturn(valueTaskOutput, "Fixture.Stamp", "InvokeAsync") == "System.Threading.Tasks.ValueTask"
    } finally {
        Directory.Delete(taskRoot, true)
        Directory.Delete(valueTaskRoot, true)
    }
}

// ── what an async function cannot say ────────────────────────────────────────────────────────────

// A bare `return` completes a UNIT task. A task that owes a RESULT still needs a value on every path,
// so the same statement in `async ...: Task<int>` is NL305 — the analyzer, not the emitter, says so.
test "a bare return in an async function that owes a result is NL305" {
    root := AdtRoot("bare-return-owes-result")
    try {
        AdtWebProject(root, "BareOwes", "", "import System.Threading.Tasks\n\nasync func Compute(x: int): Task<int> {\n    if x == 0 {\n        return\n    }\n    await Task.Delay(1)\n    return x\n}\n")
        errors: List<CompilerError> = null
        AdtCompile(root, "BareOwes", out errors)
        assert errors.Count >= 1, AdtErrorText(errors)
        assert errors[0].DiagnosticId == "NL305", AdtErrorText(errors)
        assert errors[0].Line == 5 && errors[0].Column == 9, AdtErrorText(errors)
    } finally {
        Directory.Delete(root, true)
    }
}

// Generic async free functions use the same state-machine lowering as generic async methods.
test "a generic async free function compiles" {
    root := AdtRoot("generic-async-free")
    try {
        AdtWebProject(root, "GenericFree", "", "import System.Threading.Tasks\n\nasync func Read<T>(value: T): T {\n    await Task.Delay(1)\n    return value\n}\n")
        errors: List<CompilerError> = null
        AdtCompile(root, "GenericFree", out errors)
        assert errors.Count == 0, AdtErrorText(errors)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a generic async local function inside an async owner gets a positioned semantic diagnostic" {
    root := AdtRoot("generic-async-local")
    try {
        AdtWebProject(root, "GenericLocal", "", "import System.Threading.Tasks\n\nasync func Outer(): int {\n    async func hold<U>(value: U): U {\n        await Task.Delay(1)\n        return value\n    }\n    return await hold(1)\n}\n")
        errors: List<CompilerError> = null
        AdtCompile(root, "GenericLocal", out errors)
        assert errors.Count == 1, AdtErrorText(errors)
        assert errors[0].DiagnosticId == "NL354", AdtErrorText(errors)
        assert errors[0].Line == 4 && errors[0].Column > 0, AdtErrorText(errors)
        assert errors[0].Message.Contains("generic parameters", StringComparison.Ordinal), errors[0].Message
    } finally {
        Directory.Delete(root, true)
    }
}

test "a generic async method cannot shadow its declaring type parameter" {
    root := AdtRoot("generic-async-shadowed-type-parameter")
    try {
        source := "import System.Threading.Tasks\n\nclass Box<T> {\n    async func Map<T>(value: T): T {\n        await Task.Delay(1)\n        return value\n    }\n}\n"
        AdtWebProject(root, "ShadowedAsyncTypeParameter", "", source)
        errors: List<CompilerError> = null
        AdtCompile(root, "ShadowedAsyncTypeParameter", out errors)
        assert errors.Count == 1, AdtErrorText(errors)
        assert errors[0].DiagnosticId == "NL316", AdtErrorText(errors)
        assert errors[0].Message.Contains("Type parameter 'T' shadows an enclosing type parameter", StringComparison.Ordinal), errors[0].Message
    } finally {
        Directory.Delete(root, true)
    }
}
