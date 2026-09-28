namespace NSharpLang.CensusFlowRules.Tests


// A loop's condition-true null facts apply in its body. A body assignment ends that fact only after
// the assignment has evaluated, so a read on the right hand side still sees the narrowed value.
func WhileBodyNarrowing(start: int?): int {
    total := 0
    n := start
    while n != null {
        total = total + n
        n = PreviousOrNone(n)
    }
    return total
}

func ForBodyNarrowing(start: int?): int {
    total := 0
    n := start
    for i := 0; n != null; i = i + 1 {
        total = total + n
        n = PreviousOrNone(n)
    }
    return total
}

// A write on the branch that continues must not poison the facts on the other path. The odd path
// reads n after the if and then writes it; the even path writes n and continues before that read.
func WhileContinueBeforeWrite(start: int?): int {
    total := 0
    n := start
    while n != null {
        if n % 2 == 0 {
            n = PreviousOrNone(n)
            continue
        }
        total = total + n
        n = PreviousOrNone(n)
    }
    return total
}

func ForContinueBeforeWrite(start: int?): int {
    total := 0
    n := start
    for i := 0; n != null; i = i + 1 {
        if n % 2 == 0 {
            n = PreviousOrNone(n)
            continue
        }
        total = total + n
        n = PreviousOrNone(n)
    }
    return total
}
