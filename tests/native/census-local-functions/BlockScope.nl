namespace NSharpLang.CensusLocalFunctions.Tests

// THE SOURCE SHAPES THE BLOCK-SCOPING RULE MAKES LEGAL, compiled and RUN by the tip compiler.
//
// A local function's name is in scope throughout the block that declares it, so a call may be
// written above the declaration and two local functions may call EACH OTHER. Before that rule these
// were NL412 "Function 'x' not found" — mutual recursion could not be written at all, because
// whichever of the pair came first could not see the other.
//
// Every function here is exercised from `BlockScope.tests.nl`, so the assertions are about what the
// emitted IL actually computes rather than about what the analyzer accepted.

// MUTUAL RECURSION. `even` calls `odd`, which is declared below it.
func IsEven(n: int): bool {
    func even(x: int): bool {
        if x == 0 {
            return true
        }

        return odd(x - 1)
    }

    func odd(x: int): bool {
        if x == 0 {
            return false
        }

        return even(x - 1)
    }

    return even(n)
}

// A FORWARD CALL FROM AN ORDINARY STATEMENT, above the declaration it names.
func DoubleThenAdd(n: int): int {
    doubled := doubler(n)
    func doubler(x: int): int {
        return x * 2
    }

    return doubled + doubler(1)
}

// A FORWARD CALL THAT IS THE BODY'S FIRST STATEMENT, with the declaration last.
func FirstStatementCallsLast(n: int): int {
    return describe(n)
    func describe(x: int): int {
        return x + 1
    }
}

// THREE-WAY MUTUAL RECURSION — the cycle closes through a function declared between the other two,
// so no single declaration order makes all three backward calls.
func RotateDown(n: int): int {
    func first(x: int): int {
        if x <= 0 {
            return 0
        }

        return 1 + second(x - 1)
    }

    func second(x: int): int {
        if x <= 0 {
            return 0
        }

        return 1 + third(x - 1)
    }

    func third(x: int): int {
        if x <= 0 {
            return 0
        }

        return 1 + first(x - 1)
    }

    return first(n)
}

// SELF-RECURSION still works: the name was already in scope inside its own body before this rule and
// it still is.
func Factorial(n: int): int {
    func fact(x: int): int {
        if x <= 1 {
            return 1
        }

        return x * fact(x - 1)
    }

    return fact(n)
}

// A NESTED BLOCK SEES THE ENCLOSING BLOCK'S LOCAL FUNCTIONS, including one declared BELOW the
// nested block — the name is bound for the whole enclosing block, and an inner block is part of it.
func ClassifyFromNestedBlock(n: int): int {
    if n > 0 {
        return scale(n)
    }

    func scale(x: int): int {
        return x * 7
    }

    return scale(0 - n)
}

// A LOCAL FUNCTION CALLED FROM INSIDE A LOOP BODY that is declared after the loop.
func SumScaled(n: int): int {
    total := 0
    for i := 0; i < n; i++ {
        total = total + scale(i)
    }

    func scale(x: int): int {
        return x * 3
    }

    return total
}
