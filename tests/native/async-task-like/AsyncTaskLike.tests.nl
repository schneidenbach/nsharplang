namespace NSharpLang.AsyncTaskLike.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO
import System.Reflection
import System.Reflection.Emit
import System.Runtime.CompilerServices
import System.Threading
import System.Threading.Tasks
import NSharpLang.AsyncAwaitablePatternFixtures

func AsyncMethodContainsGetResult(method: MethodInfo): bool {
    body := method.GetMethodBody()
    if body == null {
        return false
    }
    il := body.GetILAsByteArray()
    if il == null {
        return false
    }
    opcodes := new Dictionary<short, OpCode>()
    for field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static) {
        value := field.GetValue(null)
        if value is OpCode {
            opcode := (OpCode)value
            opcodes[opcode.Value] = opcode
        }
    }
    offset := 0
    while offset < il.Length {
        first := il[offset]
        opcodeValue: short = 0
        if first == 0xfe {
            if offset + 1 >= il.Length {
                return false
            }
            opcodeValue = (short)(0xfe00 | il[offset + 1])
            offset += 2
        } else {
            opcodeValue = (short)first
            offset += 1
        }
        opcode: OpCode = OpCodes.Nop
        if !opcodes.TryGetValue(opcodeValue, out opcode) {
            return false
        }
        operandOffset := offset
        if opcode.Value == OpCodes.Call.Value || opcode.Value == OpCodes.Callvirt.Value {
            if operandOffset + 4 > il.Length {
                return false
            }
            token := BitConverter.ToInt32(il, operandOffset)
            resolved: MethodBase? = null
            try {
                resolved = method.Module.ResolveMethod(token)
            } catch error: ArgumentException {
                resolved = null
            }
            if resolved != null && resolved.Name == "GetResult" {
                return true
            }
        }
        operandBytes: int = 0
        operandType := opcode.OperandType
        if operandType == OperandType.ShortInlineBrTarget || operandType == OperandType.ShortInlineI || operandType == OperandType.ShortInlineVar {
            operandBytes = 1
        } else if operandType == OperandType.InlineVar {
            operandBytes = 2
        } else if operandType == OperandType.InlineI8 || operandType == OperandType.InlineR {
            operandBytes = 8
        } else if operandType == OperandType.InlineSwitch {
            if operandOffset + 4 > il.Length {
                return false
            }
            count := BitConverter.ToInt32(il, operandOffset)
            operandBytes = 4 + count * 4
        } else if operandType != OperandType.InlineNone {
            operandBytes = 4
        }
        offset = operandOffset + operandBytes
        if offset > il.Length {
            return false
        }
    }
    return false
}

func AsyncServiceAsyncMethodFacts(): string {
    facts := ""
    for method in typeof(AsyncService).GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly) {
        stateMachineAttribute := method.GetCustomAttribute<AsyncStateMachineAttribute>()
        if stateMachineAttribute != null {
            machineType := stateMachineAttribute.StateMachineType
            kickoffHasGetResult := AsyncMethodContainsGetResult(method)
            facts = "state=" + machineType.IsValueType.ToString()
                + ", interface=" + typeof(IAsyncStateMachine).IsAssignableFrom(machineType).ToString()
                + ", generated=" + (machineType.GetCustomAttribute<CompilerGeneratedAttribute>() != null).ToString()
                + ", debugger=" + (method.GetCustomAttribute<DebuggerStepThroughAttribute>() != null).ToString()
                + ", kickoffGetResult=" + kickoffHasGetResult.ToString()
        }
    }
    return facts
}

func AllAsyncKickoffsAvoidGetResult(): bool {
    flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly
    for type in typeof(AsyncService).Assembly.GetTypes() {
        for method in type.GetMethods(flags) {
            if method.GetCustomAttribute<AsyncStateMachineAttribute>() != null && AsyncMethodContainsGetResult(method) {
                return false
            }
        }
    }
    return true
}

// Every test touches a MEMBER of an async call result — the exact move that used to crash
// `nlc check` for the bare-`Task` family before the task-identity fix.
test "an async unit Task call result is a value whose members resolve and run" {
    work := UnitWork()
    work.Wait()
    assert work.IsCompleted
}

test "an async Task of int call result carries its awaited result" {
    actual := CountedWork().Result
    assert actual == 41, "CountedWork returned " + actual.ToString()
}

