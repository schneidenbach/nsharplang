namespace Example

import System.Collections.Generic


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

// THE TWO SPELLINGS ARE ONE IDENTITY. `Example.Handle` used to fall out of the bottom of the
// analyzer's resolution walk as a SECOND type instance beside the one `Handle` resolves to, so a
// value the bare spelling accepted was NL202 against the qualified one — for a non-generic subclass
// as much as for a generic one, so it was never an arity defect. Both spellings are written below,
// in every position a type reference can stand: a return type, a parameter, a local, a cast, an `is`
// test, a generic argument and (above) a base list.
func MakeHandle(): Handle {
    return new Handle<string>("h")
}

func MakeQualifiedHandle(): Example.Handle {
    return new Handle<string>("q")
}

func MakeQualifiedGenericHandle(): Example.Handle<string> {
    return new Handle<string>("g")
}

func QualifiedRoundTrip(handle: Example.Handle): string {
    local: Example.Handle = handle
    if !(local is Example.Handle) {
        return "not-a-handle"
    }

    generic: Example.Handle<string> = MakeQualifiedGenericHandle()
    return generic.Value
}

func QualifiedHandleList(): List<Example.Handle> {
    handles := new List<Example.Handle>()
    handles.Add(new Handle<string>("in-list"))
    return handles
}
