namespace NSharpLang.SystemsGauntletFacts.Tests

import System
import System.Collections
import System.Diagnostics
import System.IO
import System.Text.Json


// THE ACCEPTANCE GAUNTLET AND THE FACTS BENEATH IT, IN N#.
//
// These replace the three families of `tests/SystemsNSharpTests.cs` whose bodies read something the
// CLI's JSON does not expose: the GAUNTLET method that walks `tests/fixtures/systems-gauntlet` (24
// declaration lines, 5 in-body `Assert.` plus 25 rows inside `AssertSystemsGolden`,
// `AssertDiagnosticsGolden`, `AssertPerfGolden`, `AssertPerfSites` and `AssertStringSites`), the two
// PARSER-AST methods that read lifetimes off the compilation unit (36 lines, 10 asserts), and the
// one RUNTIME-ABI method that reads `Result<T, E>` (23 lines, 14 asserts).
//
// WHY THESE THREE ARE ONE PROJECT AND THE OTHER 56 ARE NOT. The rule this campaign classifies by is
// what a body READS. 56 of the file's 60 methods read a systems report, and they migrate to
// `tests/native/systems-analysis-census`, which reaches its subject entirely through spawned CLI
// processes. These three read the PARSER's declaration facts — return lifetimes, scoped parameters,
// ref-struct-ness, return-type text — and the RUNTIME's `Result` struct, and no `nlc` surface
// answers either: `returnLifetime`, `isRefStruct` and the type-reference text appear in NO JSON
// envelope the toolchain writes. Measured, that is exactly why the gauntlet cannot be split from
// them: of its ten cases, EIGHT are decided by the report alone, and TWO — `04-heap-arena` and
// `05-ref-struct-reader` — carry the three golden keys (`returnLifetime`, `resultAbi`, `refStruct`)
// that only the parser can answer. Splitting the corpus would split one method's claims across two
// projects, which this campaign does not do.
//
// SO THIS PROJECT CARRIES TWO INSTRUMENTS, AND BOTH ARE ITS OWN. The spawn kernel is
// `tests/native/systems-proof-corpus`'s, renamed; the reflection kernel is
// `tests/native/analyzer-clean-source`'s, renamed. Each native project carries its own plumbing by
// design; there is no shared prelude to import.
//
// ALL 135 DECODED GAUNTLET CLAIM ROWS WERE EVALUATED BEFORE THIS FILE WAS WRITTEN, AND ALL 135
// HOLD — 132 through the shipped CLI and 3 through the parser. What is new is that the goldens are
// no longer read by a `switch` that throws: `GfSystemsGoldenVerdict`, `GfDiagnosticsGoldenVerdict`
// and `GfPerfGoldenVerdict` answer a `key=ok` row per expectation the golden actually carries, so a
// broken expectation NAMES ITSELF, and the pinned verdict string states exactly which keys drove
// each case. The deleted `foreach` over `expected` said nothing about which keys it had seen.
//
// AND EVERY CASE NOW PINS ITS WHOLE REPORT BESIDE ITS VERDICTS: the envelope, the diagnostic census,
// every finding row and every trusted-site row. The deleted body asserted one `Assert.Contains` per
// golden key and never stated what else the analyzer said about the sample — including, on three of
// the ten cases, findings no golden mentions at all.


// ─── THE PARSER KERNEL, BY REFLECTION ─────────────────────────────────────────────────────────

// The recovery parser is reached by reflection rather than by name: a DIRECT
// `ColumnarParserRecovery.ParseFileAst(...)` call declines at columnar emit (measured, minimised
// out of repo), while the reflection route this arc has used since slice 25 compiles and runs.
func SetGfObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func GfMember(owner: object, memberName: string): object? {
    property := owner.GetType().GetProperty(memberName)
    if property != null {
        return property.GetValue(owner)
    }

    field := owner.GetType().GetField(memberName)
    if field != null {
        return field.GetValue(owner)
    }

    throw new InvalidOperationException("The production type exposed no '" + memberName + "' member.")
}

func GfRequiredMember(owner: object, memberName: string): object {
    value := GfMember(owner, memberName)
    if value == null {
        throw new InvalidOperationException("The production '" + memberName + "' member was null.")
    }

    return value
}

func GfText(owner: object, memberName: string): string {
    value := GfMember(owner, memberName)
    if value == null {
        return "<null>"
    }

    return value.ToString() ?? "<null>"
}

func GfParse(source: string, fileName: string): object {
    parserType := Type.GetType("NSharpLang.Compiler.Columnar.ColumnarParserRecovery, NSharpLang.Compiler.BootstrapServices")
    if parserType == null {
        throw new InvalidOperationException("The production recovery parser was not loadable.")
    }

    parseParameterTypes := new Type[](2)
    parseParameterTypes[0] = typeof(string)
    parseParameterTypes[1] = typeof(string)
    parseMethod := parserType.GetMethod("ParseFileAst", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production ParseFileAst entry point was not found.")
    }

    parseArguments := new object?[](2)
    SetGfObject(parseArguments, 0, source)
    SetGfObject(parseArguments, 1, fileName)
    parsed := parseMethod.Invoke(null, parseArguments)
    if parsed == null {
        throw new InvalidOperationException("The production recovery parser returned no result.")
    }

    return parsed
}

// The deleted `Parse` helper asserted two things about every parse it performed — a non-null
// compilation unit and no error-severity recovery diagnostic — and then threw the rest away. This
// states both AND the whole diagnostic census, so a recovery artefact can never hide inside a
// declaration claim.
func GfParseCensus(source: string, fileName: string): string {
    parsed := GfParse(source, fileName)
    unit := GfMember(parsed, "CompilationUnit")
    census := "unit="
    if unit == null {
        census = census + "<null>"
    } else {
        census = census + "present"
    }

    errors := GfMember(parsed, "Errors") as IList
    if errors == null {
        return census + ";errors=<not-a-list>"
    }

    census = census + ";errors=" + errors.Count.ToString()
    index := 0
    while index < errors.Count {
        entry := errors[index]
        if entry != null {
            census = census + ";" + GfText(entry, "Code") + ":" + GfText(entry, "Severity") + "@" + GfText(entry, "Line") + ":" + GfText(entry, "Column")
        }

        index = index + 1
    }

    return census
}

