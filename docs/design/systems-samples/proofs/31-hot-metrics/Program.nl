namespace SystemsProofs.HotMetrics

import System
import System.Threading

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

[boundary]
func Export(metrics: Metrics): string {
    return alloc $"packets={metrics.packets} errors={metrics.errors}"
}

func Main() {
    metrics := Metrics { packets: 0, errors: 0 }
    RecordPacket(ref metrics)
    print Export(metrics)
}
