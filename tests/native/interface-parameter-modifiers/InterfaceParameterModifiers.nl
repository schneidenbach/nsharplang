namespace NSharpLang.InterfaceParameterModifiers.Tests

interface IModifierService {
    func Count(params values: int[]): int
    func Increment(ref value: int)
    func Read(out value: int)
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
