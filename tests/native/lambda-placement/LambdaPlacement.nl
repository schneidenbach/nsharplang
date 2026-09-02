namespace NSharpLang.LambdaPlacement.Tests

import System.Collections.Generic
import System.Linq

// A reference type whose instance-method lambdas exercise both N#-owned non-capturing placements:
//   * a body that touches only its own parameters becomes an assembly-static method on the program type,
//     which is ldftn'd cross-type from this instance method (assembly visibility keeps that verifiable);
//   * a body that reaches the enclosing chain becomes a private instance method on this type, bound to
//     the current instance.
class Accumulator {
    seed: int

    constructor(start: int) {
        seed = start
    }

    func Increment(x: int): int {
        return x + seed
    }

    // No captures, no `this`: an assembly-static program method, ldftn'd cross-type from this instance
    // method.
    func DoubleAll(values: List<int>): List<int> {
        return values.Select(v => v * 2).ToList()
    }

    // this-capture: the lambda calls the bare instance method `Increment`, which resolves on the enclosing
    // chain, so it binds to the current instance as a private instance method on Accumulator.
    func OffsetAll(values: List<int>): List<int> {
        return values.Select(v => Increment(v)).ToList()
    }

    // A this-capture lambda held in a delegate local so a test can reflect on its exact placement and
    // invoke it. The returned string is "IsPrivate|IsStatic|DeclaringType|Invoke(5)".
    func InspectThisCapturePlacement(): string {
        adder: Func<int, int> = v => Increment(v)
        method := adder.get_Method()
        return method.get_IsPrivate().ToString() + "|" + method.get_IsStatic().ToString() + "|" + method.get_DeclaringType().get_Name() + "|" + adder(5).ToString()
    }

    // Two lambdas in one body: each gets a distinct generated identity and both run.
    func Bounds(values: List<int>): (int, int) {
        lowest := values.Select(v => v - 1).Min()
        highest := values.Select(v => v + 1).Max()
        return (lowest, highest)
    }
}

// A second reference type. The static lambda written in its method also lands on the shared program type,
// so the program-static placement is proven across more than one owning type.
class Scaler {
    func TripleAll(values: List<int>): List<int> {
        return values.Select(v => v * 3).ToList()
    }
}

// A captured-parameter lambda routes through the fenced C# display-class residual (a value capture, not
// N#-owned yet). It is included so the residual is proven unregressed alongside the N#-owned placements.
class Filter {
    func AtLeast(threshold: int, values: List<int>): List<int> {
        return values.Where(v => v >= threshold).ToList()
    }
}
