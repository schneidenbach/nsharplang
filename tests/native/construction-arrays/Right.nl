namespace NSharpLang.ConstructionArrays.Right

enum Selection: string {
    Value = "right"
}

class EnumDefaulted {
    Required: int
    Selected: Selection

    constructor(seed: int, selected: Selection = Selection . Value) {
        this.Required = seed
        this.Selected = selected
    }
}

class PrimaryEnumDefaulted(seed: int, selected: Selection = Selection . Value) {
    func RequiredValue(): int {
        return seed
    }

    func SelectedValue(): Selection {
        return selected
    }
}

class Widget {
    Value: int

    constructor(value: int) {
        this.Value = value
    }

    func Side(): string {
        return "right"
    }
}
