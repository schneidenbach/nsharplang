namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.Loader
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
// that context where the test output directory is. `tests/native/test-assembly-load-contexts` pins
// that fact and says why it is safe: the gate runs one `nlc test` PROCESS per project, so exactly
// one emitted assembly is pinned per process and it dies with the process.

// The sink xunit hands every execution message. It accumulates the rows in arrival order and
// releases `WaitForCompletion` when the assembly finishes.
class XunitResultSink: IMessageSink, IDisposable {
    finishedValue: ManualResetEventSlim
    verboseValue: bool
    outcomeRanksValue: int[]
    outcomeCountValue: int
    resultsValue: List<NativeTestResult>

    constructor(verbose: bool, expectedResultCount: int) {
        finishedValue = new ManualResetEventSlim()
        verboseValue = verbose
        outcomeRanksValue = new int[](Math.Max(expectedResultCount, 4))
        outcomeCountValue = 0
        resultsValue = new List<NativeTestResult>()
    }

    func OnMessage(message: IMessageSinkMessage): bool {
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
            resultsValue.Add(new NativeTestResult(
                TestCommandKernels.GetXunitRunnerErrorName(),
                TestCommandKernels.GetXunitRunnerErrorDisplayName(),
                TestCommandKernels.GetFailedOutcome(),
                TestCommandKernels.GetZeroTestDuration(),
                XunitTestRunner.FormatXunitFailure(error),
                TestCommandKernels.GetXunitRunnerErrorDisplayName()
            ))
            AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetFailedOutcome()))
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
        return new NativeTestRun(resultsValue, outcomeRanksValue, outcomeCountValue)
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

        resultsValue.Add(result)
        AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank(outcome))

        if !verboseValue {
            return
        }

        elapsedText := TestCommandKernels.FormatTestElapsedMilliseconds((double)(message.ExecutionTime * 1000))
        Console.WriteLine(TestCommandKernels.GetVerboseMessage(outcome, displayName, elapsedText, errorMessage))
    }

    func AddOutcomeRank(rank: int) {
        if outcomeCountValue == outcomeRanksValue.Length {
            Array.Resize(ref outcomeRanksValue, Math.Max(outcomeRanksValue.Length * 2, 4))
        }

        outcomeRanksValue[outcomeCountValue] = rank
        outcomeCountValue = outcomeCountValue + 1
    }
}

static class XunitTestRunner {
    static func Run(assemblyPath: string, filter: string?, verbose: bool, timeoutMs: int?): NativeTestRun {
        assemblyDirectory := TestCommandKernels.GetAssemblyDirectory(assemblyPath)
        if assemblyDirectory == null {
            throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.")
        }

        probeDirectory := assemblyDirectory

        // `on`/`off` is the N# spelling of `+=`/`-=`, and the handle remembers the exact delegate,
        // so the `finally` below removes the same instance that was added.
        resolvingSubscription := on AssemblyLoadContext.Default.Resolving (context, assemblyName) => XunitTestRunner.ResolveFromTestOutput(context, assemblyName, probeDirectory)
        appDomainSubscription := on AppDomain.CurrentDomain.AssemblyResolve (sender, eventArgs) => XunitTestRunner.ResolveFromTestOutput(AssemblyLoadContext.Default, new AssemblyName(eventArgs.Name), probeDirectory)
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

            using executionSink := new XunitResultSink(verbose, testCases.Count)
            executionOptions := TestFrameworkOptions.ForExecution(assemblyConfiguration)
            controller.RunTests(testCases, executionSink, executionOptions)

            if !executionSink.WaitForCompletion(timeoutMs) {
                throw new TimeoutException(TestCommandKernels.GetRunTimedOutMessage())
            }

            return executionSink.ToRun()
        } finally {
            off resolvingSubscription
            off appDomainSubscription
        }
    }

    // An assembly already in the context wins, so a dependency the host has loaded is shared rather
    // than duplicated; otherwise the test output directory is probed by simple name.
    static func ResolveFromTestOutput(context: AssemblyLoadContext, assemblyName: AssemblyName, assemblyDirectory: string): Assembly? {
        for assembly in context.Assemblies {
            if AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName) {
                return assembly
            }
        }

        candidatePath := TestCommandKernels.GetAssemblyCandidatePath(assemblyDirectory, assemblyName.Name)
        if File.Exists(candidatePath) {
            return context.LoadFromAssemblyPath(candidatePath)
        }

        return null
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
