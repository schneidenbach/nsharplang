// Models.nl - Defines public types for export
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func GetInfo(): string {
        return $"{Name} is {Age} years old"
    }
}

enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}