// `TypeReferenceText` in the deleted file was a C# switch over six `TypeReference` shapes. It is
// ported here as a dispatch on the runtime type NAME, which is how this arc has read production AST
// nodes since slice 25.
func GfTypeText(reference: object?): string {
    if reference == null {
        return ""
    }

    kind := reference.GetType().Name
    if kind == "SimpleTypeReference" {
        return GfText(reference, "Name")
    }

    if kind == "GenericTypeReference" {
        arguments := GfMember(reference, "TypeArguments") as IList
        text := GfText(reference, "Name") + "<"
        if arguments != null {
            index := 0
            while index < arguments.Count {
                if index > 0 {
                    text = text + ", "
                }

                text = text + GfTypeText(arguments[index])
                index = index + 1
            }
        }

        return text + ">"
    }

    if kind == "ArrayTypeReference" {
        return GfTypeText(GfMember(reference, "ElementType")) + "[]"
    }

    if kind == "NullableTypeReference" {
        return GfTypeText(GfMember(reference, "InnerType")) + "?"
    }

    if kind == "ByRefTypeReference" {
        return "&" + GfTypeText(GfMember(reference, "InnerType"))
    }

    if kind == "UnionTypeReference" {
        arms := GfMember(reference, "Arms") as IList
        text := ""
        if arms != null {
            index := 0
            while index < arms.Count {
                if index > 0 {
                    text = text + " | "
                }

                text = text + GfTypeText(arms[index])
                index = index + 1
            }
        }

        return text
    }

    return reference.ToString() ?? ""
}

func GfParameterCensus(declaration: object): string {
    parameters := GfMember(declaration, "Parameters") as IList
    if parameters == null {
        return "<none>"
    }

    census := ""
    index := 0
    while index < parameters.Count {
        parameter := parameters[index]
        if parameter != null {
            if census != "" {
                census = census + ","
            }

            census = census + GfText(parameter, "Name") + ":" + GfTypeText(GfMember(parameter, "Type"))
                + ":scoped=" + GfText(parameter, "IsScoped") + ":lifetime=" + GfText(parameter, "Lifetime")
        }

        index = index + 1
    }

    if census == "" {
        return "<none>"
    }

    return census
}

func GfTypeParameterCensus(declaration: object): string {
    typeParameters := GfMember(declaration, "TypeParameters") as IList
    if typeParameters == null {
        return "<null>"
    }

    census := ""
    index := 0
    while index < typeParameters.Count {
        entry := typeParameters[index]
        if entry != null {
            if census != "" {
                census = census + ","
            }

            census = census + GfText(entry, "Name")
        }

        index = index + 1
    }

    if census == "" {
        return "<none>"
    }

    return census
}

// One row per top-level declaration, stating the kind, the name, and — for the two kinds this
// slice's claims are about — the lifetime, return-type and ref-struct facts no CLI surface exposes.
func GfDeclarationCensus(source: string, fileName: string): string {
    unit := GfRequiredMember(GfParse(source, fileName), "CompilationUnit")
    declarations := GfMember(unit, "Declarations") as IList
    if declarations == null {
        return "<not-a-list>"
    }

    census := ""
    index := 0
    while index < declarations.Count {
        declaration := declarations[index]
        if declaration != null {
            if census != "" {
                census = census + "|"
            }

            kind := declaration.GetType().Name
            census = census + kind + ":" + GfText(declaration, "Name")
            if kind == "FunctionDeclaration" {
                census = census + ";typeParameters=" + GfTypeParameterCensus(declaration)
                    + ";returnType=" + GfTypeText(GfMember(declaration, "ReturnType"))
                    + ";returnLifetime=" + GfText(declaration, "ReturnLifetime")
                    + ";parameters=" + GfParameterCensus(declaration)
            }

            if kind == "StructDeclaration" {
                census = census + ";refStruct=" + GfText(declaration, "IsRefStruct")
            }
        }

        index = index + 1
    }

    return census
}


// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────

class GfRun {
    ExitCode: int
    Stdout: string
    Stderr: string

    constructor(exitCode: int, stdout: string, stderr: string) {
        ExitCode = exitCode
        Stdout = stdout
        Stderr = stderr
    }
}

// Start a child process, drain BOTH pipes to completion, wait for it, and dispose it. Draining
// before waiting is what keeps a chatty child from deadlocking against a full pipe buffer, and the
// `Dispose` is what guarantees this project leaves no orphan `dotnet` process behind.
func GfRunProcess(fileName: string, arguments: string, workingDirectory: string): GfRun {
    startInfo := new ProcessStartInfo { FileName: fileName, Arguments: arguments }
    startInfo.WorkingDirectory = workingDirectory
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true
    startInfo.UseShellExecute = false

    process := new Process { StartInfo: startInfo }
    process.Start()
    stdout := process.StandardOutput.ReadToEnd()
    stderr := process.StandardError.ReadToEnd()
    process.WaitForExit()
    exitCode := process.ExitCode
    process.Dispose()
    return new GfRun(exitCode, stdout, stderr)
}

// The repository root, found by walking up from the directory this test assembly was loaded into
// (which is the CLI's own directory, because `nlc test` hosts the emitted tests in its process).
func GfRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln"))
            && Directory.Exists(Path.Combine(directory, "src"))
            && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this test tree.")
}

func GfCliDll(): string {
    root := GfRepositoryRoot()
    binDirectory := Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin")
    cliDll := Path.Combine(Path.Combine(Path.Combine(binDirectory, "Debug"), "net10.0"), "Cli.dll")
    if !File.Exists(cliDll) {
        throw new InvalidOperationException("The CLI this project drives was not built: " + cliDll)
    }

    return cliDll
}