test "a null assertion nested in an async call argument runs before the first suspension" {
    directory := Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"))
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := CreateDirectoryBeforeAwait(directory, gate.Task)
    assert Directory.Exists(directory)
    assert !pending.IsCompleted
    gate.SetResult(57)
    assert pending.Result == 57
    Directory.Delete(directory, true)
}

test "an async unit ValueTask call result converts to a waitable task" {
    converted := UnitValueWork().AsTask()
    converted.Wait()
    assert converted.IsCompleted
}

test "an async ValueTask of int call result carries its awaited result" {
    assert CountedValueWork().AsTask().Result == 42
}

test "an await foreach inside a bare Task function drains and completes" {
    drained := DrainAll()
    drained.Wait()
    assert drained.IsCompleted
}

test "an await foreach inside a Task of int function accumulates the async iterator" {
    assert SumCounted().Result == 3
}

test "await reaches any value with the awaiter pattern, task or not" {
    counted := YieldingWork()
    countedValue := counted.GetAwaiter().GetResult()
    assert countedValue == 42

    unit := YieldOnce()
    unit.Wait()
    assert unit.get_IsCompleted()

    assert AwaitCustom(7).GetAwaiter().GetResult() == 7
    assert AwaitCustom(0).GetAwaiter().GetResult() == 0
}

test "an incomplete ValueTask await suspends and later returns its value" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    source := new ValueTask<int>(gate.Task)
    pending := AwaitValueTask(source)
    assert !pending.IsCompleted

    gate.SetResult(27)
    assert pending.AsTask().Result == 27
}

test "awaits nested in call arguments preserve their values across suspension" {
    first := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    second := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    third := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitNestedArguments(first.Task, second.Task, third.Task)
    assert !pending.IsCompleted

    first.SetResult(10)
    assert !pending.IsCompleted
    second.SetResult(20)
    assert !pending.IsCompleted
    third.SetResult(30)
    assert pending.Result == 60
}

test "an interpolated string inside an awaited call argument is spilled and resumed" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitInterpolatedArgument(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(37)
    assert pending.Result == "value 37"
}

test "an async method can register and await a task continuation with a lambda callback" {
    source := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    counter := new ContinuationCounter()
    pending := AwaitContinuationCallback(source.Task, gate.Task, counter)
    assert !pending.IsCompleted

    source.SetResult(1)
    gate.SetResult(2)
    assert pending.Result == 1
}

test "an async method discards a returned task before its next suspension" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitAfterDiscardedTask(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(42)
    assert pending.Result == 42
}

test "an async method can discard a stream continuation and await its completion signal" {
    source := new MemoryStream([72, 105, 33])
    destination := new MemoryStream()
    copied := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitDiscardedStreamContinuation(source, destination, copied, gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(43)
    assert pending.Result == 43
    assert destination.Length == 3
}

test "a value-returning call is discarded in a void-compatible async lambda" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    counter := new ContinuationCounter()
    pending := AwaitVoidCompatibleExpressionLambda(gate.Task, counter)
    assert !pending.IsCompleted

    gate.SetResult(7)
    assert pending.Result == 7
}

test "awaits nested in a binary expression spill both values across suspension" {
    first := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    second := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitNestedBinary(first.Task, second.Task)
    assert !pending.IsCompleted

    first.SetResult(19)
    assert !pending.IsCompleted
    second.SetResult(23)
    assert pending.Result == 42
}

test "an indexed receiver is spilled while its awaited index is pending" {
    values := new List<int>()
    values.Add(42)
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitIndexedValue(values, gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(0)
    assert pending.Result == 42
}

test "await in a loop resumes at its loop state and keeps the accumulated value" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitLoop(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(20)
    assert pending.Result == 22
}

test "awaits in try catch and finally preserve handler order through suspension" {
    source := new TaskCompletionSource<int>()
    catchGate := new TaskCompletionSource()
    finallyGate := new TaskCompletionSource()
    trace := new List<string>()
    pending := AwaitHandlers(source.Task, catchGate.Task, finallyGate.Task, trace)
    assert !pending.IsCompleted

    source.SetResult(1)
    assert string.Join(",", trace) == "catch-start", "before catchGate: " + string.Join(",", trace)
    catchGate.SetResult()
    assert string.Join(",", trace) == "catch-start,catch-end,finally-start", "before finallyGate: " + string.Join(",", trace)
    assert !pending.IsCompleted
    finallyGate.SetResult()
    assert pending.Result == 73, "handler result was " + pending.Result.ToString()
    assert string.Join(",", trace) == "catch-start,catch-end,finally-start,finally-end", "after finallyGate: " + string.Join(",", trace)
}

test "await using suspends during asynchronous disposal and then exits the region" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    trace := new List<string>()
    pending := AwaitUsingResource(gate.Task, trace)
    assert !pending.IsCompleted
    assert string.Join(",", trace) == "body"

    gate.SetResult()
    assert pending.Result == 31
    assert string.Join(",", trace) == "body,disposed,tail"
}

