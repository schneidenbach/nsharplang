// Expression-Bodied Members Example
// Demonstrates the => syntax for properties and methods
class Person {
    FirstName: string
    LastName: string
    BirthYear: int

    // Expression-bodied property
    FullName: string => FirstName + " " + LastName

    // Expression-bodied property with calculation
    Age: int => 2025 - BirthYear

    // Expression-bodied method
    func GetGreeting(): string => "Hello, " + FullName + "!"

    constructor(firstName: string, lastName: string, birthYear: int) {
        FirstName = firstName
        LastName = lastName
        BirthYear = birthYear
    }
}

class Calculator {
    Value: int

    // Expression-bodied property
    Double: int => Value * 2
    Triple: int => Value * 3

    // Expression-bodied methods
    func Add(x: int): int => Value + x
    func Subtract(x: int): int => Value - x
    func Multiply(x: int): int => Value * x

    constructor(value: int) {
        Value = value
    }
}

class Rectangle {
    Width: double
    Height: double

    // Expression-bodied properties for calculated values
    Area: double => Width * Height
    Perimeter: double => 2 * (Width + Height)
    IsSquare: bool => Width == Height

    constructor(width: double, height: double) {
        Width = width
        Height = height
    }
}

class Program {
    static func Main() {
        print "=== Expression-Bodied Members Demo ==="

        // Test Person with expression-bodied properties
        person := new Person("John", "Doe", 1990)
        print person.FullName
        print person.Age
        print person.GetGreeting()

        // Test Calculator with expression-bodied methods
        calc := new Calculator(10)
        print calc.Double
        print calc.Triple
        print calc.Add(5)
        print calc.Multiply(3)

        // Test Rectangle with calculated properties
        rect := new Rectangle(5.0, 10.0)
        print rect.Area
        print rect.Perimeter
        print rect.IsSquare

        square := new Rectangle(5.0, 5.0)
        print square.IsSquare
    }
}
