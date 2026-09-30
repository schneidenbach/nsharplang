namespace NSharpLang.Cli

import System
import System.Collections.Generic
import System.Diagnostics
import System.Reflection
import System.Threading.Tasks

// THE NUnit-SHAPED RUNNER, WHICH IS THE ISOLATED ONE.
//
// `TestCommandKernels.ShouldRunNUnit(projectConfig.TestFramework)` chooses this route. It loads the
// emitted assembly into a private collectible `NativeTestLoadContext` and unloads it in a `finally`,
// so nothing the run touched is pinned afterwards.
//
// Discovery admits a public instance method that is declared on a non-abstract class, is not a
// special name and is not a lifecycle name, and that either carries a test attribute OR sits on a
// type named `NSharpTests`.
static class ReflectionTestRunner {
    static func Run(assemblyPath: string, filter: string?, verbose: bool, timeoutMs: int?): NativeTestRun {
        assemblyDirectory := TestCommandKernels.GetAssemblyDirectory(assemblyPath)
        if assemblyDirectory == null {
            throw new InvalidOperationException($"Could not determine the test assembly directory for '{assemblyPath}'.")
        }

        loadContext := new NativeTestLoadContext(assemblyDirectory)

        try {
            assembly := loadContext.LoadFromAssemblyPath(assemblyPath)
            testCases := new List<NativeTestCase>()
            for candidate in DiscoverNativeTests(assembly) {
                if string.IsNullOrWhiteSpace(filter) {
                    testCases.Add(candidate)
                    continue
                }

                if TestCommandKernels.MatchesFilter(
                    filter,
                    candidate.DisplayName,
                    "",
                    candidate.FullyQualifiedName
                ) {
                    testCases.Add(candidate)
                }
            }

            results := new List<NativeTestResult>()
            outcomeRanks := new int[](testCases.Count)
            outcomeCount := 0
            for testCase in testCases {
                result := RunNativeTest(testCase, verbose, timeoutMs)
                results.Add(result)
                outcomeRanks[outcomeCount] = TestCommandKernels.GetNativeTestOutcomeRank(result.Outcome)
                outcomeCount = outcomeCount + 1
            }

            return new NativeTestRun(results, outcomeRanks, outcomeCount)
        } finally {
            loadContext.Unload()
        }
    }

    // ONE CASE PER METHOD. N# owns table-driven cases by LOWERING each row into its own test
    // declaration before emit, so every row arrives here already named and already alone — there is
    // no row expansion left for the runner to decide.
    //
    // The C# owner spelled this as an iterator. The list is filled eagerly instead, which is
    // unobservable: the one caller materialises the whole sequence before running anything.
    static func DiscoverNativeTests(assembly: Assembly): List<NativeTestCase> {
        discovered := new List<NativeTestCase>()
        for declaringType in assembly.GetTypes() {
            if !declaringType.IsClass || declaringType.IsAbstract {
                continue
            }

            for method in declaringType.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.DeclaredOnly) {
                if method.IsSpecialName || TestCommandKernels.IsLifecycleMethodName(method.Name) {
                    continue
                }

                attributes := method.GetCustomAttributesData()
                isTest := false
                for attribute in attributes {
                    if TestCommandKernels.IsTestMethodAttributeName(attribute.AttributeType.FullName) {
                        isTest = true
                    }
                }

                if !isTest && !TestCommandKernels.IsNSharpTestsTypeName(declaringType.Name) {
                    continue
                }

                discovered.Add(new NativeTestCase(
                    TestCommandKernels.GetPreferredDisplayName(GetNSharpDescription(attributes), method.Name),
                    TestCommandKernels.GetTestFullName(declaringType.FullName, method.Name),
                    method,
                    GetSkipReason(attributes)
                ))
            }
        }

