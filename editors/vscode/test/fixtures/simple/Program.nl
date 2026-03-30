namespace SimpleTest

import System

func greet(name: string): string {
    return $"Hello, {name}!"
}

func add(a: int, b: int): int {
    return a + b
}

enum Color {
    Red,
    Green,
    Blue
}

enum Status: string {
    Active = "active",
    Inactive = "inactive"
}

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

func Main() {
    message := greet("World")
    print message

    result := add(3, 4)
    print $"3 + 4 = {result}"

    numbers := [1, 2, 3, 4, 5]
    for num in numbers {
        print num
    }

    person := new Person("Alice", 30)
    print person.GetInfo()
}
