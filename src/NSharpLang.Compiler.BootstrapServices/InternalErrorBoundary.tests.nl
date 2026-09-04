namespace NSharpLang.Cli

import System
import NSharpLang.Compiler

test "internal errors preserve the invariant sentence and the concrete exception type without a guessed span" {
    error := new InvalidOperationException("AnalyzerScopeStack requires a non-empty scope stack before Peek.")
    expected := "error NL924: Internal compiler error.\nThis is a bug in N#, not in your code.\nAnalyzerScopeStack requires a non-empty scope stack before Peek.\nException: System.InvalidOperationException\nReport this failure: https://schneidenbach.github.io/nsharplang/docs/errors/NL924"
    assert InternalErrorBoundary.Render(error, "") == expected
    assert InternalErrorBoundary.Render(error, "src/Example.nl") == "src/Example.nl: " + expected
    assert InternalErrorBoundary.ExitCode() == 2
}

test "the internal error boundary preserves a command's successful or diagnostic exit status" {
    assert InternalErrorBoundary.Execute(() => 0) == 0
    assert InternalErrorBoundary.Execute(() => 1) == 1
    assert InternalErrorBoundary.Execute(() => 17) == 17
}

test "NL924 is a non-configurable build-blocking compiler diagnostic" {
    descriptor := new DiagnosticDescriptor("", "", DiagnosticSource.Compiler, DiagnosticCategory.Semantic, DiagnosticSeverity.Warning, false)
    assert DiagnosticCatalog.TryGetDescriptor("NL924", out descriptor)
    assert descriptor.Title == "Internal Compiler Error"
    assert descriptor.DefaultSeverity == DiagnosticSeverity.Error
    assert descriptor.BlocksBuildByDefault
    assert !descriptor.IsConfigurable
    assert DiagnosticCatalog.DocsUrlFor("NL924") == "https://schneidenbach.github.io/nsharplang/docs/errors/NL924"
}
