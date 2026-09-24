namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

class ColumnarReductionShape {
    AccumulatorNode: int
    ArrayNode: int
    IndexNode: int
    BoundNode: int
    Accumulator: string
    Array: string
    Index: string
    ElementType: Type
    Helper: MethodInfo

    constructor(accumulatorNode: int, arrayNode: int, indexNode: int, boundNode: int, accumulator: string, array: string, index: string, elementType: Type, helper: MethodInfo) {
        AccumulatorNode = accumulatorNode
        ArrayNode = arrayNode
        IndexNode = indexNode
        BoundNode = boundNode
        Accumulator = accumulator
        Array = array
        Index = index
        ElementType = elementType
        Helper = helper
    }
}

class ColumnarRangeCountShape {
    CounterNode: int
    ArrayNode: int
    IndexNode: int
    BoundNode: int
    LoNode: int
    HiNode: int
    Counter: string
    Index: string

    constructor(counterNode: int, arrayNode: int, indexNode: int, boundNode: int, loNode: int, hiNode: int, counter: string, index: string) {
        CounterNode = counterNode
        ArrayNode = arrayNode
        IndexNode = indexNode
        BoundNode = boundNode
        LoNode = loNode
        HiNode = hiNode
        Counter = counter
        Index = index
    }
}

class ColumnarMinMaxReduction {
    AccumulatorNode: int
    Accumulator: string
    IsMin: bool

    constructor(accumulatorNode: int, accumulator: string, isMin: bool) {
        AccumulatorNode = accumulatorNode
        Accumulator = accumulator
        IsMin = isMin
    }
}

class ColumnarMinMaxShape {
    ArrayNode: int
    IndexNode: int
    BoundNode: int
    Index: string
    Reductions: IReadOnlyList<ColumnarMinMaxReduction>

    constructor(arrayNode: int, indexNode: int, boundNode: int, index: string, reductions: IReadOnlyList<ColumnarMinMaxReduction>) {
        ArrayNode = arrayNode
        IndexNode = indexNode
        BoundNode = boundNode
        Index = index
        Reductions = reductions
    }
}

class ColumnarCountTransitionsShape {
    CounterNode: int
    ArrayNode: int
    IndexNode: int
    PreviousNode: int
    BoundNode: int
    Counter: string
    Index: string
    Previous: string

    constructor(counterNode: int, arrayNode: int, indexNode: int, previousNode: int, boundNode: int, counter: string, index: string, previous: string) {
        CounterNode = counterNode
        ArrayNode = arrayNode
        IndexNode = indexNode
        PreviousNode = previousNode
        BoundNode = boundNode
        Counter = counter
        Index = index
        Previous = previous
    }
}
