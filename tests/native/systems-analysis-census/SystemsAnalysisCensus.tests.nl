namespace NSharpLang.SystemsAnalysisCensus.Tests

import System
import System.Diagnostics
import System.IO
import System.Text.Json


// THE SYSTEMS POLICY CENSUS, ANSWERED BY THE SHIPPED CLI, IN N#.
//
// These replace the two families of `tests/SystemsNSharpTests.cs` whose bodies read a SYSTEMS
// REPORT: the 52 SYSTEMS-ANALYSIS methods (996 declaration lines, 106 in-body `Assert.`) and the 4
// CLI-IN-PROCESS methods (147 lines, 28 asserts). 56 methods become 58 blocks here, because the
// one `[Theory]` carries two `InlineData` rows and one method analysed the same source under two
// different sidecar policies — and each of those is its own independently reported test rather than
// a second half hidden behind the first failure.
//
// WHY THE SHIPPED CLI AND NOT `MultiFileCompiler`. The deleted helper built the report IN PROCESS:
// `ProjectFileParser.CreateDefault(...)`, four mutations of the returned `ProjectConfig`, and
// `new MultiFileCompiler(...).CompileForAnalysis()`. Every one of those mutations has a project.yml
// spelling — `language.profile`, `language.systems.mode`, `.stackBudgetBytes`, `.warmup`,
// `.hotSummaryFiles`, `.allowHotSidecars` — so routing through `nlc check --project …
// --systems-report` states the same fixture through the surface a USER has, YAML parser included,
// and pins the versioned envelope rather than an in-memory object. It is also measured cheap: one
// spawn is 0.15 s, so the whole family costs about ten seconds.
//
// AND IT COSTS NO REFLECTION. This project declares NO dependencies at all and loads no compiler
// assembly: it is the second native project (after `tests/native/systems-proof-corpus`) to reach
// its subject entirely through spawned processes, so the `Assembly.Load` debt the AOT single-binary
// end state forbids is not bought here either.
//
// THE ROUTE WAS PRICED BY MEASUREMENT, NOT BY ARGUMENT. All 109 run-expanded claim rows of the
// deleted analysis family (106 static rows; the `[Theory]`'s three rows run twice) were evaluated
// against the CLI's answers before a line of this file was written, and ALL 109 HOLD — no false
// clean. The same 54 fixtures were run a second time under `outputType: exe` instead of `library`,
// and the systems report is byte-identical on all 54, so the one field the deleted `CreateDefault`
// disagreed with this project file about changes nothing it claims.
//
// WHAT THE PINS SAY THAT THE DELETED ONES COULD NOT. Every block states the WHOLE envelope
// (command, ok, checked files, both schema versions, profile, mode, AOT target, the AOT block, the
// warmup list and the summary counts), the WHOLE of every finding row, the WHOLE of every function
// summary — all fifteen effect flags and the recorded call list — the WHOLE of every trusted site,
// and the diagnostic census the CLI wrote. The deleted assertions read a code and a severity off a
// `f => …` lambda and said nothing about the rest.
//
// AND THAT IS HOW THE HEADLINE BECAME VISIBLE: **TWENTY OF THE 54 FIXTURES DO NOT COMPILE CLEAN.**
// They carry 22 non-systems ERROR rows the deleted assertions could not see, and two of them
// undermined the claim their own method was making —
// `SystemsStrict_DisposeCallSatisfiesObviousResourceOwnership` proved that a `Dispose()` call
// satisfies NSYS090 while the analyzer reports `NL303: Member 'Dispose' not found on type
// 'FileStream'`, and `PoolRent_MustBeReturnedOnObviousLexicalPath` proves the pool rule over a
// receiver the analyzer reports as `NL301: Variable 'ArrayPool' not found`. The systems policy
// answers over source the compiler rejects, and every one of those rows is pinned below.
//
// THE FIRST OF THOSE TWO WAS A PRODUCT DEFECT AND IT IS NOW FIXED; THE BLOCK BELOW PINS THE FIXED
// BEHAVIOUR AND ITS PROOF IS THE INVERSION IT USED TO HAVE. Decided by the member NAME alone, the
// ledger discharge accepted ONLY a disposal that does NOT resolve: this fixture's `stream.Dispose()`
// closed the resource obligation (and suppressed NSYS050) while `NL303` said the member is not
// there, and the SAME source with `func Dispose()` really declared reported NSYS090 "is not disposed"
// with no other diagnostic at all — a false negative on broken source and a false POSITIVE on
// correct source, from one rule. `SystemsCallPolicy` now takes the analyzer's own verdict
// (`MemberIsPositivelyRejected`) and the resolved half of the walk discharges through
// `MarkDeclaredCalleeDischarges`. The three blocks that state this subject — this fixture, the pool
// rental below it and the coincidental-name NSYS050 — carry the fixed rows, and the pool fixture's
// own NSYS130 is UNCHANGED, which is what proves the fix did not simply switch the rule off.
//
// A STRUCTURALLY VACUOUS CLAIM IS RETIRED, AND ITS TWIN IS NOT. The deleted
// `Assert.True(string.IsNullOrWhiteSpace(stderr))` in `CheckCommand_SystemsReport_EmitsVersionedJson`
// could not fail: every `Console.Error` path in `CheckCommand.Execute` is gated on text mode, and
// `--systems-report` never enters it — measured again here, a project that does not exist at all
// still answers with an EMPTY standard error. It is replaced by the diagnostic census. The same
// claim in `QueryPerf_ReturnsSystemsFindingAtPosition` is NOT vacuous, and the measure is why:
// `query perf` writes 138 bytes to standard error on a missing project and 70 on a malformed
// `--pos`, so that channel is live and the silence is kept as a claim.


// ─── THE SPAWN KERNEL ─────────────────────────────────────────────────────────────────────────

class SacRun {
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
func SacRunProcess(fileName: string, arguments: string, workingDirectory: string): SacRun {
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
    return new SacRun(exitCode, stdout, stderr)
}

// The repository root, found by walking up from the directory this test assembly was loaded into
// (which is the CLI's own directory, because `nlc test` hosts the emitted tests in its process).
func SacRepositoryRoot(): string {
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

func SacCliDll(): string {
    root := SacRepositoryRoot()
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
func SacFixture(name: string, projectYaml: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-systems-analysis-census-" + name)
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }

    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, "project.yml"), projectYaml)
    return directory
}

func SacWrite(directory: string, fileName: string, text: string) {
    File.WriteAllText(Path.Combine(directory, fileName), text)
}

func SacCleanup(directory: string) {
    if Directory.Exists(directory) {
        Directory.Delete(directory, true)
    }
}

func SacCheck(directory: string): SacRun {
    return SacRunProcess("dotnet", SacCliDll() + " check --project " + directory + " --systems-report", directory)
}

func SacInvoke(directory: string, arguments: string): SacRun {
    return SacRunProcess("dotnet", SacCliDll() + " " + arguments, directory)
}


// ─── THE CENSUS KERNEL ────────────────────────────────────────────────────────────────────────

// Every pinned value below is produced by walking the SHIPPED JSON's own properties in document
// order, so a row states the WHOLE row rather than the two or three fields a `f => f.Code == …`
// lambda happened to look at, and a new field cannot appear unnoticed.
func SacElementText(element: JsonElement): string {
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

            arrayText = arrayText + SacElementText(arrayEnumerator.Current)
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

        objectText = objectText + property.Name + "=" + SacElementText(property.Value)
        objectFirst = false
    }

    return objectText + "}"
}

// A row is the object's own property list, in document order, with absolute fixture paths reduced
// to their file names so the pin is stable across machines and temp directories.
func SacRowText(element: JsonElement): string {
    text := ""
    enumerator := element.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        value := SacElementText(property.Value)
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

func SacSection(stdout: string, sectionName: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    report := document.RootElement.GetProperty("systemsReport")
    section := report.GetProperty(sectionName).Clone()
    document.Dispose()
    return section
}

func SacCount(stdout: string, sectionName: string): int {
    return SacSection(stdout, sectionName).GetArrayLength()
}

func SacRow(stdout: string, sectionName: string, index: int): string {
    section := SacSection(stdout, sectionName)
    if index >= section.GetArrayLength() {
        return "<no-such-row>"
    }

    position := 0
    enumerator := section.EnumerateArray()
    while enumerator.MoveNext() {
        if position == index {
            return SacRowText(enumerator.Current)
        }

        position = position + 1
    }

    return "<no-such-row>"
}

// The whole report minus its three arrays: the envelope a consumer reads first.
func SacEnvelope(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    root := document.RootElement
    report := root.GetProperty("systemsReport")
    text := "command=" + SacElementText(root.GetProperty("command"))
        + ";ok=" + SacElementText(root.GetProperty("ok"))
        + ";checkedFiles=" + SacElementText(root.GetProperty("checkedFiles"))
        + ";envelopeSchema=" + SacElementText(root.GetProperty("schemaVersion"))
        + ";reportSchema=" + SacElementText(report.GetProperty("schemaVersion"))
        + ";profile=" + SacElementText(report.GetProperty("profile"))
        + ";mode=" + SacElementText(report.GetProperty("mode"))
        + ";aotTarget=" + SacElementText(report.GetProperty("aotTarget"))
        + ";aot=" + SacElementText(report.GetProperty("aot"))
        + ";warmup=" + SacElementText(report.GetProperty("warmup"))
        + ";summary=" + SacElementText(report.GetProperty("summary"))
    document.Dispose()
    return text
}

// The diagnostics the CLI actually wrote — the runtime census that replaces the deleted
// `Assert.True(string.IsNullOrWhiteSpace(stderr))`, which could not fail (see the banner).
func SacDiagnosticCensus(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    diagnostics := document.RootElement.GetProperty("diagnostics")
    census := ""
    enumerator := diagnostics.EnumerateArray()
    while enumerator.MoveNext() {
        entry := enumerator.Current
        if census != "" {
            census = census + "|"
        }

        census = census + SacElementText(entry.GetProperty("code")) + ":"
            + SacElementText(entry.GetProperty("severity")) + "@"
            + SacElementText(entry.GetProperty("line")) + ":"
            + SacElementText(entry.GetProperty("column")) + "+"
            + SacElementText(entry.GetProperty("length"))
    }

    document.Dispose()
    return census
}


// ─── THE CLI-ENVELOPE KERNEL ──────────────────────────────────────────────────────────────────

// `build --perf-report`, `query perf` and `query trusted` answer envelopes of their own, and the
// four CLI blocks at the end of this file pin them the same way: whole rows, in document order.
func SacRootSection(stdout: string, sectionName: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    section := document.RootElement.GetProperty(sectionName).Clone()
    document.Dispose()
    return section
}

func SacRootCount(stdout: string, sectionName: string): int {
    return SacRootSection(stdout, sectionName).GetArrayLength()
}

func SacRootRow(stdout: string, sectionName: string, index: int): string {
    section := SacRootSection(stdout, sectionName)
    if index >= section.GetArrayLength() {
        return "<no-such-row>"
    }

    position := 0
    enumerator := section.EnumerateArray()
    while enumerator.MoveNext() {
        if position == index {
            return SacRowText(enumerator.Current)
        }

        position = position + 1
    }

    return "<no-such-row>"
}

func SacPerfSection(stdout: string, sectionName: string): JsonElement {
    document := JsonDocument.Parse(stdout)
    section := document.RootElement.GetProperty("perfReport").GetProperty(sectionName).Clone()
    document.Dispose()
    return section
}

func SacPerfRow(stdout: string, sectionName: string, index: int): string {
    section := SacPerfSection(stdout, sectionName)
    if index >= section.GetArrayLength() {
        return "<no-such-row>"
    }

    position := 0
    enumerator := section.EnumerateArray()
    while enumerator.MoveNext() {
        if position == index {
            return SacRowText(enumerator.Current)
        }

        position = position + 1
    }

    return "<no-such-row>"
}

// The perf report's OWN shape: every array it carries, in document order, with its length. The
// deleted `Assert.Equal(JsonValueKind.Array, …)` calls asked four of these whether they were arrays
// at all; this says which arrays exist and how full each one is.
func SacPerfShape(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    report := document.RootElement.GetProperty("perfReport")
    shape := ""
    enumerator := report.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        if shape != "" {
            shape = shape + ";"
        }

        if property.Value.ValueKind == JsonValueKind.Array {
            shape = shape + property.Name + "=" + property.Value.GetArrayLength().ToString()
        } else {
            shape = shape + property.Name + "=<not-an-array>"
        }
    }

    document.Dispose()
    return shape
}

