namespace NSharpLang.CensusFlowRules.Tests


// A `for` LOOP'S UPDATE CLAUSE READS WHAT ITS CONDITION PROVED.
//
// The update runs after the body and only ever with the condition true, so `d = d.BaseDef` under
// `d != null` dereferences a `d` the condition proved -- as long as the body cannot write `d`, because
// a `continue` taken before such a write reaches the update with the write still ahead of it. The
// compiler's own base-chain walks are this shape, and until the update was narrowed they had to step
// with `d?.BaseDef`. A `Nullable<T>` the condition proved is read as its `T` there too, by the analyzer
// and by the emitter alike.
class ChainDef {
    Name: string
    BaseDef: ChainDef?

    constructor(name: string, baseDef: ChainDef?) {
        Name = name
        BaseDef = baseDef
    }
}

func ChainNameLength(start: ChainDef?): int {
    count := 0
    for d := start; d != null; d = d.BaseDef {
        count = count + d.Name.Length
    }
    return count
}

func PreviousOrNone(n: int): int? {
    if n <= 0 {
        return null
    }
    return n - 1
}

func CountDownSteps(start: int?): int {
    steps := 0
    for n := start; n != null; n = PreviousOrNone(n) {
        steps = steps + 1
    }
    return steps
}

// A conjunction proves its null test, and the counter beside it reads the narrowed value.
func BoundedSteps(start: int?, limit: int): int {
    steps := 0
    n := start
    for i := 0; n != null && i < limit; i = i + n {
        steps = steps + 1
    }
    return steps
}
