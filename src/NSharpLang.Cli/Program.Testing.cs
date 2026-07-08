using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
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
            var candidatePath = Path.Combine(assemblyDirectory, $"{assemblyName.Name}.dll");
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
            if (outputMode == 1)
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message, summary: NativeTestSummary.EmptyFailure);
                return 1;
            }

            return Error(message);
        }

        if (collectCoverage || coverageReport)
        {
            var message = TestCommandKernels.GetCoverageUnsupportedMessage();
            if (outputMode == 1)
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message, summary: NativeTestSummary.EmptyFailure);
                return 1;
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
                "Debug",
                testOutputDir,
                includeTests: true,
                verbose: verbose);

            if (outputPath == null)
            {
                var message = TestCommandKernels.GetBuildFailedMessage();
                if (outputMode == 1)
                {
                    OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), message, summary: NativeTestSummary.EmptyFailure);
                    return 1;
                }

                return Error(message);
            }

            var testRun = TestCommandKernels.ShouldRunNUnit(projectConfig.TestFramework)
                ? RunReflectionTests(outputPath, filter, verbose, timeoutMs)
                : RunXunitTests(outputPath, filter, verbose, timeoutMs);
            var testResults = testRun.Results;
            var summary = TestCommandKernels.SummarizeNativeTestRun(testRun);

            if (outputMode == 1)
            {
                OutputNativeTestJson(projectRoot, summary.Ok, testResults, summary: summary);
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
            if (outputMode == 2)
            {
                Console.WriteLine(TestCommandKernels.GetFailedElapsedMessage(ProgramCommandKernels.FormatElapsedMilliseconds(stopwatch.ElapsedMilliseconds)));
            }

            if (outputMode == 1)
            {
                OutputNativeTestJson(projectRoot, false, Array.Empty<NativeTestResult>(), ex.Message, summary: NativeTestSummary.EmptyFailure);
                return 1;
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
        var assemblyDirectory = Path.GetDirectoryName(assemblyPath)
            ?? throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.");

        Assembly? resolveFromTestOutput(AssemblyLoadContext context, AssemblyName assemblyName)
        {
            var alreadyLoaded = context.Assemblies.FirstOrDefault(assembly =>
                AssemblyName.ReferenceMatchesDefinition(assembly.GetName(), assemblyName));
            if (alreadyLoaded != null)
            {
                return alreadyLoaded;
            }

            var candidatePath = Path.Combine(assemblyDirectory, $"{assemblyName.Name}.dll");
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

                    var displayName = GetXunitDescription(testCase) ?? testCase.DisplayName;
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
                throw new TimeoutException("Test run timed out.");
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
                    AddResult(passed, "passed", null);
                    break;
                case ITestSkipped skipped:
                    AddResult(skipped, "skipped", skipped.Reason);
                    break;
                case ITestFailed failed:
                    AddResult(failed, "failed", FormatXunitFailure(failed));
                    break;
                case IErrorMessage error:
                    _results.Add(new NativeTestResult(
                        "xunit.runner",
                        "xUnit runner",
                        "failed",
                        "0.000s",
                        FormatXunitFailure(error),
                        "xUnit runner"));
                    AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank("failed"));
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
            var displayName = GetXunitDisplayName(message.Test);
            var result = new NativeTestResult(
                GetXunitFullyQualifiedName(testCase),
                displayName,
                outcome,
                $"{message.ExecutionTime:F3}s",
                errorMessage,
                GetXunitDescription(testCase) ?? displayName);

            _results.Add(result);
            AddOutcomeRank(TestCommandKernels.GetNativeTestOutcomeRank(outcome));

            if (!verbose)
            {
                return;
            }

            Console.WriteLine(errorMessage == null
                ? TestCommandKernels.GetVerbosePassedMessage(
                    displayName,
                    (message.ExecutionTime * 1000).ToString("F0", CultureInfo.InvariantCulture))
                : outcome == "skipped"
                    ? TestCommandKernels.GetVerboseSkippedMessage(displayName, errorMessage)
                    : TestCommandKernels.GetVerboseFailedMessage(displayName, errorMessage));
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

    private static string GetXunitDisplayName(ITest test)
        => GetXunitDescription(test.TestCase) ?? test.DisplayName;

    private static string? GetXunitDescription(ITestCase testCase)
        => testCase.Traits.TryGetValue("NSharpDescription", out var descriptions)
            ? descriptions.FirstOrDefault()
            : null;

    private static string GetXunitFullyQualifiedName(ITestCase testCase)
        => $"{testCase.TestMethod.TestClass.Class.Name}.{testCase.TestMethod.Method.Name}";

    private static string FormatXunitFailure(IFailureInformation failure)
        => string.Join(Environment.NewLine, failure.Messages.Where(message => !string.IsNullOrWhiteSpace(message)));

    private static NativeTestRun RunReflectionTests(
        string assemblyPath,
        string? filter,
        bool verbose,
        int? timeoutMs)
    {
        var assemblyDirectory = Path.GetDirectoryName(assemblyPath)
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
                if (!isTest && !string.Equals(type.Name, "NSharpTests", StringComparison.Ordinal))
                {
                    continue;
                }

                var displayName = GetNSharpDescription(attributes) ?? method.Name;
                var skipReason = GetSkipReason(attributes);
                var dataRows = GetInlineDataRows(attributes).ToArray();
                if (dataRows.Length == 0)
                {
                    dataRows = new[] { Array.Empty<object?>() };
                }

                foreach (var row in dataRows)
                {
                    var suffix = row.Length == 0 ? string.Empty : $"({string.Join(", ", row.Select(value => value ?? "null"))})";
                    yield return new NativeTestCase(
                        displayName + suffix,
                        $"{type.FullName}.{method.Name}",
                        method,
                        row,
                        skipReason);
                }
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
                "skipped",
                "0.000s",
                testCase.SkipReason,
                testCase.DisplayName);
        }

        try
        {
            var instance = Activator.CreateInstance(testCase.Method.DeclaringType!);
            try
            {
                InvokeLifecycle(instance, "InitializeAsync", timeoutMs);
                InvokeLifecycle(instance, "Setup", timeoutMs);
                InvokeTestMethod(instance, testCase.Method, testCase.Arguments, timeoutMs);
            }
            finally
            {
                try { InvokeLifecycle(instance, "Teardown", timeoutMs); } catch { }
                try { InvokeLifecycle(instance, "DisposeAsync", timeoutMs); } catch { }
                (instance as IDisposable)?.Dispose();
            }

            stopwatch.Stop();
            if (verbose)
            {
                Console.WriteLine(TestCommandKernels.GetVerbosePassedMessage(
                    testCase.DisplayName,
                    stopwatch.Elapsed.TotalMilliseconds.ToString("F0", CultureInfo.InvariantCulture)));
            }

            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                "passed",
                $"{stopwatch.Elapsed.TotalSeconds:F3}s",
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
                "failed",
                $"{stopwatch.Elapsed.TotalSeconds:F3}s",
                failure.Message,
                testCase.DisplayName);
        }
    }

    private static void InvokeTestMethod(object? instance, MethodInfo method, object?[] arguments, int? timeoutMs)
    {
        if (method.GetParameters().Length != arguments.Length)
        {
            throw new InvalidOperationException(
                $"Test '{method.DeclaringType?.FullName}.{method.Name}' expects {method.GetParameters().Length} argument(s), but {arguments.Length} were supplied.");
        }

        WaitForPossibleAsyncResult(method.Invoke(instance, arguments), timeoutMs);
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
            throw new TimeoutException("Test timed out.");
        }
    }

    private static bool IsLifecycleMethod(MethodInfo method)
        => method.Name is "Setup" or "Teardown" or "InitializeAsync" or "DisposeAsync" or "Dispose";

    private static bool IsTestMethodAttribute(CustomAttributeData attribute)
    {
        var name = attribute.AttributeType.FullName;
        return name is "Xunit.FactAttribute"
            or "Xunit.TheoryAttribute"
            or "NUnit.Framework.TestAttribute"
            or "NUnit.Framework.TestCaseAttribute";
    }

    private static string? GetNSharpDescription(IEnumerable<CustomAttributeData> attributes)
    {
        foreach (var attribute in attributes.Where(attribute => attribute.AttributeType.FullName == "Xunit.TraitAttribute"))
        {
            if (attribute.ConstructorArguments.Count == 2
                && string.Equals(attribute.ConstructorArguments[0].Value as string, "NSharpDescription", StringComparison.Ordinal)
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
            if (attribute.AttributeType.FullName == "NUnit.Framework.IgnoreAttribute"
                && attribute.ConstructorArguments.FirstOrDefault().Value is string ignoreReason)
            {
                return ignoreReason;
            }

            var skip = attribute.NamedArguments.FirstOrDefault(argument => argument.MemberName == "Skip");
            if (skip.TypedValue.Value is string skipReason)
            {
                return skipReason;
            }
        }

        return null;
    }

    private static IEnumerable<object?[]> GetInlineDataRows(IEnumerable<CustomAttributeData> attributes)
    {
        foreach (var attribute in attributes)
        {
            if (attribute.AttributeType.FullName is not ("Xunit.InlineDataAttribute" or "NUnit.Framework.TestCaseAttribute"))
            {
                continue;
            }

            if (attribute.ConstructorArguments.Count != 1)
            {
                continue;
            }

            var argument = attribute.ConstructorArguments[0];
            if (argument.Value is IReadOnlyCollection<CustomAttributeTypedArgument> values)
            {
                yield return values.Select(value => value.Value).ToArray();
            }
            else
            {
                yield return new[] { argument.Value };
            }
        }
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

    private static void OutputNativeTestJson(
        string projectRoot,
        bool ok,
        IReadOnlyList<NativeTestResult> testResults,
        string? errorMessage = null,
        NativeTestSummary? summary = null)
    {
        var summaryValue = summary ?? throw new InvalidOperationException("N# test JSON output requires an N# outcome summary.");
        Console.WriteLine(TestCommandKernels.NativeTestJson(projectRoot, ok, testResults, errorMessage, summaryValue));
    }

}
