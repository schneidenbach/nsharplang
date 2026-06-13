namespace NSharpLang.Compiler.Columnar;

internal readonly struct ColumnarNodeTable
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStarts;
    private readonly int[] _childCounts;
    private readonly int[] _childIndices;
    private readonly int[]? _spanStarts;

    public ColumnarNodeTable(
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
        _spanStarts = spanStarts;
    }

    public int Kind(int index) => _kinds[index];

    public int ValueStart(int index) => _valueStarts[index];

    public int ValueLength(int index) => _valueLengths[index];

    public int ChildCount(int index) => _childCounts[index];

    public int Child(int index, int childOrdinal) => _childIndices[_childStarts[index] + childOrdinal];

    public int SpanStart(int index)
        => _spanStarts is not null
            ? _spanStarts[index]
            : throw new System.InvalidOperationException("Columnar node span starts were not provided.");

    public string Text(string source, int index) => source.Substring(_valueStarts[index], _valueLengths[index]);
}
