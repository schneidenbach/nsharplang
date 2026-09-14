namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import System.Collections.Generic
import System.IO
import System.Threading
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Helpers for the language-server contract rows converted from the retired xunit suites.
//
// `Diagnostic` in THIS file means the LSP wire diagnostic (OmniSharp), not the N# linter
// diagnostic; the compiler-side types are spelled out in full so both families can be named in
// the same file without an ambiguous import.
//
// Every helper here reaches the server through its PUBLIC surface except LsdConvert* /
// LscConvert*, which reflect over `LspDiagnosticConverter` because that converter is declared
// `internal` and the xunit suite only reached it through InternalsVisibleTo.

// The location of a completion trigger inside a source buffer: the 0-based line holding the
// target text, and the 0-based character immediately after it (where the caret sits while the
// user is typing the prefix).
record LscCompletionTarget(line: int, character: int) {
    Line: int = line
    Character: int = character
}

func LscRequiredType(name: string): Type {
    resolved := Type.GetType(name)
    if resolved == null {
        throw new InvalidOperationException("Required type was not found: " + name)
    }
    return resolved
}

func LscConvertCompilerError(error: NSharpLang.Compiler.CompilerError): Diagnostic {
    converterType := LscRequiredType("NSharpLang.LanguageServer.Services.LspDiagnosticConverter, LanguageServer")
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(NSharpLang.Compiler.CompilerError)
    method := converterType.GetMethod("FromCompilerError", parameterTypes)
    if method == null {
        throw new InvalidOperationException("LspDiagnosticConverter.FromCompilerError was not found.")
    }
    arguments := new object?[](1)
    LscPut(arguments, 0, error)
    converted := method.Invoke(null, arguments) as Diagnostic
    if converted == null {
        throw new InvalidOperationException("Compiler diagnostic conversion returned null.")
    }
    return converted
}

func LscConvertLinterDiagnostic(diagnostic: NSharpLang.Compiler.Diagnostic): Diagnostic {
    converterType := LscRequiredType("NSharpLang.LanguageServer.Services.LspDiagnosticConverter, LanguageServer")
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(NSharpLang.Compiler.Diagnostic)
    method := converterType.GetMethod("FromLinterDiagnostic", parameterTypes)
    if method == null {
        throw new InvalidOperationException("LspDiagnosticConverter.FromLinterDiagnostic was not found.")
    }
    arguments := new object?[](1)
    LscPut(arguments, 0, diagnostic)
    converted := method.Invoke(null, arguments) as Diagnostic
    if converted == null {
        throw new InvalidOperationException("Linter diagnostic conversion returned null.")
    }
    return converted
}

func LscPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func LscCodeText(lsp: Diagnostic): string {
    code := lsp.Code
    if code == null {
        throw new InvalidOperationException("LSP diagnostic carried no code.")
    }
    text := code.String
    if text == null {
        throw new InvalidOperationException("LSP diagnostic code had no string form.")
    }
    return text
}

func LscSourceText(lsp: Diagnostic): string {
    source := lsp.Source
    if source == null {
        throw new InvalidOperationException("LSP diagnostic carried no source.")
    }
    return source
}

func LscIsError(lsp: Diagnostic): bool {
    return (must lsp.Severity) == DiagnosticSeverity.Error
}

func LscIsWarning(lsp: Diagnostic): bool {
    return (must lsp.Severity) == DiagnosticSeverity.Warning
}

func LscIsInformation(lsp: Diagnostic): bool {
    return (must lsp.Severity) == DiagnosticSeverity.Information
}

// Asserts the whole conversion contract for one span: 0-based, single-line, end-exclusive and
// never collapsed to an empty range.
func LscAssertRange(lsp: Diagnostic, line0: int, startCharacter: int, endCharacter: int) {
    assert lsp.Range.Start.Line == line0
    assert lsp.Range.End.Line == line0
    assert lsp.Range.Start.Character == startCharacter
    assert lsp.Range.End.Character == endCharacter
    assert lsp.Range.End.Character > lsp.Range.Start.Character
}

// Reflection setter used only because N# object initializers cannot yet write an init-only
// (modreq IsExternalInit) property on an external type; the property itself is public.
func LscSetProperty(target: object, name: string, value: object?) {
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required property was not found: " + name)
    }
    property.SetValue(target, value)
}

func LscCompletionRequest(uri: string, line: int, character: int): CompletionParams {
    request := new CompletionParams()
    LscSetProperty(request, "TextDocument", new TextDocumentIdentifier(DocumentUri.From(uri)))
    LscSetProperty(request, "Position", new Position(line, character))
    return request
}

func LscCompletionAt(handler: CompletionHandler, uri: string, line: int, character: int): CompletionList {
    task := handler.Handle(LscCompletionRequest(uri, line, character), CancellationToken.None)
    task.Wait()
    response := task.Result
    if response == null {
        throw new InvalidOperationException("Completion handler returned no response.")
    }
    return response
}

func LscFindCompletionTarget(source: string, target: string): LscCompletionTarget {
    index := source.IndexOf(target, StringComparison.Ordinal)
    if index < 0 {
        throw new InvalidOperationException("Test source must contain the completion target text: " + target)
    }
    line := 0
    lineStart := 0
    scan := 0
    while scan < index {
        if source[scan] == '\n' {
            line = line + 1
            lineStart = scan + 1
        }
        scan = scan + 1
    }
    return new LscCompletionTarget(line, index - lineStart + target.Length)
}

func LscSingleCompletionItem(completion: CompletionList, label: string): CompletionItem {
    found: CompletionItem? = null
    count := 0
    for item in completion.Items {
        if item.Label == label {
            found = item
            count = count + 1
        }
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected one completion item labelled " + label + ", found " + count.ToString() + "."
        )
    }
    return found
}

func LscAdditionalEditCount(item: CompletionItem): int {
    edits := item.AdditionalTextEdits
    if edits == null {
        return 0
    }
    count := 0
    for edit in edits {
        _ = edit
        count = count + 1
    }
    return count
}

// Creates a throwaway workspace root carrying the minimal project.yml the workspace scanner
// needs, mirroring the fixture the retired xunit suite built per test.
func LscNewWorkspaceRoot(): string {
    root := LsdTempRoot("nsharp-lsp-workspace-diagnostics-")
    Directory.CreateDirectory(root)
    LsdWriteFile(root, "project.yml", "name: WorkspaceDiagnostics")
    return root
}

func LscPublicationUris(publications: IReadOnlyList<DocumentDiagnosticsPublication>): List<string> {
    uris := new List<string>()
    index := 0
    while index < publications.Count {
        uris.Add(publications[index].Uri)
        index = index + 1
    }
    return uris
}

func LscCountEndingWith(values: IReadOnlyList<string>, suffix: string): int {
    count := 0
    index := 0
    while index < values.Count {
        if values[index].EndsWith(suffix, StringComparison.Ordinal) {
            count = count + 1
        }
        index = index + 1
    }
    return count
}

func LscCountContaining(values: IReadOnlyList<string>, fragment: string): int {
    count := 0
    index := 0
    while index < values.Count {
        if values[index].Contains(fragment, StringComparison.Ordinal) {
            count = count + 1
        }
        index = index + 1
    }
    return count
}
