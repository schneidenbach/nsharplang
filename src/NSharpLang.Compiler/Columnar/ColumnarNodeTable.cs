namespace NSharpLang.Compiler.Columnar;

internal readonly struct ColumnarNodeTable
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStarts;
    private readonly int[] _childCounts;
    private readonly int[] _childIndices;

    internal ColumnarNodeTable(
        int[] kinds,
        int[] valueStarts,
        int[] valueLengths,
        int[] childStarts,
        int[] childCounts,
        int[] childIndices,
        int[]? spanStarts = null)
    {
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStarts = childStarts;
        _childCounts = childCounts;
        _childIndices = childIndices;
    }

    internal int Kind(int index) => _kinds[index];

    internal int ValueStart(int index) => _valueStarts[index];

    internal int[] Kinds => _kinds;

    internal int[] ValueLengths => _valueLengths;

    internal int ChildCount(int index) => _childCounts[index];

    internal int Child(int index, int childOrdinal) => _childIndices[_childStarts[index] + childOrdinal];

    internal string Text(string source, int index) => source.Substring(_valueStarts[index], _valueLengths[index]);
}
