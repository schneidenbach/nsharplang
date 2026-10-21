namespace NSharpLang.MemberLookup.Tests

import System
import System.Collections.Generic
import System.Linq

// EXTENSION METHODS ARE CANDIDATES WHEN NO INSTANCE METHOD OF THE NAME IS APPLICABLE (GitHub #236;
// C# §12.8.10.2). Member lookup answered with the receiver's instance methods alone, so the
// extension overloads were never considered and the call was NL402.
func instanceByLambdaShape(values: List<int>): int => values.FindAll(value => value > 15).Count

class DelegateTarget {
    Last: string = ""

    func M(callback: Func<int, int>): string => "instance:" + callback(41).ToString()
}

class LambdaCandidateTarget {
    func Choose(value: string): string => "string:" + value

    func Choose(value: Func<int>): string => "delegate:" + value().ToString()
}

func lambdaCandidateRejectsNonDelegate(): string => new LambdaCandidateTarget().Choose(() => 73)

// Keep the extension declarations in this project so the repro does not depend on ASP.NET or a
// C# fixture. The first overload is the Action-shaped extension selected by the typed string lambda;
// the second has the same delegate signature as the instance and must lose when that instance fits.
func M(this target: DelegateTarget, callback: Action<string>): string {
    target.Last = "extension"
    callback(target.Last)
    return target.Last
}

func M(this target: DelegateTarget, callback: Func<int, int>): string {
    return target.Last + ":extension-func:" + callback(41).ToString()
}

// A referenced extension: `List<int>` declares an instance `Contains(int)`, and
// `Enumerable.Contains(source, value, comparer)` is the only overload that takes a comparer.
func comparerExtension(values: List<int>): bool => values.Contains(20, EqualityComparer<int>.Default)

func comparerExtensionMissing(values: List<int>): bool => values.Contains(99, EqualityComparer<int>.Default)

func instanceContains(values: List<int>): bool => values.Contains(20)

func instanceByDelegate(values: List<int>): int => values.Find(value => value > 15)

// SAME-NAMED INSTANCE AND EXTENSION METHODS WITH DIFFERENT DELEGATE SHAPES (GitHub #236).
// The instance candidate is `M(Func<int, int>)`; a typed string lambda rejects it and selects the
// receiver-style `M(this DelegateTarget, Action<string>)` extension.
func delegateInstanceCall(target: DelegateTarget): string => target.M(value => value + 1)

func delegateExtensionCall(target: DelegateTarget): string {
    selected := target.M((text: string) => { })
    return selected + ":" + target.Last
}
