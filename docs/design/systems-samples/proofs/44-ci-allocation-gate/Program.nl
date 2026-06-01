namespace SystemsProofs.CiAllocationGate

import System

[hot]
[alloc(none)]
func Sum(values: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < values.Length; i++ {
        total = total + values[i]
    }
    return total
}

[boundary]
func Main() {
    values := alloc new int[] { 1, 2, 3 }
    print Sum(values)
}

// CI proof command:
// nlc check --systems-report
// nlc build --perf-report