test "a normal using region remains open across an awaited body and disposes on return" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    trace := new List<string>()
    pending := AwaitInsideUsing(gate.Task, trace)
    assert !pending.IsCompleted

    gate.SetResult(18)
    assert pending.Result == 18
    assert string.Join(",", trace) == "body,disposed"
}

test "await foreach composes an async iterator suspension with the consuming task machine" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := ConsumeWaitAndYield(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(44)
    assert pending.Result == 44
}

test "ConfigureAwait(false) resumes without the captured single-thread context" {
    context := new SingleThreadTestContext()
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    previous := SynchronizationContext.Current
    SynchronizationContext.SetSynchronizationContext(context)
    pending := ObserveConfiguredContext(gate.Task, context)
    SynchronizationContext.SetSynchronizationContext(previous)
    assert !pending.IsCompleted

    gate.SetResult(1)
    pending.Wait()
    assert pending.Result
}

test "selected source ConfigureAwait extension resumes a pending task" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitSourceExtensionConfigured(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(91)
    assert pending.Result == 91
}

test "selected referenced ConfigureAwait extension resumes a pending task" {
    configured := new ReflectedConfiguredAwaitable()
    pending := AwaitReflectedExtensionConfigured(configured)
    assert !pending.IsCompleted

    configured.Complete(92)
    assert pending.Result == 92
}

test "a critical awaiter registers with UnsafeOnCompleted" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    trace := new List<string>()
    pending := AwaitCritical(new CriticalAwaitable(gate.Task, trace))
    assert !pending.IsCompleted
    assert string.Join(",", trace) == "unsafe"

    gate.SetResult(38)
    assert pending.Result == 38
    assert string.Join(",", trace) == "unsafe"
}

test "an async iterator registers a critical awaiter through its interface slot" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    trace := new List<string>()
    pending := ConsumeCriticalAwait(new CriticalAwaitable(gate.Task, trace))
    assert !pending.IsCompleted
    assert string.Join(",", trace) == "unsafe"

    gate.SetResult(40)
    assert pending.Result == 40
    assert string.Join(",", trace) == "unsafe"
}

test "an explicit INotifyCompletion implementation resumes through interface dispatch" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitExplicitNotify(new ExplicitNotifyAwaitable(gate.Task))
    assert !pending.IsCompleted

    gate.SetResult(39)
    assert pending.Result == 39
}

test "source interface inheritance preserves the INotifyCompletion slot during emission" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitInheritedNotify(new InheritedNotifyAwaitable(gate.Task))
    assert !pending.IsCompleted

    gate.SetResult(41)
    assert pending.Result == 41
}

test "an explicit base INotifyCompletion slot resolves through a source interface's inherited closure" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitInheritedExplicitNotify(new InheritedExplicitNotifyAwaitable(gate.Task))
    assert !pending.IsCompleted

    gate.SetResult(48)
    assert pending.Result == 48
}

test "an interface-typed source awaiter resumes through its interface slots" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitSourceInterfaceAwaiter(new SourceInterfaceAwaitable(gate.Task))
    assert !pending.IsCompleted

    gate.SetResult(49)
    assert pending.Result == 49
}

test "a constructed generic source interface awaiter suspends and resumes through interface slots" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitConstructedGenericSourceInterface(new GenericSourceInterfaceAwaitable(gate.Task))
    assert !pending.IsCompleted

    gate.SetResult(50)
    assert pending.Result == 50
}

test "a generic owner implementation maps its constructed source interface slots after suspension" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitGenericOwnerSourceInterface(new GenericOwnerSourceInterfaceAwaitable<int>(gate.Task, 56))
    assert !pending.IsCompleted

    gate.SetResult(56)
    assert pending.Result == 56
}