// ─── THE FIXTURE KERNEL ───────────────────────────────────────────────────────────────────────

// Every block owns its own temporary project directory, writes it, drives the shipped CLI over it,
// and deletes it before it asserts anything — so a failing assertion never leaks a fixture.
// Every gauntlet case is analysed as the deleted `Analyze(source, profile: "systems")` analysed it:
// a strict systems project whose single source is the case's own `sample.nl`.
func GfFixture(name: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-systems-gauntlet-facts-" + name)
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }

    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    return directory
}

// The gauntlet corpus on disk, under the repository this test assembly was built from.
func GfCaseDirectory(caseName: string): string {
    root := GfRepositoryRoot()
    gauntlet := Path.Combine(Path.Combine(Path.Combine(root, "tests"), "fixtures"), "systems-gauntlet")
    directory := Path.Combine(gauntlet, caseName)
    if !Directory.Exists(directory) {
        throw new InvalidOperationException("The gauntlet case directory is missing: " + directory)
    }

    return directory
}

func GfWrite(directory: string, fileName: string, text: string) {
    File.WriteAllText(Path.Combine(directory, fileName), text)
}

func GfCleanup(directory: string) {
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }
}

func GfCheck(directory: string): GfRun {
    return GfRunProcess("dotnet", GfCliDll() + " check --project " + directory + " --systems-report", directory)
}


// ─── THE CENSUS KERNEL ────────────────────────────────────────────────────────────────────────

// Every pinned value below is produced by walking the SHIPPED JSON's own properties in document
// order, so a row states the WHOLE row rather than the two or three fields a `f => f.Code == …`
// lambda happened to look at, and a new field cannot appear unnoticed.
func GfElementText(element: JsonElement): string {
    kind := element.ValueKind
    if kind == JsonValueKind.String {
        return element.GetString() ?? "<null>"
    }

    if kind == JsonValueKind.Number {
        return element.GetRawText()
    }

    if kind == JsonValueKind.True {
        return "True"
    }

    if kind == JsonValueKind.False {
        return "False"
    }

    if kind == JsonValueKind.Null {
        return "<null>"
    }

    if kind == JsonValueKind.Array {
        arrayText := "["
        arrayFirst := true
        arrayEnumerator := element.EnumerateArray()
        while arrayEnumerator.MoveNext() {
            if !arrayFirst {
                arrayText = arrayText + ","
            }

            arrayText = arrayText + GfElementText(arrayEnumerator.Current)
            arrayFirst = false
        }

        return arrayText + "]"
    }

    objectText := "{"
    objectFirst := true
    objectEnumerator := element.EnumerateObject()
    while objectEnumerator.MoveNext() {
        property := objectEnumerator.Current
        if !objectFirst {
            objectText = objectText + ","
        }

        objectText = objectText + property.Name + "=" + GfElementText(property.Value)
        objectFirst = false
    }

    return objectText + "}"
}

// A row is the object's own property list, in document order, with absolute fixture paths reduced
// to their file names so the pin is stable across machines and temp directories.
func GfRowText(element: JsonElement): string {
    text := ""
    enumerator := element.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        value := GfElementText(property.Value)
        if property.Name == "file" {
            value = Path.GetFileName(value) ?? ""
        }

        if text != "" {
            text = text + ";"
        }

        text = text + property.Name + "=" + value
    }

    return text
}

func GfSection(stdout: string, sectionName: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    report := document.RootElement.GetProperty("systemsReport")
    section := report.GetProperty(sectionName).Clone()
    document.Dispose()
    return section
}

func GfCount(stdout: string, sectionName: string): int {
    return GfSection(stdout, sectionName).GetArrayLength()
}

func GfRow(stdout: string, sectionName: string, index: int): string {
    section := GfSection(stdout, sectionName)
    if index >= section.GetArrayLength() {
        return "<no-such-row>"
    }

    position := 0
    enumerator := section.EnumerateArray()
    while enumerator.MoveNext() {
        if position == index {
            return GfRowText(enumerator.Current)
        }

        position = position + 1
    }

    return "<no-such-row>"
}

// The whole report minus its three arrays: the envelope a consumer reads first.
func GfEnvelope(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    report := root.GetProperty("systemsReport")
    text := "command=" + GfElementText(root.GetProperty("command"))
        + ";ok=" + GfElementText(root.GetProperty("ok"))
        + ";checkedFiles=" + GfElementText(root.GetProperty("checkedFiles"))
        + ";envelopeSchema=" + GfElementText(root.GetProperty("schemaVersion"))
        + ";reportSchema=" + GfElementText(report.GetProperty("schemaVersion"))
        + ";profile=" + GfElementText(report.GetProperty("profile"))
        + ";mode=" + GfElementText(report.GetProperty("mode"))
        + ";aotTarget=" + GfElementText(report.GetProperty("aotTarget"))
        + ";aot=" + GfElementText(report.GetProperty("aot"))
        + ";warmup=" + GfElementText(report.GetProperty("warmup"))
        + ";summary=" + GfElementText(report.GetProperty("summary"))
    document.Dispose()
    return text
}

// The diagnostics the CLI actually wrote — the runtime census that replaces the deleted
// `Assert.True(string.IsNullOrWhiteSpace(stderr))`, which could not fail (see the banner).
func GfDiagnosticCensus(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    diagnostics := document.RootElement.GetProperty("diagnostics")
    census := ""
    enumerator := diagnostics.EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if census != "" {
            census = census + "|"
        }

        census = census + GfElementText(entry.GetProperty("code")) + ":"
            + GfElementText(entry.GetProperty("severity")) + "@"
            + GfElementText(entry.GetProperty("line")) + ":"
            + GfElementText(entry.GetProperty("column")) + "+"
            + GfElementText(entry.GetProperty("length"))
    }

    document.Dispose()
    return census
}



// ─── THE GOLDEN KERNEL ────────────────────────────────────────────────────────────────────────

