// Performance refactor — Unit 16: Result/error happy-path benchmarks.
//
// These benchmarks measure the N# Go-style (result, err) error-tuple pattern on both the
// success path (initializer never throws) and the failure path (initializer throws and the
// exception is captured into `err`). The strategy doc
// (docs/design/performance-compiler-refactor.md, "Error Handling And Exceptions") requires
// that the success path stays exception-free at runtime; these benchmarks let us measure the
// happy-path cost against the throwing failure path.
//
// Discovered by `nlc bench` (any function whose name starts with "bench").

import System

func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("Cannot divide by zero")
    }
    return a / b
}

// Success path: the initializer never throws, so `err` stays null and the catch is never
// entered. This should approach the cost of a plain method call plus a null check.
func benchResultErrorSuccessPath(): int {
    total := 0
    for i := 1; i <= 1000; i = i + 1 {
        value, err := Divide(i, 1)
        if err == null {
            total = total + value
        }
    }
    return total
}

// Failure path: the initializer throws on every iteration, exercising the exception-capture
// branch. This is the expensive path by design (a real CLR exception is thrown and unwound)
// and exists to contrast with the success-path benchmark above.
func benchResultErrorFailurePath(): int {
    failures := 0
    for i := 1; i <= 1000; i = i + 1 {
        value, err := Divide(i, 0)
        if err != null {
            failures = failures + 1
        }
    }
    return failures
}
