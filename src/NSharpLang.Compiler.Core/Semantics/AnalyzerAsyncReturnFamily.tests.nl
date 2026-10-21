namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.Columnar


// THE TASK AN UNANNOTATED `async` MEMBER RETURNS, pinned at the analyzer's public entry point: the
// project's `language.asyncDefaultType` reaches it through `ApplyLanguageSettings`, and a member that
// fills a slot takes the slot's family whatever the project says.
func AsyncFamilyErrors(analyzer: Analyzer, source: string): List<CompilerError> {
    projectRoot := Path.Combine(Path.GetTempPath(), "nsharp-async-family-" + Guid.NewGuid().ToString("N"))
    filePath := Path.Combine(projectRoot, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null
    Directory.CreateDirectory(projectRoot)
    errors := new List<CompilerError>()
    try {
        result := analyzer.Analyze(unit, filePath, projectRoot, source)
        for error in result.Errors {
            if error.Severity == ErrorSeverity.Error {
                errors.Add(error)
            }
        }
    } finally {
        Directory.Delete(projectRoot, true)
    }

    return errors
}

func AsyncFamilyAnalyzer(): Analyzer {
    analyzer := new Analyzer()
    analyzer.LoadSystemAssemblies()
    return analyzer
}

func AsyncFamilyConfig(asyncDefaultType: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("AsyncFamilyProbe")
    config.Language.AsyncDefaultType = asyncDefaultType
    return config
}

func AsyncFamilyText(errors: List<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + Convert.ToInt32(error.Code).ToString() + " " + error.Line.ToString() + ":" + error.Column.ToString() + " " + error.Message + "\n"
    }
    return text
}

func AsyncFamilyFreeFunctionSource(): string {
    return "import System.Threading.Tasks\n\nasync func getUser(id: int): string {\n    await Task.Delay(1)\n    return \"user\" + id.ToString()\n}\n\nfunc probe(): Task<string> {\n    return getUser(1)\n}\n"
}

func AsyncFamilyGenericAsyncOwnerSource(): string {
    return "import System.Threading.Tasks\n\nasync func genericOwner<T>(source: Task<T>): Task<T> {\n    async func readLocal(value: Task<T>): Task<T> {\n        return await value\n    }\n    return await readLocal(source)\n}\n\nasync func ownGenericLocal(source: Task<int>): Task<int> {\n    async func local<U>(value: Task<U>): Task<U> {\n        return await value\n    }\n    return await local(source)\n}\n\nclass GenericClass<T> {\n    async func ReadLocal(source: Task<T>): Task<T> {\n        async func local(value: Task<T>): Task<T> {\n            return await value\n        }\n        return await local(source)\n    }\n}\n\nstruct GenericStruct<T> {\n    async func ReadLocal(source: Task<T>): Task<T> {\n        async func local(value: Task<T>): Task<T> {\n            return await value\n        }\n        return await local(source)\n    }\n}\n"
}

test "an unannotated async function wraps in ValueTask until the project says Task" {
    analyzer := AsyncFamilyAnalyzer()
    try {
        assert analyzer.AsyncDefaultFamily == AsyncTaskFamily.ValueTask
        valueTask := AsyncFamilyErrors(analyzer, AsyncFamilyFreeFunctionSource())
        assert valueTask.Count == 1, AsyncFamilyText(valueTask)
        assert valueTask[0].Code == ErrorCode.TypeMismatch, AsyncFamilyText(valueTask)
        assert valueTask[0].Message.Contains("ValueTask<string>", StringComparison.Ordinal), valueTask[0].Message

        analyzer.ApplyLanguageSettings(AsyncFamilyConfig("Task"))
        assert analyzer.AsyncDefaultFamily == AsyncTaskFamily.Task
        task := AsyncFamilyErrors(analyzer, AsyncFamilyFreeFunctionSource())
        assert task.Count == 0, AsyncFamilyText(task)
    } finally {
        analyzer.Dispose()
    }
}

