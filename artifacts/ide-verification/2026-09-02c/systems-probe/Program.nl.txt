namespace SystemsProofs.HotMetrics

struct Metrics {
    packets: long
    errors: long
}

[hot]
func RecordPacket(metrics: &Metrics) {
    Interlocked.Increment(ref metrics.packets)
}

[hot]
func RecordError(metrics: &Metrics) {
    Interlocked.Increment(ref metrics.errors)
}

[trusted(reason: "probe: nothing unsafe happens here", owner: "ide-verification")]
func Audit(metrics: Metrics): long {
    return metrics.packets + metrics.errors
}

[boundary]
func Export(metrics: Metrics): string {
    if metrics.packets < 0 {
        return alloc "invalid packets"
    }
    if metrics.errors < 0 {
        return alloc "invalid errors"
    }
    return alloc "metrics ok"
}

func Main() {
    metrics := new Metrics { packets: 0, errors: 0 }
    RecordPacket(ref metrics)
    print Export(metrics)
}
