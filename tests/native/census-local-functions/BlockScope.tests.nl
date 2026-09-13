namespace NSharpLang.CensusLocalFunctions.Tests

import System.Reflection


// RUNTIME contracts for a local function being visible in its whole block.
//
// Each of these compiled to NL412 "Function 'x' not found" before the rule landed, so the fact that
// the assembly exists at all is half the contract; the other half is that the emitted IL computes
// the right answer, which is what forward calls and mutual recursion could get wrong in a way an
// analyzer-only test could not see.
test "two local functions that call each other both resolve and both run" {
    assert IsEven(0)
    assert !IsEven(1)
    assert IsEven(10)
    assert !IsEven(7)
}

test "a call written above the declaration calls the same function the later call does" {
    // 21 doubled is 42, plus `doubler(1)` written BELOW the declaration.
    assert DoubleThenAdd(21) == 44
    assert DoubleThenAdd(0) == 2
}

test "a body whose FIRST statement calls a local function declared last" {
    assert FirstStatementCallsLast(41) == 42
}

test "a three-way cycle closes through a function no declaration order could reach backwards" {
    assert RotateDown(0) == 0
    assert RotateDown(1) == 1
    assert RotateDown(7) == 7
}

test "self-recursion is untouched by the block rule" {
    assert Factorial(1) == 1
    assert Factorial(5) == 120
}

test "a nested block sees a local function the enclosing block declares below it" {
    assert ClassifyFromNestedBlock(6) == 42
    assert ClassifyFromNestedBlock(0 - 6) == 42
}

test "a loop body calls a local function declared after the loop" {
    // 0*3 + 1*3 + 2*3 + 3*3
    assert SumScaled(4) == 18
    assert SumScaled(0) == 0
}

test "a local function declared BELOW the return that calls it is not dead code" {
    // The declaration is not a statement that runs in the enclosing list, so the unreachable rule
    // skips it — exactly as C# does — while an ordinary statement there would still be reported.
    assert FirstStatementCallsLast(0) == 1
}