test "async locals inside generic async owners analyze without diagnostics" {
    analyzer := AsyncFamilyAnalyzer()
    try {
        errors := AsyncFamilyErrors(analyzer, AsyncFamilyGenericAsyncOwnerSource())
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}

test "async lambdas in generic methods and types analyze without diagnostics" {
    analyzer := AsyncFamilyAnalyzer()
    source := "import System\nimport System.Threading.Tasks\n\nasync func Read<T>(source: Task<T>): Task<T> {\n    read: Func<Task<T>> = async () => {\n        return await source\n    }\n    return await read()\n}\n\nclass Box<T> {\n    async func Read(source: Task<T>): Task<T> {\n        read: Func<Task<T>> = async () => {\n            return await source\n        }\n        return await read()\n    }\n}\n"
    try {
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}

// The language server's shared analyzer serves every project in the workspace: re-applying the
// settings is what moves it from one project's answer to the next.
test "re-applying the language settings moves a shared analyzer between project defaults" {
    analyzer := AsyncFamilyAnalyzer()
    try {
        analyzer.LoadFromProjectConfig(AsyncFamilyConfig("Task"), null)
        assert AsyncFamilyErrors(analyzer, AsyncFamilyFreeFunctionSource()).Count == 0

        analyzer.ApplyLanguageSettings(AsyncFamilyConfig("ValueTask"))
        assert AsyncFamilyErrors(analyzer, AsyncFamilyFreeFunctionSource()).Count == 1

        analyzer.ApplyLanguageSettings(AsyncFamilyConfig("Task"))
        assert AsyncFamilyErrors(analyzer, AsyncFamilyFreeFunctionSource()).Count == 0
    } finally {
        analyzer.Dispose()
    }
}

test "an override of a metadata Task slot is typed Task under the ValueTask default" {
    source := "import System.IO\nimport System.Threading\nimport System.Threading.Tasks\n\nclass CountingStream: MemoryStream {\n    override async func FlushAsync(_token: CancellationToken) {\n        await Task.Delay(1)\n    }\n}\n\nfunc probe(stream: CountingStream): Task {\n    return stream.FlushAsync(CancellationToken.None)\n}\n"
    analyzer := AsyncFamilyAnalyzer()
    try {
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}

test "an implementation of a source interface member is typed with that member's task" {
    source := "import System.Threading.Tasks\n\ninterface IWorker {\n    func RunAsync(seed: int): Task<int>\n}\n\nclass Doubler: IWorker {\n    async func RunAsync(seed: int): int {\n        await Task.Delay(1)\n        return seed * 2\n    }\n}\n\nclass Tripler: IWorker {\n    async func IWorker.RunAsync(seed: int): int {\n        await Task.Delay(1)\n        return seed * 3\n    }\n}\n\nfunc probe(worker: Doubler): Task<int> {\n    return worker.RunAsync(1)\n}\n"
    analyzer := AsyncFamilyAnalyzer()
    try {
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}

// The slot wins in the other direction too: a `Task` project still implements a `ValueTask` slot.
test "an implementation of a ValueTask slot stays ValueTask under the Task default" {
    source := "import System\nimport System.Threading.Tasks\n\nclass Lease: IAsyncDisposable {\n    async func DisposeAsync() {\n        await Task.Delay(1)\n    }\n}\n\nfunc probe(lease: Lease): ValueTask {\n    return lease.DisposeAsync()\n}\n"
    analyzer := AsyncFamilyAnalyzer()
    try {
        analyzer.ApplyLanguageSettings(AsyncFamilyConfig("Task"))
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}

test "a member that writes the other task family is told what the slot returns and how to match it" {
    source := "import System.IO\nimport System.Threading\nimport System.Threading.Tasks\n\ninterface IWorker {\n    func RunAsync(): Task<int>\n}\n\nclass Worker: IWorker {\n    async func RunAsync(): ValueTask<int> {\n        await Task.Delay(1)\n        return 7\n    }\n}\n\nclass CountingStream: MemoryStream {\n    override async func FlushAsync(_token: CancellationToken): ValueTask {\n        await Task.Delay(1)\n    }\n}\n"
    analyzer := AsyncFamilyAnalyzer()
    try {
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 2, AsyncFamilyText(errors)

        worker := errors[0]
        assert worker.Code == ErrorCode.TypeMismatch
        assert worker.Line == 10 && worker.Column == 16 && worker.Length == 8, AsyncFamilyText(errors)
        assert worker.Message == "'RunAsync' returns 'ValueTask<int>', but the interface member it implements, 'IWorker.RunAsync', returns 'Task<int>'", worker.Message
        assert (worker.Suggestion ?? "") == "Declare the return as ': Task<int>' to match. .NET binds an override or an interface implementation by its exact return type, and 'Task' and 'ValueTask' are different types. On an 'async' member you can also leave the return unannotated: N# then takes 'Task' from 'IWorker.RunAsync'.", worker.Suggestion ?? ""

        stream := errors[1]
        assert stream.Code == ErrorCode.TypeMismatch
        assert stream.Line == 17 && stream.Column == 25, AsyncFamilyText(errors)
        assert stream.Message == "'FlushAsync' returns 'ValueTask', but the base member it overrides, 'MemoryStream.FlushAsync', returns 'Task'", stream.Message
        assert (stream.Suggestion ?? "").StartsWith("Declare the return as ': Task' to match.", StringComparison.Ordinal), stream.Suggestion ?? ""
    } finally {
        analyzer.Dispose()
    }
}

test "a static member and a non-override fill no slot and take the project default" {
    source := "import System.IO\nimport System.Threading.Tasks\n\nclass Holder: MemoryStream {\n    static async func MakeAsync(): int {\n        await Task.Delay(1)\n        return 1\n    }\n}\n\nfunc probe(): ValueTask<int> {\n    return Holder.MakeAsync()\n}\n"
    analyzer := AsyncFamilyAnalyzer()
    try {
        errors := AsyncFamilyErrors(analyzer, source)
        assert errors.Count == 0, AsyncFamilyText(errors)
    } finally {
        analyzer.Dispose()
    }
}
