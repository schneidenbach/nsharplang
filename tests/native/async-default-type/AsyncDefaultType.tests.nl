namespace NSharpLang.AsyncDefaultType.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Threading.Tasks
import NSharpLang.Cli
import NSharpLang.Compiler

class AdtProcessResult {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

func AdtRunProcess(arguments: string, workingDirectory: string): AdtProcessResult {
    startInfo := new ProcessStartInfo { FileName: "dotnet", Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false
    startInfo.EnvironmentVariables["NLC_NO_DAEMON"] = "1"
    process := new Process { StartInfo: startInfo }
    process.Start()
    stdout := process.StandardOutput.ReadToEnd()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    result := new AdtProcessResult(process.ExitCode, stdout, stderr)
    process.Dispose()
    return result
}

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

func AdtBuildAwaitablePatternFixture(root: string): string {
    fixtureDirectory := Path.Combine(root, "fixture")
    outputDirectory := Path.Combine(root, "fixture-bin")
    Directory.CreateDirectory(fixtureDirectory)
    Directory.CreateDirectory(outputDirectory)
    projectPath := Path.Combine(fixtureDirectory, "AwaitablePatternFixture.csproj")
    project := "<Project Sdk=\"Microsoft.NET.Sdk\">\n  <PropertyGroup>\n    <TargetFramework>net10.0</TargetFramework>\n    <ImplicitUsings>enable</ImplicitUsings>\n    <Nullable>enable</Nullable>\n  </PropertyGroup>\n</Project>\n"
    source := "using System;\nusing System.Runtime.CompilerServices;\nusing System.Threading.Tasks;"
    source = source + "\n\nnamespace AwaitablePatternFixtures;"
    source = source + "\n\npublic interface EarlierCompletion {\n    void OnCompleted(Action continuation);\n}"
    source = source + "\n\npublic sealed class MixedAwaitable(Task source) {\n    public MixedAwaiter GetAwaiter<T>() => throw new InvalidOperationException(\"generic GetAwaiter selected\");\n    public MixedAwaiter GetAwaiter() => new(source);\n}"
    source = source + "\n\npublic sealed class MixedAwaiter(Task source) : EarlierCompletion, INotifyCompletion {\n    public bool IsCompleted => source.IsCompleted;\n    public int GetResult<T>() => throw new InvalidOperationException(\"generic GetResult selected\");\n    public int GetResult() { source.GetAwaiter().GetResult(); return 73; }\n    public void OnCompleted(object continuation) { }\n    void EarlierCompletion.OnCompleted(Action continuation) { }\n    void INotifyCompletion.OnCompleted(Action continuation) => source.GetAwaiter().OnCompleted(continuation);\n}"
    source = source + "\n\npublic sealed class GenericOnlyAwaitable {\n    public MixedAwaiter GetAwaiter<T>() => new(Task.CompletedTask);\n}"
    source = source + "\n\npublic sealed class PrivateMemberAwaitable {\n    public PrivateMemberAwaiter GetAwaiter() => new();\n}"
    source = source + "\n\npublic sealed class PrivateMemberAwaiter : INotifyCompletion {\n    private bool IsCompleted => true;\n    private int GetResult() => 89;\n    public void OnCompleted(Action continuation) => continuation();\n}"
    source = source + "\n\npublic sealed class ExtensionAwaitable(Task source) {\n    public Task Source { get; } = source;\n}"
    source = source + "\n\npublic static class AwaitableExtensions {\n    public static MixedAwaiter GetAwaiter(this ExtensionAwaitable value) => new(value.Source);\n}"
    source = source + "\n\npublic sealed class GenericExtensionAwaitable<T>(Task<T> source) {\n    public Task<T> Source { get; } = source;\n}"
    source = source + "\n\npublic sealed class GenericExtensionAwaiter<T>(Task<T> source) : ICriticalNotifyCompletion {\n    public bool IsCompleted => source.IsCompleted;\n    public T GetResult<U>() => throw new InvalidOperationException(\"generic GetResult selected\");\n    public T GetResult() => source.GetAwaiter().GetResult();\n    public void OnCompleted(Action continuation) { }\n    public void UnsafeOnCompleted(Action continuation) => source.GetAwaiter().UnsafeOnCompleted(continuation);\n}"
    source = source + "\n\npublic class ReflectedCompletionBase(Task<int> source) : INotifyCompletion {\n    protected Task<int> Source { get; } = source;\n    public void OnCompleted(object continuation) { }\n    public void OnCompleted(Action continuation) => Source.GetAwaiter().OnCompleted(continuation);\n}"
    source = source + "\n\npublic sealed class ReflectedInheritedAwaiter(Task<int> source) : ReflectedCompletionBase(source) {\n    public bool IsCompleted => Source.IsCompleted;\n    public int GetResult<T>() => throw new InvalidOperationException(\"generic GetResult selected\");\n    public int GetResult() => Source.GetAwaiter().GetResult();\n}"
    source = source + "\n\npublic sealed class ReflectedInheritedAwaitable(Task<int> source) {\n    public ReflectedInheritedAwaiter GetAwaiter() => new(source);\n}"
    source = source + "\n\npublic sealed class ImplicitDecoyAwaiter(Task<int> source) : INotifyCompletion {\n    public bool IsCompleted => source.IsCompleted;\n    public int GetResult<T>() => throw new InvalidOperationException(\"generic GetResult selected\");\n    public int GetResult() => source.GetAwaiter().GetResult();\n    public void OnCompleted(object continuation) { }\n    public void OnCompleted(Action continuation) => source.GetAwaiter().OnCompleted(continuation);\n}"
    source = source + "\n\npublic sealed class ImplicitDecoyAwaitable(Task<int> source) {\n    public ImplicitDecoyAwaiter GetAwaiter() => new(source);\n}"
    source = source + "\n\npublic sealed class GenericGetResultOnlyAwaitable {\n    public GenericGetResultOnlyAwaiter GetAwaiter() => new();\n}"
    source = source + "\n\npublic sealed class GenericGetResultOnlyAwaiter : INotifyCompletion {\n    public bool IsCompleted => true;\n    public int GetResult<T>() => 91;\n    public void OnCompleted(Action continuation) => continuation();\n}"
    source = source + "\n\npublic sealed class NonImplementingAwaitable {\n    public NonImplementingAwaiter GetAwaiter() => new();\n}"
    source = source + "\n\npublic sealed class NonImplementingAwaiter {\n    public bool IsCompleted => true;\n    public int GetResult() => 92;\n    public void OnCompleted(Action continuation) => continuation();\n}"
    source = source + "\n\npublic static class GenericAwaitableExtensions {\n    public static GenericExtensionAwaiter<T> GetAwaiter<T>(this GenericExtensionAwaitable<T> value) => new(value.Source);\n}\n"
    File.WriteAllText(projectPath, project)
    File.WriteAllText(Path.Combine(fixtureDirectory, "Awaitables.cs"), source)
    build := AdtRunProcess("build \"" + projectPath + "\" --output \"" + outputDirectory + "\" --disable-build-servers -nr:false -v q", fixtureDirectory)
    assert build.ExitCode == 0, build.Stdout + build.Stderr
    fixtureAssembly := Path.Combine(outputDirectory, "AwaitablePatternFixture.dll")
    assert File.Exists(fixtureAssembly), fixtureAssembly
    return fixtureAssembly
}

func AdtCompileAwaitableSource(root: string, name: string, fixtureAssembly: string, source: string, out errors: List<CompilerError>): string {
    File.Copy(fixtureAssembly, Path.Combine(root, "AwaitablePatternFixture.dll"), true)
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\ndependencies:\n  - dll: AwaitablePatternFixture.dll\n")
    File.WriteAllText(Path.Combine(root, "Program.nl"), source)
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    CompilationReferenceResolver.AddResolvedDllReferences(root, config, new ReferenceResolutionOptions { Quiet: true })
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    outputPath := Path.Combine(Path.Combine(root, "out"), name + ".dll")
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath) ?? root)
    result := compiler.CompileToIlAssembly(name, outputPath, true, true)
    errors = new List<CompilerError>()
    for error in result.Errors {
        errors.Add(error)
    }
    return outputPath
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

test "a generic async local function inside an async owner compiles" {
    root := AdtRoot("generic-async-local")
    try {
        AdtWebProject(root, "GenericLocal", "", "import System.Threading.Tasks\n\nasync func Outer(): int {\n    async func hold<U>(value: U): U {\n        await Task.Delay(1)\n        return value\n    }\n    return await hold(1)\n}\n")
        errors: List<CompilerError> = null
        AdtCompile(root, "GenericLocal", out errors)
        assert errors.Count == 0, AdtErrorText(errors)
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

test "await selects non-generic overloads and rejects generic-only GetAwaiter" {
    fixtureRoot := AdtRoot("await-pattern-overloads-fixture")
    runtimeRoot := AdtRoot("await-pattern-overloads-runtime")
    negativeRoot := AdtRoot("await-pattern-overloads-negative")
    try {
        fixture := AdtBuildAwaitablePatternFixture(fixtureRoot)
        runtimeSource := "namespace AwaitablePatternProbe\n\nimport System\nimport System.Runtime.CompilerServices\nimport System.Threading.Tasks\nimport AwaitablePatternFixtures\n\n"
        runtimeSource = runtimeSource + "class SourceInstanceAwaiter(source: Task<int>): INotifyCompletion {\n    IsCompleted: bool { get { return source.IsCompleted } }\n    func GetResult(): int { return source.GetAwaiter().GetResult() }\n    func OnCompleted(_continuation: object) { }\n    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }\n}\n\nclass SourceInstanceAwaitable(source: Task<int>) {\n    func GetAwaiter(): SourceInstanceAwaiter { return new SourceInstanceAwaiter(source) }\n}\n"
        runtimeSource = runtimeSource + "class SourceCompletionBase: INotifyCompletion {\n    Source: Task<int>\n    public constructor(source: Task<int>) { Source = source }\n    func OnCompleted(continuation: Action) { Source.GetAwaiter().OnCompleted(continuation) }\n}\n\nclass SourceInheritedAwaiter: SourceCompletionBase {\n    public constructor(source: Task<int>): base(source) { }\n    IsCompleted: bool { get { return Source.IsCompleted } }\n    func GetResult(): int { return Source.GetAwaiter().GetResult() }\n}\n\nclass SourceInheritedAwaitable(source: Task<int>) {\n    func GetAwaiter(): SourceInheritedAwaiter { return new SourceInheritedAwaiter(source) }\n}\n"
        runtimeSource = runtimeSource + "class SourceExtensionBox(source: Task<int>) {\n    Source: Task<int> { get { return source } }\n}\n\nclass SourceExtensionAwaiter(source: Task<int>): INotifyCompletion {\n    IsCompleted: bool { get { return source.IsCompleted } }\n    func GetResult(): int { return source.GetAwaiter().GetResult() }\n    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }\n}\n\nfunc GetAwaiter(this value: SourceExtensionBox): SourceExtensionAwaiter {\n    return new SourceExtensionAwaiter(value.Source)\n}\n"
        runtimeSource = runtimeSource + "class SourceCriticalBox<T>(source: Task<int>) {\n    Source: Task<int> { get { return source } }\n}\n\nclass SourceCriticalAwaiter(source: Task<int>): ICriticalNotifyCompletion {\n    IsCompleted: bool { get { return source.IsCompleted } }\n    func GetResult(): int { return source.GetAwaiter().GetResult() }\n    func OnCompleted(continuation: Action) { source.GetAwaiter().OnCompleted(continuation) }\n    func UnsafeOnCompleted(continuation: Action) { source.GetAwaiter().UnsafeOnCompleted(continuation) }\n}\n\nfunc GetAwaiter<T>(this value: SourceCriticalBox<T>): SourceCriticalAwaiter {\n    return new SourceCriticalAwaiter(value.Source)\n}\n\nclass Probe {\n"
        runtimeSource = runtimeSource + "    static async func ReadTask(source: Task<int>): Task<int> {\n        return await source\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadSourceInstance(source: Task<int>): Task<int> {\n        return await new SourceInstanceAwaitable(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadSourceInherited(source: Task<int>): Task<int> {\n        return await new SourceInheritedAwaitable(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadSourceExtension(source: Task<int>): Task<int> {\n        return await new SourceExtensionBox(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadSourceGenericExtension(source: Task<int>): Task<int> {\n        return await new SourceCriticalBox<int>(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func Read(source: Task): Task<int> {\n        return await new MixedAwaitable(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadExtension(source: Task): Task<int> {\n        return await new ExtensionAwaitable(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadGenericExtension(source: Task<int>): Task<int> {\n        return await new GenericExtensionAwaitable<int>(source)\n    }\n\n"
        runtimeSource = runtimeSource + "    static async func ReadInheritedReflectedBase(source: Task<int>): Task<int> {\n        return await new ReflectedInheritedAwaitable(source)\n    }\n"
        runtimeSource = runtimeSource + "    static async func ReadImplicitDecoy(source: Task<int>): Task<int> {\n        return await new ImplicitDecoyAwaitable(source)\n    }\n"
        runtimeSource = runtimeSource + "    static async func ReadSourceInheritedReflectedBase(source: Task<int>): Task<int> {\n        return await new SourceInheritedReflectedAwaitable(source)\n    }\n}\n\nclass SourceInheritedReflectedAwaiter: ReflectedCompletionBase {\n    public constructor(source: Task<int>): base(source) { }\n    IsCompleted: bool { get { return Source.IsCompleted } }\n    func GetResult(): int { return Source.GetAwaiter().GetResult() }\n}\n\nclass SourceInheritedReflectedAwaitable(source: Task<int>) {\n    func GetAwaiter(): SourceInheritedReflectedAwaiter { return new SourceInheritedReflectedAwaiter(source) }\n}\n"
        runtimeErrors: List<CompilerError> = null
        runtimeAssembly := AdtCompileAwaitableSource(runtimeRoot, "AwaitPatternRuntime", fixture, runtimeSource, out runtimeErrors)
        assert runtimeErrors.Count == 0, AdtErrorText(runtimeErrors)
        runtimeDirectory := Path.GetDirectoryName(runtimeAssembly) ?? runtimeRoot
        File.Copy(fixture, Path.Combine(runtimeDirectory, "AwaitablePatternFixture.dll"), true)
        assembly := Assembly.LoadFrom(runtimeAssembly)
        owner := assembly.GetType("AwaitablePatternProbe.Probe")
        assert owner != null
        names := new List<string>()
        names.Add("ReadTask")
        names.Add("ReadSourceInstance")
        names.Add("ReadSourceInherited")
        names.Add("ReadSourceExtension")
        names.Add("ReadSourceGenericExtension")
        names.Add("Read")
        names.Add("ReadExtension")
        names.Add("ReadGenericExtension")
        names.Add("ReadInheritedReflectedBase")
        names.Add("ReadImplicitDecoy")
        names.Add("ReadSourceInheritedReflectedBase")
        gates := new List<TaskCompletionSource<int>>()
        pendingTasks := new List<Task<int>>()
        for name in names {
            method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
            assert method != null, name
            gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
            arguments := new object[](1)
            arguments[0] = gate.Task
            pending := method.Invoke(null, arguments) as Task<int>
            assert pending != null, name
            assert !pending.IsCompleted, name + " did not suspend on its pending source"
            gates.Add(gate)
            pendingTasks.Add(pending)
        }
        index := 0
        while index < gates.Count {
            gates[index].SetResult(100 + index)
            index += 1
        }
        index = 0
        while index < pendingTasks.Count {
            task := pendingTasks[index]
            assert task.Wait(TimeSpan.FromSeconds(5)), names[index] + " did not resume through its selected continuation slot"
            expected := (names[index] == "Read" || names[index] == "ReadExtension") ? 73 : 100 + index
            assert task.Result == expected, names[index] + " returned " + task.Result.ToString()
            index += 1
        }

        negativeSource := "namespace AwaitablePatternProbe\n\nimport System.Threading.Tasks\nimport AwaitablePatternFixtures\n\nclass Probe {\n    static async func Read(value: GenericOnlyAwaitable): Task<int> {\n        return await value\n    }\n}\n"
        negativeErrors: List<CompilerError> = null
        AdtCompileAwaitableSource(negativeRoot, "AwaitPatternNegative", fixture, negativeSource, out negativeErrors)
        assert negativeErrors.Count == 1, AdtErrorText(negativeErrors)
        assert negativeErrors[0].Line == 8 && negativeErrors[0].Column == 22, AdtErrorText(negativeErrors)
        assert negativeErrors[0].Message.Contains("awaiter pattern is incomplete", StringComparison.Ordinal), AdtErrorText(negativeErrors)

        privateSource := "namespace AwaitablePatternProbe\n\nimport System.Threading.Tasks\nimport AwaitablePatternFixtures\n\nclass Probe {\n    static async func Read(value: PrivateMemberAwaitable): Task<int> {\n        return await value\n    }\n}\n"
        privateErrors: List<CompilerError> = null
        AdtCompileAwaitableSource(negativeRoot, "AwaitPatternPrivate", fixture, privateSource, out privateErrors)
        assert privateErrors.Count == 1, AdtErrorText(privateErrors)
        assert privateErrors[0].Line == 8 && privateErrors[0].Column == 22, AdtErrorText(privateErrors)
        assert privateErrors[0].Message.Contains("awaiter pattern is incomplete", StringComparison.Ordinal), AdtErrorText(privateErrors)

        genericResultSource := "namespace AwaitablePatternProbe\n\nimport System.Threading.Tasks\nimport AwaitablePatternFixtures\n\nclass Probe {\n    static async func Read(value: GenericGetResultOnlyAwaitable): Task<int> {\n        return await value\n    }\n}\n"
        genericResultErrors: List<CompilerError> = null
        AdtCompileAwaitableSource(negativeRoot, "AwaitPatternGenericGetResult", fixture, genericResultSource, out genericResultErrors)
        assert genericResultErrors.Count == 1, AdtErrorText(genericResultErrors)
        assert genericResultErrors[0].Line == 8 && genericResultErrors[0].Column == 22, AdtErrorText(genericResultErrors)
        assert genericResultErrors[0].Message.Contains("awaiter pattern is incomplete", StringComparison.Ordinal), AdtErrorText(genericResultErrors)

        nonImplementingSource := "namespace AwaitablePatternProbe\n\nimport System.Threading.Tasks\nimport AwaitablePatternFixtures\n\nclass Probe {\n    static async func Read(value: NonImplementingAwaitable): Task<int> {\n        return await value\n    }\n}\n"
        nonImplementingErrors: List<CompilerError> = null
        AdtCompileAwaitableSource(negativeRoot, "AwaitPatternNoCompletionInterface", fixture, nonImplementingSource, out nonImplementingErrors)
        assert nonImplementingErrors.Count == 1, AdtErrorText(nonImplementingErrors)
        assert nonImplementingErrors[0].Line == 8 && nonImplementingErrors[0].Column == 22, AdtErrorText(nonImplementingErrors)
        assert nonImplementingErrors[0].Message.Contains("awaiter pattern is incomplete", StringComparison.Ordinal), AdtErrorText(nonImplementingErrors)
    } finally {
        Directory.Delete(fixtureRoot, true)
        Directory.Delete(runtimeRoot, true)
        Directory.Delete(negativeRoot, true)
    }
}