// `AssertSystemsGolden`, `AssertDiagnosticsGolden`, `AssertPerfGolden`, `AssertPerfSites`,
// `AssertStringSites` and `NormalizeDiagnosticText` are ported here as VERDICT functions rather
// than as assertions: each answers a `key=ok` / `key=FAILED` row per expectation the golden
// actually carries, so a broken expectation names ITSELF instead of failing an anonymous
// `Assert.Contains`. The deleted switch threw `InvalidOperationException` on an unknown key; the
// verdict says `key=<unhandled>`, which fails the pin the same way and reads better.
func GfNormalize(value: string): string {
    lowered := value.ToLowerInvariant()
    alphabet := "abcdefghijklmnopqrstuvwxyz0123456789"
    text := ""
    space := false
    index := 0
    while index < lowered.Length {
        piece := lowered.Substring(index, 1)
        if alphabet.IndexOf(piece, StringComparison.Ordinal) >= 0 {
            text = text + piece
            space = false
        } else {
            if !space && text != "" {
                text = text + " "
            }

            space = true
        }

        index = index + 1
    }

    return text.Trim()
}

func GfLastSegment(value: string): string {
    position := value.LastIndexOf(".", StringComparison.Ordinal)
    if position < 0 {
        return value
    }

    return value.Substring(position + 1)
}

func GfVerdict(name: string, ok: bool): string {
    if ok {
        return name + "=ok"
    }

    return name + "=FAILED"
}

func GfReport(stdout: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    report := document.RootElement.GetProperty("systemsReport").Clone()
    document.Dispose()
    return report
}

func GfHasErrorFinding(stdout: string): bool {
    enumerator := GfReport(stdout).GetProperty("findings").EnumerateArray()
    while enumerator.MoveNext() {
        if enumerator.Current.GetProperty("severity").GetString() == "error" {
            return true
        }
    }

    return false
}

func GfHasFindingWith(stdout: string, propertyName: string, expected: string): bool {
    enumerator := GfReport(stdout).GetProperty("findings").EnumerateArray()
    while enumerator.MoveNext() {
        if enumerator.Current.GetProperty(propertyName).GetString() == expected {
            return true
        }
    }

    return false
}

func GfHasFunction(stdout: string, name: string, flagName: string): bool {
    enumerator := GfReport(stdout).GetProperty("functions").EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if entry.GetProperty("name").GetString() == name && entry.GetProperty(flagName).GetBoolean() {
            return true
        }
    }

    return false
}

func GfHasEffectFlag(stdout: string, flagName: string): bool {
    enumerator := GfReport(stdout).GetProperty("functions").EnumerateArray()
    while enumerator.MoveNext() {
        if enumerator.Current.GetProperty("effects").GetProperty(flagName).GetBoolean() {
            return true
        }
    }

    return false
}

func GfHasCallContaining(stdout: string, token: string): bool {
    enumerator := GfReport(stdout).GetProperty("functions").EnumerateArray()
    while enumerator.MoveNext() {
        calls := enumerator.Current.GetProperty("calls").EnumerateArray()
        while calls.MoveNext() {
            call := calls.Current.GetString() ?? ""
            if call.IndexOf(token, StringComparison.Ordinal) >= 0 {
                return true
            }
        }
    }

    return false
}

func GfHasTrustedSite(stdout: string, name: string): bool {
    enumerator := GfReport(stdout).GetProperty("trustedSites").EnumerateArray()
    while enumerator.MoveNext() {
        if enumerator.Current.GetProperty("function").GetString() == name {
            return true
        }
    }

    return false
}

// `function` and `suggestion` are nullable on the wire — three of the fifty finding rows this
// slice pins carry no suggestion at all — and the `out`-parameter `TryGetProperty` declines on this
// emit path, so an optional read walks the object's own properties instead.
func GfProperty(element: JsonElement, propertyName: string): string {
    enumerator := element.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        if property.Name == propertyName {
            if property.Value.ValueKind == JsonValueKind.Null {
                return ""
            }

            return property.Value.GetString() ?? ""
        }
    }

    return ""
}

func GfFindingCount(stdout: string): int {
    return GfReport(stdout).GetProperty("findings").GetArrayLength()
}

// The effect-site text `AssertPerfSites` built: code, effect, function, message and suggestion
// joined by spaces with the empty parts dropped, then normalized. The golden's expected string is
// a normalized SUBSTRING of it.
func GfEffectSiteMatches(stdout: string, effect: string, expected: string): bool {
    want := GfNormalize(expected)
    enumerator := GfReport(stdout).GetProperty("findings").EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if entry.GetProperty("effect").GetString() == effect {
            text := (entry.GetProperty("code").GetString() ?? "") + " " + effect + " "
                + GfProperty(entry, "function") + " " + (entry.GetProperty("message").GetString() ?? "")
                + " " + GfProperty(entry, "suggestion")
            if GfNormalize(text).IndexOf(want, StringComparison.Ordinal) >= 0 {
                return true
            }
        }
    }

    return false
}

func GfEffectSiteCount(stdout: string, effect: string): int {
    count := 0
    enumerator := GfReport(stdout).GetProperty("findings").EnumerateArray()
    while enumerator.MoveNext() {
        if enumerator.Current.GetProperty("effect").GetString() == effect {
            count = count + 1
        }
    }

    return count
}

func GfMessageMatches(stdout: string, code: string, severity: string, expected: string): bool {
    want := GfNormalize(expected)
    enumerator := GfReport(stdout).GetProperty("findings").EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if entry.GetProperty("code").GetString() == code && entry.GetProperty("severity").GetString() == severity {
            message := GfNormalize(entry.GetProperty("message").GetString() ?? "")
            if message.IndexOf(want, StringComparison.Ordinal) >= 0 {
                return true
            }
        }
    }

    return false
}


// ─── THE THREE GOLDEN READERS ─────────────────────────────────────────────────────────────────

