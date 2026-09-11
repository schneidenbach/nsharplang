namespace SystemsProofs.HotLinqPipeline

import System

[hot]
func SumPositive(this values: ReadOnlySpan<int>): long {
    sum := 0L
    for i := 0; i < values.Length; i++ {
        x := values[i]
        if x > 0 {
            sum = sum + x
        }
    }
    return sum
}

[hot]
func Score(values: ReadOnlySpan<int>): long {
    return values.SumPositive()
}

[boundary]
func Main(): int {
    values := alloc new int[3]
    values[0] = -1
    values[1] = 5
    values[2] = 7

    score := Score(values)
    if score != 12L {
        return 1
    }
    return 0
}