        return discovered
    }

    static func RunNativeTest(testCase: NativeTestCase, verbose: bool, timeoutMs: int?): NativeTestResult {
        stopwatch := Stopwatch.StartNew()
        if !string.IsNullOrWhiteSpace(testCase.SkipReason) {
            skipReason := testCase.SkipReason
            if verbose {
                Console.WriteLine(TestCommandKernels.GetVerboseSkippedMessage(testCase.DisplayName, skipReason))
            }

            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetSkippedOutcome(),
                TestCommandKernels.GetZeroTestDuration(),
                skipReason,
                testCase.DisplayName
            )
        }

        try {
            instance := Activator.CreateInstance(must testCase.Method.DeclaringType)
            try {
                for lifecycleName in TestCommandKernels.GetPreTestLifecycleMethodNames() {
                    InvokeLifecycle(instance, lifecycleName, timeoutMs)
                }

                InvokeTestMethod(instance, testCase.Method, timeoutMs)
            } finally {
                // A post-test lifecycle failure never turns a passing test red, and never hides an
                // earlier failure: the same swallow the C# owner had.
                for lifecycleName in TestCommandKernels.GetPostTestLifecycleMethodNames() {
                    try {
                        InvokeLifecycle(instance, lifecycleName, timeoutMs)
                    } catch lifecycleError: Exception {
                    }
                }

                disposable := instance as IDisposable
                if disposable != null {
                    disposable.Dispose()
                }
            }

            stopwatch.Stop()
            if verbose {
                elapsedText := TestCommandKernels.FormatTestElapsedMilliseconds(stopwatch.Elapsed.TotalMilliseconds)
                Console.WriteLine(TestCommandKernels.GetVerbosePassedMessage(testCase.DisplayName, elapsedText))
            }

            passedDuration := TestCommandKernels.FormatTestDurationSeconds(stopwatch.Elapsed.TotalSeconds)
            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetPassedOutcome(),
                passedDuration,
                null,
                testCase.DisplayName
            )
        } catch testError: Exception {
            stopwatch.Stop()
            failure := UnwrapInvocationException(testError)
            if verbose {
                Console.WriteLine(TestCommandKernels.GetVerboseFailedMessage(testCase.DisplayName, failure.Message))
            }

            failedDuration := TestCommandKernels.FormatTestDurationSeconds(stopwatch.Elapsed.TotalSeconds)
            return new NativeTestResult(
                testCase.FullyQualifiedName,
                testCase.DisplayName,
                TestCommandKernels.GetFailedOutcome(),
                failedDuration,
                failure.Message,
                testCase.DisplayName
            )
        }
    }

    static func InvokeTestMethod(instance: object?, method: MethodInfo, timeoutMs: int?) {
        parameterCount := method.GetParameters().Length
        if !TestCommandKernels.IsSupportedTestMethodArity(parameterCount) {
            throw new InvalidOperationException(TestCommandKernels.GetUnsupportedTestArityMessage(
                TestCommandKernels.GetTestFullName(DeclaringTypeFullName(method), method.Name),
                parameterCount
            ))
        }

        WaitForPossibleAsyncResult(method.Invoke(instance, new object?[](0)), timeoutMs)
    }

    static func DeclaringTypeFullName(method: MethodInfo): string? {
        declaringType := method.DeclaringType
        if declaringType == null {
            return null
        }

        return declaringType.FullName
    }

    static func InvokeLifecycle(instance: object?, methodName: string, timeoutMs: int?) {
        if instance == null {
            return
        }

        method := instance.GetType().GetMethod(
            methodName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic,
            null,
            new Type[](0),
            null
        )
        if method == null {
            return
        }

        WaitForPossibleAsyncResult(method.Invoke(instance, new object?[](0)), timeoutMs)
    }

    static func WaitForPossibleAsyncResult(result: object?, timeoutMs: int?) {
        task := result as Task
        if task != null {
            WaitForTask(task, timeoutMs)
            return
        }

        if result is ValueTask pending {
            WaitForTask(pending.AsTask(), timeoutMs)
        }
    }

    static func WaitForTask(task: Task, timeoutMs: int?) {
        if timeoutMs == null {
            task.GetAwaiter().GetResult()
            return
        }

        timeoutValue: int = timeoutMs
        completed := task.Wait(timeoutValue)
        if !completed {
            throw new TimeoutException(TestCommandKernels.GetTestTimedOutMessage())
        }
    }

    static func GetNSharpDescription(attributes: IList<CustomAttributeData>): string? {
        for attribute in attributes {
            if !TestCommandKernels.IsXunitTraitAttributeName(attribute.AttributeType.FullName) {
                continue
            }

            arguments := attribute.ConstructorArguments
            if arguments.Count != 2 {
                continue
            }

            traitName := arguments[0].Value as string
            if !TestCommandKernels.IsNSharpDescriptionTraitName(traitName) {
                continue
            }

            description := arguments[1].Value as string
            if description != null {
                return description
            }
        }

        return null
    }

    static func GetSkipReason(attributes: IList<CustomAttributeData>): string? {
        for attribute in attributes {
            arguments := attribute.ConstructorArguments
            if TestCommandKernels.IsNUnitIgnoreAttributeName(attribute.AttributeType.FullName) && arguments.Count > 0 {
                ignoreReason := arguments[0].Value as string
                if ignoreReason != null {
                    return ignoreReason
                }
            }

            for namedArgument in attribute.NamedArguments {
                if !TestCommandKernels.IsSkipNamedArgument(namedArgument.MemberName) {
                    continue
                }

                skipReason := namedArgument.TypedValue.Value as string
                if skipReason != null {
                    return skipReason
                }

                break
            }
        }

        return null
    }

    // A reflected invocation wraps whatever the test threw; the reader must see their own exception.
    static func UnwrapInvocationException(error: Exception): Exception {
        current := error
        while current is TargetInvocationException || current is AggregateException {
            invocation := current as TargetInvocationException
            if invocation != null && invocation.InnerException != null {
                current = invocation.InnerException
                continue
            }

            aggregate := current as AggregateException
            if aggregate != null {
                innerExceptions := aggregate.InnerExceptions
                if innerExceptions.Count == 1 {
                    current = innerExceptions[0]
                    continue
                }
            }

            break
        }

        return current
    }
}