func GfSystemsGoldenVerdict(goldenPath: string, stdout: string, declarationCensus: string): string {
    document := JsonDocument.Parse(File.ReadAllText(goldenPath))
    root := document.RootElement
    verdict := GfVerdict("schemaVersion", root.GetProperty("schemaVersion").GetInt32() == 1)
    expected := root.GetProperty("expected")
    enumerator := expected.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        name := property.Name
        value := property.Value
        if name == "errors" {
            if value.ValueKind == JsonValueKind.Array && value.GetArrayLength() == 0 {
                verdict = verdict + ";" + GfVerdict("errors", !GfHasErrorFinding(stdout))
            }
        } else if name == "hot" {
            hot := value.GetString() ?? ""
            if hot == "pass" {
                verdict = verdict + ";" + GfVerdict("hot", !GfHasErrorFinding(stdout))
            } else {
                verdict = verdict + ";" + GfVerdict("hot", GfHasFunction(stdout, hot, "isHot"))
            }
        } else if name == "boundary" {
            verdict = verdict + ";" + GfVerdict("boundary", GfHasFunction(stdout, value.GetString() ?? "", "isBoundary"))
        } else if name == "bclHotSummary" {
            requiredCalls := value.EnumerateArray()
            while requiredCalls.MoveNext() {
                token := GfLastSegment(requiredCalls.Current.GetString() ?? "")
                verdict = verdict + ";" + GfVerdict("bclHotSummary." + token, GfHasCallContaining(stdout, token))
            }
        } else if name == "boundsProof" {
            verdict = verdict + ";" + GfVerdict("boundsProof", GfEffectSiteCount(stdout, "implicitTrap") == 0)
        } else if name == "concurrencyPrimitive" {
            verdict = verdict + ";" + GfVerdict("concurrencyPrimitive", GfHasEffectFlag(stdout, "usesConcurrencyPrimitive"))
        } else if name == "returnLifetime" {
            verdict = verdict + ";" + GfVerdict("returnLifetime",
                declarationCensus.IndexOf("returnLifetime=" + (value.GetString() ?? ""), StringComparison.Ordinal) >= 0)
        } else if name == "resultAbi" {
            verdict = verdict + ";" + GfVerdict("resultAbi",
                declarationCensus.IndexOf("returnType=" + (value.GetString() ?? ""), StringComparison.Ordinal) >= 0)
        } else if name == "refStruct" {
            verdict = verdict + ";" + GfVerdict("refStruct",
                declarationCensus.IndexOf("StructDeclaration:" + (value.GetString() ?? "") + ";refStruct=True", StringComparison.Ordinal) >= 0)
        } else if name == "failure" {
            verdict = verdict + ";" + GfVerdict("failure", GfFindingCount(stdout) > 0)
        } else if name == "code" {
            verdict = verdict + ";" + GfVerdict("code", GfHasFindingWith(stdout, "code", value.GetString() ?? ""))
        } else if name == "trustedSites" {
            sites := value.EnumerateArray()
            while sites.MoveNext() {
                site := sites.Current.GetString() ?? ""
                verdict = verdict + ";" + GfVerdict("trustedSite." + site, GfHasTrustedSite(stdout, site))
            }
        } else if name == "aotTarget" {
            report := GfReport(stdout)
            target := value.GetString() ?? ""
            verdict = verdict + ";" + GfVerdict("aotTarget",
                (report.GetProperty("aotTarget").GetString() ?? "") == target
                    && (report.GetProperty("aot").GetProperty("target").GetString() ?? "") == target)
        } else if name == "aot" {
            verdict = verdict + ";" + GfVerdict("aot", !GfHasFindingWith(stdout, "code", "NSYS060"))
        } else if name == "nativeImageEmitted" {
            verdict = verdict + ";" + GfVerdict("nativeImageEmitted",
                GfReport(stdout).GetProperty("aot").GetProperty("nativeImageEmitted").GetBoolean() == value.GetBoolean())
        } else {
            verdict = verdict + ";" + name + "=<unhandled>"
        }
    }

    document.Dispose()
    return verdict
}

// The deleted reader used `Regex.Match(text, "^(NSYS\d{3})\s+(error|warning):\s+(.+)$")`. `Regex`
// declines on this emit path, so the line is split on its first space and its first colon — which
// is the same grammar stated without a pattern.
func GfDiagnosticsGoldenVerdict(goldenPath: string, stdout: string): string {
    text := File.ReadAllText(goldenPath).Trim()
    verdict := GfVerdict("nonEmpty", text != "")
    if text.StartsWith("PASS:", StringComparison.Ordinal) {
        return verdict + ";" + GfVerdict("pass.noErrors", !GfHasErrorFinding(stdout))
    }

    space := text.IndexOf(" ", StringComparison.Ordinal)
    colon := text.IndexOf(":", StringComparison.Ordinal)
    if space < 0 || colon < space {
        return verdict + ";shape=FAILED"
    }

    code := text.Substring(0, space)
    severity := text.Substring(space + 1, colon - space - 1).Trim()
    message := text.Substring(colon + 1).Trim()
    return verdict + ";" + GfVerdict("line." + code + "." + severity, GfMessageMatches(stdout, code, severity, message))
}

