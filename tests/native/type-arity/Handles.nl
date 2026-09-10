namespace Example


// The namespace-qualified form of the same pair. `Handle<T>: Example.Handle` names its non-generic
// sibling through the namespace and is not a cycle; the emitted full names are `Example.Handle` and
// ``Example.Handle`1``.
class Handle {
}

class Handle<T>: Example.Handle {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

// The RETURN type is written unqualified on purpose. A namespace-qualified type reference and the
// bare one currently resolve to two different TypeInfo instances, so `func M(): Example.Handle`
// returning a subclass reports NL202 — for a non-generic subclass too, so it is not an arity defect
// and is not this project's subject. The BASE clause above is the qualified reference this project
// does pin.
func MakeHandle(): Handle {
    return new Handle<string>("h")
}
