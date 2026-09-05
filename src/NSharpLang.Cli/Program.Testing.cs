using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using Xunit;
using Xunit.Abstractions;

namespace NSharpLang.Cli;

partial class Program
{
    private sealed class NativeTestLoadContext(string assemblyDirectory)
        : AssemblyLoadContext(nameof(NativeTestLoadContext), isCollectible: true)
    {
        protected override Assembly? Load(AssemblyName assemblyName)
        {
            var candidatePath = TestCommandKernels.GetAssemblyCandidatePath(assemblyDirectory, assemblyName.Name);
            if (File.Exists(candidatePath))
            {
                return LoadFromAssemblyPath(candidatePath);
            }

            return AssemblyLoadContext.Default.Assemblies.FirstOrDefault(assembly =>
                AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName));
        }
    }

    private static int TestWithIlBackend(
        string projectRoot,
        ProjectConfig? projectConfig,
        string? filter,
        bool verbose,
        int outputMode,
        int? timeoutMs,
        bool noCache,
        bool collectCoverage,
        bool coverageReport,
        Stopwatch stopwatch)
    {
        var projectYmlPath = TestCommandKernels.GetProjectYmlPath(projectRoot);
        if (!File.Exists(projectYmlPath))
        {
            var message = TestCommandKernels.GetMissingProjectFileMessage();
            if (TestCommandKernels.IsJsonOutputMode(outputMode))
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, message);
                return TestCommandKernels.GetExitCode(false);
            }

            return Error(message);
        }

        if (collectCoverage || coverageReport)
        {
            var message = TestCommandKernels.GetCoverageUnsupportedMessage();
            if (TestCommandKernels.IsJsonOutputMode(outputMode))
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, message);
                return TestCommandKernels.GetExitCode(false);
            }

            return Error(message);
        }

        projectConfig ??= ProjectFileParser.Parse(projectYmlPath);
        var testOutputDir = TestCommandKernels.GetTestOutputDirectory(projectRoot, projectConfig.TargetFramework);
        if (noCache && Directory.Exists(testOutputDir))
        {
            Directory.Delete(testOutputDir, recursive: true);
        }

        try
        {
            var outputPath = BuildProjectWithIlBackendForCommand(
                projectRoot,
                projectConfig,
                TestCommandKernels.GetTestBuildConfiguration(),
                testOutputDir,
                includeTests: true,
                verbose: verbose);

            if (outputPath == null)
            {
                var message = TestCommandKernels.GetBuildFailedMessage();
                if (TestCommandKernels.IsJsonOutputMode(outputMode))
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, message);
                    return TestCommandKernels.GetExitCode(false);
                }

                return Error(message);
            }

            var testRun = TestCommandKernels.ShouldRunNUnit(projectConfig.TestFramework)
                ? RunReflectionTests(outputPath, filter, verbose, timeoutMs)
                : RunXunitTests(outputPath, filter, verbose, timeoutMs);
            var testResults = testRun.Results;
            var summary = TestCommandKernels.SummarizeNativeTestRun(testRun);

            if (TestCommandKernels.IsJsonOutputMode(outputMode))
            {
                OutputNativeTestJson(projectRoot, summary.Ok, testResults, summary);
            }
            else
            {
                Console.WriteLine(TestCommandKernels.GetSummaryMessage(
                    summary.Passed,
                    summary.Failed,
                    summary.Skipped,
                    summary.Total));
                Console.WriteLine(TestCommandKernels.GetCompletedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)));
            }

            return TestCommandKernels.GetExitCode(summary.Ok);
        }
        catch (Exception ex)
        {
            if (TestCommandKernels.IsTextOutputMode(outputMode))
            {
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)));
            }

            if (TestCommandKernels.IsJsonOutputMode(outputMode))
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), NativeTestSummary.EmptyFailure, ex.Message);
                return TestCommandKernels.GetExitCode(false);
            }

            return Error(TestCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    private static NativeTestRun RunXunitTests(
        string assemblyPath,
        string? filter,
        bool verbose,
        int? timeoutMs)
    {
        var assemblyDirectory = TestCommandKernels.GetAssemblyDirectory(assemblyPath)
            ?? throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.");

        Assembly? resolveFromTestOutput(AssemblyLoadContext context, AssemblyName assemblyName)
        {
            var alreadyLoaded = context.Assemblies.FirstOrDefault(assembly =>
                AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName));
            if (alreadyLoaded != null)
            {
                return alreadyLoaded;
            }

            var candidatePath = TestCommandKernels.GetAssemblyCandidatePath(assemblyDirectory, assemblyName.Name);
            return File.Exists(candidatePath)
                ? context.LoadFromAssemblyPath(candidatePath)
                : null;
        }

        Assembly? resolveFromAppDomain(object? _, ResolveEventArgs args)
        {
            var assemblyName = new AssemblyName(args.Name);
            return resolveFromTestOutput(AssemblyLoadContext.Default, assemblyName);
        }

        AssemblyLoadContext.Default.Resolving += resolveFromTestOutput;
        AppDomain.CurrentDomain.AssemblyResolve += resolveFromAppDomain;
        try
        {
            using var diagnosticSink = new NullMessageSink();
            using var controller = new XunitFrontController(
                AppDomainSupport.Denied,
                assemblyPath,
                configFileName: null,
                shadowCopy: false,
                shadowCopyFolder: null,
                sourceInformationProvider: null,
                diagnosticMessageSink: diagnosticSink);

            using var discoverySink = new TestDiscoverySink(() => false);
            var assemblyConfiguration = new TestAssemblyConfiguration
            {
                DiagnosticMessages = verbose,
                InternalDiagnosticMessages = verbose,
                PreEnumerateTheories = true,
                ShadowCopy = false
            };
            var discoveryOptions = TestFrameworkOptions.ForDiscovery(assemblyConfiguration);
            controller.Find(includeSourceInformation: false, discoverySink, discoveryOptions);
            discoverySink.Finished.WaitOne();

            var testCases = discoverySink.TestCases
                .Where(testCase =>
                {
                    if (string.IsNullOrWhiteSpace(filter))
                    {
                        return true;
                    }

                    var displayName = TestCommandKernels.GetPreferredDisplayName(GetXunitDescription(testCase), testCase.DisplayName);
                    return TestCommandKernels.MatchesFilter(
                        filter,
                        displayName,
                        testCase.DisplayName,
                        GetXunitFullyQualifiedName(testCase));
                })
                .ToArray();

            using var executionSink = new XunitResultSink(verbose, testCases.Length);
            var executionOptions = TestFrameworkOptions.ForExecution(assemblyConfiguration);
            controller.RunTests(testCases, executionSink, executionOptions);

            if (!executionSink.WaitForCompletion(timeoutMs))
            {
                throw new TimeoutException(TestCommandKernels.GetRunTimedOutMessage());
            }

            return executionSink.ToRun();
        }
        finally
        {
            AssemblyLoadContext.Default.Resolving -= resolveFromTestOutput;
            AppDomain.CurrentDomain.AssemblyResolve -= resolveFromAppDomain;
        }
    }

    private sealed class XunitResultSink(bool verbose, int expectedResultCount) : IMessageSink, IDisposable
    {
        private readonly ManualResetEventSlim _finished = new();
        private int[] _outcomeRanks = new int[Math.Max(expectedResultCount, 4)];
        private int _outcomeCount;
        private readonly List<NativeTestResult> _results = new();

        public bool OnMessage(IMessageSinkMessage message)
        {
            switch (message)
            {
                case ITestPassed passed:
                    AddResult(passed, TestCommandKernels.GetPassedOutcome(), null);
                    break;
                case ITestSkipped skipped:
                    AddResult(skipped, TestCommandKernels.GetSkippedOutcome(), skipped.Reason);
                    break;
                case ITestFailed failed:
                    AddResult(failed, TestCommandKernels.GetFailedOutcome(), FormatXunitFailure(failed));
                    break;
                case IErrorMessage error:
                    _results.Add(new NativeTestResult(
                        TestCommandKernels.GetXunitRunnerErrorName(),
                        TestCommandKernels.GetXunitRunnerErrorDisplayName(),
                        TestCommandKernels.GetFailedOutcome(),
                        TestCommandKernels.GetZeroTestDuration(),
                        FormatXunitFailure(error),
                        TestCommandKernels.GetXunitRunnerErrorDisplayName()));
                    AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank(TestCommandKernels.GetFailedOutcome()));
                    break;
                case ITestAssemblyFinished:
                    _finished.Set();
                    break;
            }

            return true;
        }

        public bool WaitForCompletion(int? timeoutMs)
        {
            if (timeoutMs.HasValue)
            {
                return _finished.Wait(timeoutMs.Value);
            }

            _finished.Wait();
            return true;
        }

        public void Dispose()
        {
            _finished.Dispose();
        }

        public NativeTestRun ToRun() => new(_results, _outcomeRanks, _outcomeCount);

        private void AddResult(ITestResultMessage message, string outcome, string? errorMessage)
        {
            var testCase = message.Test.TestCase;
            var displayName = TestCommandKernels.GetPreferredDisplayName(GetXunitDescription(testCase), message.Test.DisplayName);
            var result = new NativeTestResult(
                GetXunitFullyQualifiedName(testCase),
                displayName,
                outcome,
                TestCommandKernels.FormatTestDurationSeconds((double)message.ExecutionTime),
                errorMessage,
                TestCommandKernels.GetPreferredDisplayName(GetXunitDescription(testCase), displayName));

            _results.Add(result);
            AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank(outcome));

            if (!verbose)
            {
                return;
            }

            Console.WriteLine(TestCommandKernels.GetVerboseMessage(
                outcome,
                displayName,
                TestCommandKernels.FormatTestElapsedMilliseconds((double)(message.ExecutionTime * 1000)),
                errorMessage));
        }

        private void AddOutcomeRank(int rank)
        {
            if (_outcomeCount == _outcomeRanks.Length)
            {
                Array.Resize(ref _outcomeRanks, Math.Max(_outcomeRanks.Length * 2, 4));
            }

            _outcomeRanks[_outcomeCount] = rank;
            _outcomeCount++;
        }
    }

    private static string? GetXunitDescription(ITestCase testCase)
        => testCase.Traits.TryGetValue(TestCommandKernels.GetNSharpDescriptionTraitKey(), out var descriptions)
            ? descriptions.FirstOrDefault()
            : null;

    private static string GetXunitFullyQualifiedName(ITestCase testCase)
        => TestCommandKernels.GetTestFullName(testCase.TestMethod.TestClass.Class.Name, testCase.TestMethod.Method.Name);

    private static string FormatXunitFailure(IFailureInformation failure)
        => TestCommandKernels.JoinFailureMessages(failure.Messages);

    private static NativeTestRun RunReflectionTests(
        string assemblyPath,
        string? filter,
        bool verbose,
        int? timeoutMs)
    {
        var assemblyDirectory = TestCommandKernels.GetAssemblyDirectory(assemblyPath)
            ?? throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.");
        var loadContext = new NativeTestLoadContext(assemblyDirectory);

        try
        {
            var assembly = loadContext.LoadFromAssemblyPath(assemblyPath);
            var testCases = DiscoverNativeTests(assembly)
                .Where(testCase =>
                    string.IsNullOrWhiteSpace(filter)
                    || TestCommandKernels.MatchesFilter(
                        filter,
                        testCase.DisplayName,
                        string.Empty,
                        testCase.FullyQualifiedName))
                .ToArray();

            var results = new List<NativeTestResult>(testCases.Length);
            var outcomeRanks = new int[testCases.Length];
            var outcomeCount = 0;
            foreach (var testCase in testCases)
            {
                var result = RunNativeTest(testCase, verbose, timeoutMs);
                results.Add(result);
                outcomeRanks[outcomeCount] = TestCommandKernels.GetNativeTestOutcomeRank(result.Outcome);
                outcomeCount++;
            }

            return new NativeTestRun(results, outcomeRanks, outcomeCount);
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static IEnumerable<NativeTestCase> DiscoverNativeTests(Assembly assembly)
    {
        foreach (var type in assembly.GetTypes().Where(type => type.IsClass && !type.IsAbstract))
        {
            foreach (var method in type.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly))
            {
                if (method.IsSpecialName || IsLifecycleMethod(method))
                {
                    continue;
                }

                var attributes = method.GetCustomAttributesData();
                var isTest = attributes.Any(IsTestMethodAttribute);
                if (!isTest && !TestCommandKernels.IsNSharpTestsTypeName(type.Name))
                {
                    continue;
                }

                // ONE CASE PER METHOD. N# owns table-driven cases by LOWERING each row into its own
                // test declaration before emit, so every row arrives here already named and already
                // alone — there is no row expansion left for the runner to decide.
                yield return new NativeTestCase(
                    TestCommandKernels.GetPreferredDisplayName(GetNSharpDescription(attributes), method.Name),
                    TestCommandKernels.GetTestFullName(type.FullName, method.Name),
                    method,
                    GetSkipReason(attributes));
            }
        }
    }

    private static NativeTestResult RunNativeTest(NativeTestCase testCase, bool verbose, int? timeoutMs)
    {
        var stopwatch = Stopwatch.StartNew();
        if (!string.IsNullOrWhiteSpace(testCase.SkipReason))
        {
            if (verbose)
            {
                Console.WriteLine(TestCommandKernels.GetVerboseSkippedMessage(testCase.DisplayName, testCase.SkipReason));
            }

            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetSkippedOutcome(),
                TestCommandKernels.GetZeroTestDuration(),
                testCase.SkipReason,
                testCase.DisplayName);
        }

        try
        {
            var instance = Activator.CreateInstance(testCase.Method.DeclaringType!);
            try
            {
                foreach (var lifecycleName in TestCommandKernels.GetPreTestLifecycleMethodNames())
                {
                    InvokeLifecycle(instance, lifecycleName, timeoutMs);
                }

                InvokeTestMethod(instance, testCase.Method, timeoutMs);
            }
            finally
            {
                foreach (var lifecycleName in TestCommandKernels.GetPostTestLifecycleMethodNames())
                {
                    try { InvokeLifecycle(instance, lifecycleName, timeoutMs); } catch { }
                }

                (instance as IDisposable)?.Dispose();
            }

            stopwatch.Stop();
            if (verbose)
            {
                Console.WriteLine(TestCommandKernels.GetVerbosePassedMessage(
                    testCase.DisplayName,
                    TestCommandKernels.FormatTestElapsedMilliseconds(stopwatch.Elapsed.TotalMilliseconds)));
            }

            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetPassedOutcome(),
                TestCommandKernels.FormatTestDurationSeconds(stopwatch.Elapsed.TotalSeconds),
                null,
                testCase.DisplayName);
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            var failure = UnwrapInvocationException(ex);
            if (verbose)
            {
                Console.WriteLine(TestCommandKernels.GetVerboseFailedMessage(testCase.DisplayName, failure.Message));
            }

            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetFailedOutcome(),
                TestCommandKernels.FormatTestDurationSeconds(stopwatch.Elapsed.TotalSeconds),
                failure.Message,
                testCase.DisplayName);
        }
    }

    private static void InvokeTestMethod(object? instance, MethodInfo method, int? timeoutMs)
    {
        if (!TestCommandKernels.IsSupportedTestMethodArity(method.GetParameters().Length))
        {
            throw new InvalidOperationException(TestCommandKernels.GetUnsupportedTestArityMessage(
                TestCommandKernels.GetTestFullName(method.DeclaringType?.FullName, method.Name), method.GetParameters().Length));
        }

        WaitForPossibleAsyncResult(method.Invoke(instance, Array.Empty<object?>()), timeoutMs);
    }

    private static void InvokeLifecycle(object? instance, string methodName, int? timeoutMs)
    {
        if (instance == null)
        {
            return;
        }

        var method = instance.GetType().GetMethod(
            methodName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            binder: null,
            types: Type.EmptyTypes,
            modifiers: null);
        if (method == null)
        {
            return;
        }

        WaitForPossibleAsyncResult(method.Invoke(instance, Array.Empty<object?>()), timeoutMs);
    }

    private static void WaitForPossibleAsyncResult(object? result, int? timeoutMs)
    {
        switch (result)
        {
            case Task task:
                WaitForTask(task, timeoutMs);
                break;
            case ValueTask valueTask:
                WaitForTask(valueTask.AsTask(), timeoutMs);
                break;
        }
    }

    private static void WaitForTask(Task task, int? timeoutMs)
    {
        if (!timeoutMs.HasValue)
        {
            task.GetAwaiter().GetResult();
            return;
        }

        if (!task.Wait(timeoutMs.Value))
        {
            throw new TimeoutException(TestCommandKernels.GetTestTimedOutMessage());
        }
    }

    private static bool IsLifecycleMethod(MethodInfo method)
        => TestCommandKernels.IsLifecycleMethodName(method.Name);

    private static bool IsTestMethodAttribute(CustomAttributeData attribute)
        => TestCommandKernels.IsTestMethodAttributeName(attribute.AttributeType.FullName);

    private static string? GetNSharpDescription(IEnumerable<CustomAttributeData> attributes)
    {
        foreach (var attribute in attributes.Where(attribute => TestCommandKernels.IsXunitTraitAttributeName(attribute.AttributeType.FullName)))
        {
            if (attribute.ConstructorArguments.Count == 2
                && TestCommandKernels.IsNSharpDescriptionTraitName(attribute.ConstructorArguments[0].Value as string)
                && attribute.ConstructorArguments[1].Value is string description)
            {
                return description;
            }
        }

        return null;
    }

    private static string? GetSkipReason(IEnumerable<CustomAttributeData> attributes)
    {
        foreach (var attribute in attributes)
        {
            if (TestCommandKernels.IsNUnitIgnoreAttributeName(attribute.AttributeType.FullName)
                && attribute.ConstructorArguments.FirstOrDefault().Value is string ignoreReason)
            {
                return ignoreReason;
            }

            var skip = attribute.NamedArguments.FirstOrDefault(argument => TestCommandKernels.IsSkipNamedArgument(argument.MemberName));
            if (skip.TypedValue.Value is string skipReason)
            {
                return skipReason;
            }
        }

        return null;
    }

    private static Exception UnwrapInvocationException(Exception ex)
    {
        while (ex is TargetInvocationException or AggregateException)
        {
            if (ex is TargetInvocationException { InnerException: { } inner })
            {
                ex = inner;
                continue;
            }

            if (ex is AggregateException { InnerExceptions.Count: 1 } aggregate)
            {
                ex = aggregate.InnerExceptions[0];
                continue;
            }

            break;
        }

        return ex;
    }

    // The N# outcome summary is REQUIRED, and the SIGNATURE is what requires it — not a sentence.
    private static void OutputNativeTestJson(
        string projectRoot,
        bool ok,
        IReadOnlyList<NativeTestResult> testResults,
        NativeTestSummary summary,
        string? errorMessage = null)
    {
        Console.WriteLine(TestCommandKernels.NativeTestJson(projectRoot, ok, testResults, errorMessage, summary));
    }

}
