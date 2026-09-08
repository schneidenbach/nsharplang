namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections

class ConstructorChainExpressionRecorder {
    Events: string

    constructor() {
        Events = ""
    }

    func Add(label: string) {
        if Events.Length > 0 {
            Events = Events + ","
        }
        Events = Events + label
    }
}

class ConstructorChainExpressionBase<T> {
    Value: T

    constructor(recorder: ConstructorChainExpressionRecorder, first: string, value: T, suffix: string? = null) {
        recorder.Add("base")
        Value = value
    }
}

class ConstructorChainExpressionDerived: ConstructorChainExpressionBase<int> {
    constructor(recorder: ConstructorChainExpressionRecorder, seed: int): base(recorder, MarkText(recorder, "first", "alpha"), Build(recorder, seed), null) {
        recorder.Add("body")
    }

    private static func MarkText(recorder: ConstructorChainExpressionRecorder, label: string, value: string): string {
        recorder.Add(label)
        return value
    }

    private static func Build(recorder: ConstructorChainExpressionRecorder, seed: int): int {
        recorder.Add("second")
        return seed + 1
    }
}

class ConstructorChainExpressionSelf {
    Value: int

    constructor(recorder: ConstructorChainExpressionRecorder, seed: int): this(recorder, Build(recorder, seed)) {
        recorder.Add("delegating")
    }

    constructor(recorder: ConstructorChainExpressionRecorder, value: int, suffix: string? = null) {
        recorder.Add("target")
        Value = value
    }

    private static func Build(recorder: ConstructorChainExpressionRecorder, seed: int): int {
        recorder.Add("self-argument")
        return seed + 2
    }
}

class ConstructorChainExpressionOptions {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

class ConstructorChainExpressionCollisionBase {
    Seen: int

    constructor(value: int) {
        Seen = value
    }
}

class ConstructorChainExpressionCollision: ConstructorChainExpressionCollisionBase {
    Value: int

    constructor(baseOptions: ConstructorChainExpressionOptions): base(baseOptions.Value) {
        Value = 1
    }
}

class ConstructorChainExpressionStaticBase {
    Seen: int

    constructor(value: int) {
        Seen = value
    }
}

class ConstructorChainExpressionStatic: ConstructorChainExpressionStaticBase {
    private static Seed: int = 17

    constructor(): base(Seed) {
    }
}

class ConstructorChainExpressionThrowBase {
    constructor(recorder: ConstructorChainExpressionRecorder, first: string, second: string) {
        recorder.Add("throw-target")
    }
}

class ConstructorChainExpressionThrowDerived: ConstructorChainExpressionThrowBase {
    constructor(recorder: ConstructorChainExpressionRecorder): base(recorder, MarkText(recorder, "throw-first", "alpha"), FailBeforeTarget(recorder)) {
        recorder.Add("throw-body")
    }

    private static func MarkText(recorder: ConstructorChainExpressionRecorder, label: string, value: string): string {
        recorder.Add(label)
        return value
    }

