namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Runtime.Loader
import System.Text
import System.Threading
import Xunit
import Xunit.Abstractions

// THE DEFAULT `nlc test` RUNNER: xunit's front controller, driven from N#.
//
// Every decision this file makes about WHAT a result is called, how long it took, which outcome
// rank it carries and whether a filter admits it belongs to `TestCommandKernels` in Compiler.Core.
// What lives here is HOSTING only — the two assembly-resolution hooks, xunit's runner-utility
// object model, and the message sink that turns xunit's messages into `NativeTestResult` rows.
//
// This runner is NOT isolated, and that is deliberate and recorded: it hands the assembly path to
// `XunitFrontController`, which loads it into the DEFAULT context, and the two hooks below teach
// that context where the test output directory and the project's shared frameworks are.
// `tests/native/test-assembly-load-contexts` pins that fact and says why it is safe: the gate runs
// one `nlc test` PROCESS per project, so exactly one emitted assembly is pinned per process and it
// dies with the process.
class XunitTestOutputChunk {
    IsError: bool
    Text: string

    constructor(isError: bool, text: string) {
        IsError = isError
        Text = text
    }
}

// Console is process-wide, so let xUnit execute cases concurrently while associating every write
// with the currently executing test through AsyncLocal. Chunks are replayed after completion in
// the same stable order as the result rows.
class XunitTestOutputCapture {
    currentTestKey: AsyncLocal<string?>
    currentTestKeyValue: PropertyInfo
    chunksByTest: Dictionary<string, List<XunitTestOutputChunk>>
    unscopedChunks: List<XunitTestOutputChunk>
    gate: object
    stdoutTarget: TextWriter
    stderrTarget: TextWriter
    streamImmediately: bool

    constructor(stdout: TextWriter, stderr: TextWriter) {
        currentTestKey = new AsyncLocal<string?>()
        valueProperty := typeof(AsyncLocal<string>).GetProperty("Value")
        if valueProperty == null {
            throw new InvalidOperationException("AsyncLocal.Value property was not found.")
        }

        currentTestKeyValue = valueProperty
        chunksByTest = new Dictionary<string, List<XunitTestOutputChunk>>(StringComparer.Ordinal)
        unscopedChunks = new List<XunitTestOutputChunk>()
        gate = new object()
        stdoutTarget = stdout
        stderrTarget = stderr
        streamImmediately = false
    }

    func StreamImmediately() {
        streamImmediately = true
    }

    func BeginTest(test: ITest) {
        key := GetTestKey(test)
        lock gate {
            if !chunksByTest.ContainsKey(key) {
                chunksByTest[key] = new List<XunitTestOutputChunk>()
            }
        }

        currentTestKeyValue.SetValue(currentTestKey, key)
    }

    func EndTest() {
        currentTestKeyValue.SetValue(currentTestKey, null)
    }

    func Capture(isError: bool, text: string) {
        if text.Length == 0 {
            return
        }

        if streamImmediately {
            if isError {
                stderrTarget.Write(text)
            } else {
                stdoutTarget.Write(text)
            }

            return
        }

        key := currentTestKeyValue.GetValue(currentTestKey) as string
        chunk := new XunitTestOutputChunk(isError, text)
        lock gate {
            if key == null {
                unscopedChunks.Add(chunk)
                return
            }

            testKey := key ?? ""
            chunks: List<XunitTestOutputChunk>? = null
            if !chunksByTest.TryGetValue(testKey, out chunks) {
                chunks = new List<XunitTestOutputChunk>()
                chunksByTest[testKey] = chunks ?? new List<XunitTestOutputChunk>()
            }

            (chunks ?? new List<XunitTestOutputChunk>()).Add(chunk)
        }
    }

    func ReplayUnscoped() {
        Replay(unscopedChunks)
    }

    func ReplayTest(testKey: string) {
        chunks: List<XunitTestOutputChunk>? = null
        lock gate {
            chunksByTest.TryGetValue(testKey, out chunks)
        }

        if chunks != null {
            Replay(chunks ?? new List<XunitTestOutputChunk>())
        }
    }

    func Replay(chunks: IReadOnlyList<XunitTestOutputChunk>) {
        for chunk in chunks {
            if chunk.IsError {
                Console.Error.Write(chunk.Text)
            } else {
                Console.Out.Write(chunk.Text)
            }
        }
    }

    static func GetTestKey(test: ITest): string {
        return test.TestCase.UniqueID + "\n" + test.DisplayName
    }
}

// StringWriter supplies the encoding property which the pinned seed compiler cannot override on
// an external abstract base; all write paths are redirected into the per-test capture above.
class XunitTestOutputWriter: StringWriter {
    capture: XunitTestOutputCapture
    isError: bool

