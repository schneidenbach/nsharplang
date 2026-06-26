namespace NSharpLang.Compiler.Performance

public enum GuardKind {
    MinLength,
    IndexWithin,
    NonZero
}

public class Guard {
    Kind: GuardKind
    Target: string
    Value: int
    Secondary: string?

    constructor(Kind: GuardKind, Target: string, Value: int = 0, Secondary: string? = null) {
        this.Kind = Kind
        this.Target = Target
        this.Value = Value
        this.Secondary = Secondary
    }

    public static func MinLength(target: string, value: int): Guard => new Guard(GuardKind.MinLength, target, value)

    public static func IndexWithin(target: string, index: string): Guard => new Guard(GuardKind.IndexWithin, target, 0, index)

    public static func NonZero(target: string): Guard => new Guard(GuardKind.NonZero, target)
}

public class PoolRent {
    VariableName: string
    Line: int
    Column: int
    Returned: bool

    constructor(VariableName: string, Line: int, Column: int) {
        this.VariableName = VariableName
        this.Line = Line
        this.Column = Column
        this.Returned = false
    }
}

public class ResourceLocal {
    VariableName: string
    Kind: string
    Line: int
    Column: int
    Disposed: bool

    constructor(VariableName: string, Kind: string, Line: int, Column: int) {
        this.VariableName = VariableName
        this.Kind = Kind
        this.Line = Line
        this.Column = Column
        this.Disposed = false
    }
}
