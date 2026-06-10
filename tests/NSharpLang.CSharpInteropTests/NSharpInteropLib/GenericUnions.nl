namespace NSharpInteropLib.Unions


// Generic discriminated union — tests C# consumption of the emitted class hierarchy.
// Payload members are PascalCase so they export as public CLR fields.
union Fetched<T> {
    Hit { Value: T }
    Miss { Reason: string }
}

class FetchApi {
    static func FetchNumber(hit: bool): Fetched<int> {
        if hit {
            return new Fetched.Hit<int> { Value: 42 }
        }
        return new Fetched.Miss<int> { Reason: "no luck" }
    }
}
