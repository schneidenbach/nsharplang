namespace NSharpLang.Compiler.Columnar

public class ColumnarNodeTable {
    kinds: int[]
    valueStarts: int[]
    valueLengths: int[]
    childStarts: int[]
    childCounts: int[]
    childIndices: int[]

    Kinds: int[] => kinds
    ValueLengths: int[] => valueLengths

    constructor(
        kinds: int[],
        valueStarts: int[],
        valueLengths: int[],
        childStarts: int[],
        childCounts: int[],
        childIndices: int[],
        spanStarts: int[]? = null) {
        this.kinds = kinds
        this.valueStarts = valueStarts
        this.valueLengths = valueLengths
        this.childStarts = childStarts
        this.childCounts = childCounts
        this.childIndices = childIndices
    }

    public func Kind(index: int): int => kinds[index]

    public func ValueStart(index: int): int => valueStarts[index]

    public func ChildCount(index: int): int => childCounts[index]

    public func Child(index: int, childOrdinal: int): int => childIndices[childStarts[index] + childOrdinal]

    public func Text(source: string, index: int): string => source.Substring(valueStarts[index], valueLengths[index])
}
