namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json
import NSharpLang.Compiler.CodeIntelligence

public class DocOptionSummary {
    ProjectOption: string?
    OutputOption: string?
    Json: bool
    Open: bool
    ShowHelp: bool

    constructor(projectOption: string?, outputOption: string?, json: bool, open: bool, showHelp: bool) {
        ProjectOption = projectOption
        OutputOption = outputOption
        Json = json
        Open = open
        ShowHelp = showHelp
    }
}

public class DocOpenCommand {
    FileName: string
    Arguments: string

    constructor(fileName: string, arguments: string) {
        FileName = fileName
        Arguments = arguments
    }
}

public class DocCommandKernels {
    public static func GetOptionSummary(args: string[]): DocOptionSummary {
        projectOption: string? = null
        outputOption: string? = null
        json := false
        open := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            valueIndex := i + 1
            hasValue := valueIndex < args.Length

            if arg == "--project" {
                if projectOption == null && hasValue {
                    projectOption = args[valueIndex]
                }
            } else if arg == "--output" {
                if outputOption == null && hasValue {
                    outputOption = args[valueIndex]
                }
            } else if arg == "--json" {
                json = true
            } else if arg == "--open" {
                open = true
            } else if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            i = i + 1
        }

        return new DocOptionSummary(projectOption, outputOption, json, open, showHelp)
    }

    public static func GetOutputMode(json: bool): int {
        if json {
            return 1
        }

        return 2
    }

    public static func GetProjectRoot(projectOption: string?, currentDirectory: string): string {
        return Path.GetFullPath(projectOption ?? currentDirectory)
    }

    public static func GetOutputDirectory(projectRoot: string, outputOption: string?): string {
        if outputOption != null {
            return Path.GetFullPath(outputOption)
        }

        return Path.GetFullPath(Path.Combine(Path.Combine(projectRoot, "nsharp"), "docs"))
    }

    public static func GetSymbolDirectory(outputDir: string): string {
        return Path.Combine(outputDir, "symbols")
    }

    public static func GetRawSlug(symbol: SymbolResult): string {
        return PageKind(symbol.Kind) + "-" + symbol.Name + "-" + GetFileNameWithoutExtension(symbol.File)
    }

    public static func GetSymbolRelativePath(slug: string): string {
        return NormalizePath(Path.Combine("symbols", slug + ".html"))
    }

    public static func GetSymbolAbsolutePath(outputDir: string, relativePath: string): string {
        return Path.Combine(outputDir, relativePath)
    }

    public static func GetIndexPath(outputDir: string): string {
        return Path.Combine(outputDir, "index.html")
    }

    public static func GetManifestIndexPath(indexPath: string): string {
        return NormalizePath(indexPath)
    }

    public static func GetOpenCommand(path: string, isMacOs: bool, isWindows: bool): DocOpenCommand {
        quotedPath := QuoteProcessArgument(path)
        if isMacOs {
            return new DocOpenCommand("open", quotedPath)
        }

        if isWindows {
            return new DocOpenCommand("cmd", "/c start \"\" " + quotedPath)
        }

        return new DocOpenCommand("xdg-open", quotedPath)
    }

    public static func OrderSymbolsForGeneration(symbols: IReadOnlyList<SymbolResult>): List<SymbolResult> {
        return OrderEntriesForGeneration(symbols, false)
    }

    public static func OrderMembersForGeneration(members: IReadOnlyList<SymbolResult>): List<SymbolResult> {
        return OrderEntriesForGeneration(members, true)
    }

    public static func CreateSlugs(rawSlugs: string[]): string[] {
        result := new string[](rawSlugs.Length)
        i := 0
        while i < rawSlugs.Length {
            result[i] = CreateSlug(rawSlugs[i])
            i = i + 1
        }

        return result
    }

    public static func GetHelpText(): string {
        return "N# API Documentation\n"
            + "\n"
            + "Usage: nlc doc [options]\n"
            + "\n"
            + "Generate HTML API documentation for the current project. Similar to `cargo doc`.\n"
            + "\n"
            + "Options:\n"
            + "  --project <dir>   Project root directory (default: current directory)\n"
            + "  --output <dir>    Output directory (default: ./nsharp/docs)\n"
            + "  --json            Emit a structured JSON result envelope\n"
            + "  --open            Open the generated index in the default browser\n"
            + "  --help, -h        Show this help text\n"
            + "\n"
            + "Examples:\n"
            + "  nlc doc\n"
            + "  nlc doc --open\n"
            + "  nlc doc --json\n"
            + "  nlc doc --project examples/16-task-cli --output /tmp/nsharp-docs\n"
            + "\n"
            + "Exit codes:\n"
            + "  0  Documentation generated successfully\n"
            + "  1  Documentation generation failed"
    }

    public static func GetProjectDirectoryNotFoundMessage(projectRoot: string): string {
        return "Project directory not found: " + projectRoot
    }

    public static func GetGeneratedSummaryMessage(pageCount: int): string {
        return "Generated API docs for " + pageCount.ToString() + " symbols."
    }

    public static func GetOutputPathMessage(outputDir: string): string {
        return "Output: " + outputDir
    }

    public static func GetIndexPathMessage(indexPath: string): string {
        return "Index: " + indexPath
    }

    public static func GetOpenedMessage(): string {
        return "Opened generated documentation in the default browser."
    }

    public static func GetGenerationFailedMessage(exceptionMessage: string): string {
        return "Doc generation failed: " + exceptionMessage
    }

    public static func GetOpenFailedMessage(indexPath: string): string {
        return "Generated docs, but failed to open " + indexPath + "."
    }

    public static func GetOpenFailedWithDetailMessage(indexPath: string, exceptionMessage: string): string {
        return "Generated docs, but failed to open " + indexPath + ": " + exceptionMessage
    }

    public static func ResultJson(projectRoot: string, outputDir: string, manifest: DocManifest): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "doc"
        envelope["ok"] = true
        envelope["projectRoot"] = NormalizePath(projectRoot)
        envelope["outputDir"] = NormalizePath(outputDir)
        envelope["result"] = BuildManifest(manifest)
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func ErrorJson(projectRoot: string, message: string): string {
        envelope := new Dictionary<string, object>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "doc"
        envelope["ok"] = false
        envelope["projectRoot"] = NormalizePath(projectRoot)

        errorPayload := new Dictionary<string, object>()
        errorPayload["message"] = message
        envelope["error"] = errorPayload
        return JsonSerializer.Serialize(envelope, CreateWriteIndentedOptions())
    }

    public static func RenderSymbolPage(symbol: SymbolResult, projectRoot: string): string {
        builder := new StringBuilder()
        AppendLine(builder, "<nav><a href=\"../index.html\">Back to index</a></nav>")
        AppendLine(builder, "<header>")
        AppendLine(builder, "  <p class=\"eyebrow\">" + HtmlEncode(SymbolKindDisplay(symbol.Kind)) + "</p>")
        AppendLine(builder, "  <h1>" + HtmlEncode(symbol.Name) + "</h1>")
        AppendLine(builder, "  <p><code>" + HtmlEncode(FormatSignature(symbol)) + "</code></p>")
        AppendLine(builder, "  <p>" + HtmlEncode(DescribeLocation(projectRoot, symbol)) + "</p>")

        parameters := RenderParameterSummary(symbol)
        if parameters != "" {
            AppendLine(builder, "  " + parameters)
        }

        AppendLine(builder, "</header>")

        membersSection := RenderMembersSection(symbol)
        if membersSection != "" {
            builder.Append(membersSection)
        }

        return WrapHtml("N# API Docs - " + symbol.Name, builder.ToString())
    }

    public static func RenderIndexPage(symbols: IReadOnlyList<SymbolResult>, pages: IReadOnlyList<DocPage>, projectRoot: string): string {
        grouped := new StringBuilder()
        index := 0
        while index < symbols.Count {
            kind := symbols[index].Kind
            AppendLine(grouped, "<section>")
            AppendLine(grouped, "  <h2>" + HtmlEncode(SymbolKindDisplay(kind)) + "</h2>")
            AppendLine(grouped, "  <ul class=\"symbol-list\">")

            while index < symbols.Count && symbols[index].Kind == kind {
                symbol := symbols[index]
                pageIndex := FindPageIndex(pages, symbol)
                page := pages[pageIndex]
                AppendLine(
                    grouped,
                    "    <li><a href=\"" + HtmlEncode(page.Path) + "\">" + HtmlEncode(symbol.Name) + "</a><span>" + HtmlEncode(DescribeLocation(projectRoot, symbol)) + "</span></li>")
                index = index + 1
            }

            AppendLine(grouped, "  </ul>")
            AppendLine(grouped, "</section>")
        }

        body := new StringBuilder()
        AppendLine(body, "<header>")
        AppendLine(body, "  <p class=\"eyebrow\">N# API Reference</p>")
        AppendLine(body, "  <h1>" + HtmlEncode(ProjectName(projectRoot)) + "</h1>")
        AppendLine(body, "  <p>" + symbols.Count.ToString() + " documented symbols</p>")
        AppendLine(body, "</header>")
        builderText := grouped.ToString()
        if builderText != "" {
            body.Append(builderText)
        }

        return WrapHtml("N# API Docs", body.ToString())
    }

    public static func GetLocationText(relativePath: string, line: int, column: int): string {
        return relativePath + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetParameterText(name: string, typeName: string, hasDefault: bool, defaultValue: string): string {
        if hasDefault {
            return name + ": " + typeName + " = " + defaultValue
        }

        return name + ": " + typeName
    }

    public static func GetSignatureText(
        kind: SymbolKind,
        name: string,
        hasParameterList: bool,
        parametersText: string,
        typeName: string): string {
        prefix := SignaturePrefix(kind)
        result := prefix + name
        if hasParameterList {
            result = result + "(" + parametersText + ")"
        }

        if typeName != "" {
            result = result + ": " + typeName
        }

        return result
    }

    public static func GetPageKindText(kind: SymbolKind): string {
        return PageKind(kind)
    }

    static func OrderEntriesForGeneration(symbols: IReadOnlyList<SymbolResult>, includeAllKinds: bool): List<SymbolResult> {
        ordered := new List<SymbolResult>()
        index := 0
        while index < symbols.Count {
            symbol := symbols[index]
            if includeAllKinds || IsDocumentedSymbolKind(symbol.Kind) {
                InsertOrdered(ordered, symbol)
            }

            index = index + 1
        }

        return ordered
    }

    static func InsertOrdered(ordered: List<SymbolResult>, symbol: SymbolResult) {
        insertIndex := ordered.Count
        index := 0
        while index < ordered.Count {
            if CompareSymbols(symbol, ordered[index]) < 0 {
                insertIndex = index
                index = ordered.Count
            } else {
                index = index + 1
            }
        }

        ordered.Insert(insertIndex, symbol)
    }

    static func CompareSymbols(left: SymbolResult, right: SymbolResult): int {
        kindCompare := SymbolKindOrderRank(left.Kind) - SymbolKindOrderRank(right.Kind)
        if kindCompare != 0 {
            return kindCompare
        }

        return String.Compare(left.Name, right.Name, StringComparison.Ordinal)
    }

    static func IsDocumentedSymbolKind(kind: SymbolKind): bool {
        return kind != SymbolKind.Variable && kind != SymbolKind.Parameter
    }

    static func SymbolKindOrderRank(kind: SymbolKind): int {
        if kind == SymbolKind.Class {
            return 1
        }

        if kind == SymbolKind.Constructor {
            return 2
        }

        if kind == SymbolKind.Enum {
            return 3
        }

        if kind == SymbolKind.EnumMember {
            return 4
        }

        if kind == SymbolKind.Field {
            return 5
        }

        if kind == SymbolKind.Function {
            return 6
        }

        if kind == SymbolKind.Interface {
            return 7
        }

        if kind == SymbolKind.Method {
            return 8
        }

        if kind == SymbolKind.Parameter {
            return 9
        }

        if kind == SymbolKind.Property {
            return 10
        }

        if kind == SymbolKind.Record {
            return 11
        }

        if kind == SymbolKind.Struct {
            return 12
        }

        if kind == SymbolKind.Test {
            return 13
        }

        if kind == SymbolKind.TypeAlias {
            return 14
        }

        if kind == SymbolKind.Union {
            return 15
        }

        if kind == SymbolKind.Variable {
            return 16
        }

        return 0
    }

    static func CreateSlug(raw: string): string {
        builder := new StringBuilder(raw.Length)
        i := 0
        while i < raw.Length {
            ch := raw[i]
            if Char.IsLetterOrDigit(ch) {
                builder.Append(Char.ToLowerInvariant(ch))
            }

            i = i + 1
        }

        return builder.ToString()
    }

    static func QuoteProcessArgument(value: string): string {
        return "\"" + value + "\""
    }

    static func GetFileNameWithoutExtension(path: string): string {
        fileName := Path.GetFileName(path) ?? ""
        dotIndex := -1
        index := fileName.Length - 1
        while index >= 0 {
            if fileName[index] == '.' {
                dotIndex = index
                index = -1
            } else {
                index = index - 1
            }
        }

        if dotIndex > 0 {
            return fileName.Substring(0, dotIndex)
        }

        return fileName
    }

    static func SignaturePrefix(kind: SymbolKind): string {
        if kind == SymbolKind.Function || kind == SymbolKind.Method {
            return "func "
        }

        if kind == SymbolKind.Constructor {
            return "ctor "
        }

        if kind == SymbolKind.Class {
            return "class "
        }

        if kind == SymbolKind.Struct {
            return "struct "
        }

        if kind == SymbolKind.Record {
            return "record "
        }

        if kind == SymbolKind.Interface {
            return "interface "
        }

        if kind == SymbolKind.Enum {
            return "enum "
        }

        if kind == SymbolKind.Union {
            return "union "
        }

        if kind == SymbolKind.Property {
            return "prop "
        }

        if kind == SymbolKind.Field {
            return "field "
        }

        if kind == SymbolKind.TypeAlias {
            return "type "
        }

        if kind == SymbolKind.Test {
            return "test "
        }

        return ""
    }

    static func CreateWriteIndentedOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true }
    }

    public static func NormalizePath(path: string): string {
        normalized := OutputFormatterNormalizationKernels.NormalizePath(path)
        if normalized != null {
            return normalized ?? ""
        }

        return path
    }

    static func BuildManifest(manifest: DocManifest): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["indexPath"] = manifest.IndexPath
        payload["pageCount"] = manifest.PageCount
        payload["pages"] = BuildPages(manifest.Pages)
        return payload
    }

    static func BuildPages(pages: IReadOnlyList<DocPage>): List<Dictionary<string, object>> {
        payload := new List<Dictionary<string, object>>()
        i := 0
        while i < pages.Count {
            payload.Add(BuildPage(pages[i]))
            i = i + 1
        }

        return payload
    }

    static func BuildPage(page: DocPage): Dictionary<string, object> {
        payload := new Dictionary<string, object>()
        payload["name"] = page.Name
        payload["kind"] = page.Kind
        payload["path"] = page.Path
        return payload
    }

    static func HtmlEncode(value: string): string {
        builder := new StringBuilder()
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '&' {
                builder.Append("&amp;")
            } else if ch == '"' {
                builder.Append("&quot;")
            } else if ch == '\'' {
                builder.Append("&#39;")
            } else if ch == '<' {
                builder.Append("&lt;")
            } else if ch == '>' {
                builder.Append("&gt;")
            } else {
                builder.Append(value.Substring(index, 1))
            }

            index = index + 1
        }

        return builder.ToString()
    }

    static func WrapHtml(title: string, body: string): string {
        builder := new StringBuilder()
        AppendLine(builder, "<!DOCTYPE html>")
        AppendLine(builder, "<html lang=\"en\">")
        AppendLine(builder, "<head>")
        AppendLine(builder, "  <meta charset=\"utf-8\" />")
        AppendLine(builder, "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />")
        AppendLine(builder, "  <title>" + HtmlEncode(title) + "</title>")
        AppendLine(builder, "  <style>")
        AppendLine(builder, "    :root {")
        AppendLine(builder, "      color-scheme: light;")
        AppendLine(builder, "      --bg: #f6f3ee;")
        AppendLine(builder, "      --card: #fffdf8;")
        AppendLine(builder, "      --ink: #1f1b18;")
        AppendLine(builder, "      --muted: #5d534b;")
        AppendLine(builder, "      --line: #d9cfc5;")
        AppendLine(builder, "      --accent: #a6401b;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    * { box-sizing: border-box; }")
        AppendLine(builder, "    body {")
        AppendLine(builder, "      margin: 0;")
        AppendLine(builder, "      font-family: Georgia, \"Iowan Old Style\", \"Palatino Linotype\", serif;")
        AppendLine(builder, "      background:")
        AppendLine(builder, "        radial-gradient(circle at top left, rgba(166, 64, 27, 0.08), transparent 35%),")
        AppendLine(builder, "        linear-gradient(180deg, #fbf9f4 0%, var(--bg) 100%);")
        AppendLine(builder, "      color: var(--ink);")
        AppendLine(builder, "    }")
        AppendLine(builder, "    main {")
        AppendLine(builder, "      max-width: 960px;")
        AppendLine(builder, "      margin: 0 auto;")
        AppendLine(builder, "      padding: 48px 24px 80px;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    header, nav, section {")
        AppendLine(builder, "      background: var(--card);")
        AppendLine(builder, "      border: 1px solid var(--line);")
        AppendLine(builder, "      border-radius: 18px;")
        AppendLine(builder, "      padding: 24px;")
        AppendLine(builder, "      margin-bottom: 20px;")
        AppendLine(builder, "      box-shadow: 0 10px 40px rgba(39, 28, 20, 0.05);")
        AppendLine(builder, "    }")
        AppendLine(builder, "    h1, h2 { margin: 0 0 12px; }")
        AppendLine(builder, "    .eyebrow {")
        AppendLine(builder, "      text-transform: uppercase;")
        AppendLine(builder, "      letter-spacing: 0.12em;")
        AppendLine(builder, "      font-size: 0.78rem;")
        AppendLine(builder, "      color: var(--accent);")
        AppendLine(builder, "      margin: 0 0 8px;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    code {")
        AppendLine(builder, "      font-family: \"SF Mono\", \"JetBrains Mono\", Consolas, monospace;")
        AppendLine(builder, "      font-size: 0.95rem;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    ul {")
        AppendLine(builder, "      margin: 0;")
        AppendLine(builder, "      padding-left: 20px;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    li {")
        AppendLine(builder, "      margin: 8px 0;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    li span {")
        AppendLine(builder, "      color: var(--muted);")
        AppendLine(builder, "      margin-left: 12px;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    a {")
        AppendLine(builder, "      color: var(--accent);")
        AppendLine(builder, "      text-decoration: none;")
        AppendLine(builder, "    }")
        AppendLine(builder, "    a:hover {")
        AppendLine(builder, "      text-decoration: underline;")
        AppendLine(builder, "    }")
        AppendLine(builder, "  </style>")
        AppendLine(builder, "</head>")
        AppendLine(builder, "<body>")
        AppendLine(builder, "  <main>")
        builder.Append(body)
        AppendLine(builder, "")
        AppendLine(builder, "  </main>")
        AppendLine(builder, "</body>")
        AppendLine(builder, "</html>")
        return builder.ToString()
    }

    static func RenderParameterSummary(symbol: SymbolResult): string {
        parameterResults := symbol.Parameters
        if parameterResults == null {
            return ""
        }

        if parameterResults.Length == 0 {
            return ""
        }

        return "<p><strong>Parameters:</strong> " + HtmlEncode(FormatParameters(parameterResults)) + "</p>"
    }

    static func RenderMembersSection(symbol: SymbolResult): string {
        memberResults := symbol.Members
        if memberResults == null {
            return ""
        }

        orderedMembers := OrderMembersForGeneration(memberResults)
        if orderedMembers.Count == 0 {
            return ""
        }

        builder := new StringBuilder()
        AppendLine(builder, "<section>")
        AppendLine(builder, "  <h2>Members</h2>")
        AppendLine(builder, "  <ul class=\"member-list\">")

        i := 0
        while i < orderedMembers.Count {
            member := orderedMembers[i]
            AppendLine(builder, "    <li><code>" + HtmlEncode(FormatSignature(member)) + "</code></li>")
            i = i + 1
        }

        AppendLine(builder, "  </ul>")
        AppendLine(builder, "</section>")
        return builder.ToString()
    }

    static func FindPageIndex(pages: IReadOnlyList<DocPage>, symbol: SymbolResult): int {
        expectedKind := PageKind(symbol.Kind)
        i := 0
        while i < pages.Count {
            page := pages[i]
            if page.Name == symbol.Name && page.Kind == expectedKind {
                return i
            }

            i = i + 1
        }

        throw new InvalidOperationException("No generated documentation page exists for symbol '" + symbol.Name + "'.")
    }

    static func PageKind(kind: SymbolKind): string {
        if kind == SymbolKind.Class {
            return "class"
        }

        if kind == SymbolKind.Constructor {
            return "constructor"
        }

        if kind == SymbolKind.Enum {
            return "enum"
        }

        if kind == SymbolKind.EnumMember {
            return "enummember"
        }

        if kind == SymbolKind.Field {
            return "field"
        }

        if kind == SymbolKind.Function {
            return "function"
        }

        if kind == SymbolKind.Interface {
            return "interface"
        }

        if kind == SymbolKind.Method {
            return "method"
        }

        if kind == SymbolKind.Parameter {
            return "parameter"
        }

        if kind == SymbolKind.Property {
            return "property"
        }

        if kind == SymbolKind.Record {
            return "record"
        }

        if kind == SymbolKind.Struct {
            return "struct"
        }

        if kind == SymbolKind.Test {
            return "test"
        }

        if kind == SymbolKind.TypeAlias {
            return "typealias"
        }

        if kind == SymbolKind.Union {
            return "union"
        }

        if kind == SymbolKind.Variable {
            return "variable"
        }

        return ""
    }

    static func SymbolKindDisplay(kind: SymbolKind): string {
        if kind == SymbolKind.Class {
            return "Class"
        }

        if kind == SymbolKind.Constructor {
            return "Constructor"
        }

        if kind == SymbolKind.Enum {
            return "Enum"
        }

        if kind == SymbolKind.EnumMember {
            return "EnumMember"
        }

        if kind == SymbolKind.Field {
            return "Field"
        }

        if kind == SymbolKind.Function {
            return "Function"
        }

        if kind == SymbolKind.Interface {
            return "Interface"
        }

        if kind == SymbolKind.Method {
            return "Method"
        }

        if kind == SymbolKind.Parameter {
            return "Parameter"
        }

        if kind == SymbolKind.Property {
            return "Property"
        }

        if kind == SymbolKind.Record {
            return "Record"
        }

        if kind == SymbolKind.Struct {
            return "Struct"
        }

        if kind == SymbolKind.Test {
            return "Test"
        }

        if kind == SymbolKind.TypeAlias {
            return "TypeAlias"
        }

        if kind == SymbolKind.Union {
            return "Union"
        }

        if kind == SymbolKind.Variable {
            return "Variable"
        }

        return ""
    }

    static func AppendLine(builder: StringBuilder, text: string) {
        builder.Append(text)
        builder.Append((char)10)
    }

    static func FormatParameters(parameters: ParameterResult[]): string {
        builder := new StringBuilder()
        i := 0
        while i < parameters.Length {
            if i > 0 {
                builder.Append(", ")
            }

            builder.Append(FormatParameter(parameters[i]))
            i = i + 1
        }

        return builder.ToString()
    }

    static func FormatSignature(symbol: SymbolResult): string {
        parameters := ""
        parameterResults := symbol.Parameters
        hasParameterList := parameterResults != null
        if parameterResults != null {
            parameters = FormatParameters(parameterResults)
        }

        typeName := ""
        if !string.IsNullOrWhiteSpace(symbol.TypeName ?? "") {
            typeName = symbol.TypeName ?? ""
        }

        return GetSignatureText(symbol.Kind, symbol.Name, hasParameterList, parameters, typeName)
    }

    static func FormatParameter(parameter: ParameterResult): string {
        return GetParameterText(
            parameter.Name,
            parameter.Type,
            parameter.HasDefault,
            parameter.DefaultValue ?? "")
    }

    static func DescribeLocation(projectRoot: string, symbol: SymbolResult): string {
        relativePath := RelativePath(projectRoot, symbol.File)
        return GetLocationText(relativePath, symbol.Line, symbol.Column)
    }

    static func RelativePath(projectRoot: string, filePath: string): string {
        if !Path.IsPathRooted(filePath) {
            return NormalizePath(filePath)
        }

        relativePath := Path.GetRelativePath(projectRoot, filePath)
        return NormalizePath(relativePath)
    }

    static func ProjectName(projectRoot: string): string {
        name := Path.GetFileName(projectRoot)
        if name != null {
            if name != "" {
                return name ?? ""
            }
        }

        return projectRoot
    }

}