func SacScalars(stdout: string): string {
    document := JsonDocument.Parse(stdout)
    text := ""
    enumerator := document.RootElement.EnumerateObject()
    while enumerator.MoveNext() {
        property := enumerator.Current
        if property.Value.ValueKind == JsonValueKind.Array || property.Value.ValueKind == JsonValueKind.Object {
            if property.Name == "position" || property.Name == "summary" {
                if text != "" {
                    text = text + ";"
                }

                text = text + property.Name + "=" + SacElementText(property.Value)
            }
        } else {
            value := SacElementText(property.Value)
            if property.Name == "projectRoot" {
                value = "<fixture>"
            }

            if property.Name == "file" {
                value = Path.GetFileName(value) ?? ""
            }

            if text != "" {
                text = text + ";"
            }

            text = text + property.Name + "=" + value
        }
    }

    document.Dispose()
    return text
}

// Counting by ordinal `IndexOf`, because `Regex` construction and the static `Regex.IsMatch` both
// decline on this emit path — and by the THREE-argument overload, because the two-argument
// `IndexOf(value, startIndex)` declines as well while `(value, startIndex, StringComparison)`
// compiles.
func SacCountOccurrences(text: string, needle: string): int {
    count := 0
    index := text.IndexOf(needle, StringComparison.Ordinal)
    while index >= 0 {
        count = count + 1
        index = text.IndexOf(needle, index + needle.Length, StringComparison.Ordinal)
    }

    return count
}

// `build` DOES write to standard error, unlike `check --systems-report`, so the build block states
// what it wrote: both banner counts and whether the success line is there.
func SacStderrCensus(stderr: string): string {
    successful := "False"
    if stderr.IndexOf("Build successful!", StringComparison.Ordinal) >= 0 {
        successful = "True"
    }

    return "warningBanners=" + SacCountOccurrences(stderr, "-- WARNING").ToString()
        + ";errorBanners=" + SacCountOccurrences(stderr, "-- ERROR").ToString()
        + ";buildSuccessful=" + successful
}




// ─── THE 54 ANALYSIS BLOCKS ──────────────────────────────────────────────────────────────────


