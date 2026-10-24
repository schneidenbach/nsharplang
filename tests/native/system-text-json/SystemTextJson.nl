namespace NSharpLang.SystemTextJson.Tests

import System.Text.Json

// THE SHAPES A SYSTEM.TEXT.JSON PAYLOAD IS BUILT FROM.
//
// `JsonSerializer.Serialize(value)` is `Serialize<TValue>(TValue, JsonSerializerOptions? = null)`:
// a GENERIC declaration whose type argument is inferred from the value and whose trailing options are
// omitted. These declarations close `TValue` over a class this compilation declares, over an anonymous
// object's synthesized generic type, and over a type parameter of the calling function.
class Order {
    Id: int
    Customer: string
    Lines: string[]
}

class Holder {
    static Current: Order = new Order { Id: 9, Customer: "Static", Lines: ["s"] }

    func Render(order: Order): string {
        return JsonSerializer.Serialize(order)
    }
}

func ToJson<T>(value: T): string {
    return JsonSerializer.Serialize(value)
}

// An anonymous type has no name to write as a type argument, so a SAMPLE of it supplies one: `T` is
// inferred from the sample, and the explicit `Deserialize<T>` reads the JSON back into that type.
func ParseLike<T>(json: string, _sample: T): T? {
    return JsonSerializer.Deserialize<T>(json)
}
