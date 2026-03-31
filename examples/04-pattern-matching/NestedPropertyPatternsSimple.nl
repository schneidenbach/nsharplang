// Nested Property Patterns Example
// Demonstrates deep object destructuring in match expressions
import System

class Address {
    Street: string
    City: string
    State: string
    ZipCode: string
}

class Person {
    Name: string
    Age: int
    Address: Address
}

class Company {
    Name: string
    HQ: Address
}

func ClassifyPerson(person: Person): string {
    // Match with nested property patterns
    return match person {
        { Address: { City: "New York", State: "NY" } } => "New Yorker",
        { Address: { City: city, State: "CA" } } => $"Californian from {city}",
        { Address: { State: "TX" } } => "Texan",
        _ => "Other location"
    }
}

func DescribeCompany(company: Company): string {
    // Three-level nesting with binding
    return match company {
        { HQ: { City: "New York", State: "NY", ZipCode: zip } } => $"NYC company in {zip}",
        { HQ: { City: city, State: state } } => $"Based in {city}, {state}",
        _ => "Unknown"
    }
}

func AnalyzePerson(person: Person): string {
    // Combining age check with nested address pattern using guards
    return match person {
        { Age: age, Address: { City: "New York" } } when age < 30 => "Young New Yorker",
        { Age: age, Address: { State: "CA" } } when age >= 65 => "Senior Californian",
        _ => "Regular person"
    }
}

func Main() {
    print "=== Nested Property Patterns Example ==="
    print ""

    // Test person in NYC
    addr1 := new Address() { Street: "123 Broadway", City: "New York", State: "NY", ZipCode: "10001" }

    person1 := new Person() { Name: "Alice", Age: 25, Address: addr1 }

    print $"Person 1: {ClassifyPerson(person1)}"
    print $"Analysis: {AnalyzePerson(person1)}"
    print ""

    // Test person in California
    addr2 := new Address() { Street: "456 Main St", City: "San Francisco", State: "CA", ZipCode: "94102" }

    person2 := new Person() { Name: "Bob", Age: 70, Address: addr2 }

    print $"Person 2: {ClassifyPerson(person2)}"
    print $"Analysis: {AnalyzePerson(person2)}"
    print ""

    // Test company
    company := new Company() { Name: "TechCorp", HQ: addr1 }

    print $"Company: {DescribeCompany(company)}"
    print ""
    print "All nested property patterns working correctly!"
}