test "a receiver-inferred generic GetAwaiter extension is emitted and returns its closed value" {
    pending := AwaitGenericExtension(new GenericExtensionBox<int>(47))
    assert pending.Result == 47
}

test "reflected params constructors preserve expanded, direct-array, and empty argument shapes" {
    expanded := new ReflectedParamsBox(1, 2)
    values: int[] = [3, 4]
    direct := new ReflectedParamsBox(values)
    empty := new ReflectedParamsBox()

    assert expanded.Count == 2
    assert direct.Count == 2
    assert empty.Count == 0
}

test "reflected constructor overload bindings preserve defaults and numeric conversions after a pending gate" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := ReadReflectedConstructorShapesAfterGate(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult()
    assert pending.Result == 83
}

test "the pending awaiter matrix uses one bound pattern across source and referenced libraries" {
    gates := new List<TaskCompletionSource<int>>()
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))
    gates.Add(new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously))

    pending := new List<Task<int>>()
    pending.Add(AwaitDecoyCompletion(new DecoyCompletionAwaitable(gates[0].Task)))
    pending.Add(AwaitSourceInheritedCompletion(new SourceInheritedAwaitable(gates[1].Task)))
    pending.Add(AwaitPendingGenericExtension<int>(gates[2].Task, 82))
    pending.Add(AwaitCritical(new CriticalAwaitable(gates[3].Task, new List<string>())))
    pending.Add(AwaitExplicitNotify(new ExplicitNotifyAwaitable(gates[4].Task)))
    pending.Add(AwaitInheritedNotify(new InheritedNotifyAwaitable(gates[5].Task)))
    pending.Add(AwaitInheritedExplicitNotify(new InheritedExplicitNotifyAwaitable(gates[6].Task)))
    pending.Add(AwaitSourceImplicitDecoy(new SourceImplicitDecoyAwaitable(gates[7].Task)))
    pending.Add(AwaitReflectedInheritedCompletion(new ReflectedInheritedAwaitable(gates[8].Task)))
    pending.Add(AwaitReflectedGenericExtension(new ReflectedGenericExtensionBox<int>(gates[9].Task)))
    pending.Add(AwaitReflectedDecoyCompletion(new ReflectedDecoyAwaitable(gates[10].Task)))
    pending.Add(AwaitPendingConcreteGenericExtension(gates[11].Task, 92))

    for task in pending {
        assert !task.IsCompleted, "every matrix row must reach an incomplete await"
    }
    index := 0
    while index < gates.Count {
        gates[index].SetResult(80 + index)
        index += 1
    }
    index = 0
    while index < pending.Count {
        task := pending[index]
        assert task.Wait(TimeSpan.FromSeconds(5)), "pending await matrix row " + index.ToString() + " did not resume through its selected slot"
        expected := index == 2 ? 82 : (index == 11 ? 92 : 80 + index)
        assert task.Result == expected, "pending await matrix row " + index.ToString() + " returned the wrong result"
        index += 1
    }
}

test "GetAwaiter extension overload resolution selects the most specific receiver" {
    assert AwaitMostSpecificExtension().Result == 52
}

test "async lambda and local function captures remain shared across their awaits" {
    lambdaGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    lambdaTask := CaptureAsyncLambda(lambdaGate.Task)
    assert !lambdaTask.IsCompleted
    lambdaGate.SetResult()
    assert lambdaTask.Result == 9

    localGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    localTask := CaptureAsyncLocalFunction(localGate.Task)
    assert !localTask.IsCompleted
    localGate.SetResult()
    assert localTask.Result == 10
}

test "a synchronous lambda captures an async local across suspension" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := CaptureSynchronousLambdaAcrossAwait(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult()
    assert pending.Result == 16
}

test "a captured async local function in a synchronous owner returns before its await completes" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := StartCapturedAsyncLocalFunction(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult()
    assert pending.Result == 10
}

test "a generic async local function has a closed resumable state machine" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := StartGenericAsyncLocalFunction(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("generic local")
    assert pending.Result == "generic local"
}

test "async locals close over generic async function owners" {
    plainGate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    genericGate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    plain := GenericAsyncOwnerLocal(plainGate.Task)
    generic := GenericAsyncOwnerGenericLocal(genericGate.Task)
    assert !plain.IsCompleted && !generic.IsCompleted

    plainGate.SetResult("owner type parameter")
    genericGate.SetResult("local type parameter")
    assert plain.Result == "owner type parameter"
    assert generic.Result == "local type parameter"
}

