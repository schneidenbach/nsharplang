namespace NSharpLang.CensusPipelines.Tests

test "a Pipe constructs with its options and hands out both halves" {
    assert Pipelines.ConstructedWithOptions() == "reader:writer"
}

test "a static read off PipeScheduler answers the framework's own instance" {
    assert Pipelines.InlineSchedulerIsTheSameInstance()
}

test "bytes written into the pipe come back out of its reader" {
    assert Pipelines.RoundTrip("census").Result == "census"
    assert Pipelines.RoundTrip("").Result == ""
}
