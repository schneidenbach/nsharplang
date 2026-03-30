namespace MultiFileTest

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

    func IsAdult(): bool {
        return Age >= 18
    }
}
