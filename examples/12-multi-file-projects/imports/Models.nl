// Models.nl - Defines public types for export

class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func GetInfo(): string {
        return $"{Name} is {Age} years old"
    }
}

enum Status {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}