test "020 s41 systems analysis census: a `[hot]` function that allocates reports NSYS010 at the `new`, and the whole row — position, policy, call path and suggestion — is pinned (was SystemsNSharpTests.HotFunction_RejectsHeapAllocation)" {
    directory := SacFixture("hotfunction-rejectsheapallocation", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Make(): int {\n    value := new Box()\n    return 1\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL001:error@3:5+5|NSYS010:error@3:14+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=allocation not allowed in [hot] function;file=Program.nl;line=3;column=14;length=1;function=Make;policy=[hot];summarySource=sourceInferred;suggestion=Move allocation behind a [boundary], return caller-provided storage, or use a narrow allow(alloc) only for a cold path.;callPath=[Make]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: under `profile: systems` an unmarked `new` reports NSYS001, and the systems mode is the one the project file declares (was SystemsNSharpTests.SystemsStrict_RequiresExplicitAllocMarkerForHeapNew)" {
    directory := SacFixture("systemsstrict-requiresexplicitallocmarkerforheapnew", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Make(): Box {\n    return new Box()\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS001:error@2:12+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS001;severity=error;effect=allocation;message=heap allocation in systems strict must be marked with alloc;file=Program.nl;line=2;column=12;length=1;function=Make;policy=systems:strict;summarySource=sourceInferred;suggestion=Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary].;callPath=[Make]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: `alloc new` outside a `[hot]` path is SILENT — an empty report, a clean envelope and exit 0 (was SystemsNSharpTests.SystemsStrict_AcceptsExplicitAllocMarkerOutsideHot)" {
    directory := SacFixture("systemsstrict-acceptsexplicitallocmarkeroutsidehot", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Make(): Box {\n    return alloc new Box()\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an `alloc { … }` block is the same permission as the `alloc` prefix: the report is EMPTY (was SystemsNSharpTests.SystemsStrict_AcceptsAllocBlockForObviousAllocationSugar)" {
    directory := SacFixture("systemsstrict-acceptsallocblockforobviousallocationsugar", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Make(): Box {\n    alloc {\n        return new Box()\n    }\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an unguarded index in `[hot]` code reports NSYS120 as an implicit trap (was SystemsNSharpTests.HotFunction_RejectsUnguardedIndexTrap)" {
    directory := SacFixture("hotfunction-rejectsunguardedindextrap", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc First(bytes: byte[]): byte {\n    return bytes[0]\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS120:error@3:17+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS120;severity=error;effect=implicitTrap;message=index access in [hot] requires a proven bounds guard or allow(trap);file=Program.nl;line=3;column=17;length=1;function=First;policy=[hot];summarySource=sourceInferred;callPath=[First]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=First;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `.Length` guard ahead of the index proves the bound and the report is EMPTY (was SystemsNSharpTests.HotFunction_AcceptsSimpleLengthGuardedIndex)" {
    directory := SacFixture("hotfunction-acceptssimplelengthguardedindex", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc First(bytes: byte[]): byte {\n    if bytes.Length < 1 {\n        return 0\n    }\n    return bytes[0]\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=First;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the guard also counts when the index sits in the TRUE branch of `if index < values.Length` (was SystemsNSharpTests.HotFunction_AcceptsIfTrueBranchLengthGuardedIndex)" {
    directory := SacFixture("hotfunction-acceptsiftruebranchlengthguardedindex", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Read(values: int[], index: int): int {\n    if index < values.Length {\n        return values[index]\n    }\n    return -1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Read;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the same guard does NOT carry into the branch it excludes: indexing inside `if bytes.Length < 1` still traps (was SystemsNSharpTests.HotFunction_DoesNotApplyPostIfGuardInsideFailingBranch)" {
    directory := SacFixture("hotfunction-doesnotapplypostifguardinsidefailingbranch", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc First(bytes: byte[]): byte {\n    if bytes.Length < 1 {\n        return bytes[0]\n    }\n    return 0\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS120:error@4:21+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS120;severity=error;effect=implicitTrap;message=index access in [hot] requires a proven bounds guard or allow(trap);file=Program.nl;line=4;column=21;length=1;function=First;policy=[hot];summarySource=sourceInferred;callPath=[First]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=First;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a narrow `allow(alloc, reason: …)` block licenses the allocation and the report is EMPTY (was SystemsNSharpTests.HotFunction_AcceptsNarrowAllowAllocBlock)" {
    directory := SacFixture("hotfunction-acceptsnarrowallowallocblock", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Make(): int {\n    allow(alloc, reason: \"cold fallback table\") {\n        value := alloc new Box()\n    }\n    return 1\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `[boundary]` reports its allocation AND its unknown external call as WARNINGS, and nothing at error severity (was SystemsNSharpTests.BoundaryFunction_ReportsAllocationAndUnknownExternalCallWithoutBlocking)" {
    directory := SacFixture("boundaryfunction-reportsallocationandunknownexternalcallwith", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[boundary]\nfunc Load(): int {\n    value := new Box()\n    Console.WriteLine(\"loaded\")\n    return 1\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=1,findings=2,errors=0,warnings=2,trustedSites=0}"
    assert diagnostics == "NL001:error@3:5+5|NSYS001:warning@3:14+1|NSYS050:warning@4:22+9"
    assert findingCount == 2
    assert finding0 == "code=NSYS001;severity=warning;effect=allocation;message=boundary allocation reported for systems handoff review;file=Program.nl;line=3;column=14;length=1;function=Load;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>.;callPath=[Load]"
    assert finding1 == "code=NSYS050;severity=warning;effect=unknownExternalCall;message=boundary external call 'Console.WriteLine' reported for systems handoff review;file=Program.nl;line=4;column=22;length=9;function=Load;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep unknown external work inside the [boundary] and expose a systems-safe result.;callPath=[Load]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Load;file=Program.nl;line=2;column=1;isHot=False;isBoundary=True;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Console.WriteLine]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `[trusted]` site with only a reason is recorded as a trusted site AND reported NSYS100 for the missing governance metadata (was SystemsNSharpTests.TrustedFunction_RequiresGovernanceMetadata)" {
    directory := SacFixture("trustedfunction-requiresgovernancemetadata", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[trusted(reason: \"wraps native copy\")]\nfunc Copy(): int {\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=2,errors=2,warnings=0,trustedSites=1}"
    assert diagnostics == "NSYS100:error@2:1+4|NSYS100:error@2:1+4"
    assert findingCount == 2
    assert finding0 == "code=NSYS100;severity=error;effect=memorySafety;message=[trusted] requires reason, owner, and review metadata;file=Program.nl;line=2;column=1;length=4;function=Copy;policy=systems:strict;summarySource=sourceInferred;suggestion=Write [trusted(reason: \"...\", owner: \"...\", review: \"...\")] on the wrapper.;callPath=[Copy]"
    assert finding1 == "code=NSYS100;severity=error;effect=memorySafety;message=[trusted] wrappers must declare [memory(safe)] for Systems N# v1;file=Program.nl;line=2;column=1;length=4;function=Copy;policy=systems:strict;summarySource=sourceInferred;suggestion=Add [memory(safe)] after documenting the unsafe proof.;callPath=[Copy]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Copy;file=Program.nl;line=2;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 1
    assert trusted0 == "function=Copy;file=Program.nl;line=2;column=1;reason=wraps native copy;hasUnsafe=False;bodyStatementCount=1"
}

test "020 s41 systems analysis census: a `[memory(safe)]` + fully-attributed `[trusted]` wrapper with a restricted `unsafe` block reports NOTHING, and its trusted row carries owner and review (was SystemsNSharpTests.TrustedMemorySafeWrapper_AllowsRestrictedUnsafeBlock)" {
    directory := SacFixture("trustedmemorysafewrapper-allowsrestrictedunsafeblock", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[memory(safe)]\n[trusted(reason: \"bounds checked by caller\", owner: \"runtime-core\", review: \"SYS-1\")]\nfunc Copy(): int {\n    unsafe {\n        value := 1\n    }\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=1}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Copy;file=Program.nl;line=3;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 1
    assert trusted0 == "function=Copy;file=Program.nl;line=3;column=1;reason=bounds checked by caller;owner=runtime-core;review=SYS-1;hasUnsafe=True;bodyStatementCount=2"
}

test "020 s41 systems analysis census: `Buffer.MemoryCopy` inside a trusted memory-safe `unsafe` block is hot-callable: the function summary shows every effect false and the call recorded (was SystemsNSharpTests.BufferMemoryCopy_InTrustedUnsafeWrapper_IsHotCallable)" {
    directory := SacFixture("buffermemorycopy-intrustedunsafewrapper-ishotcallable", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "import System\n\nenum CopyStatus {\n    Ok,\n    OutOfRange\n}\n\n[memory(safe)]\n[trusted(reason: \"length is checked against both spans\", owner: \"runtime-core\", review: \"SYS-25\")]\n[hot]\nfunc CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): CopyStatus {\n    if len < 0 || len > dst.Length || len > src.Length {\n        return CopyStatus.OutOfRange\n    }\n\n    unsafe {\n        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)\n    }\n\n    return CopyStatus.Ok\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=1}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=CopyExact;file=Program.nl;line=11;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Buffer.MemoryCopy]"
    assert trustedCount == 1
    assert trusted0 == "function=CopyExact;file=Program.nl;line=11;column=1;reason=length is checked against both spans;owner=runtime-core;review=SYS-25;hasUnsafe=True;bodyStatementCount=3"
}

test "020 s41 systems analysis census: the same copy OUTSIDE the `unsafe` block fails memory safety with NSYS100 (was SystemsNSharpTests.BufferMemoryCopy_OutsideUnsafeBlock_FailsMemorySafety)" {
    directory := SacFixture("buffermemorycopy-outsideunsafeblock-failsmemorysafety", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "import System\n\n[memory(safe)]\n[trusted(reason: \"missing unsafe isolation\", owner: \"runtime-core\", review: \"SYS-25\")]\n[hot]\nfunc CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): int {\n    Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)\n    return len\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=1}"
    assert diagnostics == "NSYS100:error@7:22+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS100;severity=error;effect=memorySafety;message=Buffer.MemoryCopy must be isolated inside an unsafe block;file=Program.nl;line=7;column=22;length=1;function=CopyExact;policy=[hot];summarySource=sourceInferred;suggestion=Wrap Buffer.MemoryCopy in a small [trusted] [memory(safe)] function and document the bounds proof.;callPath=[CopyExact]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=CopyExact;file=Program.nl;line=6;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Buffer.MemoryCopy]"
    assert trustedCount == 1
    assert trusted0 == "function=CopyExact;file=Program.nl;line=6;column=1;reason=missing unsafe isolation;owner=runtime-core;review=SYS-25;hasUnsafe=False;bodyStatementCount=2"
}

test "020 s41 systems analysis census: a callee allocation is blamed on the `[hot]` caller and the finding carries the whole call path (was SystemsNSharpTests.HotFunction_PropagatesCalleeAllocationWithCallPath)" {
    directory := SacFixture("hotfunction-propagatescalleeallocationwithcallpath", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Caller(): int {\n    return Cold()\n}\n\nfunc Cold(): int {\n    value := new Box()\n    return 1\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@3:16+4|NL001:error@7:5+5"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'Cold' allocates on a hot/alloc(none) path;file=Program.nl;line=3;column=16;length=4;function=Caller;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Caller,Cold]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=Cold;file=Program.nl;line=6;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Caller;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Cold]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: two classes declare the same `Helper` and the allocating one is flagged regardless of file order (alloc file first) (was SystemsNSharpTests.HotCallee_SameMethodNameInTwoClasses_FlagsNsys010RegardlessOfFileOrder[a_alloc.nl,z_clean.nl])" {
    directory := SacFixture("hotcallee-samemethodnameintwoclasses-flagsnsys010regardlesso", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "a_alloc.nl", "class Alloc {\n    func Helper(): Box {\n        return alloc new Box()\n    }\n\n    [hot]\n    func Hot(): int {\n        value := this.Helper()\n        return value.Tag\n    }\n}\n\nclass Box {\n    Tag: int\n}\n")
    SacWrite(directory, "z_clean.nl", "class Clean {\n    func Helper(): int {\n        return 1\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@8:29+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'Alloc.Helper' allocates on a hot/alloc(none) path;file=a_alloc.nl;line=8;column=29;length=6;function=Alloc.Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Alloc.Hot,Alloc.Helper]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Alloc.Helper;file=a_alloc.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Alloc.Hot;file=a_alloc.nl;line=7;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alloc.Helper]"
    assert function2 == "name=Clean.Helper;file=z_clean.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the same pair with the CLEAN file first answers identically, which is the whole point of the row (was SystemsNSharpTests.HotCallee_SameMethodNameInTwoClasses_FlagsNsys010RegardlessOfFileOrder[z_alloc.nl,a_clean.nl])" {
    directory := SacFixture("hotcallee-samemethodnameintwoclasses-flagsnsys010regardlesso", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "z_alloc.nl", "class Alloc {\n    func Helper(): Box {\n        return alloc new Box()\n    }\n\n    [hot]\n    func Hot(): int {\n        value := this.Helper()\n        return value.Tag\n    }\n}\n\nclass Box {\n    Tag: int\n}\n")
    SacWrite(directory, "a_clean.nl", "class Clean {\n    func Helper(): int {\n        return 1\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@8:29+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'Alloc.Helper' allocates on a hot/alloc(none) path;file=z_alloc.nl;line=8;column=29;length=6;function=Alloc.Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Alloc.Hot,Alloc.Helper]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Clean.Helper;file=a_clean.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Alloc.Helper;file=z_alloc.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=Alloc.Hot;file=z_alloc.nl;line=7;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alloc.Helper]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the two same-named `Helper` classes concatenated into ONE file still resolve per class: `Alloc.Hot` is flagged (was SystemsNSharpTests.HotCallee_SameFileLaterDuplicate_StillFlagged)" {
    directory := SacFixture("hotcallee-samefilelaterduplicate-stillflagged", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "class Alloc {\n    func Helper(): Box {\n        return alloc new Box()\n    }\n\n    [hot]\n    func Hot(): int {\n        value := this.Helper()\n        return value.Tag\n    }\n}\n\nclass Box {\n    Tag: int\n}\nclass Clean {\n    func Helper(): int {\n        return 1\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@8:29+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'Alloc.Helper' allocates on a hot/alloc(none) path;file=Program.nl;line=8;column=29;length=6;function=Alloc.Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Alloc.Hot,Alloc.Helper]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Alloc.Helper;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Alloc.Hot;file=Program.nl;line=7;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alloc.Helper]"
    assert function2 == "name=Clean.Helper;file=Program.nl;line=17;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a clean hot path is NOT blamed for an unrelated allocator in another file: the report is empty and `Clean.Hot` allocates nothing (was SystemsNSharpTests.HotCallee_CleanHotPath_NotBlamedForUnrelatedAllocator)" {
    directory := SacFixture("hotcallee-cleanhotpath-notblamedforunrelatedallocator", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "a_clean.nl", "class Clean {\n    func Helper(): int {\n        return 1\n    }\n\n    [hot]\n    func Hot(): int {\n        return this.Helper()\n    }\n}\n")
    SacWrite(directory, "z_alloc.nl", "class Alloc {\n    func Helper(): Box {\n        return alloc new Box()\n    }\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Clean.Helper;file=a_clean.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Clean.Hot;file=a_clean.nl;line=7;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Clean.Helper]"
    assert function2 == "name=Alloc.Helper;file=z_alloc.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: two file-private `helper` functions with the same name are TWO distinct summaries, and only the allocating one allocates (was SystemsNSharpTests.FilePrivateTopLevelDuplicates_ResolvePerFile)" {
    directory := SacFixture("fileprivatetoplevelduplicates-resolveperfile", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "a_other.nl", "func helper(): int {\n    return 2\n}\n")
    SacWrite(directory, "z_hot.nl", "func helper(): int {\n    box := alloc new Box()\n    return box.Tag\n}\n\n[hot]\nfunc HotPath(): int {\n    return helper()\n}\n\nclass Box {\n    Tag: int\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@8:18+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'helper' allocates on a hot/alloc(none) path;file=z_hot.nl;line=8;column=18;length=6;function=HotPath;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[HotPath,helper]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=helper;file=a_other.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=helper;file=z_hot.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=HotPath;file=z_hot.nl;line=7;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[helper]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: overloads resolve by arity: calling `Helper(2)` reaches the allocating overload and flags `Alloc.Hot` (was SystemsNSharpTests.HotCallee_OverloadsResolveByArity_AllocatingOverloadFlagged)" {
    directory := SacFixture("hotcallee-overloadsresolvebyarity-allocatingoverloadflagged", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "class Alloc {\n    func Helper(): int {\n        return 1\n    }\n\n    func Helper(n: int): Box {\n        return alloc new Box()\n    }\n\n    [hot]\n    func Hot(): int {\n        value := this.Helper(2)\n        return 1\n    }\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL012:error@6:17+1|NL001:error@12:9+5|NSYS010:error@12:29+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'Alloc.Helper' allocates on a hot/alloc(none) path;file=Program.nl;line=12;column=29;length=6;function=Alloc.Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Alloc.Hot,Alloc.Helper]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Alloc.Helper;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Alloc.Helper;file=Program.nl;line=6;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=Alloc.Hot;file=Program.nl;line=11;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alloc.Helper]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: calling the zero-argument `Helper()` reaches the clean overload: no systems finding at all (was SystemsNSharpTests.HotCallee_OverloadsResolveByArity_CleanOverloadNotFlagged)" {
    directory := SacFixture("hotcallee-overloadsresolvebyarity-cleanoverloadnotflagged", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "class Alloc {\n    func Helper(): int {\n        return 1\n    }\n\n    func Helper(n: int): Box {\n        return alloc new Box()\n    }\n\n    [hot]\n    func Hot(): int {\n        return this.Helper()\n    }\n}\n\nclass Box {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL012:error@6:17+1"
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Alloc.Helper;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Alloc.Helper;file=Program.nl;line=6;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=Alloc.Hot;file=Program.nl;line=11;column=5;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alloc.Helper]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an unknown receiver is not suppressed by a coincidentally-named method elsewhere — NSYS050 names `io.Helper` (was SystemsNSharpTests.Nsys050_NotSuppressedByCoincidentalName)" {
    directory := SacFixture("nsys050-notsuppressedbycoincidentalname", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "class Unrelated {\n    func Helper(): int {\n        return 1\n    }\n}\n\n[hot]\nfunc Hot(io: SomeUnknownService): int {\n    return io.Helper()\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=0,findings=2,errors=2,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS070:error@8:10+2|NL201:error@8:14+18|NSYS050:error@9:21+6"
    assert findingCount == 2
    assert finding0 == "code=NSYS070;severity=error;effect=boundaryLeak;message=[hot] parameter 'io' exposes a systems-hostile type: managed or unsummarized type 'SomeUnknownService';file=Program.nl;line=8;column=10;length=2;function=Hot;policy=[hot];summarySource=sourceInferred;suggestion=Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.;callPath=[Hot]"
    assert finding1 == "code=NSYS050;severity=error;effect=unknownExternalCall;message=unknown external call 'io.Helper' is not callable from [hot];file=Program.nl;line=9;column=21;length=6;function=Hot;policy=[hot];summarySource=sourceInferred;suggestion=Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary].;callPath=[Hot]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=Unrelated.Helper;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Hot;file=Program.nl;line=8;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[io.Helper]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a constrained generic call resolves through its constraint interface, so the call is KNOWN and recorded as `Sortable.LessThan` (was SystemsNSharpTests.HotConstrainedGenericCall_ResolvesThroughConstraintInterface)" {
    directory := SacFixture("hotconstrainedgenericcall-resolvesthroughconstraintinterface", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "interface Sortable<T> {\n    func LessThan(other: T): bool\n}\n\nstruct Pair : Sortable<Pair> {\n    Value: int\n\n    func LessThan(other: Pair): bool {\n        return Value < other.Value\n    }\n}\n\n[hot]\nfunc SortPair<T>(items: T[]): int where T : struct, Sortable<T> {\n    if items.Length < 2 {\n        return 0\n    }\n\n    if items[1].LessThan(items[0]) {\n        tmp := items[0]\n        items[0] = items[1]\n        items[1] = tmp\n    }\n\n    return 0\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=Sortable.LessThan;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Pair.LessThan;file=Program.nl;line=8;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=SortPair;file=Program.nl;line=14;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Sortable.LessThan]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: callee resolution crosses an `import`: the allocating `MakeBox` in the imported file flags the hot caller (was SystemsNSharpTests.HotCallee_ResolvesAcrossFileImport)" {
    directory := SacFixture("hotcallee-resolvesacrossfileimport", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "lib.nl", "func MakeBox(): Box {\n    return alloc new Box()\n}\n\nclass Box {}\n")
    SacWrite(directory, "main.nl", "import \"lib\"\n\n[hot]\nfunc Hot(): int {\n    value := MakeBox()\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL001:error@5:5+5|NSYS010:error@5:21+7"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'MakeBox' allocates on a hot/alloc(none) path;file=main.nl;line=5;column=21;length=7;function=Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Hot,MakeBox]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=MakeBox;file=lib.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Hot;file=main.nl;line=4;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[MakeBox]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: with two files declaring `MakeBox`, the IMPORTED one is the one resolved, and nothing is reported unknown (was SystemsNSharpTests.HotCallee_ImportedDuplicateSourceSite_ResolvesImportedDeclaration)" {
    directory := SacFixture("hotcallee-importedduplicatesourcesite-resolvesimporteddeclar", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "libA.nl", "func MakeBox(): Box {\n    return alloc new Box()\n}\n\nclass Box {\n    Tag: int\n}\n")
    SacWrite(directory, "libB.nl", "func MakeBox(): int {\n    return 1\n}\n")
    SacWrite(directory, "main.nl", "import \"libA\"\n\n[hot]\nfunc Hot(): int {\n    value := MakeBox()\n    return value.Tag\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=3;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@5:21+7"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'MakeBox' allocates on a hot/alloc(none) path;file=main.nl;line=5;column=21;length=7;function=Hot;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[Hot,MakeBox]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function0 == "name=MakeBox;file=libA.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=MakeBox;file=libB.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=Hot;file=main.nl;line=4;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[MakeBox]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `ref struct` may hold a ref-like field and an ordinary struct may not — NSYS080 names `Holder` and not `Reader` (was SystemsNSharpTests.RefStruct_AllowsRefLikeFieldsButOrdinaryStructDoesNot)" {
    directory := SacFixture("refstruct-allowsreflikefieldsbutordinarystructdoesnot", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "import System\n\nref struct Reader {\n    buf: ReadOnlySpan<byte>\n}\n\nstruct Holder {\n    buf: ReadOnlySpan<byte>\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=0,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@8:5+3"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=ref-like field 'buf' is only allowed inside a ref struct;file=Program.nl;line=8;column=5;length=3;function=Holder;policy=systems:strict;summarySource=sourceInferred;suggestion=Declare the containing type as `ref struct`, or store a heap-safe owner such as Memory<T>/ReadOnlyMemory<T>.;callPath=[Holder]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 0
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `[hot]` function returning a ref-like value without a return lifetime reports NSYS080 as a lifetime effect (was SystemsNSharpTests.HotRefLikeReturn_RequiresReturnLifetime)" {
    directory := SacFixture("hotreflikereturn-requiresreturnlifetime", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "import System\n\n[hot]\nfunc Slice(buf: ReadOnlySpan<byte>): ReadOnlySpan<byte> {\n    return buf.Slice(0, 1)\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@4:1+5"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=[hot] function returns a ref-like value with an unknown lifetime;file=Program.nl;line=4;column=1;length=5;function=Slice;policy=[hot];summarySource=sourceInferred;suggestion=Use `returns 'a`, `returns heap(owner)`, or return an owned value instead of a ref-like view.;callPath=[Slice]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Slice;file=Program.nl;line=4;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[buf.Slice]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the stack budget is read from the project file: 65 bytes against a 64-byte budget reports NSYS080 (was SystemsNSharpTests.Stackalloc_UsesConfiguredBudget)" {
    directory := SacFixture("stackalloc-usesconfiguredbudget", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    stackBudgetBytes: 64\n")
    SacWrite(directory, "Program.nl", "func Scratch(): int {\n    scratch := stackalloc byte[65]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@2:16+10"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc reserves 65 bytes, above the configured systems stack budget of 64 bytes;file=Program.nl;line=2;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a `checked((int)65)` length is still a literal to the budget check, and the message is the over-budget one rather than the unproven one (was SystemsNSharpTests.Stackalloc_WrappedLiteralLength_UsesConfiguredBudget)" {
    directory := SacFixture("stackalloc-wrappedliterallength-usesconfiguredbudget", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    stackBudgetBytes: 64\n")
    SacWrite(directory, "Program.nl", "func Scratch(): int {\n    scratch := stackalloc byte[checked((int)65)]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@2:16+10"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc reserves 65 bytes, above the configured systems stack budget of 64 bytes;file=Program.nl;line=2;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the length survives an ALIASED cast as well: `checked((Count)65)` reports 65 bytes against 64 (was SystemsNSharpTests.Stackalloc_AliasedWrappedLiteralLength_UsesConfiguredBudget)" {
    directory := SacFixture("stackalloc-aliasedwrappedliterallength-usesconfiguredbudget", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    stackBudgetBytes: 64\n")
    SacWrite(directory, "Program.nl", "type Count = short\n\nfunc Scratch(): int {\n    scratch := stackalloc byte[checked((Count)65)]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@4:16+10"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc reserves 65 bytes, above the configured systems stack budget of 64 bytes;file=Program.nl;line=4;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=3;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a wrapped negative length reports the NEGATIVE message, and the analyzer reports NL202 beside it (was SystemsNSharpTests.Stackalloc_WrappedNegativeLength_ReportsNegative)" {
    directory := SacFixture("stackalloc-wrappednegativelength-reportsnegative", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Scratch(): int {\n    scratch := stackalloc byte[unchecked(-(1))]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@2:16+10|NL202:error@2:32+9"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc length cannot be negative;file=Program.nl;line=2;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an aliased negative length reports the same negative message (was SystemsNSharpTests.Stackalloc_AliasedWrappedNegativeLength_ReportsNegative)" {
    directory := SacFixture("stackalloc-aliasedwrappednegativelength-reportsnegative", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "type Count = short\n\nfunc Scratch(): int {\n    scratch := stackalloc byte[unchecked((Count)-1)]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@4:16+10|NL202:error@4:32+9"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc length cannot be negative;file=Program.nl;line=4;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=3;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an aliased ELEMENT type resolves to its underlying size: 65 bytes, not 1040 (was SystemsNSharpTests.Stackalloc_AliasedElementType_UsesResolvedElementSizeForBudget)" {
    directory := SacFixture("stackalloc-aliasedelementtype-usesresolvedelementsizeforbudg", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    stackBudgetBytes: 64\n")
    SacWrite(directory, "Program.nl", "type ScratchByte = byte\n\nfunc Scratch(): int {\n    scratch := stackalloc ScratchByte[65]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@4:16+10"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc reserves 65 bytes, above the configured systems stack budget of 64 bytes;file=Program.nl;line=4;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=3;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: two billion ints do not overflow the budget arithmetic into a passing negative — NSYS080 is reported (was SystemsNSharpTests.Stackalloc_OversizedCount_DoesNotOverflowBudgetCheck)" {
    directory := SacFixture("stackalloc-oversizedcount-doesnotoverflowbudgetcheck", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Scratch(): int {\n    scratch := stackalloc int[2000000000]\n    return scratch.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS080:error@2:16+10"
    assert findingCount == 1
    assert finding0 == "code=NSYS080;severity=error;effect=lifetime;message=stackalloc reserves 8000000000 bytes, above the configured systems stack budget of 4096 bytes;file=Program.nl;line=2;column=16;length=10;function=Scratch;policy=systems:strict;summarySource=sourceInferred;suggestion=Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.;callPath=[Scratch]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scratch;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: division by a non-zero FLOAT literal is not an implicit trap: the report is empty (was SystemsNSharpTests.HotDivision_ByNonZeroFloatLiteral_IsNotAnImplicitTrap)" {
    directory := SacFixture("hotdivision-bynonzerofloatliteral-isnotanimplicittrap", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Scale(n: int): double {\n    return n / 2.0\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Scale;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a flow guard introduced by an early return expires with its block, so the division AFTER the block traps (was SystemsNSharpTests.HotDivision_GuardFromEarlyReturn_ExpiresWithItsScope)" {
    directory := SacFixture("hotdivision-guardfromearlyreturn-expireswithitsscope", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Ratio(n: int, d: int, flag: bool): int {\n    if flag {\n        if d == 0 {\n            return 0\n        }\n        inside := n / d\n    }\n    outside := n / d\n    return outside\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL001:error@7:9+6|NSYS120:error@9:18+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS120;severity=error;effect=implicitTrap;message=division in [hot] requires a proven non-zero divisor or allow(trap);file=Program.nl;line=9;column=18;length=1;function=Ratio;policy=[hot];summarySource=sourceInferred;callPath=[Ratio]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Ratio;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=True,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a pool rent that is never returned reports NSYS130 — over a receiver the analyzer says does not exist (was SystemsNSharpTests.PoolRent_MustBeReturnedOnObviousLexicalPath)" {
    directory := SacFixture("poolrent-mustbereturnedonobviouslexicalpath", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Lease(): int {\n    buffer := ArrayPool.Shared.Rent(128)\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=0,warnings=1,trustedSites=0}"
    assert diagnostics == "NSYS130:warning@2:5+6|NL001:error@2:5+6|NL301:error@2:15+9"
    assert findingCount == 1
    assert finding0 == "code=NSYS130;severity=warning;effect=pool;message=pooled buffer 'buffer' rented here is not returned on an obvious lexical path;file=Program.nl;line=2;column=5;length=6;function=Lease;policy=systems:strict;summarySource=sourceInferred;suggestion=Return the buffer in a finally block, use a recognized owner/disposable pattern, or keep pooling inside a [boundary].;callPath=[Lease]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Lease;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=True,usesConcurrencyPrimitive=False,requiresWarmup=True,aotSafe=True};calls=[ArrayPool.Shared.Rent]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an undisposed resource reports NSYS090 (was SystemsNSharpTests.SystemsStrict_DisposableResourceMustBeDisposed)" {
    directory := SacFixture("systemsstrict-disposableresourcemustbedisposed", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Open(): int {\n    stream := alloc new FileStream()\n    return 1\n}\n\nclass FileStream {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS090:error@2:5+6|NL001:error@2:5+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS090;severity=error;effect=resource;message=disposable resource 'stream' created as FileStream is not disposed on an obvious lexical path;file=Program.nl;line=2;column=5;length=6;function=Open;policy=systems:strict;summarySource=sourceInferred;suggestion=Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.;callPath=[Open]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Open;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=True,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

// CHIP FIX (2026-09-01) — "the systems policy accepts unresolved members". This block is CONVERTED:
// it used to pin `findings=0` beside `NL303: Member 'Dispose' not found on type 'FileStream'`, which
// is the systems policy answering "this obligation is discharged" about a member it cannot see, and
// suppressing the unknown-external-call report on the same call for good measure. Both halves are
// gone: the resource obligation stays OPEN (NSYS090 where the resource was created) and the call
// falls through to the sentence it always deserved (NSYS050 at the call). The three blocks after it
// are the other three faces of the same rule — the resolved dispose that used to be reported as a
// leak, the resolved pool return that used to be reported as an unreturned rental, and the `allow`
// waiver, which silences the NSYS050 and NOT the NSYS090.
test "020 s41 systems analysis census (chip-converted): a `Dispose()` the analyzer says does not exist discharges NOTHING — NSYS090 stays open and the call is the unknown external call it is (was SystemsNSharpTests.SystemsStrict_DisposeCallSatisfiesObviousResourceOwnership)" {
    directory := SacFixture("systemsstrict-disposecallsatisfiesobviousresourceownership", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Open(): int {\n    stream := alloc new FileStream()\n    stream.Dispose()\n    return 1\n}\n\nclass FileStream {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=2,errors=1,warnings=1,trustedSites=0}"
    assert diagnostics == "NSYS090:error@2:5+6|NL303:error@3:12+7|NSYS050:warning@3:19+7"
    assert findingCount == 2
    assert finding0 == "code=NSYS090;severity=error;effect=resource;message=disposable resource 'stream' created as FileStream is not disposed on an obvious lexical path;file=Program.nl;line=2;column=5;length=6;function=Open;policy=systems:strict;summarySource=sourceInferred;suggestion=Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.;callPath=[Open]"
    assert finding1 == "code=NSYS050;severity=warning;effect=unknownExternalCall;message=unknown external call 'stream.Dispose' has no systems summary;file=Program.nl;line=3;column=19;length=7;function=Open;policy=systems:strict;summarySource=sourceInferred;suggestion=Add a sidecar HotSummary or put the call in a [boundary].;callPath=[Open]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    // The effect bit moved with the report: the call is now RECORDED as an unknown external call.
    assert function0 == "name=Open;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=True,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[stream.Dispose]"
    assert trustedCount == 0
}

// THE FALSE POSITIVE HALF, WHICH HAD NO UPSTREAM DIAGNOSTIC AT ALL. The same source with
// `func Dispose()` really declared reported `NSYS090 ... is not disposed` on the base CLI and nothing
// else — correct, compiling code told it leaked. The mechanism was ORDER: `WalkCall` resolves a
// project call, records it in the call graph and RETURNS, so the ledger discharge (which sat after
// that return) was reachable only on the unresolved path.
test "020 s41 systems analysis census (chip fix): a `Dispose()` that RESOLVES discharges the resource ledger, and the whole report is clean" {
    directory := SacFixture("chip-systems-unresolved-resolved-dispose", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Open(): int {\n    stream := alloc new FileStream()\n    stream.Dispose()\n    return 1\n}\n\nclass FileStream {\n    func Dispose() {\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=FileStream.Dispose;file=Program.nl;line=8;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    // The call is recorded by its RESOLVED qualified name, which is how you can tell this went down
    // the resolved branch and still discharged.
    assert function1 == "name=Open;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=True,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[FileStream.Dispose]"
    assert trustedCount == 0
}

// THE POOL LEDGER IS THE SAME RULE FROM THE OTHER SIDE, and it had the same false positive: on the
// base CLI this program reported `NSYS130: pooled buffer 'buffer' rented here is not returned`, over
// source that returns it through a project method that resolves.
test "020 s41 systems analysis census (chip fix): a `.Return(buffer)` that RESOLVES discharges the pool ledger" {
    directory := SacFixture("chip-systems-unresolved-resolved-return", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Lease(): int {\n    pool := alloc new BytePool()\n    buffer := pool.Rent(128)\n    pool.Return(buffer)\n    return buffer\n}\n\nclass BytePool {\n    func Rent(size: int): int {\n        return size\n    }\n\n    func Return(size: int): int {\n        return size\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function2 := SacRow(check.Stdout, "functions", 2)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 3
    assert function2 == "name=Lease;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=True,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[BytePool.Rent,BytePool.Return]"
    assert trustedCount == 0
}

// THE WAIVER IS PROVED NARROW. `unknownExternalCalls: allow` is the project's waiver for the NSYS050
// this fix restores, and it silences exactly that one: the resource obligation the unresolved
// `Dispose()` never discharged is still reported, and the effect bit is still set.
test "020 s41 systems analysis census (chip fix): `unknownExternalCalls: allow` waives the restored NSYS050 and NOT the NSYS090 the same call failed to discharge" {
    directory := SacFixture("chip-systems-unresolved-allow-waiver", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    unknownExternalCalls: allow\n")
    SacWrite(directory, "Program.nl", "func Open(): int {\n    stream := alloc new FileStream()\n    stream.Dispose()\n    return 1\n}\n\nclass FileStream {}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS090:error@2:5+6|NL303:error@3:12+7"
    assert findingCount == 1
    assert finding0 == "code=NSYS090;severity=error;effect=resource;message=disposable resource 'stream' created as FileStream is not disposed on an obvious lexical path;file=Program.nl;line=2;column=5;length=6;function=Open;policy=systems:strict;summarySource=sourceInferred;suggestion=Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.;callPath=[Open]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    // The WAIVER silences the report, not the fact: the effect bit is still True.
    assert function0 == "name=Open;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=True,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[stream.Dispose]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: exception control flow in a `[boundary]` is a WARNING and nothing at error severity, so the CLI exits 0 (was SystemsNSharpTests.BoundaryExceptionControlFlow_IsReportedWithoutBlocking)" {
    directory := SacFixture("boundaryexceptioncontrolflow-isreportedwithoutblocking", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[boundary]\nfunc Load(): Result<int, string> {\n    try {\n        return Ok(1)\n    } catch ex: Exception {\n        return Err(\"failed\")\n    }\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=1,findings=1,errors=0,warnings=1,trustedSites=0}"
    assert diagnostics == "NSYS120:warning@3:5+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS120;severity=warning;effect=throw;message=exception control flow is reported on systems paths;file=Program.nl;line=3;column=5;length=1;function=Load;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep try/catch inside a [boundary] and translate failures into explicit Result/error values.;callPath=[Load]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Load;file=Program.nl;line=2;column=1;isHot=False;isBoundary=True;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=True,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an unsupported concurrency primitive fails closed in `[hot]` code with NSYS140 (was SystemsNSharpTests.UnsupportedConcurrencyPrimitive_FailsClosedInHotCode)" {
    directory := SacFixture("unsupportedconcurrencyprimitive-failsclosedinhotcode", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc ReadCounter(value: int): int {\n    return Interlocked.Read(value)\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL402:error@3:24+4|NSYS140:error@3:28+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS140;severity=error;effect=concurrency;message=concurrency primitive 'Interlocked.Read' has no v1 HotSummary semantics;file=Program.nl;line=3;column=28;length=1;function=ReadCounter;policy=[hot];summarySource=sourceInferred;suggestion=Use Volatile.Read/Write, Interlocked.Exchange/CompareExchange/Increment/Decrement/Add, or Thread.MemoryBarrier.;callPath=[ReadCounter]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=ReadCounter;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=True,requiresWarmup=False,aotSafe=True};calls=[Interlocked.Read]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an `IEnumerable<int>` parameter on a `[hot]` surface is a boundary leak (was SystemsNSharpTests.HotBoundarySurface_RejectsSystemsHostileTypes)" {
    directory := SacFixture("hotboundarysurface-rejectssystemshostiletypes", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "import System.Collections.Generic\n\n[hot]\nfunc Count(values: IEnumerable<int>): int {\n    return 0\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS070:error@4:12+6|NL012:error@4:12+6"
    assert findingCount == 1
    assert finding0 == "code=NSYS070;severity=error;effect=boundaryLeak;message=[hot] parameter 'values' exposes a systems-hostile type: IEnumerable;file=Program.nl;line=4;column=12;length=6;function=Count;policy=[hot];summarySource=sourceInferred;suggestion=Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.;callPath=[Count]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Count;file=Program.nl;line=4;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a struct-constrained generic comparer is NOT a boundary leak (was SystemsNSharpTests.HotBoundarySurface_AcceptsStructConstrainedGenericComparer)" {
    directory := SacFixture("hotboundarysurface-acceptsstructconstrainedgenericcomparer", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "interface ValueComparer<T> {\n    func Less(a: T, b: T): bool\n}\n\n[hot]\nfunc Sort<T, TComparer>(values: Span<T>, comparer: TComparer): int where T : struct where TComparer : struct, ValueComparer<T> {\n    return values.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL012:error@6:42+8"
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=ValueComparer.Less;file=Program.nl;line=2;column=5;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Sort;file=Program.nl;line=6;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: an UNCONSTRAINED generic comparer IS a boundary leak, and the message names the parameter (was SystemsNSharpTests.HotBoundarySurface_RejectsUnconstrainedGenericComparer)" {
    directory := SacFixture("hotboundarysurface-rejectsunconstrainedgenericcomparer", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Sort<T, TComparer>(values: Span<T>, comparer: TComparer): int where T : struct {\n    return values.Length\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS070:error@2:42+8|NL012:error@2:42+8"
    assert findingCount == 1
    assert finding0 == "code=NSYS070;severity=error;effect=boundaryLeak;message=[hot] parameter 'comparer' exposes a systems-hostile type: managed or unsummarized type 'TComparer';file=Program.nl;line=2;column=42;length=8;function=Sort;policy=[hot];summarySource=sourceInferred;suggestion=Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.;callPath=[Sort]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Sort;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: `TryGetValue` on a registered `Dictionary` member is hot-summary covered, so `Lookup` is not reported unknown (was SystemsNSharpTests.DictionaryTryGetValue_OnRegisteredDictionaryMember_IsHotSummaryCovered)" {
    directory := SacFixture("dictionarytrygetvalue-onregistereddictionarymember-ishotsumm", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    warmup:\n      - Build\n")
    SacWrite(directory, "Program.nl", "import System.Collections.Generic\n\nstatic class Catalog {\n    static Codes: Dictionary<int, int> = Build()\n}\n\n[boundary]\nfunc Build(): Dictionary<int, int> {\n    map := alloc new Dictionary<int, int>(capacity: 4)\n    map[1] = 100\n    return map\n}\n\n[hot]\nfunc Lookup(code: int): Result<int, string> {\n    value := 0\n    if Catalog.Codes.TryGetValue(code, out value) {\n        return Ok(value)\n    }\n    return Err(\"missing\")\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[Build];summary={functions=2,hotFunctions=1,boundaryFunctions=1,findings=2,errors=0,warnings=2,trustedSites=0}"
    assert diagnostics == "NSYS070:warning@8:1+5|NSYS001:warning@9:18+1"
    assert findingCount == 2
    assert finding0 == "code=NSYS070;severity=warning;effect=boundaryLeak;message=[boundary] return type exposes a systems-hostile shape: Dictionary;file=Program.nl;line=8;column=1;length=5;function=Build;policy=systems:strict;summarySource=sourceInferred;suggestion=Return Result<T,E>, Span/ReadOnlySpan with a known lifetime, a primitive, enum, or systems-safe struct.;callPath=[Build]"
    assert finding1 == "code=NSYS001;severity=warning;effect=allocation;message=boundary allocation reported for systems handoff review;file=Program.nl;line=9;column=18;length=1;function=Build;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>.;callPath=[Build]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=Build;file=Program.nl;line=8;column=1;isHot=False;isBoundary=True;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Lookup;file=Program.nl;line=15;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Catalog.Codes.TryGetValue]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the same call on an UNREGISTERED `SortedDictionary` still fails closed (was SystemsNSharpTests.TryGetValue_OnUnregisteredReceiver_StillFailsClosedInHotCode)" {
    directory := SacFixture("trygetvalue-onunregisteredreceiver-stillfailsclosedinhotcode", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    warmup:\n      - Build\n")
    SacWrite(directory, "Program.nl", "import System.Collections.Generic\n\nstatic class Catalog {\n    static Store: SortedDictionary<int, int> = Build()\n}\n\n[boundary]\nfunc Build(): SortedDictionary<int, int> {\n    map := alloc new SortedDictionary<int, int>()\n    map[1] = 100\n    return map\n}\n\n[hot]\nfunc Lookup(code: int): Result<int, string> {\n    value := 0\n    if Catalog.Store.TryGetValue(code, out value) {\n        return Ok(value)\n    }\n    return Err(\"missing\")\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[Build];summary={functions=2,hotFunctions=1,boundaryFunctions=1,findings=2,errors=1,warnings=1,trustedSites=0}"
    assert diagnostics == "NSYS001:warning@9:18+1|NSYS050:error@17:33+11"
    assert findingCount == 2
    assert finding0 == "code=NSYS001;severity=warning;effect=allocation;message=boundary allocation reported for systems handoff review;file=Program.nl;line=9;column=18;length=1;function=Build;policy=systems:strict;summarySource=sourceInferred;suggestion=Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>.;callPath=[Build]"
    assert finding1 == "code=NSYS050;severity=error;effect=unknownExternalCall;message=unknown external call 'Catalog.Store.TryGetValue' is not callable from [hot];file=Program.nl;line=17;column=33;length=11;function=Lookup;policy=[hot];summarySource=sourceInferred;suggestion=Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary].;callPath=[Lookup]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=Build;file=Program.nl;line=8;column=1;isHot=False;isBoundary=True;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Lookup;file=Program.nl;line=15;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Catalog.Store.TryGetValue]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a function-level `allow(alloc)` on a public function requires BOTH a reason and an owner — two NSYS180 rows (was SystemsNSharpTests.FunctionLevelAllow_RequiresReasonAndPublicOwner)" {
    directory := SacFixture("functionlevelallow-requiresreasonandpublicowner", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[allow(alloc)]\npublic func Visible(): int {\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    finding1 := SacRow(check.Stdout, "findings", 1)
    findingPast := SacRow(check.Stdout, "findings", 2)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=2,errors=2,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS180:error@2:8+7|NSYS180:error@2:8+7"
    assert findingCount == 2
    assert finding0 == "code=NSYS180;severity=error;effect=effectPolicy;message=function-level [allow] requires a reason;file=Program.nl;line=2;column=8;length=7;function=Visible;policy=systems:strict;summarySource=sourceInferred;suggestion=Prefer a narrow block-level allow(...), or add reason: \"...\" to the function-level policy.;callPath=[Visible]"
    assert finding1 == "code=NSYS180;severity=error;effect=effectPolicy;message=public function-level [allow] requires an owner;file=Program.nl;line=2;column=8;length=7;function=Visible;policy=systems:strict;summarySource=sourceInferred;suggestion=Add owner: \"team-or-person\" so public systems waivers are auditable.;callPath=[Visible]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Visible;file=Program.nl;line=2;column=8;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: `Ok` and `Err` are known helpers in a hot `Result` context: nothing unknown, nothing leaked (was SystemsNSharpTests.ResultHelpers_AreKnownInHotResultContext)" {
    directory := SacFixture("resulthelpers-areknowninhotresultcontext", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "enum ParseError {\n    Bad\n}\n\n[hot]\nfunc Parse(value: int): Result<int, ParseError> {\n    if value == 0 {\n        return Err(ParseError.Bad)\n    }\n    return Ok(value)\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Parse;file=Program.nl;line=6;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a discarded `Result` value reports NSYS160 on a systems path (was SystemsNSharpTests.ResultValue_MustBeUsedOnSystemsPaths)" {
    directory := SacFixture("resultvalue-mustbeusedonsystemspaths", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "enum ParseError {\n    Bad\n}\n\nfunc Parse(value: int): Result<int, ParseError> {\n    return Ok(value)\n}\n\nfunc Run(): int {\n    Parse(1)\n    return 0\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS160:error@10:10+5"
    assert findingCount == 1
    assert finding0 == "code=NSYS160;severity=error;effect=resultMustUse;message=Result returned by 'Parse' is ignored;file=Program.nl;line=10;column=10;length=5;function=Run;policy=systems:strict;summarySource=sourceInferred;suggestion=Bind the Result, return it, or explicitly inspect IsOk/IsErr so the error path is handled.;callPath=[Run]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=Parse;file=Program.nl;line=5;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=Run;file=Program.nl;line=9;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Parse]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a sidecar hot summary is REFUSED for `[hot]` when the project does not allow sidecars (was SystemsNSharpTests.SidecarHotSummary_FailsClosedForHotUnlessPolicyAllowsIt[allowHotSidecars=false])" {
    directory := SacFixture("sidecarhotsummary-failsclosedforhotunlesspolicyallowsit-allo", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    hotSummaryFiles:\n      - external.hotsummary.json\n    allowHotSidecars: false\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Run(): int {\n    return External.Fast()\n}\n")
    SacWrite(directory, "external.hotsummary.json", "{\n  \"schemaVersion\": 1,\n  \"entries\": [\n    {\n      \"schemaVersion\": 1,\n      \"assemblyIdentity\": \"External\",\n      \"targetFramework\": \"*\",\n      \"method\": \"External.Fast\",\n      \"source\": \"sidecar\",\n      \"effects\": {\n        \"aotSafe\": true,\n        \"trimSafe\": true\n      },\n      \"bodyIdentity\": \"test-body\"\n    }\n  ]\n}")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL301:error@3:12+8|NSYS050:error@3:25+4"
    assert findingCount == 1
    assert finding0 == "code=NSYS050;severity=error;effect=unknownExternalCall;message=sidecar HotSummary for 'External.Fast' is not allowed to satisfy [hot] by project policy;file=Program.nl;line=3;column=25;length=4;function=Run;policy=[hot];summarySource=sourceInferred;suggestion=Set language.systems.allowHotSidecars only after auditing the sidecar identity and body hash, or move the call behind a [boundary].;callPath=[Run]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Run;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[External.Fast]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: the same sidecar is ACCEPTED when the project allows it, and the report falls silent (was SystemsNSharpTests.SidecarHotSummary_FailsClosedForHotUnlessPolicyAllowsIt[allowHotSidecars=true])" {
    directory := SacFixture("sidecarhotsummary-failsclosedforhotunlesspolicyallowsit-allo", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    hotSummaryFiles:\n      - external.hotsummary.json\n    allowHotSidecars: true\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Run(): int {\n    return External.Fast()\n}\n")
    SacWrite(directory, "external.hotsummary.json", "{\n  \"schemaVersion\": 1,\n  \"entries\": [\n    {\n      \"schemaVersion\": 1,\n      \"assemblyIdentity\": \"External\",\n      \"targetFramework\": \"*\",\n      \"method\": \"External.Fast\",\n      \"source\": \"sidecar\",\n      \"effects\": {\n        \"aotSafe\": true,\n        \"trimSafe\": true\n      },\n      \"bodyIdentity\": \"test-body\"\n    }\n  ]\n}")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    findingPast := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == "NL301:error@3:12+8"
    assert findingCount == 0
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Run;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[External.Fast]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a sidecar hot summary with no body identity reports NSYS150 effect drift (was SystemsNSharpTests.SidecarHotSummary_MissingIdentityReportsEffectDrift)" {
    directory := SacFixture("sidecarhotsummary-missingidentityreportseffectdrift", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n    hotSummaryFiles:\n      - external.hotsummary.json\n    allowHotSidecars: true\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc Run(): int {\n    return External.Fast()\n}\n")
    SacWrite(directory, "external.hotsummary.json", "{\n  \"schemaVersion\": 1,\n  \"entries\": [\n    {\n      \"schemaVersion\": 1,\n      \"assemblyIdentity\": \"External\",\n      \"targetFramework\": \"*\",\n      \"method\": \"External.Fast\",\n      \"source\": \"sidecar\",\n      \"effects\": {\n        \"aotSafe\": true,\n        \"trimSafe\": true\n      }\n    }\n  ]\n}")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NL301:error@3:12+8|NSYS150:error@3:25+4"
    assert findingCount == 1
    assert finding0 == "code=NSYS150;severity=error;effect=effectDrift;message=sidecar HotSummary for 'External.Fast' is missing body identity or package version, so per-fact drift cannot be audited;file=Program.nl;line=3;column=25;length=4;function=Run;policy=[hot];summarySource=sourceInferred;suggestion=Key sidecar facts by MVID/body hash, source hash, or package version plus metadata identity.;callPath=[Run]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 1
    assert function0 == "name=Run;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=True,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[External.Fast]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: a source-inferred helper that gains an allocation fails its hot caller, and the message names the helper (was SystemsNSharpTests.SourceInferredHelper_GainingAllocationFailsHotCaller)" {
    directory := SacFixture("sourceinferredhelper-gainingallocationfailshotcaller", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[hot]\nfunc ParseDigits(bytes: ReadOnlySpan<byte>): Result<int, string> {\n    if bytes.Length == 0 {\n        _ = FormatForDebug()\n        return Err(\"empty\")\n    }\n    return Ok(bytes[0])\n}\n\nfunc FormatForDebug(): int[] {\n    return alloc new int[1]\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    findingPast := SacRow(check.Stdout, "findings", 1)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=2,hotFunctions=1,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS010:error@4:27+14"
    assert findingCount == 1
    assert finding0 == "code=NSYS010;severity=error;effect=allocation;message=callee 'FormatForDebug' allocates on a hot/alloc(none) path;file=Program.nl;line=4;column=27;length=14;function=ParseDigits;policy=[hot];summarySource=sourceInferred;suggestion=Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.;callPath=[ParseDigits,FormatForDebug]"
    assert findingPast == "<no-such-row>"
    assert functionCount == 2
    assert function0 == "name=FormatForDebug;file=Program.nl;line=10;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=ParseDigits;file=Program.nl;line=2;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[FormatForDebug]"
    assert trustedCount == 0
}



// ─── THE FOUR CLI BLOCKS ─────────────────────────────────────────────────────────────────────

test "020 s41 systems analysis census: `nlc check --project … --systems-report` writes the versioned envelope for a strict systems project, and its STDERR IS STRUCTURALLY DEAD — the deleted whitespace claim is replaced by the diagnostic census the CLI actually wrote (was SystemsNSharpTests.CheckCommand_SystemsReport_EmitsVersionedJson)" {
    directory := SacFixture("cli-check-systems-report", "name: SystemsCliTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func Make(): Box {\n    return new Box()\n}\n\nclass Box {}")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    findingCount := SacCount(check.Stdout, "findings")
    finding0 := SacRow(check.Stdout, "findings", 0)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=1,hotFunctions=0,boundaryFunctions=0,findings=1,errors=1,warnings=0,trustedSites=0}"
    assert diagnostics == "NSYS001:error@2:12+1"
    assert findingCount == 1
    assert finding0 == "code=NSYS001;severity=error;effect=allocation;message=heap allocation in systems strict must be marked with alloc;file=Program.nl;line=2;column=12;length=1;function=Make;policy=systems:strict;summarySource=sourceInferred;suggestion=Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary].;callPath=[Make]"
    assert functionCount == 1
    assert function0 == "name=Make;file=Program.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=True,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert trustedCount == 0
}

test "020 s41 systems analysis census: `nlc build --project … --perf-report` builds a strict systems project for real and writes the perf envelope — every array it carries is pinned by NAME and LENGTH, and its standard error carries the two warning banners the deleted assertion never read (was SystemsNSharpTests.BuildCommand_PerfReport_EmitsSystemsEffectSitesFromRealBuild)" {
    directory := SacFixture("cli-build-perf-report", "name: SystemsCliTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "[boundary]\nfunc Make(): object {\n    return new Box()\n}\n\nclass Box {}")
    build := SacInvoke(directory, "build --project " + directory + " --perf-report")
    exitCode := build.ExitCode
    scalars := SacScalars(build.Stdout)
    shape := SacPerfShape(build.Stdout)
    stderrCensus := SacStderrCensus(build.Stderr)
    allocationSites0 := SacPerfRow(build.Stdout, "allocationSites", 0)
    boundaryLeakSites0 := SacPerfRow(build.Stdout, "boundaryLeakSites", 0)
    SacCleanup(directory)
    assert exitCode == 0
    assert scalars == "schemaVersion=1;command=build;ok=True;projectRoot=<fixture>"
    assert shape == "allocationSites=1;delegateSites=0;boxingSites=0;dispatchSites=0;closureCaptures=0;poolSites=0;resourceSites=0;boundaryLeakSites=1;hotReadinessSites=0;implicitTrapSites=0;trustedSites=0"
    assert stderrCensus == "warningBanners=2;errorBanners=0;buildSuccessful=True"
    assert allocationSites0 == "code=NSYS001;effect=allocation;file=Program.nl;line=3;column=12;message=boundary allocation reported for systems handoff review;function=Make;suggestion=Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>."
    assert boundaryLeakSites0 == "code=NSYS070;effect=boundaryLeak;file=Program.nl;line=2;column=1;message=[boundary] return type exposes a systems-hostile shape: object;function=Make;suggestion=Return Result<T,E>, Span/ReadOnlySpan with a known lifetime, a primitive, enum, or systems-safe struct."
}

test "020 s41 systems analysis census: `nlc query perf --pos 2:12` answers the systems finding sitting at that position, and its standard error IS a live channel — 138 bytes on a missing project — so the silence here is a real claim (was SystemsNSharpTests.QueryPerf_ReturnsSystemsFindingAtPosition)" {
    directory := SacFixture("cli-query-perf", "name: SystemsCliTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n")
    SacWrite(directory, "Program.nl", "func Make(): Box {\n    return new Box()\n}\n\nclass Box {}")
    query := SacInvoke(directory, "query perf --project " + directory + " --file Program.nl --pos 2:12")
    exitCode := query.ExitCode
    stderr := query.Stderr
    scalars := SacScalars(query.Stdout)
    factCount := SacRootCount(query.Stdout, "facts")
    fact0 := SacRootRow(query.Stdout, "facts", 0)
    SacCleanup(directory)
    assert exitCode == 0
    assert stderr == ""
    assert scalars == "schemaVersion=1;command=perf;ok=True;projectRoot=<fixture>;file=Program.nl;position={line=2,column=12}"
    assert factCount == 1
    assert fact0 == "source=systems;code=NSYS001;severity=error;effect=allocation;message=heap allocation in systems strict must be marked with alloc;function=Make;policy=systems:strict;suggestion=Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary]."
}

test "020 s41 systems analysis census: `nlc query trusted` answers the audit-mode project one trusted site, and the WHOLE row is pinned — reason, owner, review, unsafe flag and body statement count (was SystemsNSharpTests.QueryTrusted_ReturnsTrustedSites)" {
    directory := SacFixture("cli-query-trusted", "name: SystemsCliTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: audit\n")
    SacWrite(directory, "Program.nl", "[trusted(reason: \"reviewed wrapper\", owner: \"runtime\", review: \"SYS-1\")]\nfunc Copy(): int {\n    return 1\n}")
    query := SacInvoke(directory, "query trusted --project " + directory)
    exitCode := query.ExitCode
    stderr := query.Stderr
    scalars := SacScalars(query.Stdout)
    resultCount := SacRootCount(query.Stdout, "results")
    result0 := SacRootRow(query.Stdout, "results", 0)
    resultPast := SacRootRow(query.Stdout, "results", 1)
    SacCleanup(directory)
    assert exitCode == 0
    assert stderr == ""
    assert scalars == "schemaVersion=1;command=trusted;ok=True;projectRoot=<fixture>;summary={trustedSites=1}"
    assert resultCount == 1
    assert result0 == "function=Copy;file=Program.nl;line=2;column=1;reason=reviewed wrapper;owner=runtime;review=SYS-1;hasUnsafe=False;bodyStatementCount=1"
    assert resultPast == "<no-such-row>"
}

// ─── 021 SLICE 3: THE REPORT ROW ORDER, THROUGH THE SHIPPED CLI ───────────────────────────────
//
// `SystemsAnalyzer.cs` carried three ordering decisions and nothing else a user could observe:
// `:86` the file walk, `:103` the trusted sites, `:244` the per-function call list. They now live
// in `SystemsReportOrder`, whose own contracts pin the rules directly. These five blocks pin the
// same rules where a USER meets them — in the versioned envelope — because two of the three were
// reachable by no contract at all before this slice: every pinned envelope in the repository
// carried `trustedSites` 0 or 1, and every pinned `calls=[…]` had at most ONE element, so a
// trusted-site sort or a call-list `Distinct` could have been deleted outright and every test
// above would still have passed.

test "021 s3 systems report order: THREE TRUSTED SITES IN THREE FILES ARE REPORTED IN PATH ORDER, NOT IN THE ORDER THE FILES WERE WRITTEN" {
    directory := SacFixture("order-trusted-three-files", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "z_last.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc ZLast(): int {\n    return 1\n}\n")
    SacWrite(directory, "a_first.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc AFirst(): int {\n    return 1\n}\n")
    SacWrite(directory, "m_mid.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc MMid(): int {\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    trusted1 := SacRow(check.Stdout, "trustedSites", 1)
    trusted2 := SacRow(check.Stdout, "trustedSites", 2)
    trustedPast := SacRow(check.Stdout, "trustedSites", 3)
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=3;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=0,boundaryFunctions=0,findings=3,errors=3,warnings=0,trustedSites=3}"
    assert trustedCount == 3
    assert trusted0 == "function=AFirst;file=a_first.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trusted1 == "function=MMid;file=m_mid.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trusted2 == "function=ZLast;file=z_last.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trustedPast == "<no-such-row>"
}

test "021 s3 systems report order: THREE TRUSTED SITES IN ONE FILE FALL THROUGH TO LINE, AND A FILE THAT SORTS EARLIER STILL COMES FIRST" {
    directory := SacFixture("order-trusted-lines", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: strict\n")
    SacWrite(directory, "z_three.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc ZOne(): int {\n    return 1\n}\n\n[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc ZTwo(): int {\n    return 2\n}\n\n[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc ZThree(): int {\n    return 3\n}\n")
    SacWrite(directory, "a_one.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc AOne(): int {\n    return 1\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    trustedCount := SacCount(check.Stdout, "trustedSites")
    trusted0 := SacRow(check.Stdout, "trustedSites", 0)
    trusted1 := SacRow(check.Stdout, "trustedSites", 1)
    trusted2 := SacRow(check.Stdout, "trustedSites", 2)
    trusted3 := SacRow(check.Stdout, "trustedSites", 3)
    trustedPast := SacRow(check.Stdout, "trustedSites", 4)
    SacCleanup(directory)
    assert exitCode == 1
    assert envelope == "command=check.systemsReport;ok=False;checkedFiles=2;envelopeSchema=1;reportSchema=1;profile=systems;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=4,hotFunctions=0,boundaryFunctions=0,findings=4,errors=4,warnings=0,trustedSites=4}"
    assert trustedCount == 4
    assert trusted0 == "function=AOne;file=a_one.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trusted1 == "function=ZOne;file=z_three.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trusted2 == "function=ZTwo;file=z_three.nl;line=7;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trusted3 == "function=ZThree;file=z_three.nl;line=12;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert trustedPast == "<no-such-row>"
}

test "021 s3 systems report order: `nlc query trusted` READS THE SAME ORDER AS THE REPORT, SO THE TWO COMMANDS CANNOT DRIFT" {
    directory := SacFixture("order-query-trusted-multi", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: systems\n  systems:\n    mode: audit\n")
    SacWrite(directory, "z_last.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc ZLast(): int {\n    return 1\n}\n")
    SacWrite(directory, "a_first.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc AFirst(): int {\n    return 1\n}\n")
    SacWrite(directory, "m_mid.nl", "[trusted(reason: \"r\", owner: \"o\", review: \"SYS-1\", expires: \"2030-01-01\")]\nfunc MMid(): int {\n    return 1\n}\n")
    query := SacInvoke(directory, "query trusted --project " + directory)
    exitCode := query.ExitCode
    stderr := query.Stderr
    scalars := SacScalars(query.Stdout)
    resultCount := SacRootCount(query.Stdout, "results")
    result0 := SacRootRow(query.Stdout, "results", 0)
    result1 := SacRootRow(query.Stdout, "results", 1)
    result2 := SacRootRow(query.Stdout, "results", 2)
    resultPast := SacRootRow(query.Stdout, "results", 3)
    SacCleanup(directory)
    assert exitCode == 0
    assert stderr == ""
    assert scalars == "schemaVersion=1;command=trusted;ok=True;projectRoot=<fixture>;summary={trustedSites=3}"
    assert resultCount == 3
    assert result0 == "function=AFirst;file=a_first.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert result1 == "function=MMid;file=m_mid.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert result2 == "function=ZLast;file=z_last.nl;line=2;column=1;reason=r;owner=o;review=SYS-1;expires=2030-01-01;hasUnsafe=False;bodyStatementCount=1"
    assert resultPast == "<no-such-row>"
}

test "021 s3 systems report order: A FUNCTION'S CALL LIST IS DE-DUPLICATED AND ORDERED CASE-SENSITIVELY — SIX CALL EXPRESSIONS BECOME FOUR NAMES" {
    directory := SacFixture("order-calls-combined", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "Program.nl", "func zeta(): int {\n    return 1\n}\n\nfunc alpha(): int {\n    return 2\n}\n\nfunc Beta(): int {\n    return 3\n}\n\nfunc Alpha2(): int {\n    return 4\n}\n\n[hot]\nfunc Caller(): int {\n    return zeta() + alpha() + zeta() + Beta() + Alpha2() + alpha()\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    diagnostics := SacDiagnosticCensus(check.Stdout)
    functionCount := SacCount(check.Stdout, "functions")
    function4 := SacRow(check.Stdout, "functions", 4)
    functionPast := SacRow(check.Stdout, "functions", 5)
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=1;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=5,hotFunctions=1,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert diagnostics == ""
    assert functionCount == 5
    // `zeta` twice and `alpha` twice collapse to one each, and the four survivors read
    // `Alpha2,Beta,alpha,zeta` — uppercase before lowercase, which is ORDINAL. A case-insensitive
    // order would read `alpha,Alpha2,Beta,zeta`, and the walk order would read `zeta,alpha,Beta,Alpha2`.
    assert function4 == "name=Caller;file=Program.nl;line=18;column=1;isHot=True;isBoundary=False;allocNone=False;summarySource=explicitHot;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[Alpha2,Beta,alpha,zeta]"
    assert functionPast == "<no-such-row>"
}

test "021 s3 systems report order: THE FILE WALK IS CASE-INSENSITIVE, SO `a_two.nl` IS REPORTED BEFORE `B_one.nl`" {
    directory := SacFixture("order-walk-case-mixed", "name: SystemsTest\noutputType: library\ntargetFramework: net10.0\nlanguage:\n  profile: default\n  systems:\n    mode: strict\n")
    SacWrite(directory, "B_one.nl", "func bOne(): int {\n    return 1\n}\n")
    SacWrite(directory, "a_two.nl", "func aTwo(): int {\n    return 2\n}\n")
    SacWrite(directory, "C_three.nl", "func cThree(): int {\n    return 3\n}\n")
    check := SacCheck(directory)
    exitCode := check.ExitCode
    envelope := SacEnvelope(check.Stdout)
    functionCount := SacCount(check.Stdout, "functions")
    function0 := SacRow(check.Stdout, "functions", 0)
    function1 := SacRow(check.Stdout, "functions", 1)
    function2 := SacRow(check.Stdout, "functions", 2)
    functionPast := SacRow(check.Stdout, "functions", 3)
    SacCleanup(directory)
    assert exitCode == 0
    assert envelope == "command=check.systemsReport;ok=True;checkedFiles=3;envelopeSchema=1;reportSchema=1;profile=default;mode=strict;aotTarget=nativeaot;aot={target=nativeaot,analysis=pass,nativeImageEmitted=False,trimSafe=True};warmup=[];summary={functions=3,hotFunctions=0,boundaryFunctions=0,findings=0,errors=0,warnings=0,trustedSites=0}"
    assert functionCount == 3
    // An ORDINAL walk would read `B_one.nl,C_three.nl,a_two.nl`, because every uppercase UTF-16
    // unit sorts before every lowercase one.
    assert function0 == "name=aTwo;file=a_two.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function1 == "name=bOne;file=B_one.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert function2 == "name=cThree;file=C_three.nl;line=1;column=1;isHot=False;isBoundary=False;allocNone=False;summarySource=sourceInferred;effects={allocates=False,boxes=False,constructsDelegate=False,capturesClosure=False,usesRuntimeDispatch=False,usesReflection=False,usesDynamicCode=False,throws=False,hasImplicitTrapObligation=False,usesUnknownExternalCall=False,usesResource=False,usesPool=False,usesConcurrencyPrimitive=False,requiresWarmup=False,aotSafe=True};calls=[]"
    assert functionPast == "<no-such-row>"
}
