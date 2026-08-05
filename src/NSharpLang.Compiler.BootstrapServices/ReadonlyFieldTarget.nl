namespace NSharpLang.Compiler

class ReadonlyFieldTarget {
    Name: string
    IsStatic: bool
    IsCurrentInstance: bool

    constructor(Name: string, IsStatic: bool, IsCurrentInstance: bool) {
        this.Name = Name
        this.IsStatic = IsStatic
        this.IsCurrentInstance = IsCurrentInstance
    }
}
