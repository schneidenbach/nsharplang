namespace NSharpLang.InterfaceParameterModifiers.Tests

interface IModifierService {
    func Count(params values: int[]): int
    func Increment(ref value: int)
    func Read(out value: int)
    func Describe(ref value: int): int
}

class ModifierService: IModifierService {
    func Count(params values: int[]): int {
        return values.Length
    }

    func Increment(ref value: int) {
        value = value + 10
    }

    func Read(out value: int) {
        value = 23
    }

    // Byref reads inside binaries, in BOTH operand orders: `value * 2` derefs the ref parameter
    // as the left operand and `100 - value` as the right operand, all planner-owned typed-ldind
    // derefs over the ldarg address.
    func Describe(ref value: int): int {
        return value * 2 + (100 - value)
    }
}

func CountThroughInterface(service: IModifierService): int {
    values := [1, 2, 3, 4]
    return service.Count(values)
}

func MutateThroughInterface(service: IModifierService): int {
    changed := 5
    observed := 0
    service.Increment(ref changed)
    service.Read(out observed)
    return changed * 100 + observed
}

func ReadThroughInterface(service: IModifierService): int {
    amount := 16
    return service.Describe(ref amount)
}
