namespace NSharpLang.Playground

import System
import System.Collections.Generic

public record PlaygroundCatalogResponse(
    SchemaVersion: int,
    DefaultExampleId: string,
    EstimatedMinutes: int,
    Examples: IReadOnlyList<PlaygroundExample>,
    Tutorial: IReadOnlyList<PlaygroundTutorialStep>,
    Capabilities: PlaygroundCapabilities) {
}

public record PlaygroundCapabilities(
    RunsInBrowser: bool,
    SupportsDiagnostics: bool,
    SupportsFormatting: bool,
    SupportsCompletions: bool,
    SupportsHover: bool,
    SupportsSyntaxHighlighting: bool,
    SupportsExecution: bool,
    SupportsTests: bool,
    Limitations: IReadOnlyList<string>) {
}

public record PlaygroundExample(
    Id: string,
    Title: string,
    Summary: string,
    Minutes: int,
    Goal: string,
    Concepts: IReadOnlyList<string>,
    Code: string,
    TestsCode: string?,
    ExpectedOutput: string? = null) {
    public HasTests: bool => !string.IsNullOrWhiteSpace(TestsCode)
}

public record PlaygroundTutorialStep(
    Id: string,
    Title: string,
    Kind: string,
    Narration: string,
    ExampleId: string?,
    Validation: PlaygroundTutorialValidation?) {
}

public record PlaygroundTutorialValidation(
    Type: string,
    ExpectedOutput: string?,
    RequiredText: string?,
    SuccessMessage: string) {
}

public record PlaygroundFile(
    Name: string,
    Code: string) {
}

public record PlaygroundCheckResponse(
    SchemaVersion: int,
    Ok: bool,
    File: string,
    Diagnostics: IReadOnlyList<PlaygroundDiagnostic>,
    Summary: PlaygroundSummary) {
}

public record PlaygroundFormatResponse(
    SchemaVersion: int,
    Ok: bool,
    File: string,
    FormattedCode: string,
    Diagnostics: IReadOnlyList<PlaygroundDiagnostic>,
    Summary: PlaygroundSummary,
    Warnings: IReadOnlyList<string>) {
}

public record PlaygroundCompletionResponse(
    SchemaVersion: int,
    Ok: bool,
    File: string,
    Context: string,
    Receiver: string?,
    ReceiverType: string?,
    Items: IReadOnlyList<PlaygroundCompletionItem>,
    Diagnostics: IReadOnlyList<PlaygroundDiagnostic>,
    Summary: PlaygroundSummary) {
}

public record PlaygroundCompletionItem(
    Label: string,
    Kind: string,
    Detail: string?,
    Documentation: string?,
    InsertText: string) {
}

public record PlaygroundHoverResponse(
    SchemaVersion: int,
    Ok: bool,
    File: string,
    Hover: PlaygroundHover?,
    Diagnostics: IReadOnlyList<PlaygroundDiagnostic>,
    Summary: PlaygroundSummary) {
}

public record PlaygroundHover(
    Signature: string,
    Documentation: string?,
    DefinedIn: string?,
    Kind: string) {
}

public record PlaygroundRunResponse(
    SchemaVersion: int,
    Ok: bool,
    File: string,
    ExitCode: int,
    Stdout: string,
    Stderr: string?,
    UnsupportedReason: string?,
    Diagnostics: IReadOnlyList<PlaygroundDiagnostic>,
    Summary: PlaygroundSummary) {
}

public record PlaygroundRunResult(
    Stdout: string,
    Stderr: string?,
    ExitCode: int) {
}

public record PlaygroundSummary(
    Errors: int,
    Warnings: int,
    Infos: int) {
}

public record PlaygroundDiagnostic(
    Code: string,
    Severity: string,
    Message: string,
    File: string,
    Line: int,
    Column: int,
    Length: int,
    SourceSnippet: string?,
    Explanation: string?,
    Suggestion: string?,
    Hint: string?) {
}

public record RuntimeError(
    Message: string) {
}
