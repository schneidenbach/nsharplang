namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import System.Threading.Tasks


// "MORE SPECIFIC PARAMETER TYPES" — THE TIE-BREAK THAT READS THE SIGNATURES AS WRITTEN.
//
// `Task.Run(() => Task.FromResult(11))` answered `Task<Task<int>>`, and every rule the resolver had
// agreed that it should: `Task.Run<TResult>(Func<TResult>)` and `Task.Run<TResult>(Func<Task<TResult>>)`
// BOTH close to `Func<Task<int>>` for this lambda, score the same, expand no params tail and default
// no parameter. C# separates them with two rules N# did not have:
//
//   * §12.6.4.4, "better conversion from expression": the delegate the lambda EXACTLY matches beats
//     one it merely converts to, which is how `Task.Run(Func<Task>)` — a perfectly good target for a
//     lambda that hands back a `Task<int>` — loses.
//   * §12.6.4.3's last tie-break, "more specific parameter types": read UNINSTANTIATED,
//     `Func<Task<TResult>>` says more than `Func<TResult>`, so it is the better member.
//
// Both answers are RUNTIME facts here, not just typing ones: each call is awaited and its result read.
func NestedTaskRun(): Task<int> {
    return Task.Run(() => Task.FromResult(11))
}

func ValueTaskRun(): Task<int> {
    return Task.Run(() => 11)
}

// A lambda that hands back a UNIT task takes the `Func<Task>` overload, which is the case that keeps
// the rule honest: the delegate it exactly matches is the non-generic one, and the answer is `Task`
// rather than `Task<Task>`.
func UnitTaskRun(): Task {
    return Task.Run(() => Task.CompletedTask)
}

// A statement body has no value to hand back, so `Action` is the delegate it matches and the result
// is the plain `Task` that overload returns.
func ActionTaskRun(sink: List<int>): Task {
    return Task.Run(() => {
        sink.Add(7)
    })
}

// AN `async` LAMBDA ANSWERS A TASK OF WHAT ITS BODY GAVE, and the overload that keeps that result is
// the one the same two rules pick: `Func<Task<TResult>>` over `Func<TResult>` (which would answer
// `Task<Task<int>>`) and over `Func<Task>` (which would throw the `int` away).
func AsyncValueTaskRun(): Task<int> {
    return Task.Run(async () => 11)
}

func AwaitedAsyncValueTaskRun(): int {
    task := AsyncValueTaskRun()
    task.Wait()
    return task.Result
}

func AwaitedNestedTaskRun(): int {
    task := NestedTaskRun()
    task.Wait()
    return task.Result
}

func AwaitedValueTaskRun(): int {
    task := ValueTaskRun()
    task.Wait()
    return task.Result
}
