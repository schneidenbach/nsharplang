// Demonstrating print, nameof, and typeof features
class Person {
    Name: string
    Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }
}

class Program {
    static func Main() {
        // print statement - no parentheses needed
        print "=== Print Statement Demo ==="
        print "Hello, world!"

        name := "Alice"
        age := 30
        print $"Name: {name}, Age: {age}"

        // nameof operator - get string name of identifier
        print "\n=== Nameof Operator Demo ==="
        print $"Variable name: {nameof(name)}"
        print $"Variable name: {nameof(age)}"

        person := new Person("Bob", 25)
        print $"Property name: {nameof(person.Name)}"
        print $"Property name: {nameof(person.Age)}"

        // typeof operator - get Type object
        print "\n=== Typeof Operator Demo ==="
        intType := typeof(int)
        stringType := typeof(string)
        personType := typeof(Person)

        print $"Type of int: {intType}"
        print $"Type of string: {stringType}"
        print $"Type of Person: {personType}"

        // Using typeof for type checks against a known type
        if personType == typeof(Person) {
            print "personType is Person!"
        }

        // Combining all three features
        print "\n=== Combined Demo ==="
        items := [1, 2, 3, 4, 5]
        print $"{nameof(items)} has type {typeof(int[])}"
        print $"Items: {items}"
    }
}
