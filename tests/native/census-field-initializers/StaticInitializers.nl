namespace NSharpLang.CensusFieldInitializers.Tests

import System.Collections.Generic
import System.Runtime.CompilerServices


// The census row that started this area: `src/NSharpLang.Runtime/Result.cs` declares
// `private const MethodImplOptions HotPathImpl = AggressiveInlining | AggressiveOptimization`.
// Its N# form is a `static readonly` of enum type whose initializer is a binary expression.
class RuntimeHotPath {
    static readonly HotPathImpl: MethodImplOptions = MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization
    static readonly Inlining: MethodImplOptions = MethodImplOptions.AggressiveInlining
}

// One row per census entry: an external static member, a unary literal, a construction, `null`,
// a binary expression over literals, string concatenation, and a call to the type's own static
// method declared after the field.
class CensusStatics {
    static readonly Limit: int = int.MaxValue
    static readonly Negative: int = -1
    static readonly Names: List<string> = new List<string>()
    static readonly None: string? = null
    static readonly Sum: int = 3 + 4
    static readonly Label: string = "a" + "b"
    static readonly Seed: int = Make(4)
    static Mutable: int = 10

    static func Make(value: int): int => value * 2
}

// Textual order, with a side effect that records it. Every initializer runs once, in source order,
// so the trace names the three fields in declaration order and each later initializer reads the
// value the earlier one produced.
class OrderedStatics {
    static Trace: string = ""
    static readonly First: int = Record("first", 1)
    static readonly Second: int = Record("second", First + 1)
    static readonly Third: int = Record("third", Second + 1)

    static func Record(name: string, value: int): int {
        Trace = Trace + name + ";"
        return value
    }
}

// The other half of the textual-order rule: an initializer that reads a static field declared
// LATER sees that field's default, not its initialized value. This is the C# rule and it is why
// the order is textual rather than dependency-driven.
class ForwardReadingStatics {
    static readonly Early: int = Later + 5
    static readonly Later: int = 7
}

// `const` keeps its metadata-literal path: the value is a compile-time constant on the field,
// not a store in the type initializer.
class ConstantStatics {
    const Limit: int = 7

    static func Read(): int => Limit
}

// A type with no static field initializer gets no type initializer at all.
class NoStaticInitializers {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

// Static storage on a generic type belongs to the INSTANTIATION, so the type initializer runs
// once per closed type and each instantiation counts independently.
class PerInstantiation<T> {
    static Count: int = 100

    static func Bump(): int {
        Count = Count + 1
        return Count
    }
}
