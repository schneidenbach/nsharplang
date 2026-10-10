namespace Census.FreeFunctionIdentity.Holder


// A USER TYPE NAMED `Program` BESIDE FREE FUNCTIONS.
//
// This is the shape `examples/02-variables-and-types`, `examples/03-functions` and
// `examples/06-classes-and-records` are written in, and it compiled and ran before free functions
// were keyed by namespace. The holder yields the name rather than fighting for it: this type stays
// `Census.FreeFunctionIdentity.Holder.Program` and the free functions below go to
// `Census.FreeFunctionIdentity.Holder.<Program>`, a spelling no source can claim.
class Program {
    Value: int

    constructor(value: int) {
        Value = value
    }

    func Doubled(): int {
        return Value * 2
    }
}

func MakeProgram(value: int): Program {
    return new Program(value)
}

func HolderHelper(): string {
    return "holder"
}

func UseHolderHelper(): string {
    return HolderHelper()
}
