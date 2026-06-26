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
