namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.Collections.Generic
import System.Globalization
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Threading
import Microsoft.Extensions.Logging
import Microsoft.Extensions.Logging.Abstractions
import NSharpLang.LanguageServer.Handlers
import NSharpLang.LanguageServer.Models
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Models
import Serilog
import Serilog.Core
import Serilog.Events
import Serilog.Extensions.Logging

// ---------------------------------------------------------------------------
// Source-literal helpers.
//
// N# raw strings keep every character between the delimiters, so a block that
// starts on the line after `"""` carries a leading newline. `LshRaw` reproduces
// the C# raw-string trim (drop one leading and one trailing newline); `LshBody`
// only drops the leading newline, matching a C# verbatim string that opened on
// its own line and ended with trailing content.
// ---------------------------------------------------------------------------
func LshBody(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        return source.Substring(1)
    }
    return source
}

func LshRaw(source: string): string {
    trimmed := LshBody(source)
    if trimmed.EndsWith("\n", StringComparison.Ordinal) {
        return trimmed.Substring(0, trimmed.Length - 1)
    }
    return trimmed
}

func LshLines(source: string): string[] {
    return source.Replace("\r\n", "\n").Split('\n')
}

// Index of the first line containing `marker`, or -1.
func LshMarkerLine(source: string, marker: string): int {
    lines := LshLines(source)
    index := 0
    while index < lines.Length {
        if lines[index].Contains(marker, StringComparison.Ordinal) {
            return index
        }
        index = index + 1
    }
    return -1
}

// Column of `token` on line `line` of `source`, or -1.
func LshLineColumn(source: string, line: int, token: string): int {
    lines := LshLines(source)
    if line < 0 || line >= lines.Length {
        return -1
    }
    return lines[line].IndexOf(token, StringComparison.Ordinal)
}

// Line of the first line that contains `lineMarker` AND `token`.
func LshSourceLine(source: string, lineMarker: string, token: string): int {
    lines := LshLines(source)
    index := 0
    while index < lines.Length {
        if lines[index].Contains(lineMarker, StringComparison.Ordinal) {
            if lines[index].IndexOf(token, StringComparison.Ordinal) >= 0 {
                return index
            }
        }
        index = index + 1
    }
    throw new InvalidOperationException(
        "No line containing '" + lineMarker + "' with token '" + token + "' found in source."
    )
}

func LshSourceCharacter(source: string, lineMarker: string, token: string): int {
    line := LshSourceLine(source, lineMarker, token)
    return LshLineColumn(source, line, token)
}

// ---------------------------------------------------------------------------
// Reflection plumbing.
//
// The LSP request records expose `init`-only setters, which the columnar
// backend cannot currently target directly (see the conversion report), so the
// harness assigns them through reflection. These are public members.
// ---------------------------------------------------------------------------

func LshSet(target: object, name: string, value: object?) {
    property := target.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required property was not found: " + name)
    }
    property.SetValue(target, value)
}

func LshTextDocument(uri: string): TextDocumentIdentifier {
    return new TextDocumentIdentifier(DocumentUri.From(uri))
}

func LshFileUri(path: string): string {
    return DocumentUri.FromFileSystemPath(path).ToString()
}