func GfPerfGoldenVerdict(goldenPath: string, stdout: string): string {
    document := JsonDocument.Parse(File.ReadAllText(goldenPath))
    root := document.RootElement
    verdict := GfVerdict("schemaVersion", root.GetProperty("schemaVersion").GetInt32() == 1)
    verdict = verdict + ";" + GfVerdict("command", (root.GetProperty("command").GetString() ?? "") == "build")
    enumerator := root.GetProperty("expected").EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        name := property.Name
        value := property.Value
        effect := ""
        if name == "allocationSites" {
            effect = "allocation"
        } else if name == "boxingSites" {
            effect = "boxing"
        } else if name == "dispatchSites" {
            effect = "dispatch"
        } else if name == "poolSites" {
            effect = "pool"
        } else if name == "boundaryLeakSites" {
            effect = "boundaryLeak"
        }

        if effect != "" {
            if value.GetArrayLength() == 0 {
                verdict = verdict + ";" + GfVerdict(name + ".empty", GfEffectSiteCount(stdout, effect) == 0)
            } else {
                sites := value.EnumerateArray()
                position := 0
                while sites.MoveNext() {
                    verdict = verdict + ";" + GfVerdict(name + "." + position.ToString(),
                        GfEffectSiteMatches(stdout, effect, sites.Current.GetString() ?? ""))
                    position = position + 1
                }
            }
        } else if name == "trustedSites" {
            sites := value.EnumerateArray()
            while sites.MoveNext() {
                site := sites.Current.GetString() ?? ""
                verdict = verdict + ";" + GfVerdict("perfTrusted." + site, GfHasTrustedSite(stdout, site))
            }
        } else if name == "aotAnalysis" {
            verdict = verdict + ";" + GfVerdict("aotAnalysis",
                (GfReport(stdout).GetProperty("aot").GetProperty("analysis").GetString() ?? "") == (value.GetString() ?? ""))
        } else {
            verdict = verdict + ";" + name + "=<unhandled>"
        }
    }

    document.Dispose()
    return verdict
}


// ─── THE RUNTIME ABI KERNEL ───────────────────────────────────────────────────────────────────

// The deleted body constructed `NSharpLang.Runtime.Result<int, string>` from C# and read it by
// reflection. N# spells that type NATIVELY, so the successor USES it — `Ok(42)` and `Err("bad")`
// through two ordinary functions — and reaches for reflection only where the language cannot:
// `out` arguments on the `TryGet*` pair decline at columnar emit, and every `System.Type` BOOLEAN
// property (`IsValueType`, `IsClass`, `IsGenericType`, `IsAbstract`) declines in every spelling
// tried, so the value-type fact is stated through `IsAssignableFrom` instead.
func GfMakeOk(): Result<int, string> {
    return Ok(42)
}

func GfMakeErr(): Result<int, string> {
    return Err("bad")
}

func GfTryGet(owner: object, methodName: string): string {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(int).MakeByRefType()
    method := owner.GetType().GetMethod(methodName, parameterTypes)
    if method == null {
        return "<no-method>"
    }

    arguments := new object?[](1)
    answer := method.Invoke(owner, arguments)
    if answer == null {
        return "<null-answer>"
    }

    slot := arguments[0]
    if slot == null {
        return (answer.ToString() ?? "") + "|<null>"
    }

    return (answer.ToString() ?? "") + "|" + (slot.ToString() ?? "")
}

func GfTryGetErr(owner: object): string {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string).MakeByRefType()
    method := owner.GetType().GetMethod("TryGetErr", parameterTypes)
    if method == null {
        return "<no-method>"
    }

    arguments := new object?[](1)
    answer := method.Invoke(owner, arguments)
    if answer == null {
        return "<null-answer>"
    }

    slot := arguments[0]
    if slot == null {
        return (answer.ToString() ?? "") + "|<null>"
    }

    return (answer.ToString() ?? "") + "|" + (slot.ToString() ?? "")
}

func GfIsValueType(owner: object): bool {
    ownerType := owner.GetType()
    valueType := Type.GetType("System.ValueType")
    if valueType == null {
        return false
    }

    return valueType.IsAssignableFrom(ownerType)
}

func GfImplementsEquatable(owner: object): bool {
    ownerType := owner.GetType()
    equatable := Type.GetType("System.IEquatable`1")
    if equatable == null {
        return false
    }

    typeArguments := new Type[](1)
    typeArguments[0] = ownerType
    closed := equatable.MakeGenericType(typeArguments)
    return closed.IsAssignableFrom(ownerType)
}

// The CLR identity of the closed type, without the assembly-qualified argument list that would
// pin this file to one runtime version.
func GfTypeName(owner: object): string {
    ownerType := owner.GetType()
    return (ownerType.Namespace ?? "<null>") + "." + ownerType.Name
}



// ─── THE TEN GAUNTLET CASES ──────────────────────────────────────────────────────────────────


