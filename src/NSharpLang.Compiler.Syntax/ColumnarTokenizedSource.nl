namespace NSharpLang.Compiler.Columnar

class ColumnarTokenizedSource {
    RawKinds: int[]
    RawStarts: int[]
    RawValueLengths: int[]
    RawCount: int
    Kinds: int[]
    Starts: int[]
    ValueLengths: int[]
    Count: int

    constructor(rawKinds: int[], rawStarts: int[], rawValueLengths: int[], rawCount: int, kinds: int[], starts: int[], valueLengths: int[], count: int) {
        RawKinds = rawKinds
        RawStarts = rawStarts
        RawValueLengths = rawValueLengths
        RawCount = rawCount
        Kinds = kinds
        Starts = starts
        ValueLengths = valueLengths
        Count = count
    }
}
