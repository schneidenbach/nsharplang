namespace Census.FreeFunctionIdentity.Spread


// The other file of the same namespace. Every call here is to a camelCase declaration it does not
// itself declare — the analyzer accepted exactly this before the emitter did, which is the shape
// that declined at `emit.call.bare-unresolved`.
func DescribeAcross(value: int): string {
    return spreadHelper(value) + "/" + spreadLabel()
}

func SpreadGroup(): System.Func<string> {
    return spreadLabel
}