test "020 s41 systems gauntlet facts: `01-packet-parser` — the packet parser discharges its slice preconditions, so the report is clean and the golden says PASS; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("01-packet-parser")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-01-packet-parser")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL402:error@21:61+5"
    assert findingCount == 0
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "StructDeclaration:Header;refStruct=False|EnumDeclaration:HeaderError|FunctionDeclaration:ParseHeader;typeParameters=<null>;returnType=Result<Header, HeaderError>;returnLifetime=<null>;parameters=buf:ReadOnlySpan<byte>:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;hot=ok;bclHotSummary.BinaryPrimitives=ok;bclHotSummary.Slice=ok;errors=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;pass.noErrors=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok;boxingSites.empty=ok;dispatchSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `02-frame-writer` — the frame writer is allocation-free and bounds-guarded; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("02-frame-writer")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-02-frame-writer")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "EnumDeclaration:WriteError|FunctionDeclaration:WriteFrame;typeParameters=<null>;returnType=Result<int, WriteError>;returnLifetime=<null>;parameters=dst:Span<byte>:scoped=False:lifetime=<null>,tag:byte:scoped=False:lifetime=<null>,length:uint:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;hot=ok;boundsProof=ok;errors=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;pass.noErrors=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok;boxingSites.empty=ok;dispatchSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `03-spsc-ring` — the SPSC ring reaches `Volatile`, `Interlocked` and `Thread.MemoryBarrier` through the BCL hot-summary pack; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("03-spsc-ring")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-03-spsc-ring")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL402:error@10:26+4|NL402:error@11:25+9"
    assert findingCount == 0
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "StructDeclaration:Ring;refStruct=False|FunctionDeclaration:Publish;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=value:int:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;hot=ok;concurrencyPrimitive=ok;errors=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;pass.noErrors=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok;boxingSites.empty=ok;dispatchSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `04-heap-arena` — the arena returns a span carrying the HEAP owner lifetime — a fact only the parser holds, read here through the declaration census; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("04-heap-arena")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-04-heap-arena")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL103:error@13:1+4"
    assert findingCount == 0
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "StructDeclaration:Arena;refStruct=False|EnumDeclaration:ArenaError|FunctionDeclaration:Allocate;typeParameters=<null>;returnType=Result<Span<byte>, ArenaError>;returnLifetime=heap(self);parameters=self:&Arena:scoped=True:lifetime='self,n:int:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;returnLifetime=ok;resultAbi=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;pass.noErrors=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok;poolSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `05-ref-struct-reader` — the ref-like field is legal in the `ref struct` and illegal in the plain one, and the ref-struct flag comes from the parser; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("05-ref-struct-reader")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-05-ref-struct-reader")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    finding0 := GfRow(check.Stdout, "findings", 0)
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=0,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@9:5+3"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=ref-like field 'buf' is only allowed inside a ref struct;file=Program.nl;line=9;column=5;length=3;function=BadReader;policy=systems:strict;summarySource=sourceInferred;suggestion=Declare the containing type as `ref struct`, or store a heap-safe owner such as Memory<T>/ReadOnlyMemory<T>.;callPath=[BadReader]"
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "StructDeclaration:FrameReader;refStruct=True|StructDeclaration:BadReader;refStruct=False"
    assert systemsVerdict == "schemaVersion=ok;refStruct=ok;failure=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;line.NSYS080.error=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `06-pooled-boundary` — the pooled boundary rents without returning and reports NSYS130; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("06-pooled-boundary")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-06-pooled-boundary")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    finding0 := GfRow(check.Stdout, "findings", 0)
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=1,findings=1,errors=0,warnings=1,trustedSites=0}"
    assert diagnostics == "NSYS130:warning@3:5+6|NL001:error@3:5+6|NL301:error@3:15+9"
    assert findingCount == 1
    assert finding0 == "code=NSYS130;severity=warning;effect=pool;message=pooled buffer 'buffer' rented here is not returned on an obvious lexical path;file=Program.nl;line=3;column=5;length=6;function=Load;policy=systems:strict;summarySource=sourceInferred;suggestion=Return the buffer in a finally block, use a recognized owner/disposable pattern, or keep pooling inside a [boundary].;callPath=[Load]"
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "FunctionDeclaration:Load;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=<none>"
    assert systemsVerdict == "schemaVersion=ok;failure=ok;code=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;line.NSYS130.warning=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;poolSites.0=ok"
}

test "020 s41 systems gauntlet facts: `07-trusted-copy` — the unsafe block without a trusted memory-safe wrapper reports NSYS100, and the trusted site is still recorded; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("07-trusted-copy")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-07-trusted-copy")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    finding0 := GfRow(check.Stdout, "findings", 0)
    trustedCount := GfCount(check.Stdout, "trustedSites")
    trusted0 := GfRow(check.Stdout, "trustedSites", 0)
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=1}"
    assert diagnostics == "NSYS100:error@11:5+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS100;severity=error;effect=memorySafety;message=unsafe block requires a [trusted] memory-safe wrapper in systems code;file=Program.nl;line=11;column=5;length=1;function=BadCopy;policy=systems:strict;summarySource=sourceInferred;suggestion=Wrap unsafe code in a small [trusted(reason, owner, review)] function with [memory(safe)].;callPath=[BadCopy]"
    assert trustedCount == 1
    assert trusted0 == "function=Copy;file=Program.nl;line=3;column=1;reason=len is checked before native copy;owner=runtime-core;review=SYS-7;hasUnsafe=True;bodyStatementCount=2"
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "FunctionDeclaration:Copy;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=<none>|FunctionDeclaration:BadCopy;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=<none>"
    assert systemsVerdict == "schemaVersion=ok;trustedSite.Copy=ok;failure=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;line.NSYS100.error=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;perfTrusted.Copy=ok;allocationSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `08-order-book` — the `[hot]` `Dictionary` parameter is a systems-hostile boundary leak; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("08-order-book")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-08-order-book")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    finding0 := GfRow(check.Stdout, "findings", 0)
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS070:error@4:18+6|NL012:error@4:18+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS070;severity=error;effect=boundaryLeak;message=[hot] parameter 'levels' exposes a systems-hostile type: Dictionary;file=Program.nl;line=4;column=18;length=6;function=ApplyUpdate;policy=[hot];summarySource=sourceInferred;suggestion=Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.;callPath=[ApplyUpdate]"
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "FunctionDeclaration:ApplyUpdate;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=levels:Dictionary<int, int>:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;failure=ok;code=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;line.NSYS070.error=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;boundaryLeakSites.0=ok"
}

test "020 s41 systems gauntlet facts: `09-native-interop` — the native interop work is quarantined at the boundary and the AOT target is the declared one; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("09-native-interop")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-09-native-interop")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=1,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "EnumDeclaration:DeviceError|FunctionDeclaration:OpenDevice;typeParameters=<null>;returnType=Result<int, DeviceError>;returnLifetime=<null>;parameters=<none>|FunctionDeclaration:UseDevice;typeParameters=<null>;returnType=int;returnLifetime=<null>;parameters=handle:int:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;boundary=ok;hot=ok;aotTarget=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;pass.noErrors=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok"
}