    constructor(capture: XunitTestOutputCapture, isError: bool) {
        this.capture = capture
        this.isError = isError
    }

    override func Write(value: char) {
        capture.Capture(isError, value.ToString())
    }

    override func Write(buffer: char[], index: int, count: int) {
        builder := new StringBuilder()
        builder.Append(buffer, index, count)
        capture.Capture(isError, builder.ToString())
    }

    override func Write(value: string?) {
        if value != null {
            capture.Capture(isError, value ?? "")
        }
    }

    override func WriteLine(value: string?) {
        capture.Capture(isError, (value ?? "") + Environment.NewLine)
    }

    override func WriteLine() {
        capture.Capture(isError, Environment.NewLine)
    }

    override func Flush() {
    }
}

class XunitTestExecutionRecord {
    Result: NativeTestResult
    OutcomeRank: int
    OutputKey: string?
    VerboseMessage: string?

    constructor(result: NativeTestResult, outcomeRank: int, outputKey: string?, verboseMessage: string?) {
        Result = result
        OutcomeRank = outcomeRank
        OutputKey = outputKey
        VerboseMessage = verboseMessage
    }
}

// The sink xunit hands every execution message. It buffers records and releases
// `WaitForCompletion` when the assembly finishes.
class XunitResultSink: IMessageSink, IDisposable {
    finishedValue: ManualResetEventSlim
    verboseValue: bool
    recordsValue: List<XunitTestExecutionRecord>
    outputCaptureValue: XunitTestOutputCapture
    recordsGate: object

    constructor(verbose: bool, expectedResultCount: int, outputCapture: XunitTestOutputCapture) {
        finishedValue = new ManualResetEventSlim()
        verboseValue = verbose
        recordsValue = new List<XunitTestExecutionRecord>(Math.Max(expectedResultCount, 4))
        outputCaptureValue = outputCapture
        recordsGate = new object()
    }

    func OnMessage(message: IMessageSinkMessage): bool {
        starting := message as ITestStarting
        if starting != null {
            outputCaptureValue.BeginTest(starting.Test)
            return true
        }

        passed := message as ITestPassed
        if passed != null {
            AddResult(passed, TestCommandKernels.GetPassedOutcome(), null)
            return true
        }

        skipped := message as ITestSkipped
        if skipped != null {
            AddResult(skipped, TestCommandKernels.GetSkippedOutcome(), skipped.Reason)
            return true
        }

        failed := message as ITestFailed
        if failed != null {
            AddResult(failed, TestCommandKernels.GetFailedOutcome(), XunitTestRunner.FormatXunitFailure(failed))
            return true
        }

        error := message as IErrorMessage
        if error != null {
            result := new NativeTestResult(
                TestCommandKernels.GetXunitRunnerErrorName(),
                TestCommandKernels.GetXunitRunnerErrorDisplayName(),
                TestCommandKernels.GetFailedOutcome(),
                TestCommandKernels.GetZeroTestDuration(),
                XunitTestRunner.FormatXunitFailure(error),
                TestCommandKernels.GetXunitRunnerErrorDisplayName()
            )
            lock recordsGate {
                recordsValue.Add(new XunitTestExecutionRecord(
                    result,
                    TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetFailedOutcome()),
                    null,
                    null
                ))
            }
            return true
        }

        finished := message as ITestFinished
        if finished != null {
            outputCaptureValue.EndTest()
            return true
        }

        assemblyFinished := message as ITestAssemblyFinished
        if assemblyFinished != null {
            finishedValue.Set()
            return true
        }

