namespace NSharpLang.SystemsVectorizationFacts.Tests


// RUNNING A KERNEL AND NAMING WHAT IT THREW.
//
// `IlShape` answers what the emitted code IS; this answers what it DOES at the edges. The deleted suite
// pinned three out-of-range behaviours per shape — a bound past the end of the array, a negative start, and
// an empty or inverted range — because the SIMD helpers take the loop's `[start, bound)` unchanged and must
// reproduce the scalar loop's exception rather than the `Vector<T>` constructor's different one. Those
// assertions went through xUnit's `Assert.Throws<TargetInvocationException>` plus an `IsType` on the inner
// exception, because the deleted tests invoked through reflection. Here the kernels are called directly, so
// the thrown type is read off the first line of `ToString()`.
class KernelRuns {

    // The full name of the exception `kernel` threw, or "no-exception".
    static func ThrownTypeOf(kernel: Func<int>): string {
        try {
            kernel()
        } catch e: Exception {
            text := e.ToString()
            stop := text.IndexOf(":")
            if stop < 0 {
                return text
            }

            return text.Substring(0, stop)
        }

        return "no-exception"
    }
}
