namespace NSharpLang.ConstructionArrays.Left

enum Selection: string {
    Value = "left"
}

class Widget {
    Value: int

    constructor(value: int) {
        this.Value = value
    }

    func Side(): string {
        return "left"
    }
}