        return true
    }

    func WaitForCompletion(timeoutMs: int?): bool {
        if timeoutMs != null {
            timeoutValue: int = timeoutMs
            return finishedValue.Wait(timeoutValue)
        }

        finishedValue.Wait()
        return true
    }

    func Dispose() {
        finishedValue.Dispose()
    }

    func ToRun(): NativeTestRun {
        SortRecords()
        results := new List<NativeTestResult>(recordsValue.Count)
        outcomeRanks := new int[](recordsValue.Count)
        index := 0
        for executionRecord in recordsValue {
            results.Add(executionRecord.Result)
            outcomeRanks[index] = executionRecord.OutcomeRank
            index = index + 1
        }

        return new NativeTestRun(results, outcomeRanks, recordsValue.Count)
    }

    func EmitOutput() {
        SortRecords()
        outputCaptureValue.ReplayUnscoped()
        for executionRecord in recordsValue {
            if executionRecord.OutputKey != null {
                outputCaptureValue.ReplayTest(executionRecord.OutputKey ?? "")
            }

            if executionRecord.VerboseMessage != null {
                Console.WriteLine(executionRecord.VerboseMessage ?? "")
            }
        }
    }

    func SortRecords() {
        i := 1
        while i < recordsValue.Count {
            current := recordsValue[i]
            j := i - 1
            while j >= 0 && CompareRecords(recordsValue[j], current) > 0 {
                recordsValue[j + 1] = recordsValue[j]
                j = j - 1
            }

            recordsValue[j + 1] = current
            i = i + 1
        }
    }

    static func CompareRecords(left: XunitTestExecutionRecord, right: XunitTestExecutionRecord): int {
        nameOrder := StringComparer.Ordinal.Compare(left.Result.Name, right.Result.Name)
        if nameOrder != 0 {
            return nameOrder
        }

        displayOrder := StringComparer.Ordinal.Compare(left.Result.DisplayName, right.Result.DisplayName)
        if displayOrder != 0 {
            return displayOrder
        }

        return StringComparer.Ordinal.Compare(left.OutputKey ?? "", right.OutputKey ?? "")
    }

    func AddResult(message: ITestResultMessage, outcome: string, errorMessage: string?) {
        testCase := message.Test.TestCase
        displayName := TestCommandKernels.GetPreferredDisplayName(XunitTestRunner.GetXunitDescription(testCase), message.Test.DisplayName)
        fullyQualifiedName := XunitTestRunner.GetXunitFullyQualifiedName(testCase)
        duration := TestCommandKernels.FormatTestDurationSeconds((double)message.ExecutionTime)
        nsharpDescription := TestCommandKernels.GetPreferredDisplayName(XunitTestRunner.GetXunitDescription(testCase), displayName)
        result := new NativeTestResult(
            fullyQualifiedName,
            displayName,
            outcome,
            duration,
            errorMessage,
            nsharpDescription
        )

        verboseMessage: string? = null
        if verboseValue {
            elapsedText := TestCommandKernels.FormatTestElapsedMilliseconds((double)(message.ExecutionTime * 1000))
            verboseMessage = TestCommandKernels.GetVerboseMessage(outcome, displayName, elapsedText, errorMessage)
        }

        lock recordsGate {
            recordsValue.Add(new XunitTestExecutionRecord(
                result,
                TestCommandKernels.GetNativeTestOutcomeRank(outcome),
                XunitTestOutputCapture.GetTestKey(message.Test),
                verboseMessage
            ))
        }
    }
}

static class XunitTestRunner {
    static func Run(assemblyPath: string, frameworkDirectories: IReadOnlyList<string>, filter: string?, verbose: bool, timeoutMs: int?): NativeTestRun {
        assemblyDirectory := TestCommandKernels.GetAssemblyDirectory(assemblyPath)
        if assemblyDirectory == null {
            throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.")
        }

        probeDirectory := assemblyDirectory
        stdout := Console.Out
        stderr := Console.Error
        outputCapture := new XunitTestOutputCapture(stdout, stderr)
        Console.SetOut(new XunitTestOutputWriter(outputCapture, false))
        Console.SetError(new XunitTestOutputWriter(outputCapture, true))
        executionSink: XunitResultSink? = null

        // `on`/`off` is the N# spelling of `+=`/`-=`, and the handle remembers the exact delegate,
        // so the `finally` below removes the same instance that was added.
        resolvingSubscription := on AssemblyLoadContext.Default.Resolving (context, assemblyName) => XunitTestRunner.ResolveTestDependency(context, assemblyName, probeDirectory, frameworkDirectories)
        appDomainSubscription := on AppDomain.CurrentDomain.AssemblyResolve (sender, eventArgs) => XunitTestRunner.ResolveTestDependency(AssemblyLoadContext.Default, new AssemblyName(eventArgs.Name), probeDirectory, frameworkDirectories)
        nativeSubscription := on AssemblyLoadContext.Default.ResolvingUnmanagedDll (requestingAssembly, libraryName) => XunitTestRunner.ResolveTestNativeLibrary(libraryName, probeDirectory)
        try {
            using diagnosticSink := new NullMessageSink()
            using controller := new XunitFrontController(
                AppDomainSupport.Denied,
                assemblyPath,
                null,
                false,
                null,
                null,
                diagnosticSink
            )

            using discoverySink := new TestDiscoverySink(() => false)
            assemblyConfiguration := new TestAssemblyConfiguration()
            assemblyConfiguration.DiagnosticMessages = verbose
            assemblyConfiguration.InternalDiagnosticMessages = verbose
            assemblyConfiguration.PreEnumerateTheories = true
            assemblyConfiguration.ShadowCopy = false

            discoveryOptions := TestFrameworkOptions.ForDiscovery(assemblyConfiguration)
            controller.Find(false, discoverySink, discoveryOptions)
            discoverySink.Finished.WaitOne()

            testCases := new List<ITestCase>()
            for testCase in discoverySink.TestCases {
                if string.IsNullOrWhiteSpace(filter) {
                    testCases.Add(testCase)
                    continue
                }

                displayName := TestCommandKernels.GetPreferredDisplayName(GetXunitDescription(testCase), testCase.DisplayName)
                if TestCommandKernels.MatchesFilter(
                    filter,
                    displayName,
                    testCase.DisplayName,
                    GetXunitFullyQualifiedName(testCase)
                ) {
                    testCases.Add(testCase)
                }
            }

            SortTestCases(testCases)
            if testCases.Count == 1 {
                // A one-test run has no cross-test ordering ambiguity. Keep its output live, and
                // preserve writes if user test code exits the process before the runner returns.
                outputCapture.StreamImmediately()
            }

            sink := new XunitResultSink(verbose, testCases.Count, outputCapture)
            executionSink = sink
            executionOptions := TestFrameworkOptions.ForExecution(assemblyConfiguration)
            // Keep test-start/finish messages on the execution context. The capture writer uses an
            // AsyncLocal key set by those messages to route process-wide Console writes per test.
            executionOptions.SetSynchronousMessageReporting(true)
            controller.RunTests(testCases, sink, executionOptions)

            if !sink.WaitForCompletion(timeoutMs) {
                throw new TimeoutException(TestCommandKernels.GetRunTimedOutMessage())
            }

            return sink.ToRun()
        } finally {
            Console.SetOut(stdout)
            Console.SetError(stderr)
            if executionSink != null {
                sink := executionSink
                sink.EmitOutput()
                sink.Dispose()
            } else {
                outputCapture.ReplayUnscoped()
            }

            off resolvingSubscription
            off appDomainSubscription
            off nativeSubscription
        }
    }