test "an async local under a generic async method preserves a value type owner parameter" {
    ownerGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    owner := GenericAsyncOwnerLocal(ownerGate.Task)
    assert !owner.IsCompleted

    ownerGate.SetResult(31)
    assert owner.Result == 31
}

test "a generic async local under a generic async method preserves both type parameter owners" {
    localGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    local := GenericAsyncOwnerGenericLocal(localGate.Task)
    assert !local.IsCompleted

    localGate.SetResult(32)
    assert local.Result == 32
}

test "an async local under a generic class method preserves a value type owner parameter" {
    classGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<int>(7)
    classLocal := service.ReadLocal(classGate.Task)
    assert !classLocal.IsCompleted

    classGate.SetResult(33)
    assert classLocal.Result == 33
}

test "a constrained generic owner keeps its IDisposable constraint in a nested async local" {
    resource := new MemoryStream()
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    owner := new ConstrainedAsyncOwner<MemoryStream>(resource)
    pending := owner.DisposeAfter(gate.Task)
    assert !pending.IsCompleted
    assert resource.CanRead

    gate.SetResult()
    assert pending.Result
    assert !resource.CanRead
}

test "`GetAwaiter()` written out works on a generic task, not only on a unit one" {
    assert AwaitedSynchronously() == 41
    assert AwaiterThroughALocal() == 11
    assert UnitAwaitedSynchronously()
}

test "an async function returns while its awaited task is incomplete and resumes with its result" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitValue(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(5)
    assert pending.Result == 5
}

test "an await inside the argument of an awaited async call spills both await results" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := AwaitTaskCallWithAwaitedArgument(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(29)
    assert pending.Result == 29

    storedGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    stored := AwaitTaskCallWithAwaitedArgumentStored(storedGate.Task)
    assert !stored.IsCompleted
    storedGate.SetResult(31)
    assert stored.Result == 31
}

test "unary numeric negation accepts a call result after await" {
    gate := new TaskCompletionSource<double>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := NegateCallAfterAwait(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(3.5)
    assert pending.Result == -3.5
}

test "as expressions after an await preserve the matched value and null mismatch" {
    matchedGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    matched := SafeCastAfterAwait("matched", matchedGate.Task)
    assert !matched.IsCompleted
    matchedGate.SetResult()
    assert matched.Result == "matched"

    mismatchGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    mismatch := SafeCastAfterAwait(new object(), mismatchGate.Task)
    assert !mismatch.IsCompleted
    mismatchGate.SetResult()
    assert mismatch.Result == null
}

test "an async local inferred from an as expression supports a null condition" {
    castGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    cast := IsSafeCastNonNullAfterAwait(new AsyncService(2), castGate.Task)
    assert !cast.IsCompleted
    castGate.SetResult()
    assert cast.Result, "an inline cast to a source class must use reference equality"

    sourceGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    sourceValue := IsSourceReferenceNonNullAfterAwait(new AsyncService(1), sourceGate.Task)
    assert !sourceValue.IsCompleted
    sourceGate.SetResult()
    assert sourceValue.Result, "a source class without equality operators must use reference equality"

    directGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    direct := IsNonNullAfterAwait("present", directGate.Task)
    assert !direct.IsCompleted
    directGate.SetResult()
    assert direct.Result, "a hoisted non-null parameter must compare non-null"

    localGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    local := SafeCastLocalAfterAwait("matched", localGate.Task)
    assert !local.IsCompleted
    localGate.SetResult()
    assert local.Result == "matched", "a local initialized from as must preserve its cast value"

    matchedGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    matched := SafeCastConditionAfterAwait("matched", matchedGate.Task)
    assert !matched.IsCompleted
    matchedGate.SetResult()
    assert matched.Result, "a matching as result must compare non-null"

    mismatchGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    mismatch := SafeCastConditionAfterAwait(new object(), mismatchGate.Task)
    assert !mismatch.IsCompleted
    mismatchGate.SetResult()
    assert !mismatch.Result, "a failed as result must compare null"
}

test "async return branches complete the task or suspend on the live path" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    completed := ReturnAfterBranch(true, gate.Task)
    assert completed.IsCompletedSuccessfully
    assert completed.Result == 17

    pending := ReturnAfterBranch(false, gate.Task)
    assert !pending.IsCompleted
    gate.SetResult(23)
    assert pending.Result == 23
}

