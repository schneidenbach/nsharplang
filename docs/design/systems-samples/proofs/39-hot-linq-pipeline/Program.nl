namespace SystemsProofs.HotLinqPipeline

import System

[hotLinq]
extension ReadOnlySpan<int> {
    func SumPositive(): long {
        sum := 0L
        for i := 0; i < self.Length; i++ {
            x := self[i]
            if x > 0 {
                sum = sum + x
            }
        }
        return sum
    }
}

[hot]
func Score(values: ReadOnlySpan<int>): long {
    return values.SumPositive()
}

func Main() {
    values := new int[] { -1, 5, 7 }
    print Score(values)
}