    private static func FailBeforeTarget(recorder: ConstructorChainExpressionRecorder): string {
        recorder.Add("throw-second")
        throw new InvalidOperationException("chain argument failure")
    }
}

func ConstructorChainExpressionEmitOutcome(source: string): string {
    attempt := ColumnarInputBuilderInvokeSingle(source)
    if !attempt.Succeeded || attempt.Program == null {
        throw new InvalidOperationException("Constructor-chain control did not parse: " + source)
    }

    arguments := new object?[](7)
    ColumnarIlEmitterPut(arguments, 0, "ConstructorChainExpressionControl")
    ColumnarIlEmitterPut(arguments, 1, "Program")
    ColumnarIlEmitterPut(arguments, 2, attempt.Program)
    ColumnarIlEmitterPut(arguments, 3, false)
    ColumnarIlEmitterPut(arguments, 4, null)
    ColumnarIlEmitterPut(arguments, 5, null)
    ColumnarIlEmitterPut(arguments, 6, null)

    ColumnarInputBuilderTraceReset()
    emitted := Convert.ToBoolean(ColumnarIlEmitterPublicMethod("TryEmitColumnarAssembly", 7).Invoke(null, arguments))
    snapshot := ColumnarInputBuilderTraceSnapshot()
    ColumnarInputBuilderTraceReset()
    if emitted {
        return "success"
    }
    if snapshot.Count == 0 {
        return "false without decline"
    }
    first := ColumnarInputBuilderRequiredItem(snapshot, 0)
    return ColumnarInputBuilderText(first, "SiteId") + "|" + ColumnarInputBuilderText(first, "MemberName")
}

func ConstructorChainExpressionParseOutcome(source: string): string {
    ColumnarInputBuilderTraceReset()
    attempt := ColumnarInputBuilderInvokeSingle(source)
    snapshot := ColumnarInputBuilderTraceSnapshot()
    ColumnarInputBuilderTraceReset()
    if attempt.Succeeded {
        return "success"
    }
    if snapshot.Count == 0 {
        return "false without decline"
    }
    first := ColumnarInputBuilderRequiredItem(snapshot, 0)
    return ColumnarInputBuilderText(first, "SiteId")
}

test "constructor chain expressions retain ordered evaluation defaults self exclusion and closed generic rebinding" {
    recorder := new ConstructorChainExpressionRecorder()
    derived := new ConstructorChainExpressionDerived(recorder, 4)
    assert derived.Value == 5
    assert recorder.Events == "first,second,base,body", recorder.Events

    selfRecorder := new ConstructorChainExpressionRecorder()
    chained := new ConstructorChainExpressionSelf(selfRecorder, 7)
    assert chained.Value == 9
    assert selfRecorder.Events == "self-argument,target,delegating", selfRecorder.Events

    collision := new ConstructorChainExpressionCollision(new ConstructorChainExpressionOptions(11))
    assert collision.Seen == 11
    assert collision.Value == 1

    staticValue := new ConstructorChainExpressionStatic()
    assert staticValue.Seen == 17
}

test "constructor chain argument exceptions occur before the target constructor body" {
    recorder := new ConstructorChainExpressionRecorder()
    failure: InvalidOperationException? = null
    try {
        ignored := new ConstructorChainExpressionThrowDerived(recorder)
        _ = ignored
    } catch error: InvalidOperationException {
        failure = error
    }
    if failure == null {
        throw new InvalidOperationException("The constructor-chain argument did not throw")
    }
    assert failure.Message == "chain argument failure"
    assert recorder.Events == "throw-first,throw-second", recorder.Events
}

test "constructor chain emission rejects ambiguous targets and pre-chain current-instance access" {
    ambiguous := "class ChainAmbiguousBase {\n    constructor(value: string) {}\n    constructor(value: object) {}\n}\nclass ChainAmbiguousDerived: ChainAmbiguousBase {\n    constructor(): base(null) {}\n}\n"
    assert ConstructorChainExpressionEmitOutcome(ambiguous) == "emit.ctor.chain-target|ChainAmbiguousDerived.constructor"

    wrongArgument := "class ChainWrongBase { constructor(value: int) {} }\nclass ChainWrongDerived: ChainWrongBase {\n    constructor(): base(\"wrong\") {}\n}\n"
    assert ConstructorChainExpressionEmitOutcome(wrongArgument) == "emit.ctor.chain-argument|ChainWrongDerived.constructor"

    explicitThis := "class ChainThisBase { constructor(value: int) {} }\nclass ChainThisDerived: ChainThisBase {\n    Value: int\n    constructor(): base(this.Value) {}\n}\n"
    assert ConstructorChainExpressionEmitOutcome(explicitThis) == "emit.ctor.chain-instance|ChainThisDerived.constructor"

    explicitBase := "class ChainExplicitBase {\n    Value: int\n    constructor(value: int) { Value = value }\n}\nclass ChainExplicitBaseDerived: ChainExplicitBase {\n    constructor(): base(base.Value) {}\n}\n"
    assert ConstructorChainExpressionParseOutcome(explicitBase) == "parse.struct"

    implicitField := "class ChainFieldBase { constructor(value: int) {} }\nclass ChainFieldDerived: ChainFieldBase {\n    Value: int\n    constructor(): base(Value) {}\n}\n"
    assert ConstructorChainExpressionEmitOutcome(implicitField) == "emit.ctor.chain-instance|ChainFieldDerived.constructor"

    instanceCall := "class ChainCallBase { constructor(value: int) {} }\nclass ChainCallDerived: ChainCallBase {\n    constructor(): base(Read()) {}\n    private func Read(): int { return 1 }\n}\n"
    assert ConstructorChainExpressionEmitOutcome(instanceCall) == "emit.ctor.chain-instance|ChainCallDerived.constructor"

    bareThis := "class ChainBareThis {\n    constructor(value: object) {}\n    constructor(): this(this) {}\n}\n"
    assert ConstructorChainExpressionParseOutcome(bareThis) == "parse.struct"

    bareBase := "class ChainBareBase { constructor(value: object) {} }\nclass ChainBareBaseDerived: ChainBareBase {\n    constructor(): base(base) {}\n}\n"
    assert ConstructorChainExpressionParseOutcome(bareBase) == "parse.struct"
}