test "a bare return in a unit task branch completes without reaching the later await" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    completed := ReturnFromUnitBranch(true, gate.Task)
    assert completed.IsCompletedSuccessfully
    assert !gate.Task.IsCompleted

    pending := ReturnFromUnitBranch(false, gate.Task)
    assert !pending.IsCompleted
    gate.SetResult()
    pending.Wait()
    assert pending.IsCompletedSuccessfully
}

test "a generic async function has its own resumable state machine" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := GenericAwait(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("generic")
    assert pending.Result == "generic"
}

test "a generic async instance method resumes with its method type parameter" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericService()
    pending := service.Echo(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("generic method")
    assert pending.Result == "generic method"
}

test "an async method on a generic class hoists its closed receiver type" {
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<string>("generic owner")
    pending := service.GetAfter(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult()
    assert pending.Result == "generic owner"
}

test "a generic async method on a generic class carries both type parameter sets" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<int>(7)
    pending := service.Echo(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("combined generic owner and method")
    assert pending.AsTask().Result == "combined generic owner and method"
}

test "async locals and lambdas close over generic class and method owners" {
    localGate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    lambdaGate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    methodLambdaGate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<string>("class owner")
    local := service.ReadLocal(localGate.Task)
    lambda := service.ReadThroughLambda(lambdaGate.Task)
    methodLambda := service.ReadThroughMethodLambda(methodLambdaGate.Task)
    assert !local.IsCompleted && !lambda.IsCompleted && !methodLambda.IsCompleted

    localGate.SetResult("class owner local")
    lambdaGate.SetResult("class owner lambda")
    methodLambdaGate.SetResult("method owner lambda")
    assert local.Result == "class owner local"
    assert lambda.Result == "class owner lambda"
    assert methodLambda.Result == "method owner lambda"
}

test "async lambdas in generic class and method owners preserve value type parameters" {
    classLambdaGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    methodLambdaGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    genericLocalGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<int>(7)
    classLambda := service.ReadThroughLambda(classLambdaGate.Task)
    methodLambda := service.ReadThroughMethodLambda(methodLambdaGate.Task)
    genericLocal := service.ReadThroughGenericLocal(genericLocalGate.Task)
    assert !classLambda.IsCompleted && !methodLambda.IsCompleted && !genericLocal.IsCompleted

    classLambdaGate.SetResult(34)
    methodLambdaGate.SetResult(35)
    genericLocalGate.SetResult(36)
    assert classLambda.Result == 34
    assert methodLambda.Result == 35
    assert genericLocal.Result == 36
}

test "a generic async local closes over its generic class and method owners" {
    gate := new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously)
    service := new AsyncGenericContainer<string>("outer value")
    pending := service.ReadThroughGenericLocal(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult("inner value")
    assert pending.Result == "inner value"
}

test "both async calls reach their awaits before either task is released" {
    firstGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    secondGate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    started := new List<int>()
    first := TrackedValue(firstGate.Task, started, 1)
    second := TrackedValue(secondGate.Task, started, 2)

    assert started.Count == 2
    assert started[0] == 1 && started[1] == 2
    assert !first.IsCompleted && !second.IsCompleted

    secondGate.SetResult(20)
    firstGate.SetResult(10)
    assert first.Result == 11
    assert second.Result == 22
}

test "an incomplete await posts its continuation to the captured single-thread context" {
    context := new SingleThreadTestContext()
    gate := new TaskCompletionSource<int>()
    previous := SynchronizationContext.Current
    SynchronizationContext.SetSynchronizationContext(context)
    pending := ObserveContinuationContext(gate.Task, context)
    SynchronizationContext.SetSynchronizationContext(previous)

    assert !pending.IsCompleted
    gate.SetResult(1)
    context.PumpUntil(pending)
    assert pending.Result
}

test "exceptions before the first await fault the task instead of escaping the call" {
    expected := new InvalidOperationException("before first await")
    pending := ThrowBeforeFirstAwait(expected, true)
    assert pending.IsFaulted
    assert (must pending.Exception).InnerException == expected

    observedOriginal := false
    try {
        pending.GetAwaiter().GetResult()
    } catch error: InvalidOperationException {
        observedOriginal = error == expected
    }
    assert observedOriginal

    expectedNoThrow := ThrowBeforeFirstAwait(expected, false)
    assert expectedNoThrow.Result == 1
}

test "exceptions after an await fault the task with the original exception" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    expected := new InvalidOperationException("after await")
    pending := ThrowAfterAwait(gate.Task, expected)
    assert !pending.IsCompleted
    gate.SetResult(9)

    observed := false
    try {
        pending.GetAwaiter().GetResult()
    } catch error: InvalidOperationException {
        observed = error == expected
    }
    assert observed
}