func LshTempRoot(prefix: string): string {
    root := Path.Combine(Path.GetTempPath(), prefix + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func LshWrite(root: string, relativePath: string, text: string): string {
    fullPath := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(fullPath)
    if directory != null && directory.Length > 0 {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(fullPath, text)
    return fullPath
}

func LshDeleteTree(root: string) {
    if Directory.Exists(root) {
        Directory.Delete(root, true)
    }
}

func LshExamplesDirFrom(start: string): string? {
    directory := start
    attempt := 0
    while attempt < 12 {
        candidate := Path.Combine(directory, "examples")
        if Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "01-hello-world")) {
            return candidate
        }
        parent := Directory.GetParent(directory)
        if parent == null {
            return null
        }
        directory = parent.FullName
        attempt = attempt + 1
    }
    return null
}

func LshExamplesDir(): string {
    fromCurrent := LshExamplesDirFrom(Directory.GetCurrentDirectory())
    if fromCurrent != null {
        return fromCurrent
    }
    fromBase := LshExamplesDirFrom(AppContext.BaseDirectory)
    if fromBase != null {
        return fromBase
    }
    throw new InvalidOperationException("Could not find examples directory")
}

// ---------------------------------------------------------------------------
// Server construction and document lifecycle.
// ---------------------------------------------------------------------------

func LshNewDocs(): DocumentManager {
    return new DocumentManager(NullLogger<DocumentManager>.Instance)
}

// Mirrors the xunit fixture: the shared TypeResolver owns a DocumentManager of
// its own, separate from the one the handlers are wired to.
func LshNewTypes(): TypeResolver {
    return new TypeResolver(new DocumentManager(NullLogger<DocumentManager>.Instance))
}

// Mirrors didOpen: editor-open documents provide source-text overrides for
// project snapshots; workspace-scanned documents keep reading from disk.
func LshOpen(docs: DocumentManager, uri: string, content: string) {
    docs.MarkEditorOpen(uri)
    docs.UpdateDocument(uri, content, 1)
}

func LshUpdate(docs: DocumentManager, uri: string, content: string) {
    existing := docs.GetDocument(uri)
    version := 1
    if existing != null {
        version = existing.Version + 1
    }
    docs.UpdateDocument(uri, content, version)
}

func LshDocument(docs: DocumentManager, uri: string): DocumentState {
    document := docs.GetDocument(uri)
    if document == null {
        throw new InvalidOperationException("DocumentManager did not retain the document: " + uri)
    }
    return document
}

// ---------------------------------------------------------------------------
// Handler invocations. Each builds the LSP request record and drives the real
// handler in-process, exactly as the language server does.
// ---------------------------------------------------------------------------

func LshCompletions(
    docs: DocumentManager,
    types: TypeResolver,
    uri: string,
    line: int,
    character: int
): CompletionList {
    handler := new CompletionHandler(docs, types, NullLogger<CompletionHandler>.Instance)
    request := new CompletionParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshHover(
    docs: DocumentManager,
    types: TypeResolver,
    uri: string,
    line: int,
    character: int
): Hover? {
    handler := new HoverHandler(docs, types, NullLogger<HoverHandler>.Instance)
    request := new HoverParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshSignatureHelp(docs: DocumentManager, uri: string, line: int, character: int): SignatureHelp? {
    handler := new SignatureHelpHandler(docs, NullLogger<SignatureHelpHandler>.Instance)
    request := new SignatureHelpParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

// ---------------------------------------------------------------------------
// Completion assertions.
// ---------------------------------------------------------------------------

func LshCompletionLabels(completions: CompletionList): List<string> {
    labels := new List<string>()
    for item in completions {
        label := item.Label
        if label != null {
            labels.Add(label)
        }
    }
    return labels
}

func LshCompletionCount(completions: CompletionList): int {
    count := 0
    for item in completions {
        count = count + 1
    }
    return count
}

func LshHasCompletion(completions: CompletionList, label: string): bool {
    for item in completions {
        if item.Label == label {
            return true
        }
    }
    return false
}

func LshCompletionKindValue(item: CompletionItem): int {
    return Convert.ToInt32(item.Kind)
}

func LshCountCompletions(completions: CompletionList, label: string): int {
    count := 0
    for item in completions {
        if item.Label == label {
            count = count + 1
        }
    }
    return count
}

func LshSingleCompletion(completions: CompletionList, label: string): CompletionItem {
    found: CompletionItem? = null
    count := 0
    for item in completions {
        if item.Label == label {
            found = item
            count = count + 1
        }
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected exactly one completion labelled " + label + ", found " + count.ToString() + "."
        )
    }
    return found
}

func LshCompletionOfKind(completions: CompletionList, label: string, kind: CompletionItemKind): CompletionItem? {
    for item in completions {
        if item.Label == label && item.Kind == kind {
            return item
        }
    }
    return null
}

// StringOrMarkupContent has three shapes; the C# rows read whichever is set.
func LshDocumentationText(documentation: StringOrMarkupContent?): string? {
    if documentation == null {
        return null
    }
    if documentation.HasMarkupContent {
        markup := documentation.MarkupContent
        if markup == null {
            return null
        }
        return markup.Value
    }
    if documentation.HasString {
        return documentation.String
    }
    return documentation.ToString()
}

// ---------------------------------------------------------------------------
// Hover assertions.
// ---------------------------------------------------------------------------

func LshHoverMarkdown(hover: Hover): string {
    contents := hover.Contents
    markup := contents.MarkupContent
    if markup != null {
        return markup.Value
    }
    strings := contents.MarkedStrings
    if strings != null {
        for entry in strings {
            value := entry.Value
            if value != null {
                return value
            }
        }
    }
    throw new InvalidOperationException("Hover carried neither markup content nor marked strings.")
}

// ---------------------------------------------------------------------------
// Completion fixtures shared by several rows.
// ---------------------------------------------------------------------------

func LshAssertSnippet(label: string, placeholders: string) {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, label.Substring(0, 1))

    completions := LshCompletions(docs, types, uri, 0, 1)

    snippet := LshCompletionOfKind(completions, label, CompletionItemKind.Snippet)
    assert snippet != null
    assert snippet.InsertTextFormat == InsertTextFormat.Snippet
    insertText := must snippet.InsertText
    parts := placeholders.Split(';')
    index := 0
    while index < parts.Length {
        assert insertText.Contains(parts[index], StringComparison.Ordinal)
        index = index + 1
    }
}

func LshPersonMemberSource(): string {
    return """
class Person {
    Name: string
    Age: int

    func Greet(): string {
        return "Hello"
    }
}

func main(): void
    let p = new Person()
    p."""
}

// Publishes a CLR type literally named `Person` into the running process so the
// completion handler has to choose between it and the N# source declaration.
func LshEnsureConflictingClrPersonType(): Type {
    assemblyName := new AssemblyName("NSharpLang.Tests.DynamicCompletionCollision")
    assemblyBuilder := AssemblyBuilder.DefineDynamicAssembly(assemblyName, AssemblyBuilderAccess.Run)
    moduleName := assemblyName.Name
    if moduleName == null {
        throw new InvalidOperationException("Dynamic assembly name was null.")
    }
    moduleBuilder := assemblyBuilder.DefineDynamicModule(moduleName)
    typeBuilder := moduleBuilder.DefineType("Person", TypeAttributes.Public)
    field := typeBuilder.DefineField("Name", typeof(string), FieldAttributes.Public)
    _ = field
    created := typeBuilder.CreateType()
    if created == null {
        throw new InvalidOperationException("Dynamic Person type creation returned null.")
    }
    return created
}

// ---------------------------------------------------------------------------
// Signature help assertions.
// ---------------------------------------------------------------------------

func LshSignatureCount(help: SignatureHelp): int {
    count := 0
    for signature in help.Signatures {
        count = count + 1
    }
    return count
}

func LshSignatureAt(help: SignatureHelp, index: int): SignatureInformation {
    position := 0
    for signature in help.Signatures {
        if position == index {
            return signature
        }
        position = position + 1
    }
    throw new InvalidOperationException("Signature help had no signature at index " + index.ToString() + ".")
}

func LshHasSignatureContaining(help: SignatureHelp, fragment: string): bool {
    for signature in help.Signatures {
        if signature.Label.Contains(fragment, StringComparison.Ordinal) {
            return true
        }
    }
    return false
}

func LshSignatureContaining(help: SignatureHelp, fragment: string): SignatureInformation {
    for signature in help.Signatures {
        if signature.Label.Contains(fragment, StringComparison.Ordinal) {
            return signature
        }
    }
    throw new InvalidOperationException("No signature label contained " + fragment + ".")
}

func LshParameterCount(signature: SignatureInformation): int {
    parameters := signature.Parameters
    if parameters == null {
        throw new InvalidOperationException("Signature did not carry a parameter container.")
    }
    count := 0
    for parameter in parameters {
        count = count + 1
    }
    return count
}

// ---------------------------------------------------------------------------
// Navigation handlers.
// ---------------------------------------------------------------------------

func LshDefinition(docs: DocumentManager, uri: string, line: int, character: int): LocationOrLocationLinks? {
    handler := new DefinitionHandler(docs, NullLogger<DefinitionHandler>.Instance)
    request := new DefinitionParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshReferences(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int,
    includeDeclaration: bool
): LocationContainer? {
    handler := new ReferencesHandler(docs, NullLogger<ReferencesHandler>.Instance)
    context := new ReferenceContext()
    LshSet(context, "IncludeDeclaration", includeDeclaration)
    request := new ReferenceParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    LshSet(request, "Context", context)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshImplementation(docs: DocumentManager, uri: string, line: int, character: int): LocationOrLocationLinks? {
    handler := new GoToImplementationHandler(docs, NullLogger<GoToImplementationHandler>.Instance)
    request := new ImplementationParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshRename(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int,
    newName: string
): WorkspaceEdit? {
    handler := new RenameHandler(docs, NullLogger<RenameHandler>.Instance)
    request := new RenameParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    LshSet(request, "NewName", newName)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshPrepareRename(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int
): RangeOrPlaceholderRange? {
    handler := new PrepareRenameHandler(docs, NullLogger<PrepareRenameHandler>.Instance)
    request := new PrepareRenameParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

// `Task.Result` surfaces handler faults wrapped in an AggregateException; the
// rows below assert on the handler's own exception, so unwrap it here.
func LshUnwrap(failure: Exception): Exception {
    aggregate := failure as AggregateException
    if aggregate == null {
        return failure
    }
    inner := aggregate.InnerException
    if inner == null {
        return failure
    }
    return inner
}

func LshRenameFailure(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int,
    newName: string
): Exception {
    try {
        edit := LshRename(docs, uri, line, character, newName)
        _ = edit
    } catch failure: Exception {
        return LshUnwrap(failure)
    }
    throw new InvalidOperationException("Rename was expected to fail but returned a result.")
}

func LshPrepareRenameFailure(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int
): Exception {
    try {
        result := LshPrepareRename(docs, uri, line, character)
        _ = result
    } catch failure: Exception {
        return LshUnwrap(failure)
    }
    throw new InvalidOperationException("Prepare rename was expected to fail but returned a result.")
}

// ---------------------------------------------------------------------------
// Location assertions.
//
// The xunit original reached into the private `_items` field of
// LocationOrLocationLinks; the container is publicly enumerable, so this reads
// the same answer through the protocol surface.
// ---------------------------------------------------------------------------

func LshSingleLocation(value: LocationOrLocationLinks): Location {
    for item in value {
        if item.IsLocation {
            location := item.Location
            if location != null {
                return location
            }
        }
        if item.IsLocationLink {
            link := item.LocationLink
            if link != null {
                converted := new Location()
                LshSet(converted, "Uri", link.TargetUri)
                LshSet(converted, "Range", link.TargetRange)
                return converted
            }
        }
    }
    throw new InvalidOperationException("Definition response carried no location.")
}

func LshLocationCount(locations: LocationContainer): int {
    count := 0
    for location in locations {
        count = count + 1
    }
    return count
}

func LshHasLocationUri(locations: LocationContainer, uri: string): bool {
    for location in locations {
        if location.Uri.ToString() == uri {
            return true
        }
    }
    return false
}

func LshHasLocationAt(locations: LocationContainer, uri: string, line: int): bool {
    for location in locations {
        if location.Uri.ToString() == uri && location.Range.Start.Line == line {
            return true
        }
    }
    return false
}

func LshHasLocationEndingWith(locations: LocationContainer, suffix: string): bool {
    for location in locations {
        if location.Uri.ToString().EndsWith(suffix, StringComparison.Ordinal) {
            return true
        }
    }
    return false
}

// ---------------------------------------------------------------------------
// Workspace edit assertions.
// ---------------------------------------------------------------------------

func LshChangedUris(edit: WorkspaceEdit): List<string> {
    changes := edit.Changes
    if changes == null {
        throw new InvalidOperationException("Workspace edit carried no changes.")
    }
    uris := new List<string>()
    for pair in changes {
        uris.Add(pair.Key.ToString())
    }
    return uris
}

func LshChangesUri(edit: WorkspaceEdit, uri: string): bool {
    return LshChangedUris(edit).Contains(uri)
}

func LshEditsFor(edit: WorkspaceEdit, uri: string): List<TextEdit> {
    changes := edit.Changes
    if changes == null {
        throw new InvalidOperationException("Workspace edit carried no changes.")
    }
    edits := new List<TextEdit>()
    for pair in changes {
        if pair.Key.ToString() == uri {
            for textEdit in pair.Value {
                edits.Add(textEdit)
            }
        }
    }
    return edits
}

func LshAllEdits(edit: WorkspaceEdit): List<TextEdit> {
    changes := edit.Changes
    if changes == null {
        throw new InvalidOperationException("Workspace edit carried no changes.")
    }
    edits := new List<TextEdit>()
    for pair in changes {
        for textEdit in pair.Value {
            edits.Add(textEdit)
        }
    }
    return edits
}

func LshHasEdit(edits: List<TextEdit>, newText: string, line: int): bool {
    index := 0
    while index < edits.Count {
        if edits[index].NewText == newText && edits[index].Range.Start.Line == line {
            return true
        }
        index = index + 1
    }
    return false
}

func LshHasEditAt(edits: List<TextEdit>, newText: string, line: int, character: int): bool {
    index := 0
    while index < edits.Count {
        candidate := edits[index]
        if candidate.NewText == newText && candidate.Range.Start.Line == line && candidate.Range.Start.Character == character {
            return true
        }
        index = index + 1
    }
    return false
}

func LshHasEditOnLine(edits: List<TextEdit>, line: int): bool {
    index := 0
    while index < edits.Count {
        if edits[index].Range.Start.Line == line {
            return true
        }
        index = index + 1
    }
    return false
}

// ---------------------------------------------------------------------------
// Log capture.
//
// `ILogger<T>` cannot currently be implemented directly in N# (generic
// interface methods are accepted by the front end but are not wired into the
// interface slot at emit time — see the conversion report), so the capturing
// logger is assembled from the language server's own Serilog provider and a
// sink implemented here.
// ---------------------------------------------------------------------------

class LshLogSink: ILogEventSink {
    Events: List<LogEvent> = new List<LogEvent>()

    func Emit(logEvent: LogEvent) {
        Events.Add(logEvent)
    }
}

func LshCapturingDocs(sink: LshLogSink): DocumentManager {
    configuration := new LoggerConfiguration()
    verbose := configuration.MinimumLevel.Verbose()
    serilogLogger := verbose.WriteTo.Sink(sink).CreateLogger()
    factory := new SerilogLoggerFactory(serilogLogger, false)
    return new DocumentManager(new Logger<DocumentManager>(factory))
}

func LshWarningsContaining(sink: LshLogSink, fragment: string): List<LogEvent> {
    matches := new List<LogEvent>()
    index := 0
    while index < sink.Events.Count {
        logEvent := sink.Events[index]
        if logEvent.Level == LogEventLevel.Warning {
            rendered := logEvent.RenderMessage(CultureInfo.InvariantCulture)
            if rendered.Contains(fragment, StringComparison.Ordinal) {
                matches.Add(logEvent)
            }
        }
        index = index + 1
    }
    return matches
}

func LshEventPropertyText(logEvent: LogEvent, name: string): string? {
    properties := logEvent.Properties
    if !properties.ContainsKey(name) {
        return null
    }
    value := properties[name]
    scalar := value as ScalarValue
    if scalar == null {
        return value.ToString()
    }
    raw := scalar.Value
    if raw == null {
        return null
    }
    return raw.ToString()
}

func LshAnyUriEndsWith(uris: List<string>, suffix: string): bool {
    index := 0
    while index < uris.Count {
        if uris[index].EndsWith(suffix, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }
    return false
}

// ---------------------------------------------------------------------------
// Inlay hints.
// ---------------------------------------------------------------------------

func LshInlayHints(
    docs: DocumentManager,
    uri: string,
    startLine: int,
    startCharacter: int,
    endLine: int,
    endCharacter: int
): InlayHintContainer? {
    handler := new InlayHintHandler(docs, NullLogger<InlayHintHandler>.Instance)
    request := new InlayHintParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(
        request,
        "Range",
        new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            new Position(startLine, startCharacter),
            new Position(endLine, endCharacter)
        )
    )
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshHints(hints: InlayHintContainer): List<InlayHint> {
    collected := new List<InlayHint>()
    for hint in hints {
        collected.Add(hint)
    }
    return collected
}

func LshHintLabel(hint: InlayHint): string {
    label := hint.Label.String
    if label == null {
        throw new InvalidOperationException("Inlay hint carried no string label.")
    }
    return label
}

func LshHintLines(hints: InlayHintContainer): List<int> {
    lines := new List<int>()
    for hint in hints {
        lines.Add(hint.Position.Line)
    }
    lines.Sort()
    return lines
}

// ---------------------------------------------------------------------------
// Document symbols.
// ---------------------------------------------------------------------------

func LshDocumentSymbols(docs: DocumentManager, uri: string): SymbolInformationOrDocumentSymbolContainer? {
    handler := new DocumentSymbolHandler(docs, NullLogger<DocumentSymbolHandler>.Instance)
    request := new DocumentSymbolParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshSymbols(container: SymbolInformationOrDocumentSymbolContainer): List<DocumentSymbol> {
    symbols := new List<DocumentSymbol>()
    for entry in container {
        symbol := entry.DocumentSymbol
        if symbol == null {
            throw new InvalidOperationException("Document symbol response carried a non-document-symbol entry.")
        }
        symbols.Add(symbol)
    }
    return symbols
}

func LshChildren(symbol: DocumentSymbol): List<DocumentSymbol> {
    children := symbol.Children
    if children == null {
        throw new InvalidOperationException("Document symbol '" + symbol.Name + "' carried no children.")
    }
    collected := new List<DocumentSymbol>()
    for child in children {
        collected.Add(child)
    }
    return collected
}

func LshHasChild(children: List<DocumentSymbol>, name: string, kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind): bool {
    index := 0
    while index < children.Count {
        if children[index].Name == name && children[index].Kind == kind {
            return true
        }
        index = index + 1
    }
    return false
}

func LshHasChildDetail(children: List<DocumentSymbol>, name: string, kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind, detail: string): bool {
    index := 0
    while index < children.Count {
        candidate := children[index]
        if candidate.Name == name && candidate.Kind == kind && candidate.Detail == detail {
            return true
        }
        index = index + 1
    }
    return false
}

func LshChildNamed(children: List<DocumentSymbol>, name: string): DocumentSymbol {
    index := 0
    while index < children.Count {
        if children[index].Name == name {
            return children[index]
        }
        index = index + 1
    }
    throw new InvalidOperationException("No child document symbol named " + name + ".")
}

// ---------------------------------------------------------------------------
// Workspace symbols and folding ranges.
// ---------------------------------------------------------------------------

func LshWorkspaceSymbols(docs: DocumentManager, query: string): Container<WorkspaceSymbol>? {
    handler := new WorkspaceSymbolHandler(docs, NullLogger<WorkspaceSymbolHandler>.Instance)
    request := new WorkspaceSymbolParams()
    LshSet(request, "Query", query)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshWorkspaceSymbolCount(symbols: Container<WorkspaceSymbol>): int {
    count := 0
    for symbol in symbols {
        count = count + 1
    }
    return count
}

func LshHasWorkspaceSymbol(symbols: Container<WorkspaceSymbol>, name: string): bool {
    for symbol in symbols {
        if symbol.Name == name {
            return true
        }
    }
    return false
}

func LshHasWorkspaceSymbolOfKind(
    symbols: Container<WorkspaceSymbol>,
    name: string,
    kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind
): bool {
    for symbol in symbols {
        if symbol.Name == name && symbol.Kind == kind {
            return true
        }
    }
    return false
}

func LshHasWorkspaceMember(
    symbols: Container<WorkspaceSymbol>,
    name: string,
    kind: OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind,
    containerName: string
): bool {
    for symbol in symbols {
        if symbol.Name == name && symbol.Kind == kind && symbol.ContainerName == containerName {
            return true
        }
    }
    return false
}

func LshFoldingRanges(docs: DocumentManager, uri: string): Container<FoldingRange>? {
    handler := new FoldingRangeHandler(docs, NullLogger<FoldingRangeHandler>.Instance)
    request := new FoldingRangeRequestParam()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshFoldingRangeCount(ranges: Container<FoldingRange>): int {
    count := 0
    for range in ranges {
        count = count + 1
    }
    return count
}

func LshFoldingRangeStartingAt(ranges: Container<FoldingRange>, startLine: int): FoldingRange? {
    for range in ranges {
        if range.StartLine == startLine {
            return range
        }
    }
    return null
}

func LshFoldingRangeOfKind(ranges: Container<FoldingRange>, kind: FoldingRangeKind): FoldingRange? {
    for range in ranges {
        if range.Kind == kind {
            return range
        }
    }
    return null
}

// ---------------------------------------------------------------------------
// Formatting.
// ---------------------------------------------------------------------------

func LshFormattingOptions(): FormattingOptions {
    options := new FormattingOptions()
    LshSet(options, "TabSize", 4)
    LshSet(options, "InsertSpaces", true)
    return options
}

func LshFormatDocument(docs: DocumentManager, uri: string): TextEditContainer? {
    handler := new DocumentFormattingHandler(docs, NullLogger<DocumentFormattingHandler>.Instance)
    request := new DocumentFormattingParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Options", LshFormattingOptions())
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshOnTypeFormatting(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int,
    triggerCharacter: string
): TextEditContainer? {
    handler := new OnTypeFormattingHandler(docs, NullLogger<OnTypeFormattingHandler>.Instance)
    request := new DocumentOnTypeFormattingParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    LshSet(request, "Character", triggerCharacter)
    LshSet(request, "Options", LshFormattingOptions())
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshTextEdits(edits: TextEditContainer): List<TextEdit> {
    collected := new List<TextEdit>()
    for edit in edits {
        collected.Add(edit)
    }
    return collected
}

// ---------------------------------------------------------------------------
// Highlights, selection ranges and hierarchies.
// ---------------------------------------------------------------------------

func LshDocumentHighlights(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int
): DocumentHighlightContainer? {
    handler := new DocumentHighlightHandler(docs, NullLogger<DocumentHighlightHandler>.Instance)
    request := new DocumentHighlightParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshHighlightCount(highlights: DocumentHighlightContainer): int {
    count := 0
    for highlight in highlights {
        count = count + 1
    }
    return count
}

func LshSelectionRanges(docs: DocumentManager, uri: string, positions: Position[]): Container<SelectionRange>? {
    handler := new SelectionRangeHandler(docs, NullLogger<SelectionRangeHandler>.Instance)
    request := new SelectionRangeParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Positions", new Container<Position>(positions))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshSelectionRangeList(ranges: Container<SelectionRange>): List<SelectionRange> {
    collected := new List<SelectionRange>()
    for range in ranges {
        collected.Add(range)
    }
    return collected
}

func LshPrepareCallHierarchy(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int
): Container<CallHierarchyItem>? {
    handler := new CallHierarchyPrepareHandler(docs, NullLogger<CallHierarchyPrepareHandler>.Instance)
    request := new CallHierarchyPrepareParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshCallHierarchyItems(items: Container<CallHierarchyItem>): List<CallHierarchyItem> {
    collected := new List<CallHierarchyItem>()
    for item in items {
        collected.Add(item)
    }
    return collected
}

func LshOutgoingCalls(
    docs: DocumentManager,
    item: CallHierarchyItem
): Container<CallHierarchyOutgoingCall>? {
    handler := new CallHierarchyOutgoingHandler(docs, NullLogger<CallHierarchyOutgoingHandler>.Instance)
    request := new CallHierarchyOutgoingCallsParams()
    LshSet(request, "Item", item)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshOutgoingCallCount(calls: Container<CallHierarchyOutgoingCall>): int {
    count := 0
    for call in calls {
        count = count + 1
    }
    return count
}

func LshHasOutgoingCallTo(calls: Container<CallHierarchyOutgoingCall>, name: string): bool {
    for call in calls {
        if call.To.Name == name {
            return true
        }
    }
    return false
}

func LshPrepareTypeHierarchy(
    docs: DocumentManager,
    uri: string,
    line: int,
    character: int
): Container<TypeHierarchyItem>? {
    handler := new TypeHierarchyPrepareHandler(docs, NullLogger<TypeHierarchyPrepareHandler>.Instance)
    request := new TypeHierarchyPrepareParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    LshSet(request, "Position", new Position(line, character))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshSupertypes(docs: DocumentManager, item: TypeHierarchyItem): Container<TypeHierarchyItem>? {
    handler := new TypeHierarchySupertypesHandler(docs, NullLogger<TypeHierarchySupertypesHandler>.Instance)
    request := new TypeHierarchySupertypesParams()
    LshSet(request, "Item", item)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshSubtypes(docs: DocumentManager, item: TypeHierarchyItem): Container<TypeHierarchyItem>? {
    handler := new TypeHierarchySubtypesHandler(docs, NullLogger<TypeHierarchySubtypesHandler>.Instance)
    request := new TypeHierarchySubtypesParams()
    LshSet(request, "Item", item)
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshTypeHierarchyItems(items: Container<TypeHierarchyItem>): List<TypeHierarchyItem> {
    collected := new List<TypeHierarchyItem>()
    for item in items {
        collected.Add(item)
    }
    return collected
}

func LshHasTypeHierarchyItem(items: Container<TypeHierarchyItem>, name: string): bool {
    for item in items {
        if item.Name == name {
            return true
        }
    }
    return false
}

func LshTypeHierarchyCount(items: Container<TypeHierarchyItem>): int {
    count := 0
    for item in items {
        count = count + 1
    }
    return count
}

// ---------------------------------------------------------------------------
// Document links.
// ---------------------------------------------------------------------------

func LshDocumentLinks(docs: DocumentManager, uri: string): DocumentLinkContainer? {
    handler := new DocumentLinkHandler(docs, NullLogger<DocumentLinkHandler>.Instance)
    request := new DocumentLinkParams()
    LshSet(request, "TextDocument", LshTextDocument(uri))
    task := handler.Handle(request, CancellationToken.None)
    return task.Result
}

func LshDocumentLinkCount(links: DocumentLinkContainer): int {
    count := 0
    for link in links {
        count = count + 1
    }
    return count
}

func LshHasLinkTargetContaining(links: DocumentLinkContainer, fragment: string): bool {
    for link in links {
        target := link.Target
        if target != null {
            text := target.ToString()
            if text != null && text.Contains(fragment, StringComparison.Ordinal) {
                return true
            }
        }
    }
    return false
}

// WorkspaceSymbolHandler.matchesQuery is internal; reached through reflection
// for the same reason the semantic token helpers are. The name is camelCase because
// the language server is N# now, and casing is what decides export there — the member
// and its accessibility are the same ones the C# `internal static MatchesQuery` had.
func LshMatchesQuery(symbolName: string, query: string): bool {
    method := typeof(WorkspaceSymbolHandler).GetMethod(
        "matchesQuery",
        BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic
    )
    if method == null {
        throw new InvalidOperationException("WorkspaceSymbolHandler.matchesQuery was not found.")
    }
    arguments := new object?[](2)
    LshPut(arguments, 0, symbolName)
    LshPut(arguments, 1, query)
    result := method.Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("WorkspaceSymbolHandler.matchesQuery returned null.")
    }
    return Convert.ToBoolean(result)
}

// ---------------------------------------------------------------------------
// CLI/editor parity helpers.
// ---------------------------------------------------------------------------

func LshCompletionSignatures(completions: CompletionList): List<string> {
    values := new List<string>()
    for item in completions {
        values.Add(item.Label + ":" + LshCompletionKindValue(item).ToString())
    }
    values.Sort(StringComparer.Ordinal)
    return values
}

func LshHasCompletionStartingWith(completions: CompletionList, prefix: string): bool {
    for item in completions {
        label := item.Label
        if label != null && label.StartsWith(prefix, StringComparison.Ordinal) {
            return true
        }
    }
    return false
}

func LshAssertSameSignatures(expected: List<string>, actual: List<string>) {
    if expected.Count != actual.Count {
        throw new InvalidOperationException(
            "Completion parity mismatch: CLI produced " + expected.Count.ToString() + " entries, the language server produced " + actual.Count.ToString() + "."
        )
    }
    index := 0
    while index < expected.Count {
        if expected[index] != actual[index] {
            throw new InvalidOperationException(
                "Completion parity mismatch at " + index.ToString() + ": CLI said " + expected[index] + ", the language server said " + actual[index] + "."
            )
        }
        index = index + 1
    }
}

func LshMemberCompletionProject(): string {
    root := LshTempRoot("nsharp-d3-")
    LshWrite(root, "project.yml", "name: MemberCompletion\nversion: 1.0.0\noutputType: exe\ntargetFramework: net10.0\nentry: Program.nl\n")
    LshWrite(root, "Models.nl", "namespace MemberCompletion.Models\n\npublic class Sensor {\n    Name: string = \"\"\n    Reading: double = 0\n}\n")
    LshWrite(root, "Program.nl", LshMemberCompletionProgramText())
    return root
}

func LshMemberCompletionProgramText(): string {
    return "namespace MemberCompletion.App\n\nimport System\nimport MemberCompletion.Models\n\nfunc Main() {\n    sensor := new Sensor()\n    label := sensor.Name\n    print label.Length\n}\n"
}
