namespace NSharpLang.Compiler.Columnar

public class ColumnarNodeTable {
    kinds: int[]
    valueStarts: int[]
    valueLengths: int[]
    childStarts: int[]
    childCounts: int[]
    childIndices: int[]
    spanStarts: int[]?
    spanLengths: int[]?

    Kinds: int[] => kinds
    ValueLengths: int[] => valueLengths

    constructor(
        kindsValue: int[],
        valueStartsValue: int[],
        valueLengthsValue: int[],
        childStartsValue: int[],
        childCountsValue: int[],
        childIndicesValue: int[],
        spanStartsValue: int[]? = null,
        spanLengthsValue: int[]? = null) {
        this.kinds = kindsValue
        this.valueStarts = valueStartsValue
        this.valueLengths = valueLengthsValue
        this.childStarts = childStartsValue
        this.childCounts = childCountsValue
        this.childIndices = childIndicesValue
        this.spanStarts = spanStartsValue
        this.spanLengths = spanLengthsValue
    }

    public func Kind(index: int): int => kinds[index]

    public func ValueStart(index: int): int => valueStarts[index]

    public func ChildCount(index: int): int => childCounts[index]

    public func Child(index: int, childOrdinal: int): int => childIndices[childStarts[index] + childOrdinal]

    public func Text(source: string, index: int): string => source.Substring(valueStarts[index], valueLengths[index])

    public func SpanStart(index: int): int {
        spans := spanStarts
        if spans == null {
            return valueStarts[index]
        }

        return spans[index]
    }

    public func SpanLength(index: int): int {
        spans := spanLengths
        if spans == null {
            return valueLengths[index]
        }

        return spans[index]
    }
}
