namespace NSharpLang.CensusEmitShapes.Tests


// A SAME-ARITY OVERLOAD SET DECLARED IN THIS PROJECT IS CHOSEN BY ITS ARGUMENTS, NOT BY DECLARATION
// ORDER.
//
// The emitter's STATIC user-call arm resolved by name and arity alone and took the first declaration
// it met, so `Sink.Accept([1, "b", null])` bound `Accept(int[])` and then declined at
// `emit.call.static-user-argument` — for a literal the analyzer had already target-typed at
// `object[]`. A COLLECTION EXPRESSION is the shape that shows it, because it has no type of its own
// to score with; what it does have is an answer to "can you be emitted at this parameter", which is
// the predicate the INSTANCE arm has always used to separate a same-arity set.
class Sink {
    static func Accept(values: int[]): string {
        return "int:" + values.Length.ToString()
    }

    static func Accept(values: object[]): string {
        return "object:" + values.Length.ToString()
    }

    func Take(values: int[]): string {
        return "int:" + values.Length.ToString()
    }

    func Take(values: object[]): string {
        return "object:" + values.Length.ToString()
    }
}

func MixedStatic(): string {
    return Sink.Accept([1, "b", null])
}

func TypedStatic(): string {
    return Sink.Accept([1, 2, 3])
}

func MixedInstance(sink: Sink): string {
    return sink.Take([1, "b", null])
}