test "an exception from an awaiting finally replaces the pending exception" {
    finallyGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    original := new InvalidOperationException("try body")
    replacement := new ApplicationException("finally body")
    pending := ThrowFromAwaitingFinally(Task.CompletedTask, finallyGate.Task, original, replacement)
    assert !pending.IsCompleted

    finallyGate.SetResult()
    observed := false
    try {
        pending.GetAwaiter().GetResult()
    } catch error: ApplicationException {
        observed = error == replacement
    }
    assert observed
    assert pending.IsFaulted
    assert (must pending.Exception).InnerException == replacement
}

test "a successful awaiting finally preserves the pending exception" {
    finallyGate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    original := new InvalidOperationException("try body")
    pending := ThrowThroughAwaitingFinally(Task.CompletedTask, finallyGate.Task, original)
    assert !pending.IsCompleted

    finallyGate.SetResult()
    observed := false
    try {
        pending.GetAwaiter().GetResult()
    } catch error: InvalidOperationException {
        observed = error == original
    }
    assert observed
    assert pending.IsFaulted
    assert (must pending.Exception).InnerException == original
}

test "cancellation while awaiting completes the returned task as canceled" {
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := PropagateCancellation(gate.Task)
    assert !pending.IsCompleted

    gate.SetCanceled()
    canceled := false
    try {
        pending.Wait()
    } catch error: AggregateException {
        canceled = pending.IsCanceled && error.InnerException is TaskCanceledException
    }
    assert canceled
}

test "an instance async method captures its class receiver across suspension" {
    service := new AsyncService(37)
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := service.ClassRead(gate.Task)
    assert !pending.IsCompleted
    service.Value = 39
    gate.SetResult()
    assert pending.Result == 39
}

test "an awaited assignment to an instance field resumes without retaining its receiver on the stack" {
    service := new AsyncService(37)
    gate := new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := service.ClassWrite(gate.Task)
    assert !pending.IsCompleted

    gate.SetResult(41)
    assert pending.Result == 41
    assert service.Value == 41
}

test "an instance async method copies its struct receiver across suspension" {
    counter := new AsyncCounter(53)
    gate := new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously)
    pending := counter.StructRead(gate.Task)
    assert !pending.IsCompleted
    counter.Value = 79
    gate.SetResult()
    assert pending.Result == 53
}

test "an async kickoff exposes its generated value-type state machine metadata" {
    facts := AsyncServiceAsyncMethodFacts()
    assert facts == "state=True, interface=True, generated=True, debugger=True, kickoffGetResult=False", "async machine facts: " + facts
}

test "generated async kickoffs do not block on GetResult" {
    assert AllAsyncKickoffsAvoidGetResult()
}

test "a synchronously completed await keeps the ValueTask fast path" {
    iterations := 10000
    for i := 0; i < 1000; i++ {
        NextValue(i).GetAwaiter().GetResult()
        TouchValue().GetAwaiter().GetResult()
        NextTask(i).GetAwaiter().GetResult()
    }

    before := GC.GetAllocatedBytesForCurrentThread()
    for i := 0; i < iterations; i++ {
        NextValue(i).GetAwaiter().GetResult()
        TouchValue().GetAwaiter().GetResult()
    }
    valueTaskBytes := GC.GetAllocatedBytesForCurrentThread() - before

    before = GC.GetAllocatedBytesForCurrentThread()
    for i := 0; i < iterations; i++ {
        NextTask(i).GetAwaiter().GetResult()
    }
    taskBytes := GC.GetAllocatedBytesForCurrentThread() - before

    // Fewer bytes than calls means no call allocated (the smallest object is 24 bytes); the Task
    // control shows the counter does see a per-call allocation when there is one.
    assert valueTaskBytes < iterations, "ValueTask async calls allocated " + valueTaskBytes.ToString() + " bytes"
    assert taskBytes >= iterations * 24, "Task async calls allocated only " + taskBytes.ToString() + " bytes"
}