    // Test output is process-wide, so execution and result order use this ordinal key in every
    // runner invocation, whether it is in-process or in a daemon worker.
    static func SortTestCases(testCases: List<ITestCase>) {
        i := 1
        while i < testCases.Count {
            current := testCases[i]
            j := i - 1
            while j >= 0 && CompareTestCases(testCases[j], current) > 0 {
                testCases[j + 1] = testCases[j]
                j = j - 1
            }

            testCases[j + 1] = current
            i = i + 1
        }
    }

    static func CompareTestCases(left: ITestCase, right: ITestCase): int {
        nameOrder := StringComparer.Ordinal.Compare(GetXunitFullyQualifiedName(left), GetXunitFullyQualifiedName(right))
        if nameOrder != 0 {
            return nameOrder
        }

        return StringComparer.Ordinal.Compare(left.DisplayName, right.DisplayName)
    }

    // An assembly already in the context wins, so a dependency the host has loaded is shared rather
    // than duplicated; otherwise the test output directory and then the project's shared-framework
    // directories are probed by simple name (`TestCommandKernels.FindAssemblyCandidatePath`).
    static func ResolveTestDependency(context: AssemblyLoadContext, assemblyName: AssemblyName, assemblyDirectory: string, frameworkDirectories: IReadOnlyList<string>): Assembly? {
        for assembly in context.Assemblies {
            if AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName) {
                return assembly
            }
        }

        candidatePath := TestCommandKernels.FindAssemblyCandidatePath(assemblyDirectory, frameworkDirectories, assemblyName.Name)
        if candidatePath != null {
            return context.LoadFromAssemblyPath(candidatePath)
        }

        return null
    }

    // A native library a test's package ships (`runtimes/<rid>/native/*`) is found in the test output
    // directory by the host's RID fallback order; the CLI's own host knows only its own directory.
    static func ResolveTestNativeLibrary(libraryName: string, assemblyDirectory: string): IntPtr {
        libraryPath := TestCommandKernels.FindNativeLibraryPath(assemblyDirectory, libraryName, RuntimeInformation.RuntimeIdentifier)
        if libraryPath == null {
            return IntPtr.Zero
        }

        return NativeLibrary.Load(libraryPath)
    }

    // The `[Trait("NSharpDescription", "…")]` row an N# `test "…"` declaration emits is what supplies
    // the sentence a reader wrote; a plain xunit fact has none.
    static func GetXunitDescription(testCase: ITestCase): string? {
        descriptions: List<string>? = null
        if testCase.Traits.TryGetValue(TestCommandKernels.GetNSharpDescriptionTraitKey(), out descriptions) {
            resolved := descriptions
            if resolved.Count == 0 {
                return null
            }

            return resolved[0]
        }

        return null
    }

    static func GetXunitFullyQualifiedName(testCase: ITestCase): string {
        return TestCommandKernels.GetTestFullName(testCase.TestMethod.TestClass.Class.Name, testCase.TestMethod.Method.Name)
    }

    static func FormatXunitFailure(failure: IFailureInformation): string {
        return TestCommandKernels.JoinFailureMessages(failure.Messages)
    }
}
