// Product-route fixture for external base and interface resolution. Each declaration is admitted
// only if ColumnarBaseTypePlanner classified the base/interface and emitted the exact TypeBuilder
// metadata; the gate builds this project with `nlc build` and verifies the emitted IL with ILVerify.

// External runtime base class with a public parameterless constructor.
class DocumentError: Exception {
    func Tag(): int {
        return 7
    }
}

// External abstract base whose only parameterless constructor is protected — the same shape as the
// generated Web API controller's ControllerBase. The synthesized default constructor chains to it.
class WeatherTag: Attribute {
    func Count(): int {
        return 3
    }
}

// External runtime interface implementation.
class ManagedResource: IDisposable {
    func Dispose() {
    }
}

// External base and external interface together.
class TrackedResource: Attribute, IDisposable {
    func Dispose() {
    }
}

class Widget {
    Size: int
}

// Source base plus an external interface.
class Gauge: Widget, IDisposable {
    func Dispose() {
    }
}
