namespace NSharpLang.Cli

import System.Collections.Generic

func NativeRun(outcomeRanks: int[], outcomeCount: int): NativeTestRun {
    return new NativeTestRun(new List<NativeTestResult>(), outcomeRanks, outcomeCount)
}

test "native test summaries reject empty discovery" {
    summary := TestCommandKernels.SummarizeNativeTestRun(NativeRun(new int[](0), 0))

    assert !summary.Ok
    assert summary.Total == 0
    assert summary.Passed == 0
    assert summary.Failed == 0
    assert summary.Skipped == 0
}

test "native test summaries accept a nonempty successful run" {
    outcomes := new int[](2)
    outcomes[0] = TestCommandKernels.GetNativeTestOutcomeRank("passed")
    outcomes[1] = TestCommandKernels.GetNativeTestOutcomeRank("skipped")

    summary := TestCommandKernels.SummarizeNativeTestRun(NativeRun(outcomes, outcomes.Length))

    assert summary.Ok
    assert summary.Total == 2
    assert summary.Passed == 1
    assert summary.Failed == 0
    assert summary.Skipped == 1
}
