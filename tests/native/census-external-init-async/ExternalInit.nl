namespace NSharpLang.CensusExternalInitAsync.Tests

import System.Diagnostics.Metrics
import System.Threading
import System.Threading.Tasks

// MeterOptions.Scope and InstrumentAdvice<T>.HistogramBucketBoundaries are framework members that
// are `init`-only, so every setter reference carries modreq(IsExternalInit).
func BuildSync(): int {
    meter := new MeterOptions("sync") { Scope: "a" }
    advice := new InstrumentAdvice<int> { HistogramBucketBoundaries: [1, 2, 3] }
    return (must advice.HistogramBucketBoundaries).Count * 10 + meter.Name.Length
}

async func BuildTwoInAsync(): int {
    meter := new MeterOptions("async") { Scope: "a" }
    advice := new InstrumentAdvice<int> { HistogramBucketBoundaries: [1, 2, 3] }
    await Task.Delay(1, CancellationToken.None)
    return (must advice.HistogramBucketBoundaries).Count * 10 + meter.Name.Length
}

async func BuildOneInAsync(): int {
    meter := new MeterOptions("one") { Scope: "a" }
    await Task.Yield()
    return meter.Name.Length
}

async func BuildSameTypeTwiceInAsync(): int {
    first := new MeterOptions("first") { Scope: "a" }
    second := new MeterOptions("second") { Scope: "b" }
    await Task.Yield()
    return first.Name.Length * 10 + second.Name.Length
}

async func BuildNestedInListInAsync(): int {
    list := [new MeterOptions("x") { Scope: "a" }, new MeterOptions("yy") { Scope: "b" }]
    advice := new InstrumentAdvice<int> { HistogramBucketBoundaries: [1, 2] }
    await Task.Yield()
    return list[1].Name.Length * 10 + (must advice.HistogramBucketBoundaries).Count
}
