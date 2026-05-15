namespace NSharpInteropLib.Models


// Record with properties and methods - tests record consumption from C#
record Person {
    Name: string
    Age: int
    Email: string

    func GetDisplayName(): string {
        return $"{Name} ({Age})"
    }
}

// Record with primary constructor
record Address(street: string, city: string, zip: string) {
    FullAddress: string => $"{street}, {city} {zip}"
}

// Class with constructor and instance methods
class PersonService {
    people: System.Collections.Generic.List<Person>

    constructor() {
        people = new System.Collections.Generic.List<Person>()
    }

    func Add(person: Person) {
        people.Add(person)
    }

    func GetAll(): System.Collections.Generic.List<Person> {
        return people
    }

    Count: int => people.Count
}

// Numeric enum
enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

// String-valued enum
enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}