test "020 s41 systems gauntlet facts: `10-json-cli` — the JSON CLI reports its boundary external call and emits no native image; the four goldens are on disk, and the whole report is pinned beside their verdicts (was SystemsNSharpTests.AcceptanceGauntlet_FixturesMatchSystemsPerfAndDiagnosticExpectations)" {
    caseDirectory := GfCaseDirectory("10-json-cli")
    sampleExists := File.Exists(Path.Combine(caseDirectory, "sample.nl"))
    systemsGoldenExists := File.Exists(Path.Combine(caseDirectory, "systems.golden.json"))
    diagnosticsGoldenExists := File.Exists(Path.Combine(caseDirectory, "diagnostics.golden.txt"))
    perfGoldenExists := File.Exists(Path.Combine(caseDirectory, "perf-report.golden.json"))
    source := File.ReadAllText(Path.Combine(caseDirectory, "sample.nl"))
    directory := GfFixture("gauntlet-10-json-cli")
    GfWrite(directory, "Program.nl", source)
    check := GfCheck(directory)
    exitCode := check.ExitCode
    envelope := GfEnvelope(check.Stdout)
    diagnostics := GfDiagnosticCensus(check.Stdout)
    parseCensus := GfParseCensus(source, "sample.nl")
    declarations := GfDeclarationCensus(source, "sample.nl")
    systemsVerdict := GfSystemsGoldenVerdict(Path.Combine(caseDirectory, "systems.golden.json"), check.Stdout, declarations)
    diagnosticsVerdict := GfDiagnosticsGoldenVerdict(Path.Combine(caseDirectory, "diagnostics.golden.txt"), check.Stdout)
    perfVerdict := GfPerfGoldenVerdict(Path.Combine(caseDirectory, "perf-report.golden.json"), check.Stdout)
    findingCount := GfCount(check.Stdout, "findings")
    finding0 := GfRow(check.Stdout, "findings", 0)
    trustedCount := GfCount(check.Stdout, "trustedSites")
    GfCleanup(directory)
    assert sampleExists
    assert systemsGoldenExists
    assert diagnosticsGoldenExists
    assert perfGoldenExists
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=1,findings=1,errors=0,warnings=1,trustedSites=0}"
    assert diagnostics == "NL103:error@13:15+33|NSYS050:warning@13:39+9"
    assert findingCount == 1
    assert finding0 == "code=NSYS050;severity=warning;effect=unknownExternalCall;message=boundary external call 'JsonSerializer.Serialize' reported for systems handoff review;file=Program.nl;line=13;column=39;length=9;function=EmitJson;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep unknown external work inside the [boundary] and expose a systems-safe result.;callPath=[EmitJson]"
    assert trustedCount == 0
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "EnumDeclaration:CliError|RecordDeclaration:CliPayload|FunctionDeclaration:EmitJson;typeParameters=<null>;returnType=Result<string, CliError>;returnLifetime=<null>;parameters=payload:CliPayload:scoped=False:lifetime=<null>|FunctionDeclaration:Score;typeParameters=<null>;returnType=Result<int, CliError>;returnLifetime=<null>;parameters=value:int:scoped=False:lifetime=<null>"
    assert systemsVerdict == "schemaVersion=ok;boundary=ok;hot=ok;code=ok;nativeImageEmitted=ok"
    assert diagnosticsVerdict == "nonEmpty=ok;line.NSYS050.warning=ok"
    assert perfVerdict == "schemaVersion=ok;command=ok;allocationSites.empty=ok"
}


// ─── THE LIFETIME SYNTAX THE CLI DOES NOT EXPOSE ──────────────────────────────────────────────


test "020 s41 systems gauntlet facts: a lifetime-parameterised function records its type parameter, its RETURN lifetime and the `scoped` lifetime of the parameter that carries one — and the two parameters that carry none are pinned as well (was SystemsNSharpTests.LifetimeSyntax_ParsesScopedParameterAndReturnLifetime)" {
    source := "import System\n\nfunc Slice<'a>(buf: ReadOnlySpan<byte> scoped 'a, start: int, len: int): ReadOnlySpan<byte> returns 'a {\n    return buf.Slice(start, len)\n}\n"
    parseCensus := GfParseCensus(source, "Program.nl")
    declarations := GfDeclarationCensus(source, "Program.nl")
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "FunctionDeclaration:Slice;typeParameters='a;returnType=ReadOnlySpan<byte>;returnLifetime='a;parameters=buf:ReadOnlySpan<byte>:scoped=True:lifetime='a,start:int:scoped=False:lifetime=<null>,len:int:scoped=False:lifetime=<null>"
}

test "020 s41 systems gauntlet facts: a `returns heap(arena)` lifetime is recorded verbatim, and the by-ref parameter it names is NOT scoped — which is the measured difference from the gauntlet arena, whose `self` is (was SystemsNSharpTests.LifetimeSyntax_ParsesHeapReturnLifetime)" {
    source := "import System\n\nfunc Slice(arena: &Arena, start: int, len: int): Span<byte> returns heap(arena) {\n    return arena.backing.AsSpan(start, len)\n}\n\nstruct Arena {\n    backing: byte[]\n}\n"
    parseCensus := GfParseCensus(source, "Program.nl")
    declarations := GfDeclarationCensus(source, "Program.nl")
    assert parseCensus == "unit=present;errors=0"
    assert declarations == "FunctionDeclaration:Slice;typeParameters=<null>;returnType=Span<byte>;returnLifetime=heap(arena);parameters=arena:&Arena:scoped=False:lifetime=<null>,start:int:scoped=False:lifetime=<null>,len:int:scoped=False:lifetime=<null>|StructDeclaration:Arena;refStruct=False"
}


// ─── THE RUNTIME ABI ──────────────────────────────────────────────────────────────────────────


test "020 s41 systems gauntlet facts: the `Result<T, E>` runtime ABI is an allocation-free tagged struct — read through the LANGUAGE rather than through `typeof`, because N# spells this type natively, and through reflection only where the language declines (was SystemsNSharpTests.ResultRuntimeAbi_IsAllocationFreeTaggedStruct)" {
    ok := GfMakeOk()
    err := GfMakeErr()
    assert ok.IsOk
    assert !ok.IsErr
    assert ok.OkValueUnchecked == 42
    assert err.IsErr
    assert !err.IsOk
    assert err.ErrValueUnchecked == "bad"
    assert GfIsValueType(ok)
    assert GfImplementsEquatable(ok)
    assert GfTryGet(ok, "TryGetOk") == "True|42"
    assert GfTryGetErr(ok) == "False|<null>"
    assert GfTryGetErr(err) == "True|bad"
    assert GfTryGet(err, "TryGetOk") == "False|0"
    assert GfTypeName(ok) == "NSharpLang.Runtime.Result`2"
}
