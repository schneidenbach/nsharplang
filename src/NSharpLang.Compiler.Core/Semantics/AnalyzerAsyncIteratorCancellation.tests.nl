namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// The cancellation selection rule is source-semantic: it must resolve aliases/imports and the BCL
// attribute identity the same way the normal analyzer does. These contracts therefore drive real
// source through Analyzer.Analyze instead of testing a spelling-only helper.
func AsyncIteratorCancellationDiagnostics(source: string): List<CompilerError> {
    root := Path.Combine(Path.GetTempPath(), "nsharp-async-iterator-cancellation-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    filePath := Path.Combine(root, "Probe.nl")
    parsed := ColumnarParserRecovery.ParseFileAst(source, filePath)
    assert parsed.Errors.Count == 0
    unit := parsed.CompilationUnit
    assert unit != null

    analyzer := new Analyzer()
    try {
        analyzer.LoadSystemAssemblies()
        result := analyzer.Analyze(unit, filePath, root, source)
        matches := new List<CompilerError>()
        for error in result.Errors {
            if error.Code == ErrorCode.AsyncIteratorCancellationTokenSelection {
                matches.Add(error)
            }
        }
        return matches
    } finally {
        analyzer.Dispose()
        Directory.Delete(root, true)
    }
}

func AsyncIteratorCancellationSource(signature: string): string {
    return "import System.Collections.Generic\nimport System.Runtime.CompilerServices\nimport System.Threading\n\n" + signature + " { yield 1 }\n"
}

test "an async iterator with multiple cancellation tokens requires one BCL selection" {
    errors := AsyncIteratorCancellationDiagnostics(AsyncIteratorCancellationSource("async func* Read(source: CancellationToken, request: CancellationToken): IAsyncEnumerable<int>"))
    assert errors.Count == 1
    assert errors[0].Message == "Async iterator 'Read' has 2 `CancellationToken` parameters, so N# cannot infer which one receives the consumer's cancellation token"
    assert errors[0].Suggestion == "Mark exactly one `CancellationToken` parameter with `[EnumeratorCancellation]`. Other token parameters remain independent."
    assert errors[0].Line == 5
}

test "an async iterator accepts exactly one semantically resolved BCL selection" {
    errors := AsyncIteratorCancellationDiagnostics(AsyncIteratorCancellationSource("async func* Read(source: CancellationToken, [EnumeratorCancellation] request: CancellationToken): IAsyncEnumerable<int>"))
    assert errors.Count == 0
}

test "an async iterator with one cancellation token selects it automatically" {
    errors := AsyncIteratorCancellationDiagnostics(AsyncIteratorCancellationSource("async func* Read(request: CancellationToken): IAsyncEnumerable<int>"))
    assert errors.Count == 0
}

test "EnumeratorCancellation cannot select a parameter of another type" {
    errors := AsyncIteratorCancellationDiagnostics(AsyncIteratorCancellationSource("async func* Read([EnumeratorCancellation] request: int, source: CancellationToken, other: CancellationToken): IAsyncEnumerable<int>"))
    assert errors.Count == 1
    assert errors[0].Message == "`[EnumeratorCancellation]` on parameter 'request' cannot select a cancellation token because the parameter is not a `CancellationToken`"
}
